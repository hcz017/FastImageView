import Foundation

public struct ImageCatalog: Equatable, Sendable {
    public var files: [ImageFile]
    public var keyword: String
    public var selectedFormats: Set<ImageFormat>
    public var selectionID: URL?

    public init() {
        files = []
        keyword = ""
        selectedFormats = []
        selectionID = nil
    }

    public var filtered: [ImageFile] {
        files.filter { file in
            let keywordOK = keyword.isEmpty || file.filename.localizedCaseInsensitiveContains(keyword)
            let formatOK = selectedFormats.isEmpty || selectedFormats.contains(file.format)
            return keywordOK && formatOK
        }
    }

    public var availableFormats: [ImageFormat] {
        let present = Set(files.map(\.format))
        return ImageFormat.allCases.filter { present.contains($0) }
    }

    public var selectedFile: ImageFile? {
        guard let selectionID else { return nil }
        return filtered.first { $0.url == selectionID }
    }

    public mutating func replaceFiles(_ files: [ImageFile]) {
        self.files = files
        keyword = ""
        selectedFormats = []
        selectionID = files.first?.url
    }

    public mutating func clampSelection() {
        if let selectionID, filtered.contains(where: { $0.url == selectionID }) { return }
        selectionID = filtered.first?.url
    }

    public mutating func moveSelection(by delta: Int) {
        let items = filtered
        guard let selectionID, let index = items.firstIndex(where: { $0.url == selectionID }) else { return }
        let next = index + delta
        guard items.indices.contains(next) else { return }
        self.selectionID = items[next].url
    }

    @discardableResult
    public mutating func removeSelected() -> ImageFile? {
        let items = filtered
        guard let selectionID, let index = items.firstIndex(where: { $0.url == selectionID }) else { return nil }
        let removed = items[index]
        files.removeAll { $0.url == removed.url }
        let remaining = filtered
        if remaining.isEmpty {
            self.selectionID = nil
        } else if index < remaining.count {
            self.selectionID = remaining[index].url
        } else {
            self.selectionID = remaining[remaining.count - 1].url
        }
        return removed
    }

    public mutating func restore(_ file: ImageFile) {
        let previous = selectionID
        files.append(file)
        files.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        if filtered.contains(where: { $0.url == file.url }) {
            selectionID = file.url
        } else if let previous, filtered.contains(where: { $0.url == previous }) {
            selectionID = previous
        } else {
            selectionID = filtered.first?.url
        }
    }
}
