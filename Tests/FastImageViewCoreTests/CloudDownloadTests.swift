import XCTest
import CoreGraphics
@testable import FastImageViewCore

private final class CloudScanner: FolderScanning {
    var files: [ImageFile] = []
    func scan(folder: URL) throws -> [ImageFile] { files }
}

private final class CloudPipeline: PreviewPipeline {
    var generation = 0
    var onGenerationChange: (() -> Void)?
    var thumbnailRequests: [URL] = []
    var viewerCurrents: [URL] = []
    func reset() {}
    func cancel(url: URL) {}
    func requestThumbnail(file: ImageFile) { thumbnailRequests.append(file.url) }
    func cancelQueuedThumbnail(url: URL) {}
    func showViewer(current: ImageFile, previous: ImageFile?, next: ImageFile?, maxPixelSize: Int) {
        viewerCurrents.append(current.url)
    }
    func cachedThumbnail(file: ImageFile) -> CGImage? { nil }
    func cachedViewerImage(file: ImageFile) -> CGImage? { nil }
    func didFail(url: URL) -> Bool { false }
}

private final class FakeCloudDownloader: CloudDownloading {
    var requested: [URL] = []
    var states: [URL: ICloudState] = [:]
    var rejectsRequests = false
    func requestDownload(url: URL) -> Bool {
        guard !rejectsRequests else { return false }
        requested.append(url)
        return true
    }
    func state(of url: URL) -> ICloudState? { states[url] }
}

private final class EmptyTrash: TrashStorage {
    func exists(_ url: URL) -> Bool { false }
    func trash(at url: URL) throws -> URL { throw CocoaError(.fileNoSuchFile) }
    func move(from: URL, to: URL) throws {}
}

@MainActor
final class CloudDownloadTests: XCTestCase {
    private func file(_ name: String, state: ICloudState = .notDownloaded) -> ImageFile {
        ImageFile(
            url: URL(fileURLWithPath: "/pics/\(name)"),
            filename: name,
            format: .jpeg,
            modificationDate: .distantPast,
            iCloudState: state
        )
    }

    private func makeModel(files: [ImageFile]) -> (BrowserModel, CloudPipeline, FakeCloudDownloader) {
        let scanner = CloudScanner()
        scanner.files = files
        let pipeline = CloudPipeline()
        let downloader = FakeCloudDownloader()
        let model = BrowserModel(
            scanner: scanner,
            deletion: DeletionService(storage: EmptyTrash()),
            previews: pipeline,
            cloudDownloader: downloader
        )
        return (model, pipeline, downloader)
    }

    private func open(_ model: BrowserModel, files: [ImageFile], selecting: URL? = nil) {
        let token = model.beginOpening(folder: URL(fileURLWithPath: "/pics"), selecting: selecting)
        model.acceptScan(generation: token, outcome: .success(files))
    }

    func testThumbnailRequestStartsCloudDownload() {
        let pending = file("a.jpg")
        let (model, pipeline, downloader) = makeModel(files: [pending])
        model.thumbnailRequest(pending)
        XCTAssertEqual(downloader.requested, [pending.url])
        XCTAssertTrue(model.isCloudDownloading(pending.url))
        XCTAssertTrue(pipeline.thumbnailRequests.isEmpty)
    }

    func testDownloadCompletionUpdatesStateAndQueuesDecode() {
        let pending = file("a.jpg")
        let (model, pipeline, downloader) = makeModel(files: [pending])
        open(model, files: [pending])
        model.thumbnailRequest(pending)

        downloader.states[pending.url] = .downloaded
        model.pollCloudDownloads()

        XCTAssertEqual(model.catalog.files.first?.iCloudState, .downloaded)
        XCTAssertEqual(pipeline.thumbnailRequests, [pending.url])
        XCTAssertFalse(model.isCloudDownloading(pending.url))
    }

    func testDownloadsAreCappedAndQueued() {
        let files = (0..<5).map { file("\($0).jpg") }
        let (model, _, downloader) = makeModel(files: files)
        open(model, files: files)
        for item in files { model.thumbnailRequest(item) }

        XCTAssertEqual(downloader.requested, Array(files.prefix(4).map(\.url)))
        XCTAssertTrue(files.allSatisfy { model.isCloudDownloading($0.url) })

        for item in files.prefix(4) {
            downloader.states[item.url] = .downloaded
        }
        model.pollCloudDownloads()
        XCTAssertEqual(downloader.requested.count, 5)
    }

    func testReleaseDropsQueuedDownload() {
        let files = (0..<5).map { file("\($0).jpg") }
        let (model, _, downloader) = makeModel(files: files)
        open(model, files: files)
        for item in files { model.thumbnailRequest(item) }

        model.thumbnailRelease(files[4])
        XCTAssertFalse(model.isCloudDownloading(files[4].url))
        XCTAssertEqual(downloader.requested.count, 4)

        for item in files.prefix(4) {
            downloader.states[item.url] = .downloaded
        }
        model.pollCloudDownloads()
        XCTAssertEqual(downloader.requested.count, 4)
    }

    func testRejectedDownloadKeepsPlaceholderState() {
        let pending = file("a.jpg")
        let (model, _, downloader) = makeModel(files: [pending])
        downloader.rejectsRequests = true
        model.thumbnailRequest(pending)
        XCTAssertFalse(model.isCloudDownloading(pending.url))
        XCTAssertTrue(downloader.requested.isEmpty)
    }

    func testAlreadyDownloadedFileSkipsRequest() {
        let pending = file("a.jpg")
        let (model, pipeline, downloader) = makeModel(files: [pending])
        open(model, files: [pending])
        downloader.states[pending.url] = .downloaded

        model.thumbnailRequest(pending)

        XCTAssertTrue(downloader.requested.isEmpty)
        XCTAssertFalse(model.isCloudDownloading(pending.url))
        XCTAssertEqual(model.catalog.files.first?.iCloudState, .downloaded)
        XCTAssertEqual(pipeline.thumbnailRequests, [pending.url])
    }

    func testOpeningViewerRequestsDownloadForCurrentImage() {
        let files = [file("a.jpg"), file("b.jpg"), file("c.jpg")]
        let (model, pipeline, downloader) = makeModel(files: files)
        open(model, files: files, selecting: files[1].url)

        XCTAssertTrue(downloader.requested.contains(files[1].url))
        XCTAssertTrue(model.isCloudDownloading(files[1].url))
        XCTAssertEqual(pipeline.viewerCurrents, [files[1].url])
    }
}
