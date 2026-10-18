import XCTest
@testable import FastImageViewCore

private final class ScriptedScanner: FolderScanning {
    var result: Result<[ImageFile], Error> = .success([])
    func scan(folder: URL) throws -> [ImageFile] {
        try result.get()
    }
}

private final class RecordingPipeline: PreviewPipeline {
    var generation = 0
    var onGenerationChange: (() -> Void)?
    var resetCount = 0
    var cancelled: [URL] = []
    var viewerCurrents: [URL] = []
    var viewerPixelSizes: [Int] = []
    var thumbnailRequests: [URL] = []
    func reset() { resetCount += 1 }
    func cancel(url: URL) { cancelled.append(url) }
    func requestThumbnail(file: ImageFile) { thumbnailRequests.append(file.url) }
    func cancelQueuedThumbnail(url: URL) {}
    var failedURLs: Set<URL> = []
    func showViewer(current: ImageFile, previous: ImageFile?, next: ImageFile?, maxPixelSize: Int) {
        viewerCurrents.append(current.url)
        viewerPixelSizes.append(maxPixelSize)
    }
    func cachedThumbnail(file: ImageFile) -> CGImage? { nil }
    func cachedViewerImage(file: ImageFile) -> CGImage? { nil }
    func didFail(url: URL) -> Bool { failedURLs.contains(url) }
}

private final class ModelTrash: TrashStorage {
    var files: Set<String>
    init(files: Set<String>) { self.files = files }
    func exists(_ url: URL) -> Bool { files.contains(url.path) }
    func trash(at url: URL) throws -> URL {
        guard files.remove(url.path) != nil else { throw CocoaError(.fileNoSuchFile) }
        let dest = URL(fileURLWithPath: "/trash/\(url.lastPathComponent)")
        files.insert(dest.path)
        return dest
    }
    func move(from: URL, to: URL) throws {
        guard files.remove(from.path) != nil else { throw CocoaError(.fileNoSuchFile) }
        files.insert(to.path)
    }
}

@MainActor
final class BrowserModelTests: XCTestCase {
    private func file(_ name: String, format: ImageFormat = .jpeg) -> ImageFile {
        ImageFile(url: URL(fileURLWithPath: "/pics/\(name)"), filename: name, format: format, modificationDate: .distantPast, iCloudState: .notCloud)
    }

    private func model(files: [ImageFile]) -> (BrowserModel, RecordingPipeline, ModelTrash) {
        let scanner = ScriptedScanner()
        scanner.result = .success(files)
        let pipeline = RecordingPipeline()
        let trash = ModelTrash(files: Set(files.map(\.url.path)))
        let model = BrowserModel(scanner: scanner, deletion: DeletionService(storage: trash), previews: pipeline)
        return (model, pipeline, trash)
    }

    func testStaleScanDoesNotReplaceNewerFolder() {
        let scanner = ScriptedScanner()
        let pipeline = RecordingPipeline()
        let model = BrowserModel(scanner: scanner, deletion: DeletionService(storage: ModelTrash(files: [])), previews: pipeline)
        let old = model.beginOpen()
        let newer = model.beginOpen()
        model.acceptScan(generation: old, outcome: .success([file("old.jpg")]))
        XCTAssertNil(model.folderURL)
        model.pendingFolderURL = URL(fileURLWithPath: "/new")
        model.acceptScan(generation: newer, outcome: .success([file("new.jpg")]))
        XCTAssertEqual(model.catalog.files.map(\.filename), ["new.jpg"])
        XCTAssertEqual(model.folderURL, URL(fileURLWithPath: "/new"))
    }

    func testDeleteThenUndoRestoresSelectionInsideFilter() {
        let (model, pipeline, _) = model(files: [file("a.jpg"), file("b.jpg"), file("c.jpg")])
        let generation = model.beginOpen()
        model.pendingFolderURL = URL(fileURLWithPath: "/pics")
        model.acceptScan(generation: generation, outcome: .success([file("a.jpg"), file("b.jpg"), file("c.jpg")]))
        model.deleteSelected()
        XCTAssertEqual(model.catalog.selectedFile?.filename, "b.jpg")
        XCTAssertEqual(pipeline.cancelled.count, 1)
        model.undo()
        XCTAssertEqual(model.catalog.selectedFile?.filename, "a.jpg")
        XCTAssertEqual(model.catalog.files.count, 3)
    }

    func testUndoKeepsSelectionWhenRestoredFileIsFilteredOut() {
        let files = [file("a.jpg"), file("b.nef", format: .nef)]
        let (model, _, _) = model(files: files)
        let generation = model.beginOpen()
        model.pendingFolderURL = URL(fileURLWithPath: "/pics")
        model.acceptScan(generation: generation, outcome: .success(files))
        model.deleteSelected()
        model.toggleFormat(.nef)
        model.undo()
        XCTAssertEqual(model.catalog.selectedFile?.filename, "b.nef")
        XCTAssertTrue(model.catalog.files.contains(where: { $0.filename == "a.jpg" }))
    }

    func testFailedOpenKeepsCurrentFolder() {
        let scanner = ScriptedScanner()
        let model = BrowserModel(scanner: scanner, deletion: DeletionService(storage: ModelTrash(files: [])), previews: RecordingPipeline())
        let first = model.beginOpen()
        model.pendingFolderURL = URL(fileURLWithPath: "/ok")
        model.acceptScan(generation: first, outcome: .success([file("a.jpg")]))
        let second = model.beginOpen()
        model.pendingFolderURL = URL(fileURLWithPath: "/bad")
        model.acceptScan(generation: second, outcome: .failure(CocoaError(.fileReadNoPermission)))
        XCTAssertEqual(model.folderURL, URL(fileURLWithPath: "/ok"))
        XCTAssertEqual(model.catalog.files.map(\.filename), ["a.jpg"])
        XCTAssertNotNil(model.statusMessage)
    }

    func testNotDownloadedSkipsThumbnailQueue() {
        let pending = ImageFile(url: URL(fileURLWithPath: "/pics/c.jpg"), filename: "c.jpg", format: .jpeg, modificationDate: .distantPast, iCloudState: .notDownloaded)
        let (model, pipeline, _) = model(files: [pending])
        model.thumbnailRequest(pending)
        XCTAssertTrue(pipeline.thumbnailRequests.isEmpty)
    }

    func testMissingFileIsRemovedWithoutUndo() {
        let files = [file("a.jpg"), file("b.jpg")]
        let (model, pipeline, _) = model(files: files)
        let generation = model.beginOpen()
        model.pendingFolderURL = URL(fileURLWithPath: "/pics")
        model.acceptScan(generation: generation, outcome: .success(files))
        pipeline.failedURLs.insert(files[0].url)
        model.noteUnavailable(files[0].url)
        XCTAssertEqual(model.catalog.selectedFile?.filename, "b.jpg")
        model.undo()
        XCTAssertEqual(model.catalog.files.map(\.filename), ["b.jpg"])
    }

    func testOpenFileSelectsThatImageInTheViewer() {
        let files = [file("a.jpg"), file("b.jpg")]
        let (model, pipeline, _) = model(files: files)
        let generation = model.beginOpening(
            folder: URL(fileURLWithPath: "/pics"),
            selecting: files[1].url,
            screenLongEdge: 1800
        )
        model.acceptScan(generation: generation, outcome: .success(files))
        XCTAssertEqual(model.mode, .viewer)
        XCTAssertEqual(model.catalog.selectedFile?.filename, "b.jpg")
        XCTAssertEqual(pipeline.viewerCurrents, [files[1].url])
    }

    func testRefreshRemovesDeletedFileAndFollowsRename() {
        let files = [file("a.jpg"), file("b.jpg")]
        let (model, pipeline, _) = model(files: files)
        let generation = model.beginOpen()
        model.pendingFolderURL = URL(fileURLWithPath: "/pics")
        model.acceptScan(generation: generation, outcome: .success(files))
        model.setKeyword("jpg")
        model.applyFolderListing(
            files,
            identityByPath: [
                files[0].url.path: "same",
                files[1].url.path: "other"
            ]
        )
        let renamed = ImageFile(
            url: URL(fileURLWithPath: "/pics/a-renamed.jpg"),
            filename: "a-renamed.jpg",
            format: .jpeg,
            modificationDate: .distantPast,
            iCloudState: .notCloud
        )
        model.applyFolderListing(
            [renamed, files[1]],
            identityByPath: [
                renamed.url.path: "same",
                files[1].url.path: "other"
            ]
        )
        XCTAssertEqual(model.catalog.keyword, "jpg")
        XCTAssertEqual(model.catalog.selectedFile?.filename, "a-renamed.jpg")
        XCTAssertEqual(pipeline.cancelled, [files[0].url])
    }

    func testScanningFlagFollowsTheLatestGeneration() {
        let (model, _, _) = model(files: [])
        let old = model.beginOpening(folder: URL(fileURLWithPath: "/old"))
        XCTAssertTrue(model.isScanning)
        let new = model.beginOpening(folder: URL(fileURLWithPath: "/new"))
        model.acceptScan(generation: old, outcome: .success([]))
        XCTAssertTrue(model.isScanning)
        model.acceptScan(generation: new, outcome: .success([]))
        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.folderURL, URL(fileURLWithPath: "/new"))
    }

    func testListingRevisionOnlyChangesWhenFilesChange() {
        let files = [file("a.jpg"), file("b.jpg")]
        let (model, _, _) = model(files: files)
        let generation = model.beginOpen()
        model.pendingFolderURL = URL(fileURLWithPath: "/pics")
        model.acceptScan(generation: generation, outcome: .success(files))
        let revision = model.listingRevision

        model.applyFolderListing(files, identityByPath: [:])
        XCTAssertEqual(model.listingRevision, revision)

        model.applyFolderListing(files + [file("c.jpg")], identityByPath: [:])
        XCTAssertEqual(model.listingRevision, revision + 1)
    }

    func testLeavingFitRequestsAFullSizeDecode() {
        let files = [file("a.jpg")]
        let (model, pipeline, _) = model(files: files)
        let generation = model.beginOpening(folder: URL(fileURLWithPath: "/pics"), selecting: files[0].url, screenLongEdge: 1800)
        model.acceptScan(generation: generation, outcome: .success(files))
        XCTAssertEqual(pipeline.viewerPixelSizes, [1800])
        model.noteViewerLayout(ViewerLayout(contentWidth: 100, contentHeight: 80, viewportWidth: 200, viewportHeight: 160, fitScale: 0.5))
        model.zoom(by: ZoomMath.step, screenLongEdge: 1800)
        XCTAssertEqual(pipeline.viewerPixelSizes.last, 16384)
        XCTAssertEqual(model.zoom, .multiple(1.25))
    }

    func testDragPanClampsAndFitClearsIt() {
        let (model, _, _) = model(files: [])
        model.noteViewerLayout(ViewerLayout(contentWidth: 400, contentHeight: 200, viewportWidth: 300, viewportHeight: 200, fitScale: 1))
        model.setZoomMultiple(2, screenLongEdge: 1800)
        model.setPan(x: 1000, y: 10)
        XCTAssertEqual(model.pan.x, 50)
        model.setZoomMultiple(1, screenLongEdge: 1800)
        XCTAssertEqual(model.pan, .zero)
        XCTAssertEqual(model.zoom, .fit)
    }

    func testRenderGenerationFollowsPipelineChanges() {
        let (model, pipeline, _) = model(files: [])
        XCTAssertEqual(model.renderGeneration, 0)
        pipeline.generation = 7
        pipeline.onGenerationChange?()
        XCTAssertEqual(model.renderGeneration, 7)
    }
}
