import Foundation

public enum BrowserMode: Equatable, Sendable {
    case noFolder
    case grid
    case viewer
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
    case fit
    case actualPixels
    case zoomIn
    case zoomOut
    case copyImage
    case toggleCaptureInfo
    case openFolder
}

public struct KeyChord: Equatable, Sendable {
    public var keyCode: UInt16
    public var command: Bool
    public var charactersIgnoringModifiers: String
    public init(keyCode: UInt16, command: Bool, charactersIgnoringModifiers: String) {
        self.keyCode = keyCode
        self.command = command
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
    }
}

public func interpretKey(_ key: KeyChord, focus: KeyFocus, mode: BrowserMode) -> KeyAction {
    if key.command && key.keyCode == 31 { return .openFolder }
    if focus == .keyword {
        if key.keyCode == 53 || key.keyCode == 36 { return .resignKeywordFocus }
        return .passThrough
    }
    if key.keyCode == 51 || key.keyCode == 117 { return .deletePhoto }
    if key.command && key.keyCode == 6 { return .undoTrash }
    if key.command && key.keyCode == 8 { return .copyImage }
    if key.command && key.keyCode == 3 && mode != .noFolder { return .focusSearch }
    if mode == .viewer && key.command && key.keyCode == 24 { return .zoomIn }
    if mode == .viewer && key.command && key.keyCode == 27 { return .zoomOut }
    switch key.keyCode {
        case 124: return .move(1)
        case 123: return .move(-1)
        case 125: return mode == .grid ? .moveRow(1) : .move(1)
        case 126: return mode == .grid ? .moveRow(-1) : .move(-1)
    case 36 where mode == .grid: return .openViewer
    case 49 where mode == .grid && !key.command: return .openViewer
    case 53 where mode == .viewer: return .closeViewer
    case 49 where mode == .viewer && !key.command: return .closeViewer
    case 29 where mode == .viewer: return .fit
    case 18 where mode == .viewer: return .actualPixels
    case 34 where mode == .viewer: return .toggleCaptureInfo
    default: return .passThrough
    }
}
