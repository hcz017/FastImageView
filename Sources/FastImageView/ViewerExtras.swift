import AppKit
import SwiftUI
import FastImageViewCore

@MainActor
final class GIFClip: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var frames: [CGImage] = []
    @Published private(set) var delays: [Double] = []

    func clear() {
        url = nil
        frames = []
        delays = []
    }

    func load(url: URL, maxPixelSize: Int) {
        self.url = url
        frames = []
        delays = []
        Task.detached(priority: .userInitiated) {
            let decoded = GIFDecoder.decode(url: url, maxPixelSize: maxPixelSize)
            await MainActor.run {
                guard self.url == url else { return }
                self.frames = decoded?.frames ?? []
                self.delays = decoded?.delays ?? []
            }
        }
    }
}

enum SearchFieldFinder {
    static func find(in window: NSWindow) -> NSTextField? {
        var root: NSView? = window.contentView
        while let parent = root?.superview { root = parent }
        return root.flatMap(searchField(in:))
    }

    private static func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSSearchField { return field }
        if let field = view as? NSTextField {
            let placeholder = field.placeholderString ?? field.placeholderAttributedString?.string ?? ""
            if placeholder.contains("搜索") { return field }
        }
        for subview in view.subviews {
            if let found = searchField(in: subview) { return found }
        }
        return nil
    }
}
