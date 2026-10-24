import Foundation

public enum BrowserMode: Equatable, Sendable {
    case noFolder
    case grid
    case viewer
    case compare
}

public enum KeyFocus: Equatable, Sendable {
    case keyword
    case browser
}

public enum KeyAction: Equatable, Sendable {
    case passThrough
    case resignKeywordFocus
    case deletePhoto
    case undoTrash
    case move(Int)
    case moveRow(Int)
    case focusSearch
    case openViewer
    case closeViewer
    case zoomIn
    case zoomOut
    case copyImage
    case toggleCaptureInfo
    case openFolder
    case setRating(Int)
    case toggleRatingFilter(Int)
    case openCompare
    /// 吞掉按键，避免系统发出提示音。
    case consume
}

public struct KeyChord: Equatable, Sendable {
    public var keyCode: UInt16
    public var command: Bool
    public var shift: Bool
    public var charactersIgnoringModifiers: String

    public init(keyCode: UInt16, command: Bool, shift: Bool = false, charactersIgnoringModifiers: String) {
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
    }
}

public func interpretKey(_ key: KeyChord, focus: KeyFocus, mode: BrowserMode) -> KeyAction {
    if key.command && key.keyCode == 31 { return .openFolder }
    if focus == .keyword {
        if key.keyCode == 53 || key.keyCode == 36 { return .resignKeywordFocus }
        return .passThrough
    }
    // 网格与大图都用 1...5 设置分级；Shift 加数字只在网格中切换筛选。
    if mode == .grid || mode == .viewer, !key.command, let level = ratingLevel(for: key.keyCode) {
        if !key.shift { return .setRating(level) }
        if mode == .grid { return .toggleRatingFilter(level) }
    }
    // 对比模式只处理缩放与退出；其余按键吞掉，避免误操作网格或设置分级。
    if mode == .compare {
        if key.command && key.keyCode == 24 { return .zoomIn }
        if key.command && key.keyCode == 27 { return .zoomOut }
        switch key.keyCode {
        case 53, 49: return .closeViewer
        case 51, 117, 123, 124, 125, 126, 36, 35, 18, 19, 20, 21, 23: return .consume
        default: break
        }
    }
    if mode == .grid, !key.command, !key.shift, key.keyCode == 35 { return .openCompare }
    if key.keyCode == 51 || key.keyCode == 117 { return .deletePhoto }
    if key.command && key.keyCode == 6 { return .undoTrash }
    if key.command && key.keyCode == 8 { return .copyImage }
    if key.command && key.keyCode == 3 && mode != .noFolder { return .focusSearch }
    if (mode == .viewer || mode == .compare) && key.command && key.keyCode == 24 { return .zoomIn }
    if (mode == .viewer || mode == .compare) && key.command && key.keyCode == 27 { return .zoomOut }
    switch key.keyCode {
        case 124: return .move(1)
        case 123: return .move(-1)
        case 125: return mode == .grid ? .moveRow(1) : .move(1)
        case 126: return mode == .grid ? .moveRow(-1) : .move(-1)
    case 36 where mode == .grid: return .openViewer
    case 49 where mode == .grid && !key.command: return .openViewer
    case 53 where mode == .viewer: return .closeViewer
    case 49 where mode == .viewer && !key.command: return .closeViewer
    case 34 where mode == .viewer: return .toggleCaptureInfo
    default: return .passThrough
    }
}

/// 数字键 1...5 对应的分级；其余键返回 nil。
private func ratingLevel(for keyCode: UInt16) -> Int? {
    switch keyCode {
    case 18: return 1
    case 19: return 2
    case 20: return 3
    case 21: return 4
    case 23: return 5
    default: return nil
    }
}
