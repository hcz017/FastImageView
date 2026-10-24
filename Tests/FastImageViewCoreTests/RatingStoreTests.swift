import XCTest
@testable import FastImageViewCore

final class RatingStoreTests: XCTestCase {
    func testUserDefaultsRoundTripDropsInvalidValues() {
        let suite = "RatingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsRatingStore(defaults: defaults)

        store.save(["/a": 3, "/b": 0, "/c": 6, "/d": -1])
        XCTAssertEqual(store.load(), ["/a": 3])

        store.save([:])
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertNil(defaults.dictionary(forKey: UserDefaultsRatingStore.storageKey))
    }

    func testInMemoryStoreRoundTrip() {
        let store = InMemoryRatingStore()
        XCTAssertTrue(store.load().isEmpty)

        store.save(["/a": 5])
        XCTAssertEqual(store.load(), ["/a": 5])
        XCTAssertEqual(store.ratings, ["/a": 5])
    }
}
