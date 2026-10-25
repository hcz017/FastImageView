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
    @State private var comparePanOrigin: ImagePan?
    @State private var gridColumns = 1
    @State private var pendingSearchFocus = false
    @State private var formatMenuPresented = false
    @State private var ratingMenuPresented = false
    @State private var captureSummary = ""
    @State private var showCaptureInfo = false
    @StateObject private var ratingFeedback = RatingFeedbackModel()
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
            case .compare:
                compareView
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle(windowTitle)
        .navigationSubtitle(toolbarSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if model.mode == .viewer || model.mode == .compare {
                    Button {
                        if model.mode == .compare {
                            model.closeCompare()
                        } else if model.canReturnToCompare {
                            model.returnToCompare(screenLongEdge: screenLongEdge())
                        } else {
                            model.closeViewer()
                        }
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
                compareToolbarItems
            }
            ToolbarItem(placement: .destructiveAction) {
                if model.mode != .noFolder, model.mode != .compare, model.catalog.selectedFile != nil {
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
                formatMenuPresented = false
                ratingMenuPresented = false
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .background {
            EventMonitor(
                scroll: $scroll,
                model: model,
                toasts: toasts,
                ratingFeedback: ratingFeedback,
                gridColumns: gridColumns,
                filterMenuPresented: formatMenuPresented || ratingMenuPresented
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
        case .compare:
            var text = "已选 \(model.compareFiles.count) · 共 \(model.catalog.files.count) 张"
            if model.compareZoom != .fit {
                text += " · \(model.compareZoomLabel)"
            }
            return text
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
        case .compare:
            let folder = model.folderURL?.lastPathComponent ?? "FastImageView"
            return "对比 \(model.compareFiles.count) 张 · \(folder)"
        case .noFolder:
            return "FastImageView"
        }
    }

    @ViewBuilder
    private var gridToolbarItems: some View {
        if model.mode == .grid {
            formatMenu
            ratingMenu
            compareButton
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
                Picker("显示方式", selection: fitPickerSelection) {
                    Text("适合").tag(Optional(ViewerFit.fit))
                    Text("100%").tag(Optional(ViewerFit.actual))
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("适合窗口 (0) / 实际像素 (1)")
                .accessibilityLabel("显示方式")
                Button {
                    showCaptureInfo.toggle()
                } label: {
                    Image(systemName: showCaptureInfo ? "info.circle.fill" : "info.circle")
                }
                .help(showCaptureInfo ? "隐藏图片信息 (I)" : "显示图片信息 (I)")
                .accessibilityLabel("图片信息")
                .accessibilityValue(showCaptureInfo ? "显示中" : "已隐藏")
            }
        }
    }

    @ViewBuilder
    private var compareButton: some View {
        let count = model.compareCandidateFiles.count
        Button {
            openCompare()
        } label: {
            Label(count == 2 || count == 3 ? "对比 \(count) 张" : "对比", systemImage: "rectangle.split.3x1")
        }
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .disabled(!model.canOpenCompare)
        .help("对比选中的 2–3 张图片 (P)")
        .accessibilityLabel("对比选中的图片")
    }

    @ViewBuilder
    private var compareToolbarItems: some View {
        if model.mode == .compare, !model.compareFiles.isEmpty {
            ControlGroup {
                Button {
                    model.zoomCompare(by: 1 / ZoomMath.step, screenLongEdge: screenLongEdge())
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("缩小 (⌘−)")
                .accessibilityLabel("缩小")
                Text(model.compareZoomLabel)
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 44)
                    .accessibilityLabel("缩放 \(model.compareZoomLabel)")
                Button {
                    model.zoomCompare(by: ZoomMath.step, screenLongEdge: screenLongEdge())
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("放大 (⌘+)")
                .accessibilityLabel("放大")
            }
            ControlGroup {
                Toggle("适合窗口", isOn: compareFitToggle)
                    .help("适合窗口")
                Toggle("实际像素", isOn: compareActualToggle)
                    .help("实际像素")
            }
        }
    }

    private var compareFitToggle: Binding<Bool> {
        Binding(
            get: { model.compareZoom == .fit },
            set: { if $0 { model.setCompareFit(.fit, screenLongEdge: screenLongEdge()) } }
        )
    }

    private var compareActualToggle: Binding<Bool> {
        Binding(
            get: {
                if case .actual = model.compareZoom { return true }
                return false
            },
            set: { if $0 { model.setCompareFit(.actual, screenLongEdge: screenLongEdge()) } }
        )
    }

    private func openCompare() {
        if !model.openCompare(screenLongEdge: screenLongEdge()) {
            toasts.show("请选择 2 到 3 张图片进行对比", canUndo: false)
        }
    }

    /// 分段控件只覆盖「适合 / 实际像素」两种状态；自定义缩放（⌘±、捏合、滚轮）
    /// 返回 nil，两个分段都不高亮，由左侧的缩放百分比标签说明当前比例。
    private var fitPickerSelection: Binding<ViewerFit?> {
        Binding(
            get: {
                switch model.zoom {
                case .fit: return .fit
                case .actual: return .actual
                case .multiple: return nil
                }
            },
            set: { fit in
                guard let fit else { return }
                model.setFit(fit, screenLongEdge: screenLongEdge())
            }
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
        Button {
            formatMenuPresented = true
        } label: {
            HStack(spacing: theme.spacingXS) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(formatMenuTitle)
                    .frame(minWidth: theme.formatMenuTitleMinWidth, alignment: .leading)
            }
        }
        .fixedSize()
        .help("按格式筛选")
        .disabled(model.catalog.availableFormats.isEmpty)
        .popover(isPresented: $formatMenuPresented) {
            formatMenuContent
        }
        .accessibilityLabel("按格式筛选")
        .accessibilityValue(formatMenuTitle)
    }

    private var formatMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            FilterMenuRow(
                title: "全部格式",
                checked: model.catalog.selectedFormats.isEmpty,
                enabled: !model.catalog.selectedFormats.isEmpty,
                action: clearFormats
            )
            Divider()
                .padding(.vertical, theme.spacingXS)
            ForEach(model.catalog.availableFormats, id: \.self) { format in
                FilterMenuRow(
                    title: format.badge,
                    checked: model.catalog.selectedFormats.contains(format),
                    enabled: true,
                    action: { model.toggleFormat(format) }
                )
            }
        }
        .padding(theme.spacingXS)
        .frame(minWidth: theme.formatMenuWidth, alignment: .leading)
    }

    private var ratingMenu: some View {
        Button {
            ratingMenuPresented = true
        } label: {
            HStack(spacing: theme.spacingXS) {
                Image(systemName: model.catalog.hasRatingFilter ? "star.circle.fill" : "star.circle")
                Text("分级")
            }
        }
        .fixedSize()
        .help("按分级筛选")
        .popover(isPresented: $ratingMenuPresented) {
            ratingMenuContent
        }
        .accessibilityLabel("按分级筛选")
        .accessibilityValue(model.catalog.hasRatingFilter ? "已启用筛选" : "未启用筛选")
    }

    private var ratingMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            FilterMenuRow(
                title: "全部评级",
                checked: !model.catalog.hasRatingFilter,
                enabled: model.catalog.hasRatingFilter,
                reservesRatingSlot: true,
                action: model.clearRatingFilter
            )
            FilterMenuRow(
                title: "未分级",
                checked: model.catalog.includesUnrated,
                enabled: true,
                reservesRatingSlot: true,
                action: model.toggleUnratedFilter
            )
            Divider()
                .padding(.vertical, theme.spacingXS)
            ForEach(1...5, id: \.self) { level in
                FilterMenuRow(
                    title: "\(level) 级",
                    checked: model.catalog.selectedRatings.contains(level),
                    enabled: true,
                    ratingLevel: level,
                    action: { model.toggleRatingFilter(level) }
                )
            }
        }
        .padding(theme.spacingXS)
        .frame(minWidth: theme.formatMenuWidth, alignment: .leading)
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

    private func clearFormats() {
        let formats = model.catalog.selectedFormats
        for format in formats {
            model.toggleFormat(format)
        }
    }

    private func clearFilters() {
        model.setKeyword("")
        clearFormats()
        model.clearRatingFilter()
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
            .overlay(alignment: .bottomTrailing) {
                if let level = model.rating(for: file) {
                    RatingBadge(level: level)
                        .padding(theme.spacingXS)
                }
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
        let compareCount = model.compareCandidateFiles.count
        let model = self.model
        let toasts = self.toasts
        let target = ContextMenuTarget()
        target.onOpen = {
            model.openViewer(screenLongEdge: screenLongEdge())
        }
        target.onCompare = {
            if !model.openCompare(screenLongEdge: screenLongEdge()) {
                toasts.show("请选择 2 到 3 张图片进行对比", canUndo: false)
            }
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
        target.onRate = { level in
            model.setRating(level)
        }
        target.onClearRating = {
            model.clearRating()
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        if canOpenViewer {
            addContextItem(menu, title: "在大图中打开", action: #selector(ContextMenuTarget.openAction(_:)), target: target)
        }
        if (2...3).contains(compareCount) {
            addContextItem(menu, title: "对比 \(compareCount) 张", action: #selector(ContextMenuTarget.compareAction(_:)), target: target)
        }
        addContextItem(menu, title: "在访达中显示", action: #selector(ContextMenuTarget.revealAction(_:)), target: target)
        addContextItem(menu, title: copy.filenames.count > 1 ? "拷贝 \(copy.filenames.count) 个文件名" : "拷贝文件名", action: #selector(ContextMenuTarget.copyNameAction(_:)), target: target)
        addContextItem(menu, title: copy.urls.count > 1 ? "拷贝 \(copy.urls.count) 张图片" : "拷贝图片", action: #selector(ContextMenuTarget.copyImageAction(_:)), target: target)
        addContextItem(menu, title: copy.paths.count > 1 ? "拷贝 \(copy.paths.count) 个路径" : "拷贝路径", action: #selector(ContextMenuTarget.copyPathAction(_:)), target: target)
        addRatingSubmenu(to: menu, target: target, targets: model.catalog.deletionTargets)
        menu.addItem(.separator())
        addContextItem(menu, title: "移到废纸篓", action: #selector(ContextMenuTarget.trashAction(_:)), target: target)
        return menu
    }

    /// 网格右键的「分级」子菜单：多选且等级不一致时不勾选任何项。
    private func addRatingSubmenu(to menu: NSMenu, target: ContextMenuTarget, targets: [ImageFile]) {
        let levels = Set(targets.compactMap { model.rating(for: $0) })
        let current = levels.count == 1 ? levels.first : nil
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for level in 1...5 {
            let item = NSMenuItem(
                title: "\(level) 级",
                action: #selector(ContextMenuTarget.rateAction(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = level
            item.state = current == level ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let clear = NSMenuItem(
            title: "清除分级",
            action: #selector(ContextMenuTarget.clearRatingAction(_:)),
            keyEquivalent: ""
        )
        clear.target = target
        clear.isEnabled = !levels.isEmpty
        submenu.addItem(clear)
        let root = NSMenuItem(title: "分级", action: nil, keyEquivalent: "")
        root.submenu = submenu
        menu.addItem(root)
    }

    @ViewBuilder
    private func ratingContextMenu(_ file: ImageFile) -> some View {
        let current = model.rating(for: file)
        Menu("分级") {
            ForEach(1...5, id: \.self) { level in
                Button {
                    ratingFeedback.rate(level, in: model)
                } label: {
                    if current == level {
                        Label("\(level) 级", systemImage: "checkmark")
                    } else {
                        Text("\(level) 级")
                    }
                }
            }
            Divider()
            Button("清除分级") { ratingFeedback.clear(in: model) }
                .disabled(current == nil)
        }
    }

    private func addContextItem(_ menu: NSMenu, title: String, action: Selector, target: ContextMenuTarget) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = target
        menu.addItem(item)
    }

    // MARK: - 对比

    private var compareView: some View {
        let _ = model.renderGeneration
        return HStack(spacing: 0) {
            ForEach(Array(model.compareFiles.enumerated()), id: \.element.url) { entry in
                if entry.offset > 0 {
                    Divider()
                }
                comparePane(file: entry.element, index: entry.offset)
            }
        }
        .background(theme.viewerCanvas)
    }

    private func comparePane(file: ImageFile, index: Int) -> some View {
        GeometryReader { geo in
            let metrics = compareMetrics(file: file, viewport: geo.size)
            ZStack {
                compareContent(file, metrics: metrics.content)
                    .frame(width: metrics.content.width, height: metrics.content.height)
                    .offset(x: model.comparePan.x, y: model.comparePan.y)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(compareDrag)
            .onTapGesture(count: 2) {
                model.openViewerFromCompare(url: file.url, screenLongEdge: screenLongEdge())
            }
            .onAppear {
                publishCompareLayout(file: file, metrics: metrics, viewport: geo.size)
            }
            .onChange(of: geo.size) { _, size in
                publishCompareLayout(file: file, metrics: compareMetrics(file: file, viewport: size), viewport: size)
            }
            .onChange(of: model.compareZoom) { _, _ in
                publishCompareLayout(file: file, metrics: compareMetrics(file: file, viewport: geo.size), viewport: geo.size)
            }
            .onChange(of: model.renderGeneration) { _, _ in
                publishCompareLayout(file: file, metrics: compareMetrics(file: file, viewport: geo.size), viewport: geo.size)
            }
            .overlay(alignment: .bottom) {
                compareLabel(file, index: index)
            }
            .contextMenu {
                Button("在大图中打开") {
                    model.openViewerFromCompare(url: file.url, screenLongEdge: screenLongEdge())
                }
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
                Button("拷贝文件名") { Clipboard.copyFilenames([file.filename]) }
                Button("拷贝图片") { copyImages([file.url]) }
                Button("拷贝路径") { Clipboard.copyPaths([file.url.path]) }
            }
        }
    }

    @ViewBuilder
    private func compareContent(_ file: ImageFile, metrics: CGSize) -> some View {
        if file.iCloudState == .notDownloaded {
            StatePlaceholder(icon: "icloud.and.arrow.down", message: "未下载")
                .frame(width: metrics.width, height: metrics.height)
        } else if model.failed(file.url) {
            StatePlaceholder(icon: "exclamationmark.triangle", message: "无法打开")
                .frame(width: metrics.width, height: metrics.height)
                .onAppear { model.noteUnavailable(file.url) }
        } else if let image = model.cachedViewerImage(file) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: metrics.width, height: metrics.height)
        } else {
            StatePlaceholder(icon: "photo", message: "加载中…")
                .frame(width: metrics.width, height: metrics.height)
        }
    }

    private func compareMetrics(file: ImageFile, viewport: CGSize) -> (fitScale: Double, content: CGSize) {
        guard let source = model.compareSourceSize(for: file)
            ?? model.cachedViewerImage(file).map({ ImagePixelSize(width: $0.width, height: $0.height) })
        else {
            return (1, CGSize(width: viewport.width, height: viewport.height))
        }
        let pad = Double(theme.spacingLG)
        let fitW = max(Double(viewport.width) - pad * 2, 1)
        let fitH = max(Double(viewport.height) - pad * 2, 1)
        let fitScale = ZoomMath.fitScale(
            imageWidth: Double(source.width),
            imageHeight: Double(source.height),
            viewportWidth: fitW,
            viewportHeight: fitH
        )
        let display = ZoomMath.displayScale(
            fitScale: fitScale,
            multiple: model.compareMultiple(fitScale: fitScale)
        )
        return (
            fitScale,
            CGSize(width: Double(source.width) * display, height: Double(source.height) * display)
        )
    }

    private func publishCompareLayout(file: ImageFile, metrics: (fitScale: Double, content: CGSize), viewport: CGSize) {
        model.noteCompareLayout(
            url: file.url,
            layout: ViewerLayout(
                contentWidth: Double(metrics.content.width),
                contentHeight: Double(metrics.content.height),
                viewportWidth: Double(viewport.width),
                viewportHeight: Double(viewport.height),
                fitScale: metrics.fitScale
            )
        )
    }

    private var compareDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if comparePanOrigin == nil { comparePanOrigin = model.comparePan }
                let origin = comparePanOrigin ?? .zero
                model.setComparePan(
                    x: origin.x + Double(value.translation.width),
                    y: origin.y + Double(value.translation.height)
                )
            }
            .onEnded { _ in
                comparePanOrigin = nil
            }
    }

    private func compareLabel(_ file: ImageFile, index: Int) -> some View {
        HStack(spacing: theme.spacingSM) {
            Text("\(index + 1)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            Text(file.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, theme.spacingMD)
        .padding(.vertical, theme.spacingXS)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, theme.spacingMD)
        .allowsHitTesting(false)
        .accessibilityLabel("第 \(index + 1) 张，\(file.filename)")
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
                ratingContextMenu(file)
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
            .overlay(alignment: .bottomTrailing) {
                if let feedback = ratingFeedback.current {
                    RatingFeedbackBadge(level: feedback.level, clearing: feedback.clearing)
                        .id(feedback.id)
                        .padding(theme.spacingXL)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
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
                ratingFeedback.dismiss()
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
        if model.mode == .compare {
            pendingSearchFocus = true
            model.closeCompare()
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
            .frame(height: theme.badgeHeight)
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

/// 大图右下角的分级反馈：设置时弹出黄色徽标，取消时先褪色再淡出。
@MainActor
private final class RatingFeedbackModel: ObservableObject {
    struct Feedback: Identifiable, Equatable {
        let id = UUID()
        let level: Int
        let clearing: Bool
    }

    @Published private(set) var current: Feedback?
    private var dismissTask: Task<Void, Never>?

    /// 设置分级；若目标本来已是该级，BrowserModel 会清除它，此时播放褪色动画。
    func rate(_ level: Int, in model: BrowserModel) {
        let previous = model.catalog.selectedFile.flatMap { model.rating(for: $0) }
        model.setRating(level)
        let updated = model.catalog.selectedFile.flatMap { model.rating(for: $0) }
        if let updated {
            show(Feedback(level: updated, clearing: false))
        } else if let previous {
            show(Feedback(level: previous, clearing: true))
        }
    }

    func clear(in model: BrowserModel) {
        let previous = model.catalog.selectedFile.flatMap { model.rating(for: $0) }
        model.clearRating()
        if let previous {
            show(Feedback(level: previous, clearing: true))
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }

    private func show(_ feedback: Feedback) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            current = feedback
        }
        let delay: UInt64 = feedback.clearing ? 1_100_000_000 : 900_000_000
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, self?.current?.id == feedback.id else { return }
            withAnimation(.easeOut(duration: feedback.clearing ? 0.4 : 0.28)) {
                self?.current = nil
            }
        }
    }
}

/// 设置分级时弹入黄色徽标；取消分级时先褪色，再由外层淡出。
private struct RatingFeedbackBadge: View {
    @Environment(\.appTheme) private var theme
    let level: Int
    let clearing: Bool
    @State private var appeared = false
    @State private var desaturated = false

    var body: some View {
        RatingBadge(level: level, size: theme.ratingFeedbackSize)
            .saturation(desaturated ? 0 : 1)
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    appeared = true
                }
            }
            .task(id: clearing) {
                guard clearing else { return }
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.easeInOut(duration: 0.4)) {
                    desaturated = true
                }
            }
            .accessibilityLabel(clearing ? "已取消分级" : "分级 \(level)")
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

/// 筛选面板中的一行：点击只切换勾选，不关闭面板。
private struct FilterMenuRow: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let checked: Bool
    let enabled: Bool
    var reservesRatingSlot = false
    var ratingLevel: Int?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacingSM) {
                if let ratingLevel {
                    RatingBadge(level: ratingLevel, showsShadow: false)
                    .accessibilityHidden(true)
                } else if reservesRatingSlot {
                    Color.clear
                        .frame(width: theme.badgeHeight, height: theme.badgeHeight)
                }
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: theme.spacingSM)
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .opacity(checked ? 1 : 0)
                    .frame(width: theme.menuCheckmarkWidth, alignment: .trailing)
            }
            .padding(.horizontal, theme.spacingSM)
            .padding(.vertical, theme.spacingXS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.radiusBadge)
                    .fill(hovered && enabled ? theme.recentRowHoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .accessibilityValue(checked ? "已勾选" : "未勾选")
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
    var onCompare: (() -> Void)?
    var onReveal: (() -> Void)?
    var onCopyName: (() -> Void)?
    var onCopyImage: (() -> Void)?
    var onCopyPath: (() -> Void)?
    var onTrash: (() -> Void)?
    var onRate: ((Int) -> Void)?
    var onClearRating: (() -> Void)?

    @objc func openAction(_ sender: Any?) { onOpen?() }
    @objc func compareAction(_ sender: Any?) { onCompare?() }
    @objc func revealAction(_ sender: Any?) { onReveal?() }
    @objc func copyNameAction(_ sender: Any?) { onCopyName?() }
    @objc func copyImageAction(_ sender: Any?) { onCopyImage?() }
    @objc func copyPathAction(_ sender: Any?) { onCopyPath?() }
    @objc func trashAction(_ sender: Any?) { onTrash?() }
    @objc func rateAction(_ sender: NSMenuItem) { onRate?(sender.tag) }
    @objc func clearRatingAction(_ sender: Any?) { onClearRating?() }
}

private struct EventMonitor: NSViewRepresentable {
    @Binding var scroll: ScrollAccumulator
    var model: BrowserModel
    var toasts: ToastModel
    var ratingFeedback: RatingFeedbackModel
    var gridColumns: Int
    var filterMenuPresented: Bool

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
        context.coordinator.ratingFeedback = ratingFeedback
        context.coordinator.gridColumns = gridColumns
        context.coordinator.filterMenuPresented = filterMenuPresented
        nsView.coordinator = context.coordinator
    }

    @MainActor
    final class Coordinator {
        var scroll: Binding<ScrollAccumulator>?
        var model: BrowserModel?
        var toasts: ToastModel?
        var ratingFeedback: RatingFeedbackModel?
        var gridColumns = 1
        var filterMenuPresented = false

        func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard let model else { return event }
            // 筛选面板打开时按键交给面板处理（Esc 关闭），不再驱动网格选择/打开/删除。
            if filterMenuPresented { return event }
            let chord = KeyChord(
                keyCode: event.keyCode,
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
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
            case .setRating(let level):
                if model.mode == .viewer {
                    ratingFeedback?.rate(level, in: model)
                } else {
                    model.setRating(level)
                }
                return nil
            case .toggleRatingFilter(let level):
                model.toggleRatingFilter(level)
                return nil
            case .focusSearch:
                NotificationCenter.default.post(name: .focusSearchRequested, object: nil)
                return nil
            case .openViewer:
                NSApp.keyWindow?.makeFirstResponder(nil)
                model.openViewer(screenLongEdge: screenLongEdge())
                return nil
            case .openCompare:
                if !model.openCompare(screenLongEdge: screenLongEdge()) {
                    toasts?.show("请选择 2 到 3 张图片进行对比", canUndo: false)
                }
                return nil
            case .closeViewer:
                if model.mode == .compare {
                    model.closeCompare()
                } else if model.canReturnToCompare {
                    model.returnToCompare(screenLongEdge: screenLongEdge())
                } else {
                    model.closeViewer()
                }
                return nil
            case .zoomIn:
                if model.mode == .compare {
                    model.zoomCompare(by: ZoomMath.step, screenLongEdge: screenLongEdge())
                } else {
                    model.zoom(by: ZoomMath.step, screenLongEdge: screenLongEdge())
                }
                return nil
            case .zoomOut:
                if model.mode == .compare {
                    model.zoomCompare(by: 1 / ZoomMath.step, screenLongEdge: screenLongEdge())
                } else {
                    model.zoom(by: 1 / ZoomMath.step, screenLongEdge: screenLongEdge())
                }
                return nil
            case .copyImage:
                NotificationCenter.default.post(name: .copyImageRequested, object: nil)
                return nil
            case .toggleCaptureInfo:
                NotificationCenter.default.post(name: .toggleCaptureInfoRequested, object: nil)
                return nil
            case .consume:
                return nil
            case .openFolder:
                return event
            }
        }

        func handleMagnify(_ event: NSEvent) -> NSEvent? {
            guard let model else { return event }
            switch model.mode {
            case .viewer:
                model.applyMagnification(event.magnification, screenLongEdge: screenLongEdge())
                return nil
            case .compare:
                model.applyCompareMagnification(event.magnification, screenLongEdge: screenLongEdge())
                return nil
            case .grid, .noFolder:
                return event
            }
        }

        func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
            guard let model, let scroll else { return event }
            if model.mode == .compare {
                if event.modifierFlags.contains(.command) {
                    // 惯性事件会带上一段手势的余量，混进缩放会突然改变倍率。
                    if event.momentumPhase.isEmpty {
                        model.applyCompareScrollZoom(event.scrollingDeltaY, screenLongEdge: screenLongEdge())
                    }
                } else if model.comparePrefersPan {
                    model.comparePanBy(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
                }
                return nil
            }
            guard model.mode == .viewer else { return event }
            if event.modifierFlags.contains(.command) {
                if event.momentumPhase.isEmpty {
                    model.applyScrollZoom(event.scrollingDeltaY, screenLongEdge: screenLongEdge())
                }
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
