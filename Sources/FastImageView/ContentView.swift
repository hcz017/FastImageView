import AppKit
import Combine
import SwiftUI
import FastImageViewCore

struct ContentView: View {
    @Bindable var model: BrowserModel
    @FocusState private var keywordFocused: Bool
    @State private var scroll = ScrollAccumulator()

    var body: some View {
        VStack(spacing: 0) {
            switch model.mode {
            case .noFolder:
                empty
            case .grid, .viewer:
                header
                if model.mode == .grid {
                    filterBar
                    grid
                } else if let file = model.catalog.selectedFile {
                    viewer(file)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            model.syncPreviewGeneration()
        }
        .background {
            EventMonitor(
                keywordFocused: $keywordFocused,
                scroll: $scroll,
                model: model
            )
        }
        .alert("无法完成操作", isPresented: errorPresented) {
            Button("好") { model.statusMessage = nil }
        } message: {
            Text(model.statusMessage ?? "")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Button("打开文件夹") { chooseFolder(model) }
            if let openError = model.openError { Text(openError) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Button("打开文件夹") { chooseFolder(model) }
            Text(model.folderURL?.lastPathComponent ?? "")
            Spacer()
        }
        .padding(8)
    }

    private var filterBar: some View {
        HStack {
            TextField("文件名", text: keyword)
                .textFieldStyle(.roundedBorder)
                .focused($keywordFocused)
            ForEach(model.catalog.availableFormats, id: \.self) { format in
                let on = model.catalog.selectedFormats.contains(format)
                Button(format.rawValue) { model.toggleFormat(format) }
                    .buttonStyle(.bordered)
                    .tint(on ? .accentColor : nil)
                    .focusable(false)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var keyword: Binding<String> {
        Binding(get: { model.catalog.keyword }, set: { model.setKeyword($0) })
    }

    private var grid: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 8)]
        return ScrollView {
            if model.catalog.filtered.isEmpty {
                Text("没有匹配的图片").frame(maxWidth: .infinity, minHeight: 240)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.catalog.filtered) { file in
                        cell(file)
                    }
                }
                .padding(8)
            }
        }
    }

    private func cell(_ file: ImageFile) -> some View {
        let selected = model.catalog.selectionID == file.url
        return VStack {
            thumbnail(file)
            Text(file.filename).lineLimit(1).font(.caption)
        }
        .padding(4)
        .background(selected ? Color.accentColor.opacity(0.25) : Color.clear)
        .overlay {
            ClickCountCatcher { clickCount in
                select(file)
                if clickCount >= 2 {
                    keywordFocused = false
                    model.openViewer(screenLongEdge: screenLongEdge())
                }
            }
        }
        .onAppear { model.thumbnailRequest(file) }
    }

    private func select(_ file: ImageFile) {
        model.select(url: file.url)
    }

    private func viewer(_ file: ImageFile) -> some View {
        let _ = model.renderGeneration
        return VStack {
            Text(file.filename)
            Group {
                if file.iCloudState == .notDownloaded {
                    Text("未下载")
                } else if model.failed(file.url) {
                    Text("无法打开")
                        .onAppear { model.noteUnavailable(file.url) }
                } else if let image = model.cachedViewerImage(file) {
                    if model.fit == .actual {
                        ScrollView([.horizontal, .vertical]) {
                            Image(decorative: image, scale: 1)
                        }
                    } else {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func thumbnail(_ file: ImageFile) -> some View {
        let _ = model.renderGeneration
        if file.iCloudState == .notDownloaded {
            label("未下载")
        } else if let image = model.cachedThumbnail(file) {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else if model.failed(file.url) {
            label("无法打开")
                .onAppear { model.noteUnavailable(file.url) }
        } else {
            label(" ")
        }
    }

    private func label(_ text: String) -> some View {
        ZStack { Text(text) }
            .frame(width: 160, height: 120)
            .background(Color.gray.opacity(0.15))
    }
}

func screenLongEdge() -> Int {
    let screen = NSScreen.main
    let scale = screen?.backingScaleFactor ?? 2
    let width = Int((screen?.frame.width ?? 1440) * scale)
    let height = Int((screen?.frame.height ?? 900) * scale)
    return max(width, height)
}

/// Captures AppKit `mouseDown` so `NSEvent.clickCount` distinguishes single vs double click immediately.
private struct ClickCountCatcher: NSViewRepresentable {
    var onClick: (Int) -> Void

    func makeNSView(context: Context) -> ClickCountView {
        let view = ClickCountView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: ClickCountView, context: Context) {
        nsView.onClick = onClick
    }
}

private final class ClickCountView: NSView {
    var onClick: ((Int) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func mouseDown(with event: NSEvent) {
        onClick?(event.clickCount)
    }
}

private struct EventMonitor: NSViewRepresentable {
    @FocusState.Binding var keywordFocused: Bool
    @Binding var scroll: ScrollAccumulator
    var model: BrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MonitorHostView {
        let view = MonitorHostView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MonitorHostView, context: Context) {
        context.coordinator.keywordFocused = $keywordFocused
        context.coordinator.scroll = $scroll
        context.coordinator.model = model
        nsView.coordinator = context.coordinator
    }

    @MainActor
    final class Coordinator {
        var keywordFocused: FocusState<Bool>.Binding?
        var scroll: Binding<ScrollAccumulator>?
        var model: BrowserModel?

        func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard let model, let keywordFocused else { return event }
            let chord = KeyChord(
                keyCode: event.keyCode,
                command: event.modifierFlags.contains(.command),
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? ""
            )
            let focus: KeyFocus = keywordFocused.wrappedValue ? .keyword : .browser
            switch interpretKey(chord, focus: focus, mode: model.mode) {
            case .passThrough:
                return event
            case .resignKeywordFocus:
                keywordFocused.wrappedValue = false
                return nil
            case .deletePhoto:
                model.deleteSelected()
                return nil
            case .undoTrash:
                model.undo()
                return nil
            case .move(let delta):
                model.moveSelection(by: delta, screenLongEdge: screenLongEdge())
                return nil
            case .openViewer:
                keywordFocused.wrappedValue = false
                model.openViewer(screenLongEdge: screenLongEdge())
                return nil
            case .closeViewer:
                model.closeViewer()
                return nil
            case .fit:
                model.setFit(.fit, screenLongEdge: screenLongEdge())
                return nil
            case .actualPixels:
                model.setFit(.actual, screenLongEdge: screenLongEdge())
                return nil
            case .openFolder:
                return event
            }
        }

        func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
            guard let model, let scroll, model.mode == .viewer else { return event }
            if model.fit == .actual && event.hasPreciseScrollingDeltas {
                return event
            }
            let raw = specDeltas(
                scrollingDeltaX: event.scrollingDeltaX,
                scrollingDeltaY: event.scrollingDeltaY
            )
            let sample = ScrollSample(
                deltaX: raw.x,
                deltaY: raw.y,
                precise: event.hasPreciseScrollingDeltas,
                fingerDown: event.phase.contains(.began) || event.phase.contains(.changed) || event.phase.contains(.stationary),
                inertial: event.momentumPhase != [] && event.phase == []
            )
            var accumulator = scroll.wrappedValue
            let step = accumulator.consume(sample)
            scroll.wrappedValue = accumulator
            if step != 0 {
                model.moveSelection(by: step, screenLongEdge: screenLongEdge())
            }
            return step == 0 ? event : nil
        }
    }
}

private final class MonitorHostView: NSView {
    weak var coordinator: EventMonitor.Coordinator?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitors()
        } else {
            removeMonitors()
        }
    }

    deinit {
        removeMonitors()
    }

    private func installMonitors() {
        guard keyMonitor == nil, let coordinator else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                coordinator.handleKeyDown(event)
            }
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                coordinator.handleScrollWheel(event)
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }
}
