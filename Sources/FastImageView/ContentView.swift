import AppKit
import Combine
import SwiftUI
import FastImageViewCore

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Bindable var model: BrowserModel
    @State private var scroll = ScrollAccumulator()
    @State private var hoveredURL: URL?
    @State private var viewerHovered = false
    @State private var retainedViewerImage: CGImage?
    @StateObject private var toasts = ToastModel()

    var body: some View {
        VStack(spacing: 0) {
            switch model.mode {
            case .noFolder:
                if model.isScanning {
                    loadingState
                } else {
                    empty
                }
            case .grid:
                grid
                    .searchable(text: keyword, placement: .toolbar, prompt: "搜索文件名")
            case .viewer:
                if let file = model.catalog.selectedFile {
                    viewer(file)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle(windowTitle)
        .navigationSubtitle(toolbarSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if model.mode == .viewer {
                    Button {
                        model.closeViewer()
                    } label: {
                        Label("网格", systemImage: "chevron.backward")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("返回网格 (Esc)")
                    .accessibilityLabel("返回网格")
                } else {
                    Button {
                        chooseFolder(model)
                    } label: {
                        Label("打开", systemImage: "folder")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("打开文件夹 (⌘O)")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                gridToolbarItems
                viewerToolbarItems
            }
        }
        .overlay(alignment: .bottom) {
            toastView
        }
        .animation(.easeOut(duration: 0.18), value: toasts.current?.id)
        .onChange(of: model.folderURL) { _, _ in
            toasts.dismiss()
            retainedViewerImage = nil
        }
        .onChange(of: model.listingRevision) { _, _ in
            toasts.show("列表已更新", canUndo: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .undoTrashRequested)) { _ in
            toasts.undo(in: model)
        }
        .onChange(of: model.mode) { _, mode in
            if mode != .grid {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .background {
            EventMonitor(
                scroll: $scroll,
                model: model,
                toasts: toasts
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

    private var toolbarSubtitle: String {
        switch model.mode {
        case .grid:
            return model.folderURL == nil ? "" : folderCountText
        case .viewer:
            guard let file = model.catalog.selectedFile else { return "" }
            return viewerSubtitle(file)
        case .noFolder:
            return ""
        }
    }

    private func viewerSubtitle(_ file: ImageFile) -> String {
        var text = viewerIndexText(file)
        if model.fit == .actual, let image = model.cachedViewerImage(file) {
            text += " · \(image.width)×\(image.height)"
        }
        return text
    }

    private var windowTitle: String {
        switch model.mode {
        case .viewer:
            return model.catalog.selectedFile?.filename
                ?? model.folderURL?.lastPathComponent
                ?? "FastImageView"
        case .grid:
            return model.folderURL?.lastPathComponent ?? "FastImageView"
        case .noFolder:
            return "FastImageView"
        }
    }

    @ViewBuilder
    private var gridToolbarItems: some View {
        if model.mode == .grid {
            formatMenu
            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .help("正在读取文件夹…")
                    .accessibilityLabel("正在读取文件夹")
            }
            if model.catalog.selectedFile != nil {
                trashButton
            }
        }
    }

    @ViewBuilder
    private var viewerToolbarItems: some View {
        if model.mode == .viewer, model.catalog.selectedFile != nil {
            Picker("显示方式", selection: fitMode) {
                Text("适合窗口").tag(ViewerFit.fit)
                Text("实际像素").tag(ViewerFit.actual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            trashButton
        }
    }

    private var trashButton: some View {
        Button(role: .destructive) {
            toasts.deleteSelection(in: model)
        } label: {
            Image(systemName: "trash")
        }
        .help("移到废纸篓 (Delete)")
        .accessibilityLabel("移到废纸篓")
    }

    // MARK: - 空状态（未打开文件夹）

    private var loadingState: some View {
        VStack(spacing: theme.spacingMD) {
            ProgressView()
                .controlSize(.large)
            Text("正在读取文件夹…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: theme.spacingXL) {
                    VStack(spacing: theme.spacingSM) {
                        Image(systemName: "photo.stack")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                        Text("打开一个文件夹开始浏览")
                            .font(.title2)
                        Text("支持 JPG、PNG、HEIC、TIFF 与常见相机原片")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button("打开文件夹…") { chooseFolder(model) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    if let openError = model.openError {
                        Text(openError)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    if !model.recentFolders.isEmpty {
                        recentFolders
                    }
                }
                .padding(.horizontal, theme.spacingLG)
                .padding(.vertical, theme.spacingXL)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
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

    // MARK: - 筛选栏

    private var formatMenu: some View {
        Menu {
            Button("全部格式") { clearFormats() }
                .disabled(model.catalog.selectedFormats.isEmpty)
            Divider()
            ForEach(model.catalog.availableFormats, id: \.self) { format in
                Toggle(isOn: formatToggle(format)) {
                    Text(format.badge)
                }
            }
        } label: {
            HStack(spacing: theme.spacingXS) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(formatMenuTitle)
            }
        }
        .fixedSize()
        .help("按格式筛选")
        .disabled(model.catalog.availableFormats.isEmpty)
    }

    private var formatMenuTitle: String {
        let selected = model.catalog.selectedFormats
        if selected.isEmpty { return "格式" }
        if selected.count == 1, let format = selected.first { return "格式 · \(format.badge)" }
        return "格式 · \(selected.count)"
    }

    private var folderCountText: String {
        let total = model.catalog.files.count
        if model.catalog.keyword.isEmpty && model.catalog.selectedFormats.isEmpty {
            return "\(total) 张"
        }
        return "\(model.catalog.filtered.count)/\(total) 张"
    }

    private func formatToggle(_ format: ImageFormat) -> Binding<Bool> {
        Binding(
            get: { model.catalog.selectedFormats.contains(format) },
            set: { _ in model.toggleFormat(format) }
        )
    }

    private func clearFormats() {
        let formats = model.catalog.selectedFormats
        for format in formats {
            model.toggleFormat(format)
        }
    }

    private func clearFilters() {
        model.setKeyword("")
        clearFormats()
    }

    private var keyword: Binding<String> {
        Binding(get: { model.catalog.keyword }, set: { model.setKeyword($0) })
    }

    // MARK: - 网格

    private var grid: some View {
        let columns = [
            GridItem(
                .adaptive(minimum: theme.tileMinWidth, maximum: theme.tileMaxWidth),
                spacing: theme.gridSpacing
            )
        ]
        return Group {
            if model.catalog.filtered.isEmpty {
                StatePlaceholder(
                    icon: "photo.on.rectangle.angled",
                    message: "没有匹配的图片",
                    actionTitle: "清除筛选",
                    action: clearFilters
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: theme.gridSpacing) {
                            ForEach(model.catalog.filtered) { file in
                                cell(file).id(file.url)
                            }
                        }
                        .padding(theme.spacingLG)
                    }
                    .onAppear { revealSelection(using: proxy) }
                    .onChange(of: model.catalog.selectionID) { _, _ in
                        revealSelection(using: proxy)
                    }
                }
            }
        }
    }

    private func revealSelection(using proxy: ScrollViewProxy) {
        guard model.mode == .grid, let id = model.catalog.selectionID else { return }
        proxy.scrollTo(id)
    }

    private func cell(_ file: ImageFile) -> some View {
        let selected = model.catalog.selectionID == file.url
        return VStack(spacing: theme.spacingSM) {
            ZStack {
                theme.thumbnailPlaceholder
                thumbnail(file)
                    .scaledToFit()
            }
            .aspectRatio(theme.tileAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: theme.radiusSmall))
            .overlay(alignment: .bottomLeading) {
                formatBadge(file.format)
            }
            .overlay {
                RoundedRectangle(cornerRadius: theme.radiusSmall)
                    .strokeBorder(
                        selected
                            ? theme.selectionStroke
                            : (hoveredURL == file.url ? theme.hoverStroke : .clear),
                        lineWidth: selected ? theme.selectionStrokeWidth : 1
                    )
            }
            Text(file.filename)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.caption)
                .fontWeight(selected ? .medium : .regular)
                .foregroundStyle(selected ? .primary : .secondary)
                .help(file.filename)
        }
        .padding(theme.spacingXS)
        .contentShape(Rectangle())
        .background(selected ? theme.selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: theme.radiusLarge))
        .overlay {
            ClickCountCatcher(
                onClick: { clickCount in
                    resignSearchFocus()
                    select(file)
                    if clickCount >= 2 {
                        model.openViewer(screenLongEdge: screenLongEdge())
                    }
                },
                onHover: { hovering in
                    if hovering {
                        hoveredURL = file.url
                    } else if hoveredURL == file.url {
                        hoveredURL = nil
                    }
                },
                makeMenu: { makeContextMenu(for: file) }
            )
        }
        .onAppear { model.thumbnailRequest(file) }
        .onDisappear { model.thumbnailRelease(file) }
    }

    private func select(_ file: ImageFile) {
        model.select(url: file.url)
    }

    private func resignSearchFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func makeContextMenu(for file: ImageFile) -> NSMenu {
        model.select(url: file.url)
        resignSearchFocus()
        let model = self.model
        let toasts = self.toasts
        let target = ContextMenuTarget()
        target.onOpen = {
            model.openViewer(screenLongEdge: screenLongEdge())
        }
        target.onReveal = {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        }
        target.onCopyName = {
            copyFilename(file)
        }
        target.onTrash = {
            toasts.deleteSelection(in: model)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        addContextItem(menu, title: "在大图中打开", action: #selector(ContextMenuTarget.openAction(_:)), target: target)
        addContextItem(menu, title: "在访达中显示", action: #selector(ContextMenuTarget.revealAction(_:)), target: target)
        addContextItem(menu, title: "拷贝文件名", action: #selector(ContextMenuTarget.copyNameAction(_:)), target: target)
        menu.addItem(.separator())
        addContextItem(menu, title: "移到废纸篓", action: #selector(ContextMenuTarget.trashAction(_:)), target: target)
        return menu
    }

    private func addContextItem(_ menu: NSMenu, title: String, action: Selector, target: ContextMenuTarget) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = target
        menu.addItem(item)
    }

    private func copyFilename(_ file: ImageFile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.filename, forType: .string)
    }

    // MARK: - 查看器

    private func viewer(_ file: ImageFile) -> some View {
        let _ = model.renderGeneration
        return viewerContent(file)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.viewerCanvas)
            .contextMenu {
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
                Button("拷贝文件名") { copyFilename(file) }
                Divider()
                Button("移到废纸篓", role: .destructive) {
                    toasts.deleteSelection(in: model)
                }
            }
            .overlay(alignment: .leading) {
                viewerNavButton(previous: true, file: file)
            }
            .overlay(alignment: .trailing) {
                viewerNavButton(previous: false, file: file)
            }
            .onHover { viewerHovered = $0 }
            .onChange(of: file.url) { _, _ in
                if let image = model.cachedViewerImage(file) {
                    retainedViewerImage = image
                }
            }
            .onChange(of: model.renderGeneration) { _, _ in
                if let image = model.cachedViewerImage(file) {
                    retainedViewerImage = image
                }
            }
    }

    @ViewBuilder
    private func viewerNavButton(previous: Bool, file: ImageFile) -> some View {
        if viewerHovered {
            let items = model.catalog.filtered
            let index = items.firstIndex(where: { $0.url == file.url }) ?? 0
            let enabled = previous ? index > 0 : index + 1 < items.count
            Button {
                model.moveSelection(by: previous ? -1 : 1, screenLongEdge: screenLongEdge())
            } label: {
                Image(systemName: previous ? "chevron.left" : "chevron.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
            .padding(previous ? .leading : .trailing, theme.spacingLG)
            .help(previous ? "上一张 (←)" : "下一张 (→)")
            .accessibilityLabel(previous ? "上一张" : "下一张")
        }
    }

    private func toggleFit() {
        model.setFit(model.fit == .fit ? .actual : .fit, screenLongEdge: screenLongEdge())
    }

    private func viewerIndexText(_ file: ImageFile) -> String {
        guard let index = model.catalog.filtered.firstIndex(where: { $0.url == file.url }) else {
            return ""
        }
        return "\(index + 1)/\(model.catalog.filtered.count)"
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
            Group {
                if model.fit == .actual {
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: image, scale: 1)
                            .onTapGesture(count: 2) { toggleFit() }
                    }
                } else {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .padding(theme.spacingLG)
                        .onTapGesture(count: 2) { toggleFit() }
                }
            }
            .onAppear { retainedViewerImage = image }
        } else if let retained = retainedViewerImage {
            ZStack {
                Image(decorative: retained, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.55)
                ProgressView()
                    .controlSize(.small)
                    .padding(theme.spacingSM)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityLabel("正在加载")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatBadge(_ format: ImageFormat) -> some View {
        Text(format.badge)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(theme.badgeForeground(isRaw: format.isRaw))
            .padding(.horizontal, theme.spacingXS)
            .padding(.vertical, theme.spacingXS)
            .background(
                theme.badgeBackground(isRaw: format.isRaw),
                in: RoundedRectangle(cornerRadius: theme.radiusBadge)
            )
            .padding(theme.spacingXS)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = toasts.current {
            HStack(spacing: theme.spacingMD) {
                Image(systemName: toast.canUndo ? "trash" : "checkmark.circle")
                    .foregroundStyle(.secondary)
                Text(toast.message)
                    .font(.callout)
                if toast.canUndo {
                    Button("撤销") {
                        toasts.undo(in: model)
                    }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .help("撤销移到废纸篓 (⌘Z)")
                }
                Button {
                    toasts.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("关闭")
                .accessibilityLabel("关闭提示")
            }
            .padding(.horizontal, theme.spacingLG)
            .padding(.vertical, theme.spacingSM)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.bottom, theme.spacingLG)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

@MainActor
private final class ToastModel: ObservableObject {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let canUndo: Bool
    }

    @Published private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func deleteSelection(in model: BrowserModel) {
        let before = model.catalog.files.count
        model.deleteSelected()
        guard model.catalog.files.count < before else { return }
        show("已移到废纸篓", canUndo: true)
    }

    func undo(in model: BrowserModel) {
        let before = model.catalog.files.count
        model.undo()
        guard model.catalog.files.count > before else { return }
        show("已恢复", canUndo: false)
    }

    func show(_ message: String, canUndo: Bool) {
        dismissTask?.cancel()
        current = Toast(message: message, canUndo: canUndo)
        let id = current?.id
        let delay: UInt64 = canUndo ? 6_000_000_000 : 3_000_000_000
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, self?.current?.id == id else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

/// 空状态 / 加载状态 / 错误状态的统一占位组件。
private struct StatePlaceholder: View {
    @Environment(\.appTheme) private var theme

    var icon: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: theme.spacingMD) {
            Image(systemName: icon)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
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
    var onHover: (Bool) -> Void = { _ in }
    var makeMenu: (() -> NSMenu)? = nil

    func makeNSView(context: Context) -> ClickCountView {
        let view = ClickCountView()
        view.onClick = onClick
        view.onHover = onHover
        view.makeMenu = makeMenu
        return view
    }

    func updateNSView(_ nsView: ClickCountView, context: Context) {
        nsView.onClick = onClick
        nsView.onHover = onHover
        nsView.makeMenu = makeMenu
    }
}

private final class ClickCountView: NSView {
    var onClick: ((Int) -> Void)?
    var onHover: ((Bool) -> Void)?
    var makeMenu: (() -> NSMenu)?
    private var hoverTracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking {
            removeTrackingArea(hoverTracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(event.clickCount)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = makeMenu?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

@MainActor
private final class ContextMenuTarget: NSObject {
    var onOpen: (() -> Void)?
    var onReveal: (() -> Void)?
    var onCopyName: (() -> Void)?
    var onTrash: (() -> Void)?

    @objc func openAction(_ sender: Any?) { onOpen?() }
    @objc func revealAction(_ sender: Any?) { onReveal?() }
    @objc func copyNameAction(_ sender: Any?) { onCopyName?() }
    @objc func trashAction(_ sender: Any?) { onTrash?() }
}

private struct EventMonitor: NSViewRepresentable {
    @Binding var scroll: ScrollAccumulator
    var model: BrowserModel
    var toasts: ToastModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MonitorHostView {
        let view = MonitorHostView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MonitorHostView, context: Context) {
        context.coordinator.scroll = $scroll
        context.coordinator.model = model
        context.coordinator.toasts = toasts
        nsView.coordinator = context.coordinator
    }

    @MainActor
    final class Coordinator {
        var scroll: Binding<ScrollAccumulator>?
        var model: BrowserModel?
        var toasts: ToastModel?

        func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard let model else { return event }
            let chord = KeyChord(
                keyCode: event.keyCode,
                command: event.modifierFlags.contains(.command),
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? ""
            )
            let editingText = NSApp.keyWindow?.firstResponder is NSTextView
            let focus: KeyFocus = editingText ? .keyword : .browser
            switch interpretKey(chord, focus: focus, mode: model.mode) {
            case .passThrough:
                return event
            case .resignKeywordFocus:
                NSApp.keyWindow?.makeFirstResponder(nil)
                return nil
            case .deletePhoto:
                if let toasts {
                    toasts.deleteSelection(in: model)
                } else {
                    model.deleteSelected()
                }
                return nil
            case .undoTrash:
                if let toasts {
                    toasts.undo(in: model)
                } else {
                    model.undo()
                }
                return nil
            case .move(let delta):
                model.moveSelection(by: delta, screenLongEdge: screenLongEdge())
                return nil
            case .openViewer:
                NSApp.keyWindow?.makeFirstResponder(nil)
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
            if model.fit == .actual {
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
