import AppKit

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
