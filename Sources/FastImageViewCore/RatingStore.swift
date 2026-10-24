import Foundation

/// 分级持久化接口：键为文件标准路径，值为 1...5 的等级。
public protocol RatingStoring: Sendable {
    func load() -> [String: Int]
    func save(_ ratings: [String: Int])
}

public struct UserDefaultsRatingStore: RatingStoring, @unchecked Sendable {
    public static let storageKey = "FastImageView.ratings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [String: Int] {
        guard let raw = defaults.dictionary(forKey: Self.storageKey) else { return [:] }
        return Self.validated(raw.compactMapValues { ($0 as? NSNumber)?.intValue })
    }

    public func save(_ ratings: [String: Int]) {
        let valid = Self.validated(ratings)
        if valid.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(valid, forKey: Self.storageKey)
        }
    }

    private static func validated(_ ratings: [String: Int]) -> [String: Int] {
        ratings.filter { (1...5).contains($0.value) }
    }
}

/// 测试替身：与 `IdleFolderWatch` 一样，提供一个不做持久化的实现。
public final class InMemoryRatingStore: RatingStoring, @unchecked Sendable {
    public private(set) var ratings: [String: Int]

    public init(ratings: [String: Int] = [:]) {
        self.ratings = ratings
    }

    public func load() -> [String: Int] {
        ratings
    }

    public func save(_ ratings: [String: Int]) {
        self.ratings = ratings
    }
}
