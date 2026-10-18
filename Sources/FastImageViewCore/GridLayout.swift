import Foundation

public enum GridLayout {
    /// Matches `LazyVGrid` adaptive columns: as many as fit at `minimum`, without growing past `maximum`.
    public static func columnCount(availableWidth: Double, minimum: Double, maximum: Double, spacing: Double) -> Int {
        guard availableWidth > 0, minimum > 0 else { return 1 }
        let stride = minimum + spacing
        var count = max(1, Int(floor((availableWidth + spacing) / stride)))
        while count < 64 {
            let width = (availableWidth - Double(count - 1) * spacing) / Double(count)
            let next = count + 1
            let nextWidth = (availableWidth - Double(next - 1) * spacing) / Double(next)
            if width <= maximum || nextWidth < minimum { break }
            count = next
        }
        return count
    }

    /// Move by whole rows. A short last row still accepts a downward move from the row above.
    public static func rowIndex(from index: Int, count: Int, columns: Int, deltaRows: Int) -> Int {
        guard count > 0, columns > 0, index >= 0, index < count, deltaRows != 0 else { return index }
        let target = index + deltaRows * columns
        if target >= 0 && target < count { return target }
        if deltaRows > 0 {
            let currentRow = index / columns
            let lastRow = (count - 1) / columns
            if currentRow < lastRow { return count - 1 }
        }
        return index
    }
}
