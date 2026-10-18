import Foundation

public enum SelectionGesture: Equatable, Sendable {
    case only
    case toggle
    case extend
}

public struct ImageCatalog: Equatable, Sendable {
    public var files: [ImageFile]
    public var keyword: String
    public var selectedFormats: Set<ImageFormat>
    public var selectionID: URL?
    public var selectionIDs: Set<URL>
    public var selectionAnchor: URL?

    public init() {
        files = []
        keyword = ""
        selectedFormats = []
        selectionID = nil
        selectionIDs = []
        selectionAnchor = nil
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

    public var deletionTargets: [ImageFile] {
        let ids = activeSelectionIDs
        return filtered.filter { ids.contains($0.url) }
    }

    private var activeSelectionIDs: Set<URL> {
        if !selectionIDs.isEmpty { return selectionIDs }
        if let selectionID { return [selectionID] }
        return []
    }

    public mutating func refresh(with files: [ImageFile], renamedSelection: URL? = nil) {
        let previousID = selectionID
        let previousIDs = selectionIDs
        let previousAnchor = selectionAnchor
        let previousItems = filtered
        let previousIndex = previousID.flatMap { id in previousItems.firstIndex { $0.url == id } }
        self.files = files
        let surviving = Set(files.map(\.url))
        if let previousID, surviving.contains(previousID) {
            selectionID = previousID
            if !previousIDs.isEmpty {
                selectionIDs = previousIDs.intersection(surviving)
            }
            clampSelection()
            return
        }
        if let renamedSelection, surviving.contains(renamedSelection) {
            selectionID = renamedSelection
            if !previousIDs.isEmpty {
                var ids = previousIDs.intersection(surviving)
                if let previousID { ids.remove(previousID) }
                ids.insert(renamedSelection)
                selectionIDs = ids
                selectionAnchor = previousAnchor == previousID ? renamedSelection : previousAnchor
            }
            clampSelection()
            return
        }
        let items = filtered
        if items.isEmpty {
            selectionID = nil
            selectionIDs = []
            selectionAnchor = nil
        } else if let previousIndex, previousIndex < items.count {
            selectionID = items[previousIndex].url
            selectionIDs = [items[previousIndex].url]
            selectionAnchor = selectionID
        } else {
            selectionID = items[items.count - 1].url
            selectionIDs = selectionID.map { [$0] } ?? []
            selectionAnchor = selectionID
        }
    }

    public mutating func replaceFiles(_ files: [ImageFile]) {
        self.files = files
        keyword = ""
        selectedFormats = []
        selectionID = files.first?.url
        selectionIDs = selectionID.map { [$0] } ?? []
        selectionAnchor = selectionID
    }

    public mutating func clampSelection() {
        let visible = Set(filtered.map(\.url))
        if !selectionIDs.isEmpty {
            selectionIDs.formIntersection(visible)
        }
        if let selectionID, visible.contains(selectionID) { return }
        if let next = filtered.first(where: { selectionIDs.contains($0.url) })?.url ?? filtered.first?.url {
            selectionID = next
        } else {
            selectionID = nil
            selectionIDs = []
            selectionAnchor = nil
        }
    }

    public mutating func applySelection(url: URL, gesture: SelectionGesture) {
        let items = filtered
        guard items.contains(where: { $0.url == url }) else { return }
        switch gesture {
        case .only:
            selectionIDs = [url]
            selectionID = url
            selectionAnchor = url
        case .toggle:
            var ids = activeSelectionIDs
            if ids.contains(url) {
                ids.remove(url)
                selectionIDs = ids
                if ids.isEmpty {
                    selectionID = nil
                    selectionAnchor = nil
                } else if !(selectionID.map(ids.contains) ?? false) {
                    selectionID = items.last(where: { ids.contains($0.url) })?.url
                    if selectionAnchor == nil || !(selectionAnchor.map(ids.contains) ?? false) {
                        selectionAnchor = selectionID
                    }
                }
            } else {
                ids.insert(url)
                selectionIDs = ids
                selectionID = url
                if selectionAnchor == nil { selectionAnchor = url }
            }
        case .extend:
            let anchor = selectionAnchor ?? selectionID ?? url
            guard let start = items.firstIndex(where: { $0.url == anchor }),
                  let end = items.firstIndex(where: { $0.url == url }) else {
                applySelection(url: url, gesture: .only)
                return
            }
            let slice = items[min(start, end)...max(start, end)]
            selectionIDs = Set(slice.map(\.url))
            selectionID = url
            selectionAnchor = anchor
        }
    }

    public mutating func moveSelection(by delta: Int) {
        let items = filtered
        guard let selectionID, let index = items.firstIndex(where: { $0.url == selectionID }) else { return }
        let next = index + delta
        guard items.indices.contains(next) else { return }
        selectOnly(items[next].url)
    }

    private mutating func selectOnly(_ url: URL) {
        selectionID = url
        selectionIDs = [url]
        selectionAnchor = url
    }

    @discardableResult
    public mutating func removeSelected() -> [ImageFile] {
        remove(urls: activeSelectionIDs)
    }

    @discardableResult
    public mutating func remove(urls: Set<URL>) -> [ImageFile] {
        let items = filtered
        let indexes = items.indices.filter { urls.contains(items[$0].url) }
        guard let last = indexes.last else { return [] }
        let removed = indexes.map { items[$0] }
        files.removeAll { urls.contains($0.url) }
        let remaining = filtered
        if remaining.isEmpty {
            selectionID = nil
            selectionIDs = []
            selectionAnchor = nil
        } else {
            let following = last + 1 - indexes.count
            let next = remaining.indices.contains(following) ? remaining[following].url : remaining[remaining.count - 1].url
            selectionID = next
            selectionIDs = [next]
            selectionAnchor = next
        }
        return removed
    }

    public mutating func restore(_ file: ImageFile) {
        restore([file])
    }

    public mutating func restore(_ incoming: [ImageFile]) {
        guard !incoming.isEmpty else { return }
        let previous = selectionID
        files.append(contentsOf: incoming)
        files.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        let visible = incoming.filter { file in filtered.contains(where: { $0.url == file.url }) }
        if !visible.isEmpty {
            selectionIDs = Set(visible.map(\.url))
            selectionID = visible.last?.url
            selectionAnchor = visible.first?.url
        } else if let previous, filtered.contains(where: { $0.url == previous }) {
            selectionID = previous
        } else {
            selectionID = filtered.first?.url
            selectionIDs = selectionID.map { [$0] } ?? []
            selectionAnchor = selectionID
        }
    }
}
