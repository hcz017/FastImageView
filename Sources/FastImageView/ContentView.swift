import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import FastImageViewCore

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Bindable var model: BrowserModel
    @State private var scroll = ScrollAccumulator()
    @State private var hoveredURL: URL?
    @State private var viewerHovered = false
    @State private var retainedViewerImage: CGImage?
    @State private var dropTargeted = false
    @State private var panOrigin: ImagePan?
    @State private var gridColumns = 1
    @State private var pendingSearchFocus = false
    @State private var captureSummary = ""
    @State private var showCaptureInfo = false
    @State private var gifStarted = Date()
    @StateObject private var gifClip = GIFClip()
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
                        Label("返回", systemImage: "chevron.backward")
                    }
                    .labelStyle(.iconOnly)
                    .help("返回 (Esc)")
                    .accessibilityLabel("返回")
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
            ToolbarItem(placement: .destructiveAction) {
                if model.mode != .noFolder, model.catalog.selectedFile != nil {
                    trashButton
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .copyImageRequested)) { _ in
            copyPrimaryImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyPathsRequested)) { _ in
            copySelectionPaths()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchRequested)) { _ in
            focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCaptureInfoRequested)) { _ in
            showCaptureInfo.toggle()
        }
        .onChange(of: model.mode) { _, mode in
            guard pendingSearchFocus, mode == .grid else { return }
            pendingSearchFocus = false
            DispatchQueue.main.async { focusSearchField() }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
                return false
            }
            Task { @MainActor in
                let urls = await FileDrop.load(providers)
                model.openDropped(urls, screenLongEdge: screenLongEdge())
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: theme.radiusLarge)
                    .strokeBorder(theme.selectionStroke, lineWidth: theme.selectionStrokeWidth)
                    .background(theme.selectionFill)
                    .overlay {
                        Text("松开以打开")
                            .font(.title3.weight(.semibold))
                    }
                    .padding(theme.spacingSM)
                    .allowsHitTesting(false)
            }
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
                toasts: toasts,
                gridColumns: gridColumns
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
        if model.zoom != .fit {
            text += " · \(model.zoomLabel)"
            if let image = model.cachedViewerImage(file) ?? retainedViewerImage {
                text += " · \(image.width)×\(image.height)"
            }
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
        }
    }

    @ViewBuilder
    private var viewerToolbarItems: some View {
        if model.mode == .viewer, model.catalog.selectedFile != nil {
            ControlGroup {
                Button {
                    model.zoom(by: 1 / ZoomMath.step, screenLongEdge: screenLongEdge())
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("缩小 (⌘−)")
                .accessibilityLabel("缩小")
                Text(model.zoomLabel)
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 44)
                    .accessibilityLabel("缩放 \(model.zoomLabel)")
                Button {
                    model.zoom(by: ZoomMath.step, screenLongEdge: screenLongEdge())
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("放大 (⌘+)")
                .accessibilityLabel("放大")
            }
            ControlGroup {
                Toggle("适合窗口", isOn: fitWindowToggle)
                    .help("适合窗口 (0)")
                Toggle("实际像素", isOn: actualPixelsToggle)
                    .help("实际像素 (1)")
                Button {
                    showCaptureInfo.toggle()
                } label: {
                    Label("图片信息", systemImage: showCaptureInfo ? "info.circle.fill" : "info.circle")
                }
                .labelStyle(.titleAndIcon)
                .help(showCaptureInfo ? "隐藏图片信息 (I)" : "显示图片信息 (I)")
                .accessibilityLabel("图片信息")
                .accessibilityValue(showCaptureInfo ? "显示中" : "已隐藏")
            }
        }
    }

    /// 自定义缩放（⌘±、捏合、滚轮）时两个开关都不亮，符合实际状态。
    private var fitWindowToggle: Binding<Bool> {
        Binding(
            get: { model.zoom == .fit },
            set: { if $0 { model.setFit(.fit, screenLongEdge: screenLongEdge()) } }
        )
    }

    private var actualPixelsToggle: Binding<Bool> {
        Binding(
            get: {
                if case .actual = model.zoom { return true }
                return false
            },
            set: { if $0 { model.setFit(.actual, screenLongEdge: screenLongEdge()) } }
        )
    }

    private var trashButton: some View {
        Button(role: .destructive) {
            toasts.deleteSelection(in: model)
        } label: {
            Image(systemName: "trash")
        }
        .help(trashHelp)
        .accessibilityLabel(trashHelp)
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
                RecentFolderRow(
                    url: url,
                    missing: !FileManager.default.fileExists(atPath: url.path),
                    onOpen: { model.open(folder: url) },
                    onRemove: { model.removeRecent(url) }
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

    private var trashHelp: String {
        let count = model.catalog.deletionTargets.count
        if count > 1 { return "将 \(count) 张移到废纸篓 (Delete)" }
        return "移到废纸篓 (Delete)"
    }

    private var folderCountText: String {
        let total = model.catalog.files.count
        let count: String
        if model.catalog.keyword.isEmpty && model.catalog.selectedFormats.isEmpty {
            count = "\(total) 张"
        } else {
            count = "\(model.catalog.filtered.count)/\(total) 张"
        }
        let selected = model.catalog.deletionTargets.count
        if selected > 1 { return "已选 \(selected) · \(count)" }
        return count
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
                GeometryReader { geo in
                    let columnCount = GridLayout.columnCount(
                        availableWidth: max(0, Double(geo.size.width) - Double(theme.spacingLG) * 2),
                        minimum: Double(theme.tileMinWidth),
                        maximum: Double(theme.tileMaxWidth),
                        spacing: Double(theme.gridSpacing)
                    )
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: theme.gridSpacing) {
                                ForEach(model.catalog.filtered) { file in
                                    cell(file).id(file.url)
                                }
                            }
                            .padding(theme.spacingLG)
                        }
                        .onAppear {
                            gridColumns = columnCount
                            revealSelection(using: proxy)
                        }
                        .onChange(of: columnCount) { _, count in
                            gridColumns = count
                        }
                        .onChange(of: model.catalog.selectionID) { _, _ in
                            revealSelection(using: proxy)
                        }
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
        let selected = isSelected(file)
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
        .accessibilityAddTraits(selected ? .isSelected : [])
        .overlay {
            ClickCountCatcher(
                onClick: { clickCount, flags in
                    resignSearchFocus()
                    let gesture: SelectionGesture
                    if flags.contains(.command) {
                        gesture = .toggle
                    } else if flags.contains(.shift) {
                        gesture = .extend
                    } else {
                        gesture = .only
                    }
                    model.select(url: file.url, gesture: gesture)
                    if clickCount >= 2, gesture == .only {
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

    private func isSelected(_ file: ImageFile) -> Bool {
        let ids = model.catalog.selectionIDs
        if ids.isEmpty { return model.catalog.selectionID == file.url }
        return ids.contains(file.url)
    }

    private func resignSearchFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func makeContextMenu(for file: ImageFile) -> NSMenu {
        if !isSelected(file) {
            model.select(url: file.url)
        }
        resignSearchFocus()
        let copy = copySet(for: file)
        let canOpenViewer = model.catalog.deletionTargets.count <= 1
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
            Clipboard.copyFilenames(copy.filenames)
        }
        target.onCopyImage = {
            copyImages(copy.urls)
        }
        target.onCopyPath = {
            Clipboard.copyPaths(copy.paths)
        }
        target.onTrash = {
            toasts.deleteSelection(in: model)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        if canOpenViewer {
            addContextItem(menu, title: "在大图中打开", action: #selector(ContextMenuTarget.openAction(_:)), target: target)
        }
        addContextItem(menu, title: "在访达中显示", action: #selector(ContextMenuTarget.revealAction(_:)), target: target)
        addContextItem(menu, title: copy.filenames.count > 1 ? "拷贝 \(copy.filenames.count) 个文件名" : "拷贝文件名", action: #selector(ContextMenuTarget.copyNameAction(_:)), target: target)
        addContextItem(menu, title: copy.urls.count > 1 ? "拷贝 \(copy.urls.count) 张图片" : "拷贝图片", action: #selector(ContextMenuTarget.copyImageAction(_:)), target: target)
        addContextItem(menu, title: copy.paths.count > 1 ? "拷贝 \(copy.paths.count) 个路径" : "拷贝路径", action: #selector(ContextMenuTarget.copyPathAction(_:)), target: target)
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
                Button("拷贝文件名") { Clipboard.copyFilenames([file.filename]) }
                Button("拷贝图片") { copyImages([file.url]) }
                Button("拷贝路径") { Clipboard.copyPaths([file.url.path]) }
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
            .overlay(alignment: .topLeading) {
                if showCaptureInfo, !captureSummary.isEmpty {
                    Text(captureSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, theme.spacingMD)
                        .padding(.vertical, theme.spacingSM)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: theme.radiusSmall))
                        .frame(maxWidth: theme.captureInfoMaxWidth, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(theme.spacingLG)
                        .allowsHitTesting(false)
                        .accessibilityLabel("图片信息")
                }
            }
            .onHover { viewerHovered = $0 }
            .task(id: file.url) {
                await loadViewerDetails(file)
            }
            .onChange(of: file.url) { _, _ in
                panOrigin = nil
                captureSummary = ""
                gifStarted = Date()
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

    @ViewBuilder
    private func viewerContent(_ file: ImageFile) -> some View {
        if file.iCloudState == .notDownloaded {
            StatePlaceholder(icon: "icloud.and.arrow.down", message: "未下载")
        } else if model.failed(file.url) {
            StatePlaceholder(icon: "exclamationmark.triangle", message: "无法打开")
                .onAppear { model.noteUnavailable(file.url) }
        } else if file.format == .gif, gifClip.url == file.url, gifClip.frames.count > 1 {
            animatedGIF(gifClip.frames, delays: gifClip.delays)
        } else if let image = model.cachedViewerImage(file) {
            zoomableImage(image, dimmed: false)
                .onAppear { retainedViewerImage = image }
        } else if let retained = retainedViewerImage {
            ZStack {
                zoomableImage(retained, dimmed: true)
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

    private func zoomableImage(_ image: CGImage, dimmed: Bool) -> some View {
        let layout = ViewerImageSizing.layoutSize(
            decodedWidth: image.width,
            decodedHeight: image.height,
            source: model.viewerSourceSize
        )
        let soft = ViewerImageSizing.isUpscalingPreview(
            decodedWidth: image.width,
            decodedHeight: image.height,
            layout: layout
        )
        return zoomCanvas(imageWidth: Double(layout.width), imageHeight: Double(layout.height)) { metrics in
            placedImage(image, metrics: metrics, dimmed: dimmed, soft: soft)
        }
    }

    private func animatedGIF(_ frames: [CGImage], delays: [Double]) -> some View {
        let sample = frames[0]
        let layout = ViewerImageSizing.layoutSize(
            decodedWidth: sample.width,
            decodedHeight: sample.height,
            source: model.viewerSourceSize
        )
        return zoomCanvas(imageWidth: Double(layout.width), imageHeight: Double(layout.height)) { metrics in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let index = GIFPlayback.index(
                    elapsed: context.date.timeIntervalSince(gifStarted),
                    delays: delays
                )
                placedImage(frames[min(index, frames.count - 1)], metrics: metrics, dimmed: false, soft: false)
            }
        }
    }

    private func zoomCanvas<Content: View>(imageWidth: Double, imageHeight: Double, @ViewBuilder content: @escaping (CGSize) -> Content) -> some View {
        GeometryReader { geo in
            let metrics = viewerMetrics(imageWidth: imageWidth, imageHeight: imageHeight, viewport: geo.size)
            content(metrics.content)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(viewerDrag)
                .onTapGesture(count: 2) { toggleFit() }
                .onAppear { publishViewerLayout(metrics, viewport: geo.size) }
                .onChange(of: geo.size) { _, size in
                    publishViewerLayout(viewerMetrics(imageWidth: imageWidth, imageHeight: imageHeight, viewport: size), viewport: size)
                }
                .onChange(of: model.zoom) { _, _ in
                    publishViewerLayout(viewerMetrics(imageWidth: imageWidth, imageHeight: imageHeight, viewport: geo.size), viewport: geo.size)
                }
                .onChange(of: model.viewerSourceSize) { _, _ in
                    publishViewerLayout(viewerMetrics(imageWidth: imageWidth, imageHeight: imageHeight, viewport: geo.size), viewport: geo.size)
                }
        }
    }

    private func placedImage(_ image: CGImage, metrics: CGSize, dimmed: Bool, soft: Bool) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(soft ? .medium : .high)
            .frame(width: metrics.width, height: metrics.height)
            .opacity(dimmed ? 0.55 : 1)
            .offset(x: model.pan.x, y: model.pan.y)
    }

    private var viewerDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if panOrigin == nil { panOrigin = model.pan }
                let origin = panOrigin ?? .zero
                model.setPan(x: origin.x + Double(value.translation.width), y: origin.y + Double(value.translation.height))
            }
            .onEnded { _ in
                panOrigin = nil
            }
    }

    private func viewerMetrics(imageWidth: Double, imageHeight: Double, viewport: CGSize) -> (fitScale: Double, content: CGSize) {
        let pad = Double(theme.spacingLG)
        let fitW = max(Double(viewport.width) - pad * 2, 1)
        let fitH = max(Double(viewport.height) - pad * 2, 1)
        let fitScale = ZoomMath.fitScale(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            viewportWidth: fitW,
            viewportHeight: fitH
        )
        let display = ZoomMath.displayScale(fitScale: fitScale, multiple: model.zoomMultiple(fitScale: fitScale))
        return (fitScale, CGSize(width: imageWidth * display, height: imageHeight * display))
    }

    private func publishViewerLayout(_ metrics: (fitScale: Double, content: CGSize), viewport: CGSize) {
        model.noteViewerLayout(
            ViewerLayout(
                contentWidth: Double(metrics.content.width),
                contentHeight: Double(metrics.content.height),
                viewportWidth: Double(viewport.width),
                viewportHeight: Double(viewport.height),
                fitScale: metrics.fitScale
            )
        )
    }

    private func copySet(for file: ImageFile) -> CopySet {
        CopyRouting.make(clicked: file.url, orderedSelection: model.catalog.deletionTargets.map(\.url))
    }

    private func copyPrimaryImage() {
        let targets = model.catalog.deletionTargets
        let urls = (targets.isEmpty ? model.catalog.selectedFile.map { [$0] } ?? [] : targets).map(\.url)
        copyImages(urls)
    }

    private func copySelectionPaths() {
        let targets = model.catalog.deletionTargets
        let paths = (targets.isEmpty ? model.catalog.selectedFile.map { [$0] } ?? [] : targets).map(\.url.path)
        Clipboard.copyPaths(paths)
    }

    private func loadViewerDetails(_ file: ImageFile) async {
        let url = file.url
        if file.format == .gif {
            gifStarted = Date()
            gifClip.load(url: url, maxPixelSize: min(screenLongEdge(), GIFPlayback.maxPixel))
        } else {
            gifClip.clear()
        }
        let summary = await Task.detached(priority: .utility) {
            CaptureInfoReader.load(url: url).summary
        }.value
        guard file.url == url else { return }
        captureSummary = summary
    }

    private func focusSearch() {
        guard model.mode != .noFolder else { return }
        if model.mode == .viewer {
            pendingSearchFocus = true
            model.closeViewer()
            return
        }
        DispatchQueue.main.async { focusSearchField() }
    }

    private func focusSearchField() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        if let field = SearchFieldFinder.find(in: window) {
            window.makeFirstResponder(field)
            return
        }
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
                  let field = SearchFieldFinder.find(in: window) else { return }
            window.makeFirstResponder(field)
        }
    }

    private func copyImages(_ urls: [URL]) {
        guard Clipboard.copyImages(at: urls) else {
            model.statusMessage = urls.count > 1 ? "无法拷贝这些图片" : "无法拷贝这张图片"
            return
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
            .foregroundStyle(theme.badgeForeground(for: format))
            .padding(.horizontal, theme.spacingXS)
            .padding(.vertical, theme.spacingXS)
            .background(
                theme.badgeBackground(for: format),
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
        let removed = before - model.catalog.files.count
        guard removed > 0 else { return }
        show(removed > 1 ? "已将 \(removed) 张移到废纸篓" : "已移到废纸篓", canUndo: true)
    }

    func undo(in model: BrowserModel) {
        let before = model.catalog.files.count
        model.undo()
        let restored = model.catalog.files.count - before
        guard restored > 0 else { return }
        show(restored > 1 ? "已恢复 \(restored) 张" : "已恢复", canUndo: false)
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

private struct RecentFolderRow: View {
    @Environment(\.appTheme) private var theme
    let url: URL
    let missing: Bool
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: theme.spacingSM) {
            Button(action: onOpen) {
                HStack(spacing: theme.spacingSM) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: theme.spacingXS) {
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(missing ? "路径已不存在" : url.path)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(missing)
            .accessibilityLabel(missing ? "\(url.lastPathComponent)，路径已不存在" : url.lastPathComponent)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .help("从最近打开中移除")
            .accessibilityLabel("从最近打开中移除 \(url.lastPathComponent)")
        }
        .padding(.horizontal, theme.spacingMD)
        .padding(.vertical, theme.spacingSM)
        .background(
            hovered ? theme.recentRowHoverFill : theme.recentRowFill,
            in: RoundedRectangle(cornerRadius: theme.radiusSmall)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button("从最近打开中移除", role: .destructive) { onRemove() }
        }
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
    var onClick: (Int, NSEvent.ModifierFlags) -> Void
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
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
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
        onClick?(event.clickCount, event.modifierFlags)
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
    var onCopyImage: (() -> Void)?
    var onCopyPath: (() -> Void)?
    var onTrash: (() -> Void)?

    @objc func openAction(_ sender: Any?) { onOpen?() }
    @objc func revealAction(_ sender: Any?) { onReveal?() }
    @objc func copyNameAction(_ sender: Any?) { onCopyName?() }
    @objc func copyImageAction(_ sender: Any?) { onCopyImage?() }
    @objc func copyPathAction(_ sender: Any?) { onCopyPath?() }
    @objc func trashAction(_ sender: Any?) { onTrash?() }
}

private struct EventMonitor: NSViewRepresentable {
    @Binding var scroll: ScrollAccumulator
    var model: BrowserModel
    var toasts: ToastModel
    var gridColumns: Int

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
        context.coordinator.gridColumns = gridColumns
        nsView.coordinator = context.coordinator
    }

    @MainActor
    final class Coordinator {
        var scroll: Binding<ScrollAccumulator>?
        var model: BrowserModel?
        var toasts: ToastModel?
        var gridColumns = 1

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
            case .moveRow(let rows):
                model.moveSelection(byRows: rows, columns: gridColumns, screenLongEdge: screenLongEdge())
                return nil
            case .focusSearch:
                NotificationCenter.default.post(name: .focusSearchRequested, object: nil)
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
            case .zoomIn:
                model.zoom(by: ZoomMath.step, screenLongEdge: screenLongEdge())
                return nil
            case .zoomOut:
                model.zoom(by: 1 / ZoomMath.step, screenLongEdge: screenLongEdge())
                return nil
            case .copyImage:
                NotificationCenter.default.post(name: .copyImageRequested, object: nil)
                return nil
            case .toggleCaptureInfo:
                NotificationCenter.default.post(name: .toggleCaptureInfoRequested, object: nil)
                return nil
            case .openFolder:
                return event
            }
        }

        func handleMagnify(_ event: NSEvent) -> NSEvent? {
            guard let model, model.mode == .viewer else { return event }
            model.applyMagnification(event.magnification, screenLongEdge: screenLongEdge())
            return nil
        }

        func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
            guard let model, let scroll, model.mode == .viewer else { return event }
            if event.modifierFlags.contains(.command) {
                model.applyScrollZoom(event.scrollingDeltaY, screenLongEdge: screenLongEdge())
                return nil
            }
            if model.prefersPan {
                model.panBy(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
                return nil
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
    private var magnifyMonitor: Any?

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
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
            MainActor.assumeIsolated {
                coordinator.handleMagnify(event)
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
        if let magnifyMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
            self.magnifyMonitor = nil
        }
    }
}
