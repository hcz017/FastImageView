import Foundation

public struct CopySet: Equatable, Sendable {
    public var imageURL: URL
    public var paths: [String]

    public init(imageURL: URL, paths: [String]) {
        self.imageURL = imageURL
        self.paths = paths
    }
}

public enum CopyRouting {
    /// Right-click copies the clicked image. Paths include the whole selection when the click is inside it.
    public static func make(clicked: URL, orderedSelection: [URL]) -> CopySet {
        let source = orderedSelection.contains(clicked) && orderedSelection.count > 1 ? orderedSelection : [clicked]
        return CopySet(imageURL: clicked, paths: source.map(\.path))
    }
}
