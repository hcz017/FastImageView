import XCTest
@testable import FastImageViewCore

final class RecentFolderListTests: XCTestCase {
    func testRememberPutsNewestFirstAndDropsPastEight() {
        var list = RecentFolderList()
        for index in 0..<9 {
            list.remember(URL(fileURLWithPath: "/pics/\(index)"))
        }
        XCTAssertEqual(list.paths.count, 8)
        XCTAssertEqual(list.paths.first, "/pics/8")
        XCTAssertFalse(list.paths.contains("/pics/0"))
    }

    func testRememberMovesDuplicateToFront() {
        var list = RecentFolderList()
        list.remember(URL(fileURLWithPath: "/pics/a"))
        list.remember(URL(fileURLWithPath: "/pics/b"))
        list.remember(URL(fileURLWithPath: "/pics/a/"))
        XCTAssertEqual(list.paths, ["/pics/a", "/pics/b"])
    }

    func testRoundTripThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "RecentFolderListTests")!
        defaults.removePersistentDomain(forName: "RecentFolderListTests")
        var list = RecentFolderList()
        list.remember(URL(fileURLWithPath: "/pics/a"))
        list.save(to: defaults)
        let loaded = RecentFolderList(defaults: defaults)
        XCTAssertEqual(loaded.paths, ["/pics/a"])
    }
}

@MainActor
final class RecentFolderBrowserTests: XCTestCase {
    func testSuccessfulOpenRemembersFolderAndFailedOpenDoesNot() {
        let model = BrowserModel(
            scanner: ScriptedRecentScanner(),
            deletion: DeletionService(storage: EmptyTrash()),
            previews: EmptyPipeline()
        )
        let failed = model.beginOpen()
        model.pendingFolderURL = URL(fileURLWithPath: "/missing")
        model.acceptScan(generation: failed, outcome: .failure(CocoaError(.fileReadNoPermission)))
        XCTAssertEqual(model.recentFolders, [])

        let opened = model.beginOpen()
        model.pendingFolderURL = URL(fileURLWithPath: "/pics")
        model.acceptScan(generation: opened, outcome: .success([]))
        XCTAssertEqual(model.recentFolders.map(\.path), ["/pics"])
    }
}

private final class ScriptedRecentScanner: FolderScanning {
    var error: Error?
    func scan(folder: URL) throws -> [ImageFile] {
        if let error { throw error }
        return []
    }
}

private final class EmptyTrash: TrashStorage {
    func exists(_ url: URL) -> Bool { false }
    func trash(at url: URL) throws -> URL { url }
    func move(from: URL, to: URL) throws {}
}

private final class EmptyPipeline: PreviewPipeline {
    var generation = 0
    func reset() {}
    func cancel(url: URL) {}
    func requestThumbnail(file: ImageFile) {}
    func cancelQueuedThumbnail(url: URL) {}
    func showViewer(current: ImageFile, previous: ImageFile?, next: ImageFile?, maxPixelSize: Int) {}
    func cachedThumbnail(file: ImageFile) -> CGImage? { nil }
    func cachedViewerImage(file: ImageFile) -> CGImage? { nil }
    func didFail(url: URL) -> Bool { false }
}
