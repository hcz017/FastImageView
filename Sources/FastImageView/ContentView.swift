import AppKit
import Combine
import SwiftUI
import FastImageViewCore

struct ContentView: View {
    @Environment(\.appTheme) private var theme
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
                    Divider()
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

    // MARK: - 空状态（未打开文件夹）

    private var empty: some View {
        VStack(spacing: theme.spacingXL) {
            VStack(spacing: theme.spacingSM) {
                Image(systemName: "photo.stack")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                Text("打开一个文件夹开始浏览")
                    .font(.title2)
            }
            Button("打开文件夹…") { chooseFolder(model) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if let openError = model.openError {
                Text(openError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if !model.recentFolders.isEmpty {
                recentFolders
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private var recentFolders: some View {
        VStack(alignment: .leading, spacing: theme.spacingSM) {
            Text("最近打开")
                .font(.headline)
            ForEach(model.recentFolders, id: \.path) { url in
                Button {
                    model.open(folder: url)
                } label: {
                    HStack(spacing: theme.spacingSM) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: theme.spacingXS) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, theme.spacingMD)
                    .padding(.vertical, theme.spacingSM)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    theme.recentRowFill,
                    in: RoundedRectangle(cornerRadius: theme.radiusSmall)
                )
            }
        }
        .frame(maxWidth: 480)
        .padding(theme.spacingLG)
        .background(.background, in: RoundedRectangle(cornerRadius: theme.radiusLarge))
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: theme.spacingSM) {
            Button("打开文件夹…") { chooseFolder(model) }
            VStack(alignment: .leading, spacing: theme.spacingXS) {
                Text(model.folderURL?.lastPathComponent ?? "")
                    .font(.headline)
                    .lineLimit(1)
                if model.catalog.keyword.isEmpty && model.catalog.selectedFormats.isEmpty {
                    Text("\(model.catalog.files.count) 张图片")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("筛选出 \(model.catalog.filtered.count) / \(model.catalog.files.count) 张")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, theme.spacingLG)
        .padding(.vertical, theme.spacingSM)
        .background(.bar)
    }

    // MARK: - 筛选栏

    private var filterBar: some View {
        HStack(spacing: theme.spacingSM) {
            HStack(spacing: theme.spacingXS) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索文件名", text: keyword)
                    .textFieldStyle(.plain)
                    .focused($keywordFocused)
            }
            .padding(.horizontal, theme.spacingSM)
            .padding(.vertical, theme.spacingXS)
            .background(theme.searchFieldFill, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
            .frame(width: 220)
            ForEach(model.catalog.availableFormats, id: \.self) { format in
                Toggle(format.badge, isOn: formatToggle(format))
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
            Spacer()
        }
        .padding(.horizontal, theme.spacingLG)
        .padding(.vertical, theme.spacingSM)
        .background(.bar)
    }

    private func formatToggle(_ format: ImageFormat) -> Binding<Bool> {
        Binding(
            get: { model.catalog.selectedFormats.contains(format) },
            set: { _ in model.toggleFormat(format) }
        )
    }

    private var keyword: Binding<String> {
        Binding(get: { model.catalog.keyword }, set: { model.setKeyword($0) })
    }

    // MARK: - 网格

    private var grid: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: theme.spacingSM)]
        return ScrollViewReader { proxy in
            ScrollView {
                if model.catalog.filtered.isEmpty {
                    StatePlaceholder(
                        icon: "photo.on.rectangle.angled",
                        message: "没有匹配的图片"
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: columns, spacing: theme.spacingSM) {
                        ForEach(model.catalog.filtered) { file in
                            cell(file).id(file.url)
                        }
                    }
                    .padding(theme.spacingSM)
                }
            }
            .onAppear { revealSelection(using: proxy) }
            .onChange(of: model.catalog.selectionID) { _, _ in
                revealSelection(using: proxy)
            }
        }
    }

    private func revealSelection(using proxy: ScrollViewProxy) {
        guard model.mode == .grid, let id = model.catalog.selectionID else { return }
        proxy.scrollTo(id)
    }

    private func cell(_ file: ImageFile) -> some View {
        let selected = model.catalog.selectionID == file.url
        return VStack(spacing: theme.spacingXS) {
            thumbnail(file)
                .clipShape(RoundedRectangle(cornerRadius: theme.radiusSmall))
                .overlay(alignment: .bottomLeading) {
                    formatBadge(file.format)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radiusSmall)
                        .strokeBorder(
                            selected ? theme.selectionStroke : .clear,
                            lineWidth: theme.selectionStrokeWidth
                        )
                }
            Text(file.filename)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .padding(theme.spacingXS)
        .background(selected ? theme.selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: theme.radiusLarge))
        .overlay {
            ClickCountCatcher { clickCount in
                keywordFocused = false
                select(file)
                if clickCount >= 2 {
                    model.openViewer(screenLongEdge: screenLongEdge())
                }
            }
        }
        .onAppear { model.thumbnailRequest(file) }
        .onDisappear { model.thumbnailRelease(file) }
    }

    private func select(_ file: ImageFile) {
        model.select(url: file.url)
    }

    // MARK: - 查看器

    private func viewer(_ file: ImageFile) -> some View {
        let _ = model.renderGeneration
        return ZStack {
            viewerContent(file)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) {
            HStack(spacing: theme.spacingSM) {
                Text(file.filename)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Picker("显示方式", selection: fitMode) {
                    Text("适应窗口").tag(ViewerFit.fit)
                    Text("实际像素").tag(ViewerFit.actual)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(.horizontal, theme.spacingLG)
            .padding(.vertical, theme.spacingSM)
            .background(.bar)
        }
    }

    private var fitMode: Binding<ViewerFit> {
        Binding(
            get: { model.fit },
            set: { model.setFit($0, screenLongEdge: screenLongEdge()) }
        )
    }

    @ViewBuilder
    private func viewerContent(_ file: ImageFile) -> some View {
        if file.iCloudState == .notDownloaded {
            StatePlaceholder(icon: "icloud.and.arrow.down", message: "未下载")
        } else if model.failed(file.url) {
            StatePlaceholder(icon: "exclamationmark.triangle", message: "无法打开")
                .onAppear { model.noteUnavailable(file.url) }
        } else if let image = model.cachedViewerImage(file) {
            if model.fit == .actual {
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: image, scale: 1)
                }
            } else {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .padding(theme.spacingLG)
            }
        } else {
            StatePlaceholder(icon: "photo", message: "加载中…")
        }
    }

    @ViewBuilder
    private func thumbnail(_ file: ImageFile) -> some View {
        let _ = model.renderGeneration
        thumbnailContent(file)
    }

    @ViewBuilder
    private func thumbnailContent(_ file: ImageFile) -> some View {
        if file.iCloudState == .notDownloaded {
            thumbnailLabel("未下载")
        } else if let image = model.cachedThumbnail(file) {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else if model.failed(file.url) {
            thumbnailLabel("无法打开")
                .onAppear { model.noteUnavailable(file.url) }
        } else {
            thumbnailLabel(" ")
        }
    }

    private func thumbnailLabel(_ text: String) -> some View {
        ZStack {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 160, height: 120)
        .background(theme.thumbnailPlaceholder)
    }

    private func formatBadge(_ format: ImageFormat) -> some View {
        Text(format.badge)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, theme.spacingXS)
            .padding(.vertical, theme.spacingXS)
            .background(
                theme.badgeBackground(isRaw: format.isRaw),
                in: RoundedRectangle(cornerRadius: theme.radiusBadge)
            )
            .padding(theme.spacingXS)
    }
}

/// 空状态 / 加载状态 / 错误状态的统一占位组件。
private struct StatePlaceholder: View {
    @Environment(\.appTheme) private var theme

    var icon: String
    var message: String

    var body: some View {
        VStack(spacing: theme.spacingMD) {
            Image(systemName: icon)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
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
