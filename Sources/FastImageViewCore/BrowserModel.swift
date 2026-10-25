import CoreGraphics
import Foundation
import Observation

public protocol FolderScanning {
    func scan(folder: URL) throws -> [ImageFile]
}

public struct UndoEntry: Equatable, Sendable {
    public var files: [ImageFile]
    public var trashURLs: [URL]

    public init(files: [ImageFile], trashURLs: [URL]) {
        self.files = files
        self.trashURLs = trashURLs
    }
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
    func showCompare(files: [ImageFile], maxPixelSize: Int)
    func cachedThumbnail(file: ImageFile) -> CGImage?
    func cachedViewerImage(file: ImageFile) -> CGImage?
    func didFail(url: URL) -> Bool
}

public extension PreviewPipeline {
    /// 默认实现让测试替身无需改动即可编译。
    func showCompare(files: [ImageFile], maxPixelSize: Int) {
        guard let current = files.first else { return }
        showViewer(
            current: current,
            previous: files.count > 1 ? files[1] : nil,
            next: files.count > 2 ? files[2] : nil,
            maxPixelSize: maxPixelSize
        )
    }
}

@MainActor
@Observable
public final class BrowserModel {
    /// 对比会话快照，用于从大图返回。
    private struct CompareReturn {
        var files: [ImageFile]
        var sourceSizes: [URL: ImagePixelSize]
        var zoom: ViewerZoom
        var pan: ImagePan
    }

    public private(set) var folderURL: URL?
    public var pendingFolderURL: URL?
    public private(set) var catalog = ImageCatalog()
    public private(set) var mode: BrowserMode = .noFolder
    public private(set) var openError: String?
    public var statusMessage: String?
    public private(set) var zoom: ViewerZoom = .fit
    public private(set) var pan = ImagePan.zero
    public private(set) var compareFiles: [ImageFile] = []
    public private(set) var compareZoom: ViewerZoom = .fit
    public private(set) var comparePan = ImagePan.zero
    public private(set) var compareLayouts: [URL: ViewerLayout] = [:]
    private var compareSourceSizes: [URL: ImagePixelSize] = [:]
    /// 从对比进入大图时暂存的会话，供返回按钮与 Esc 恢复。
    private var compareReturn: CompareReturn?
    public private(set) var viewerLayout: ViewerLayout?
    public private(set) var viewerSourceSize: ImagePixelSize?
    public private(set) var screenLongEdge = 1800
    public private(set) var renderGeneration = 0
    public private(set) var generation = 0
    public private(set) var isScanning = false
    public private(set) var listingRevision = 0
    public private(set) var recentFolders: [URL]
    /// 文件标准路径 → 分级（1...5）。
    public private(set) var ratings: [String: Int]
    private var recentList: RecentFolderList
    private let recentDefaults: UserDefaults?
    private let ratingStore: any RatingStoring
    private var pendingSelectionURL: URL?
    private var pendingSelectionURLs: [URL] = []
    private var undoStack: [UndoEntry] = []
    private var fileIdentity: [String: String] = [:]
    private var folderRefreshTask: Task<Void, Never>?
    private var viewerSourceURL: URL?
    private let folderWatch: any FolderWatching
    private let scanner: any FolderScanning
    private let deletion: DeletionService
    private let previews: any PreviewPipeline
    private let cloudDownloader: any CloudDownloading
    private let imageIO = ImageIOThumbnailDecoder()
    /// 正在下载（含排队）的云盘文件，供界面显示「下载中…」。
    public private(set) var cloudDownloadingURLs = Set<URL>()
    private var activeCloudURLs = Set<URL>()
    private var queuedCloudURLs: [URL] = []
    private var cloudStartedAt: [URL: Date] = [:]
    private var cloudPollTask: Task<Void, Never>?
    private let cloudDownloadLimit = 4
    private let cloudDownloadTimeout: TimeInterval = 300

    public init(
        scanner: any FolderScanning,
        deletion: DeletionService,
        previews: any PreviewPipeline,
        recentFolders: RecentFolderList = RecentFolderList(),
        recentDefaults: UserDefaults? = nil,
        folderWatch: any FolderWatching = IdleFolderWatch(),
        ratingStore: any RatingStoring = InMemoryRatingStore(),
        cloudDownloader: any CloudDownloading = UbiquitousDownloader()
    ) {
        self.scanner = scanner
        self.deletion = deletion
        self.previews = previews
        self.recentList = recentFolders
        self.recentFolders = recentFolders.urls
        self.recentDefaults = recentDefaults
        self.folderWatch = folderWatch
        self.ratingStore = ratingStore
        self.cloudDownloader = cloudDownloader
        self.ratings = ratingStore.load()
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
            previews: LivePreviewPipeline(diskThumbnails: ThumbnailDiskStore.live()),
            recentFolders: RecentFolderList(defaults: defaults),
            recentDefaults: defaults,
            folderWatch: DispatchFolderWatch(),
            ratingStore: UserDefaultsRatingStore(defaults: defaults)
        )
    }

    public var canUndo: Bool { !undoStack.isEmpty }

    public var fit: ViewerFit {
        switch zoom {
        case .fit: return .fit
        case .actual, .multiple: return .actual
        }
    }

    public var prefersPan: Bool {
        switch zoom {
        case .fit:
            return false
        case .actual, .multiple:
            guard let layout = viewerLayout else { return true }
            return ZoomMath.prefersPan(
                contentWidth: layout.contentWidth,
                contentHeight: layout.contentHeight,
                viewportWidth: layout.viewportWidth,
                viewportHeight: layout.viewportHeight
            )
        }
    }

    public var zoomLabel: String {
        switch zoom {
        case .fit:
            return "适合"
        case .actual:
            return "100%"
        case .multiple(let value):
            let percent = Int((ZoomMath.displayScale(fitScale: viewerLayout?.fitScale ?? 1, multiple: value) * 100).rounded())
            return "\(percent)%"
        }
    }

    public func zoomMultiple(fitScale: Double) -> Double {
        switch zoom {
        case .fit:
            return 1
        case .actual:
            return ZoomMath.actualMultiple(fitScale: fitScale)
        case .multiple(let value):
            return value
        }
    }

    // MARK: 对比模式

    /// 全部可见选中项；超过 3 张时 `openCompare` 会拒绝，入口据此禁用。
    public var compareCandidateFiles: [ImageFile] { catalog.compareSelection(limit: .max) }

    public var canOpenCompare: Bool { (2...3).contains(compareCandidateFiles.count) }

    /// 大图是否由对比模式进入，可返回对比。
    public var canReturnToCompare: Bool { mode == .viewer && compareReturn != nil }

    public func compareSourceSize(for file: ImageFile) -> ImagePixelSize? {
        compareSourceSizes[file.url]
    }

    public func compareMultiple(fitScale: Double) -> Double {
        switch compareZoom {
        case .fit:
            return 1
        case .actual:
            return ZoomMath.actualMultiple(fitScale: fitScale)
        case .multiple(let value):
            return value
        }
    }

    public var comparePrefersPan: Bool {
        switch compareZoom {
        case .fit: return false
        case .actual, .multiple: return true
        }
    }

    public var compareZoomLabel: String {
        switch compareZoom {
        case .fit:
            return "适合"
        case .actual:
            return "100%"
        case .multiple(let value):
            let fitScale = compareLayouts.values.map(\.fitScale).min() ?? 1
            let percent = Int((ZoomMath.displayScale(fitScale: fitScale, multiple: value) * 100).rounded())
            return "\(percent)%"
        }
    }

    /// 仅当选中 2–3 张时进入；失败返回 `false` 且不改变模式。
    @discardableResult
    public func openCompare(screenLongEdge: Int) -> Bool {
        let files = compareCandidateFiles
        guard (2...3).contains(files.count) else { return false }
        if mode == .viewer { closeViewer() }
        self.screenLongEdge = screenLongEdge
        compareFiles = files
        compareSourceSizes = Dictionary(
            uniqueKeysWithValues: files.compactMap { file in
                guard file.iCloudState != .notDownloaded else { return nil }
                return imageIO.pixelSize(url: file.url).map { (file.url, $0) }
            }
        )
        compareZoom = .fit
        comparePan = .zero
        compareLayouts = [:]
        mode = .compare
        refreshCompareImages()
        return true
    }

    public func closeCompare() {
        if mode == .compare { mode = .grid }
        compareReturn = nil
        compareFiles = []
        compareSourceSizes = [:]
        compareZoom = .fit
        comparePan = .zero
        compareLayouts = [:]
    }

    public func openViewerFromCompare(url: URL, screenLongEdge: Int) {
        guard compareFiles.contains(where: { $0.url == url }) else { return }
        self.screenLongEdge = screenLongEdge
        var next = catalog
        next.focus(url: url)
        catalog = next
        let snapshot = CompareReturn(
            files: compareFiles,
            sourceSizes: compareSourceSizes,
            zoom: compareZoom,
            pan: comparePan
        )
        closeCompare()
        compareReturn = snapshot
        zoom = .fit
        pan = .zero
        mode = .viewer
        refreshViewer()
    }

    /// 从大图返回对比；仅当本次大图由对比进入时有效。
    @discardableResult
    public func returnToCompare(screenLongEdge: Int) -> Bool {
        guard mode == .viewer, let snapshot = compareReturn else { return false }
        self.screenLongEdge = screenLongEdge
        compareReturn = nil
        compareFiles = snapshot.files
        compareSourceSizes = snapshot.sourceSizes
        compareZoom = snapshot.zoom
        comparePan = snapshot.pan
        compareLayouts = [:]
        viewerSourceSize = nil
        viewerSourceURL = nil
        mode = .compare
        refreshCompareImages()
        return true
    }

    public func setCompareFit(_ fit: ViewerFit, screenLongEdge: Int) {
        guard mode == .compare else { return }
        self.screenLongEdge = screenLongEdge
        compareZoom = fit == .fit ? .fit : .actual
        comparePan = .zero
        refreshCompareImages()
    }

    public func setCompareZoomMultiple(_ raw: Double, screenLongEdge: Int) {
        guard mode == .compare else { return }
        self.screenLongEdge = screenLongEdge
        let previous = compareMaxPixel
        let clamped = ZoomMath.clamp(raw)
        if ZoomMath.isFit(clamped) {
            compareZoom = .fit
            comparePan = .zero
        } else {
            compareZoom = .multiple(clamped)
            reclampComparePan()
        }
        if previous != compareMaxPixel { refreshCompareImages() }
    }

    public func zoomCompare(by factor: Double, screenLongEdge: Int) {
        let fitScale = compareLayouts.values.map(\.fitScale).min() ?? 1
        setCompareZoomMultiple(compareMultiple(fitScale: fitScale) * factor, screenLongEdge: screenLongEdge)
    }

    public func applyCompareMagnification(_ magnification: Double, screenLongEdge: Int) {
        guard let current = compareGestureMultiple else { return }
        setCompareGestureMultiple(
            ZoomMath.applyingMagnify(multiple: current, magnification: magnification),
            screenLongEdge: screenLongEdge
        )
    }

    public func applyCompareScrollZoom(_ deltaY: Double, screenLongEdge: Int) {
        guard let current = compareGestureMultiple else { return }
        setCompareGestureMultiple(
            ZoomMath.applyingScroll(multiple: current, deltaY: deltaY),
            screenLongEdge: screenLongEdge
        )
    }

    /// 手势缩放基于当前倍率；`actual` 需要各格布局才能换算成共享倍率。
    private var compareGestureMultiple: Double? {
        switch compareZoom {
        case .fit:
            return 1
        case .actual:
            guard let fitScale = compareLayouts.values.map(\.fitScale).min() else { return nil }
            return ZoomMath.actualMultiple(fitScale: fitScale)
        case .multiple(let value):
            return value
        }
    }

    /// 连续手势缩放以「适合」为下限，且不在 1 附近吸附回 `.fit`，
    /// 否则捏合初期的负向抖动会让画面先缩到比当前更小。
    private func setCompareGestureMultiple(_ raw: Double, screenLongEdge: Int) {
        guard mode == .compare else { return }
        self.screenLongEdge = screenLongEdge
        let previous = compareMaxPixel
        let clamped = ZoomMath.clamp(raw)
        if clamped <= 1 {
            compareZoom = .fit
            comparePan = .zero
        } else {
            compareZoom = .multiple(clamped)
            reclampComparePan()
        }
        if previous != compareMaxPixel { refreshCompareImages() }
    }

    public func noteCompareLayout(url: URL, layout: ViewerLayout) {
        guard compareFiles.contains(where: { $0.url == url }) else { return }
        guard compareLayouts[url] != layout else { return }
        compareLayouts[url] = layout
        reclampComparePan()
    }

    public func setComparePan(x: Double, y: Double) {
        comparePan = ComparePan.clamped(x: x, y: y, layouts: Array(compareLayouts.values))
    }

    public func comparePanBy(dx: Double, dy: Double) {
        setComparePan(x: comparePan.x + dx, y: comparePan.y + dy)
    }

    private var compareMaxPixel: Int {
        PreviewMaxPixel.compare(zoom: compareZoom, panes: compareFiles.count, screenLongEdge: screenLongEdge)
    }

    private func refreshCompareImages() {
        guard !compareFiles.isEmpty else { return }
        for file in compareFiles where file.iCloudState == .notDownloaded {
            requestCloudDownload(file)
        }
        previews.showCompare(files: compareFiles, maxPixelSize: compareMaxPixel)
    }

    private func reclampComparePan() {
        comparePan = ComparePan.clamped(
            x: comparePan.x,
            y: comparePan.y,
            layouts: Array(compareLayouts.values)
        )
    }

    /// 对比快照跟随目录与筛选：不足 2 张时退回网格。
    private func refreshCompare() {
        guard mode == .compare else { return }
        let visible = Set(catalog.filtered.map(\.url))
        let kept = compareFiles.filter { visible.contains($0.url) }
        guard kept.count >= 2 else {
            closeCompare()
            return
        }
        let keptURLs = Set(kept.map(\.url))
        guard keptURLs != Set(compareFiles.map(\.url)) else { return }
        compareFiles = kept
        compareSourceSizes = compareSourceSizes.filter { keptURLs.contains($0.key) }
        compareLayouts = compareLayouts.filter { keptURLs.contains($0.key) }
        reclampComparePan()
        refreshCompareImages()
    }

    public func beginOpen() -> Int {
        generation += 1
        isScanning = true
        resetCloudDownloads()
        return generation
    }

    public func open(folder: URL, selecting file: URL? = nil, selectingMany: [URL] = [], screenLongEdge: Int? = nil) {
        let token = beginOpening(folder: folder, selecting: file, selectingMany: selectingMany, screenLongEdge: screenLongEdge)
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
            openSingleImage(file, screenLongEdge: screenLongEdge)
        }
    }

    /// 从访达打开单张图时先直接进 viewer，父目录扫描在后台补全列表。
    private func openSingleImage(_ url: URL, screenLongEdge: Int) {
        guard let file = FolderScanner.file(url: url) else {
            open(folder: url.deletingLastPathComponent(), selecting: url, screenLongEdge: screenLongEdge)
            return
        }
        self.screenLongEdge = screenLongEdge
        let folder = url.deletingLastPathComponent()
        pendingFolderURL = folder
        pendingSelectionURL = url
        pendingSelectionURLs = []
        let token = beginOpen()
        previews.reset()
        undoStack.removeAll()
        catalog.replaceFiles([file])
        folderURL = folder
        recentList.remember(folder)
        recentFolders = recentList.urls
        if let recentDefaults {
            recentList.save(to: recentDefaults)
        }
        zoom = .fit
        pan = .zero
        openError = nil
        select(url: file.url)
        mode = .viewer
        fileIdentity = FileIdentity.byPath([file])
        pendingSelectionURL = nil
        watchCurrentFolder()
        refreshViewer()

        let scanner = self.scanner
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try scanner.scan(folder: folder) }
            await MainActor.run { [weak self] in
                self?.acceptDirectScan(generation: token, outcome: outcome)
            }
        }
    }

    public func openDropped(_ urls: [URL], screenLongEdge: Int) {
        let decision = DropRouting.decide(urls: urls) { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        switch decision {
        case .none:
            statusMessage = "没有可打开的图片或文件夹"
        case .folder(let folder):
            open(folder: folder, screenLongEdge: screenLongEdge)
        case .image(let file):
            openImageFile(file, screenLongEdge: screenLongEdge)
        case .images(let folder, let files):
            open(folder: folder, selectingMany: files, screenLongEdge: screenLongEdge)
        }
    }

    func beginOpening(folder: URL, selecting file: URL? = nil, selectingMany: [URL] = [], screenLongEdge: Int? = nil) -> Int {
        if let screenLongEdge { self.screenLongEdge = screenLongEdge }
        pendingFolderURL = folder
        pendingSelectionURL = file
        pendingSelectionURLs = selectingMany
        return beginOpen()
    }

    public func acceptScan(generation: Int, outcome: Result<[ImageFile], Error>) {
        guard generation == self.generation else { return }
        isScanning = false
        switch outcome {
        case .failure(let error):
            pendingSelectionURL = nil
            pendingSelectionURLs = []
            if folderURL == nil {
                openError = error.localizedDescription
                mode = .noFolder
            } else {
                statusMessage = error.localizedDescription
            }
        case .success(let files):
            previews.reset()
            closeCompare()
            undoStack.removeAll()
            catalog.replaceFiles(files)
            syncCatalogRatings()
            folderURL = pendingFolderURL
            if let folder = pendingFolderURL {
                recentList.remember(folder)
                recentFolders = recentList.urls
                if let recentDefaults {
                    recentList.save(to: recentDefaults)
                }
            }
            zoom = .fit
            pan = .zero
            openError = nil
            let many = files.filter { file in
                pendingSelectionURLs.contains { $0.standardizedFileURL.path == file.url.standardizedFileURL.path }
            }
            if many.count > 1 {
                var next = catalog
                next.applySelection(url: many[0].url, gesture: .only)
                for match in many.dropFirst() {
                    next.applySelection(url: match.url, gesture: .toggle)
                }
                catalog = next
                mode = .grid
            } else if let wanted = (many.first?.url ?? pendingSelectionURL)?.standardizedFileURL.path,
               let match = files.first(where: { $0.url.standardizedFileURL.path == wanted }) {
                select(url: match.url)
                mode = .viewer
                refreshViewer()
            } else {
                mode = .grid
            }
            pendingSelectionURL = nil
            pendingSelectionURLs = []
            fileIdentity = FileIdentity.byPath(files)
            watchCurrentFolder()
        }
    }

    /// 单图直接打开后的后台扫描结果：只补全列表，不重置已显示的图、缩放和选中项。
    private func acceptDirectScan(generation: Int, outcome: Result<[ImageFile], Error>) {
        guard generation == self.generation else { return }
        isScanning = false
        switch outcome {
        case .failure(let error):
            statusMessage = error.localizedDescription
        case .success(let files):
            catalog.refresh(with: files)
            fileIdentity = FileIdentity.byPath(files)
            if mode == .viewer {
                if catalog.selectedFile == nil {
                    mode = .grid
                } else {
                    refreshViewer()
                }
            }
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
        syncCatalogRatings()
        fileIdentity = identityByPath
        listingRevision += 1
        for url in oldURLs.subtracting(files.map(\.url)) {
            previews.cancel(url: url)
        }
        if mode == .viewer {
            if catalog.selectedFile == nil { mode = .grid }
            else { refreshViewer() }
        } else if mode == .compare {
            refreshCompare()
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

    // MARK: 分级

    /// 当前可设置分级的图片：网格为全部选中项，大图为当前图片。
    public var ratingTargets: [ImageFile] {
        if mode == .viewer {
            return catalog.selectedFile.map { [$0] } ?? []
        }
        if mode == .compare { return [] }
        return catalog.deletionTargets
    }

    public var canRate: Bool { !ratingTargets.isEmpty }

    public func rating(for file: ImageFile) -> Int? {
        ratings[file.url.standardizedFileURL.path]
    }

    /// 作用于当前目标：若全部已是该等级则清除，否则统一设为该等级。
    public func setRating(_ level: Int) {
        guard (1...5).contains(level) else { return }
        let targets = ratingTargets
        guard !targets.isEmpty else { return }
        let allAtLevel = targets.allSatisfy { rating(for: $0) == level }
        var next = ratings
        for file in targets {
            let key = file.url.standardizedFileURL.path
            if allAtLevel {
                next.removeValue(forKey: key)
            } else {
                next[key] = level
            }
        }
        applyRatings(next)
    }

    public func clearRating() {
        let targets = ratingTargets
        guard !targets.isEmpty else { return }
        var next = ratings
        var changed = false
        for file in targets {
            if next.removeValue(forKey: file.url.standardizedFileURL.path) != nil {
                changed = true
            }
        }
        guard changed else { return }
        applyRatings(next)
    }

    public func toggleRatingFilter(_ level: Int) {
        guard (1...5).contains(level) else { return }
        var next = catalog
        if next.selectedRatings.contains(level) {
            next.selectedRatings.remove(level)
        } else {
            next.selectedRatings.insert(level)
        }
        next.clampSelection()
        catalog = next
        leaveViewerIfNeeded()
    }

    public func toggleUnratedFilter() {
        var next = catalog
        next.includesUnrated.toggle()
        next.clampSelection()
        catalog = next
        leaveViewerIfNeeded()
    }

    public func clearRatingFilter() {
        var next = catalog
        next.selectedRatings = []
        next.includesUnrated = false
        next.clampSelection()
        catalog = next
        leaveViewerIfNeeded()
    }

    private func applyRatings(_ next: [String: Int]) {
        ratings = next
        ratingStore.save(next)
        var updated = catalog
        updated.ratings = catalogRatings(for: updated.files)
        updated.clampSelection()
        catalog = updated
        leaveViewerIfNeeded()
    }

    private func syncCatalogRatings() {
        catalog.ratings = catalogRatings(for: catalog.files)
    }

    private func catalogRatings(for files: [ImageFile]) -> [URL: Int] {
        var map: [URL: Int] = [:]
        for file in files {
            if let level = ratings[file.url.standardizedFileURL.path] {
                map[file.url] = level
            }
        }
        return map
    }

    public func select(url: URL, gesture: SelectionGesture = .only) {
        var next = catalog
        next.applySelection(url: url, gesture: gesture)
        catalog = next
    }

    public func moveSelection(by delta: Int, screenLongEdge: Int) {
        self.screenLongEdge = screenLongEdge
        var next = catalog
        next.moveSelection(by: delta)
        catalog = next
        pan = .zero
        if mode == .viewer { refreshViewer() }
    }

    public func moveSelection(byRows rows: Int, columns: Int, screenLongEdge: Int) {
        self.screenLongEdge = screenLongEdge
        var next = catalog
        next.moveSelection(byRows: rows, columns: max(columns, 1))
        catalog = next
        pan = .zero
        if mode == .viewer { refreshViewer() }
    }

    public func openViewer(screenLongEdge: Int) {
        guard catalog.selectedFile != nil else { return }
        compareReturn = nil
        if mode == .compare { closeCompare() }
        self.screenLongEdge = screenLongEdge
        zoom = .fit
        pan = .zero
        mode = .viewer
        refreshViewer()
    }

    public func closeViewer() {
        if mode == .viewer { mode = .grid }
        compareReturn = nil
        viewerSourceSize = nil
        viewerSourceURL = nil
    }

    public func setFit(_ fit: ViewerFit, screenLongEdge: Int) {
        guard mode == .viewer else { return }
        self.screenLongEdge = screenLongEdge
        switch fit {
        case .fit:
            zoom = .fit
        case .actual:
            zoom = .actual
        }
        pan = .zero
        refreshViewer()
    }

    public func setZoomMultiple(_ raw: Double, screenLongEdge: Int) {
        self.screenLongEdge = screenLongEdge
        let previous = PreviewMaxPixel.viewer(zoom: zoom, screenLongEdge: screenLongEdge)
        let clamped = ZoomMath.clamp(raw)
        if ZoomMath.isFit(clamped) {
            zoom = .fit
            pan = .zero
        } else {
            zoom = .multiple(clamped)
            reclampPan()
        }
        let next = PreviewMaxPixel.viewer(zoom: zoom, screenLongEdge: screenLongEdge)
        if previous != next, mode == .viewer {
            refreshViewer()
        }
    }

    public func zoom(by factor: Double, screenLongEdge: Int) {
        let current = zoomMultiple(fitScale: viewerLayout?.fitScale ?? 1)
        setZoomMultiple(current * factor, screenLongEdge: screenLongEdge)
    }

    public func applyMagnification(_ magnification: Double, screenLongEdge: Int) {
        let current = zoomMultiple(fitScale: viewerLayout?.fitScale ?? 1)
        setZoomMultiple(
            ZoomMath.applyingMagnify(multiple: current, magnification: magnification),
            screenLongEdge: screenLongEdge
        )
    }

    public func applyScrollZoom(_ deltaY: Double, screenLongEdge: Int) {
        let current = zoomMultiple(fitScale: viewerLayout?.fitScale ?? 1)
        setZoomMultiple(ZoomMath.applyingScroll(multiple: current, deltaY: deltaY), screenLongEdge: screenLongEdge)
    }

    public func noteViewerLayout(_ layout: ViewerLayout) {
        guard layout != viewerLayout else { return }
        viewerLayout = layout
        reclampPan()
    }

    public func setPan(x: Double, y: Double) {
        guard let layout = viewerLayout else {
            pan = ImagePan(x: x, y: y)
            return
        }
        pan = ImagePan.clamped(
            x: x,
            y: y,
            contentWidth: layout.contentWidth,
            contentHeight: layout.contentHeight,
            viewportWidth: layout.viewportWidth,
            viewportHeight: layout.viewportHeight
        )
    }

    public func panBy(dx: Double, dy: Double) {
        setPan(x: pan.x + dx, y: pan.y + dy)
    }

    public func deleteSelected() {
        guard mode != .compare else { return }
        let targets = mode == .viewer
            ? (catalog.selectedFile.map { [$0] } ?? [])
            : catalog.deletionTargets
        guard !targets.isEmpty else { return }
        var trashedFiles: [ImageFile] = []
        var trashURLs: [URL] = []
        var removed: Set<URL> = []
        for file in targets {
            do {
                let trashed = try deletion.trash(url: file.url)
                trashedFiles.append(file)
                trashURLs.append(trashed.trashURL)
                removed.insert(file.url)
            } catch DeletionError.missing {
                removed.insert(file.url)
            } catch {
                statusMessage = error.localizedDescription
                break
            }
        }
        if !trashedFiles.isEmpty {
            undoStack.append(UndoEntry(files: trashedFiles, trashURLs: trashURLs))
        }
        guard !removed.isEmpty else { return }
        compareReturn = nil
        var next = catalog
        _ = next.remove(urls: removed)
        catalog = next
        for url in removed {
            previews.cancel(url: url)
            cancelCloudDownload(url)
        }
        if mode == .viewer && catalog.selectedFile == nil { mode = .grid }
        else if mode == .viewer { refreshViewer() }
    }

    public func undo() {
        guard var entry = undoStack.popLast() else { return }
        var restored: [ImageFile] = []
        while !entry.files.isEmpty {
            let file = entry.files.removeFirst()
            let trashURL = entry.trashURLs.removeFirst()
            do {
                try deletion.restore(TrashedFile(originalURL: file.url, trashURL: trashURL))
                restored.append(file)
            } catch {
                entry.files.insert(file, at: 0)
                entry.trashURLs.insert(trashURL, at: 0)
                undoStack.append(entry)
                if !restored.isEmpty {
                    var next = catalog
                    next.restore(restored)
                    catalog = next
                }
                statusMessage = error.localizedDescription
                return
            }
        }
        let previousSelection = catalog.selectionID
        var next = catalog
        next.restore(restored)
        catalog = next
        if mode == .compare {
            refreshCompare()
        } else if mode == .viewer {
            if catalog.selectedFile != nil {
                refreshViewer()
            } else if let previousSelection, catalog.filtered.contains(where: { $0.url == previousSelection }) {
                refreshViewer()
            } else {
                mode = .grid
            }
        }
    }

    public func removeRecent(_ url: URL) {
        recentList.remove(url)
        recentFolders = recentList.urls
        if let recentDefaults {
            recentList.save(to: recentDefaults)
        }
    }

    public func thumbnailRequest(_ file: ImageFile) {
        guard file.iCloudState != .notDownloaded else {
            requestCloudDownload(file)
            return
        }
        previews.requestThumbnail(file: file)
    }

    public func thumbnailRelease(_ file: ImageFile) {
        previews.cancelQueuedThumbnail(url: file.url)
        guard !activeCloudURLs.contains(file.url) else { return }
        guard !isCloudNeededByViewer(file.url) else { return }
        queuedCloudURLs.removeAll { $0 == file.url }
        cloudDownloadingURLs.remove(file.url)
    }

    /// 大图与对比模式下仍在使用的文件不应因网格 cell 消失而取消排队。
    private func isCloudNeededByViewer(_ url: URL) -> Bool {
        if mode == .viewer, catalog.selectedFile?.url == url { return true }
        if mode == .compare, compareFiles.contains(where: { $0.url == url }) { return true }
        return false
    }

    public func isCloudDownloading(_ url: URL) -> Bool {
        cloudDownloadingURLs.contains(url)
    }

    /// 可见的未下载文件自动请求下载，完成后轮询状态并补做解码。
    private func requestCloudDownload(_ file: ImageFile) {
        let url = file.url
        guard file.iCloudState == .notDownloaded else { return }
        guard !cloudDownloadingURLs.contains(url) else { return }
        // 状态可能已被访达或网盘客户端刷新，先复查再决定是否需要下载。
        if let state = cloudDownloader.state(of: url), state != .notDownloaded {
            applyDownloadedState(url)
            return
        }
        cloudDownloadingURLs.insert(url)
        if activeCloudURLs.count < cloudDownloadLimit {
            startCloudDownload(url)
        } else {
            queuedCloudURLs.append(url)
        }
        ensureCloudPolling()
    }

    private func startCloudDownload(_ url: URL) {
        cloudStartedAt[url] = Date()
        guard cloudDownloader.requestDownload(url: url) else {
            abandonCloudDownload(url)
            return
        }
        activeCloudURLs.insert(url)
    }

    private func abandonCloudDownload(_ url: URL) {
        activeCloudURLs.remove(url)
        queuedCloudURLs.removeAll { $0 == url }
        cloudDownloadingURLs.remove(url)
        cloudStartedAt.removeValue(forKey: url)
        fillCloudSlots()
    }

    /// 空出并发槽位后启动排队中的下载。
    private func fillCloudSlots() {
        while activeCloudURLs.count < cloudDownloadLimit, !queuedCloudURLs.isEmpty {
            let url = queuedCloudURLs.removeFirst()
            guard cloudDownloadingURLs.contains(url) else { continue }
            startCloudDownload(url)
        }
    }

    /// 轮询一次下载状态；测试可直接调用，无需等待定时器。
    func pollCloudDownloads() {
        let now = Date()
        for url in activeCloudURLs {
            guard let state = cloudDownloader.state(of: url) else { continue }
            if state != .notDownloaded {
                finishCloudDownload(url)
            } else if let started = cloudStartedAt[url], now.timeIntervalSince(started) > cloudDownloadTimeout {
                abandonCloudDownload(url)
            }
        }
        fillCloudSlots()
        if cloudDownloadingURLs.isEmpty {
            cloudPollTask?.cancel()
            cloudPollTask = nil
        }
    }

    private func finishCloudDownload(_ url: URL) {
        activeCloudURLs.remove(url)
        cloudStartedAt.removeValue(forKey: url)
        cloudDownloadingURLs.remove(url)
        applyDownloadedState(url)
        fillCloudSlots()
    }

    /// 下载完成后把新状态写回目录，重新请求缩略图，并刷新大图/对比。
    private func applyDownloadedState(_ url: URL) {
        var updatedFile: ImageFile?
        var next = catalog
        if let index = next.files.firstIndex(where: { $0.url == url }) {
            next.files[index].iCloudState = .downloaded
            updatedFile = next.files[index]
            catalog = next
        }
        if let index = compareFiles.firstIndex(where: { $0.url == url }) {
            var nextCompare = compareFiles
            nextCompare[index].iCloudState = .downloaded
            compareFiles = nextCompare
            if let size = imageIO.pixelSize(url: url) {
                compareSourceSizes[url] = size
            }
        }
        guard let updatedFile else { return }
        previews.requestThumbnail(file: updatedFile)
        if mode == .viewer, catalog.selectedFile?.url == url {
            refreshViewer()
        } else if mode == .compare, compareFiles.contains(where: { $0.url == url }) {
            refreshCompareImages()
        }
    }

    private func ensureCloudPolling() {
        guard cloudPollTask == nil, !cloudDownloadingURLs.isEmpty else { return }
        cloudPollTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, !self.cloudDownloadingURLs.isEmpty {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.pollCloudDownloads()
            }
            self?.cloudPollTask = nil
        }
    }

    private func resetCloudDownloads() {
        cloudPollTask?.cancel()
        cloudPollTask = nil
        cloudDownloadingURLs.removeAll()
        activeCloudURLs.removeAll()
        queuedCloudURLs.removeAll()
        cloudStartedAt.removeAll()
    }

    private func cancelCloudDownload(_ url: URL) {
        if activeCloudURLs.contains(url) {
            abandonCloudDownload(url)
        } else {
            queuedCloudURLs.removeAll { $0 == url }
            cloudDownloadingURLs.remove(url)
        }
    }

    public func noteUnavailable(_ url: URL) {
        guard previews.didFail(url: url) else { return }
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        guard catalog.files.contains(where: { $0.url == url }) else { return }
        var next = catalog
        _ = next.remove(urls: [url])
        catalog = next
        if mode == .compare {
            refreshCompare()
        } else if mode == .viewer && catalog.selectedFile == nil {
            mode = .grid
        } else if mode == .viewer {
            refreshViewer()
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

    private func reclampPan() {
        guard let layout = viewerLayout else { return }
        pan = ImagePan.clamped(
            x: pan.x,
            y: pan.y,
            contentWidth: layout.contentWidth,
            contentHeight: layout.contentHeight,
            viewportWidth: layout.viewportWidth,
            viewportHeight: layout.viewportHeight
        )
    }

    private func leaveViewerIfNeeded() {
        if mode == .viewer && catalog.selectedFile == nil {
            compareReturn = nil
            mode = .grid
        } else if mode == .compare {
            refreshCompare()
        }
    }

    private func refreshViewer() {
        guard let current = catalog.selectedFile else { return }
        rememberViewerSourceSize(for: current.url)
        let items = catalog.filtered
        let index = items.firstIndex(where: { $0.url == current.url })
        let previous = index.flatMap { $0 > 0 ? items[$0 - 1] : nil }
        let next = index.flatMap { $0 + 1 < items.count ? items[$0 + 1] : nil }
        for file in [current] + [previous, next].compactMap({ $0 }) where file.iCloudState == .notDownloaded {
            requestCloudDownload(file)
        }
        let pixels = PreviewMaxPixel.viewer(zoom: zoom, screenLongEdge: screenLongEdge)
        previews.showViewer(current: current, previous: previous, next: next, maxPixelSize: pixels)
    }

    private func rememberViewerSourceSize(for url: URL) {
        if viewerSourceURL == url, viewerSourceSize != nil { return }
        guard let file = catalog.files.first(where: { $0.url == url }),
              file.iCloudState != .notDownloaded else { return }
        viewerSourceURL = url
        viewerSourceSize = imageIO.pixelSize(url: url)
    }
}
