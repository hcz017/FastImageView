import CoreGraphics
import Foundation
import Observation

public protocol FolderScanning {
    func scan(folder: URL) throws -> [ImageFile]
}

public struct UndoEntry: Equatable, Sendable {
    public var file: ImageFile
    public var trashURL: URL
}

@MainActor
public protocol PreviewPipeline: AnyObject {
    var generation: Int { get }
    var onGenerationChange: (() -> Void)? { get set }
    func reset()
    func cancel(url: URL)
    func requestThumbnail(file: ImageFile)
    func cancelQueuedThumbnail(url: URL)
    func showViewer(current: ImageFile, previous: ImageFile?, next: ImageFile?, maxPixelSize: Int)
    func cachedThumbnail(file: ImageFile) -> CGImage?
    func cachedViewerImage(file: ImageFile) -> CGImage?
    func didFail(url: URL) -> Bool
}

@MainActor
@Observable
public final class BrowserModel {
    public private(set) var folderURL: URL?
    public var pendingFolderURL: URL?
    public private(set) var catalog = ImageCatalog()
    public private(set) var mode: BrowserMode = .noFolder
    public private(set) var openError: String?
    public var statusMessage: String?
    public private(set) var fit: ViewerFit = .fit
    public private(set) var screenLongEdge = 1800
    public private(set) var renderGeneration = 0
    public private(set) var generation = 0
    public private(set) var isScanning = false
    public private(set) var listingRevision = 0
    public private(set) var recentFolders: [URL]
    private var recentList: RecentFolderList
    private let recentDefaults: UserDefaults?
    private var pendingSelectionURL: URL?
    private var undoStack: [UndoEntry] = []
    private var fileIdentity: [String: String] = [:]
    private var folderRefreshTask: Task<Void, Never>?
    private let folderWatch: any FolderWatching
    private let scanner: any FolderScanning
    private let deletion: DeletionService
    private let previews: any PreviewPipeline

    public init(
        scanner: any FolderScanning,
        deletion: DeletionService,
        previews: any PreviewPipeline,
        recentFolders: RecentFolderList = RecentFolderList(),
        recentDefaults: UserDefaults? = nil,
        folderWatch: any FolderWatching = IdleFolderWatch()
    ) {
        self.scanner = scanner
        self.deletion = deletion
        self.previews = previews
        self.recentList = recentFolders
        self.recentFolders = recentFolders.urls
        self.recentDefaults = recentDefaults
        self.folderWatch = folderWatch
        self.renderGeneration = previews.generation
        previews.onGenerationChange = { [weak self] in
            guard let self else { return }
            self.renderGeneration = self.previews.generation
        }
    }

    public static func live() -> BrowserModel {
        let defaults = UserDefaults.standard
        return BrowserModel(
            scanner: FolderScanner(),
            deletion: DeletionService(storage: FileManagerTrashStorage()),
            previews: LivePreviewPipeline(),
            recentFolders: RecentFolderList(defaults: defaults),
            recentDefaults: defaults,
            folderWatch: DispatchFolderWatch()
        )
    }

    public var canUndo: Bool { !undoStack.isEmpty }

    public func beginOpen() -> Int {
        generation += 1
        isScanning = true
        return generation
    }

    public func open(folder: URL, selecting file: URL? = nil, screenLongEdge: Int? = nil) {
        let token = beginOpening(folder: folder, selecting: file, screenLongEdge: screenLongEdge)
        let scanner = self.scanner
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try scanner.scan(folder: folder) }
            await MainActor.run { [weak self] in
                self?.acceptScan(generation: token, outcome: outcome)
            }
        }
    }

    public func openImageFile(_ url: URL, screenLongEdge: Int) {
        let file = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) else {
            open(folder: file.deletingLastPathComponent(), selecting: file, screenLongEdge: screenLongEdge)
            return
        }
        if isDirectory.boolValue {
            open(folder: file, screenLongEdge: screenLongEdge)
        } else {
            open(folder: file.deletingLastPathComponent(), selecting: file, screenLongEdge: screenLongEdge)
        }
    }

    func beginOpening(folder: URL, selecting file: URL? = nil, screenLongEdge: Int? = nil) -> Int {
        if let screenLongEdge { self.screenLongEdge = screenLongEdge }
        pendingFolderURL = folder
        pendingSelectionURL = file
        return beginOpen()
    }

    public func acceptScan(generation: Int, outcome: Result<[ImageFile], Error>) {
        guard generation == self.generation else { return }
        isScanning = false
        switch outcome {
        case .failure(let error):
            pendingSelectionURL = nil
            if folderURL == nil {
                openError = error.localizedDescription
                mode = .noFolder
            } else {
                statusMessage = error.localizedDescription
            }
        case .success(let files):
            previews.reset()
            undoStack.removeAll()
            catalog.replaceFiles(files)
            folderURL = pendingFolderURL
            if let folder = pendingFolderURL {
                recentList.remember(folder)
                recentFolders = recentList.urls
                if let recentDefaults {
                    recentList.save(to: recentDefaults)
                }
            }
            fit = .fit
            openError = nil
            if let wanted = pendingSelectionURL?.standardizedFileURL.path,
               let match = files.first(where: { $0.url.standardizedFileURL.path == wanted }) {
                select(url: match.url)
                mode = .viewer
                refreshViewer()
            } else {
                mode = .grid
            }
            pendingSelectionURL = nil
            fileIdentity = FileIdentity.byPath(files)
            watchCurrentFolder()
        }
    }

    func applyFolderListing(_ files: [ImageFile], identityByPath: [String: String]) {
        let selectedPath = catalog.selectionID?.standardizedFileURL.path
        if files == catalog.files {
            fileIdentity = identityByPath
            return
        }
        let oldURLs = Set(catalog.files.map(\.url))
        let oldToken = selectedPath.flatMap { fileIdentity[$0] }
        let renamed = renamedSelection(selectedPath: selectedPath, oldToken: oldToken, files: files, identityByPath: identityByPath)
        catalog.refresh(with: files, renamedSelection: renamed)
        fileIdentity = identityByPath
        listingRevision += 1
        for url in oldURLs.subtracting(files.map(\.url)) {
            previews.cancel(url: url)
        }
        if mode == .viewer {
            if catalog.selectedFile == nil { mode = .grid }
            else { refreshViewer() }
        }
    }

    private func renamedSelection(selectedPath: String?, oldToken: String?, files: [ImageFile], identityByPath: [String: String]) -> URL? {
        guard let selectedPath, let oldToken else { return nil }
        guard !files.contains(where: { $0.url.standardizedFileURL.path == selectedPath }) else { return nil }
        return files.first { identityByPath[$0.url.standardizedFileURL.path] == oldToken }?.url
    }

    private func watchCurrentFolder() {
        guard let folder = folderURL else {
            folderWatch.stop()
            return
        }
        folderWatch.start(folder: folder) { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleFolderRefresh()
            }
        }
    }

    private func scheduleFolderRefresh() {
        folderRefreshTask?.cancel()
        let folder = folderURL
        let token = generation
        folderRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let folder else { return }
            guard self.folderURL == folder, self.generation == token else { return }
            let scanner = self.scanner
            let outcome = await Task.detached(priority: .utility) {
                Result { try scanner.scan(folder: folder) }
            }.value
            guard !Task.isCancelled, self.folderURL == folder, self.generation == token else { return }
            switch outcome {
            case .failure(let error):
                self.statusMessage = error.localizedDescription
            case .success(let files):
                self.applyFolderListing(files, identityByPath: FileIdentity.byPath(files))
            }
        }
    }

    public func setKeyword(_ value: String) {
        var next = catalog
        next.keyword = value
        next.clampSelection()
        catalog = next
        leaveViewerIfNeeded()
    }

    public func toggleFormat(_ format: ImageFormat) {
        var next = catalog
        if next.selectedFormats.contains(format) { next.selectedFormats.remove(format) }
        else { next.selectedFormats.insert(format) }
        next.clampSelection()
        catalog = next
        leaveViewerIfNeeded()
    }

    public func select(url: URL) {
        var next = catalog
        guard next.filtered.contains(where: { $0.url == url }) else { return }
        next.selectionID = url
        catalog = next
    }

    public func moveSelection(by delta: Int, screenLongEdge: Int) {
        self.screenLongEdge = screenLongEdge
        var next = catalog
        next.moveSelection(by: delta)
        catalog = next
        if mode == .viewer { refreshViewer() }
    }

    public func openViewer(screenLongEdge: Int) {
        guard catalog.selectedFile != nil else { return }
        self.screenLongEdge = screenLongEdge
        fit = .fit
        mode = .viewer
        refreshViewer()
    }

    public func closeViewer() {
        if mode == .viewer { mode = .grid }
    }

    public func setFit(_ fit: ViewerFit, screenLongEdge: Int) {
        guard mode == .viewer else { return }
        self.screenLongEdge = screenLongEdge
        self.fit = fit
        refreshViewer()
    }

    public func deleteSelected() {
        guard let selected = catalog.selectedFile else { return }
        do {
            let trashed = try deletion.trash(url: selected.url)
            undoStack.append(UndoEntry(file: selected, trashURL: trashed.trashURL))
            applyRemoval()
            previews.cancel(url: selected.url)
        } catch DeletionError.missing {
            applyRemoval()
            previews.cancel(url: selected.url)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    public func undo() {
        guard let entry = undoStack.popLast() else { return }
        do {
            try deletion.restore(TrashedFile(originalURL: entry.file.url, trashURL: entry.trashURL))
            let previousSelection = catalog.selectionID
            var next = catalog
            next.restore(entry.file)
            catalog = next
            if mode == .viewer {
                if catalog.filtered.contains(where: { $0.url == entry.file.url }) {
                    refreshViewer()
                } else if let previousSelection, catalog.filtered.contains(where: { $0.url == previousSelection }) {
                    refreshViewer()
                } else {
                    mode = .grid
                }
            }
        } catch {
            undoStack.append(entry)
            statusMessage = error.localizedDescription
        }
    }

    public func thumbnailRequest(_ file: ImageFile) {
        guard file.iCloudState != .notDownloaded else { return }
        previews.requestThumbnail(file: file)
    }

    public func thumbnailRelease(_ file: ImageFile) {
        previews.cancelQueuedThumbnail(url: file.url)
    }

    public func noteUnavailable(_ url: URL) {
        guard previews.didFail(url: url) else { return }
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        guard catalog.files.contains(where: { $0.url == url }) else { return }
        if catalog.selectionID == url {
            applyRemoval()
        } else {
            var next = catalog
            next.files.removeAll { $0.url == url }
            next.clampSelection()
            catalog = next
        }
        previews.cancel(url: url)
    }

    public func cachedThumbnail(_ file: ImageFile) -> CGImage? {
        previews.cachedThumbnail(file: file)
    }

    public func cachedViewerImage(_ file: ImageFile) -> CGImage? {
        previews.cachedViewerImage(file: file)
    }

    public func failed(_ url: URL) -> Bool { previews.didFail(url: url) }

    private func applyRemoval() {
        var next = catalog
        _ = next.removeSelected()
        catalog = next
        if mode == .viewer && catalog.selectedFile == nil { mode = .grid }
        else if mode == .viewer { refreshViewer() }
    }

    private func leaveViewerIfNeeded() {
        if mode == .viewer && catalog.selectedFile == nil { mode = .grid }
    }

    private func refreshViewer() {
        guard let current = catalog.selectedFile else { return }
        let items = catalog.filtered
        let index = items.firstIndex(where: { $0.url == current.url })
        let previous = index.flatMap { $0 > 0 ? items[$0 - 1] : nil }
        let next = index.flatMap { $0 + 1 < items.count ? items[$0 + 1] : nil }
        let pixels = PreviewMaxPixel.viewer(fit: fit, screenLongEdge: screenLongEdge, isRaw: current.format.isRaw)
        previews.showViewer(current: current, previous: previous, next: next, maxPixelSize: pixels)
    }
}
