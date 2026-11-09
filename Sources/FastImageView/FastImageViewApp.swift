import AppKit
import SwiftUI
import FastImageViewCore

@main
struct FastImageViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = BrowserModel.live()

    init() {
        // `swift run` 启动的是裸可执行文件，没有 app bundle。
        // AppKit 因此不会把它变成前台应用，窗口也不会显示。
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    var body: some Scene {
        Window("FastImageView", id: "browser") {
            ContentView(model: model)
                .environment(\.appTheme, AppTheme())
                .background(SingleWindow())
                .onAppear { appDelegate.attach(model) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件夹") { chooseFolder(model) }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("搜索文件名") {
                    NotificationCenter.default.post(name: .focusSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(model.mode == .noFolder)
                Menu("打开最近") {
                    ForEach(model.recentFolders, id: \.path) { url in
                        Button(url.lastPathComponent) { model.open(folder: url) }
                    }
                }
                .disabled(model.recentFolders.isEmpty)
            }
            CommandGroup(after: .undoRedo) {
                Button("撤销移到废纸篓") {
                    NotificationCenter.default.post(name: .undoTrashRequested, object: nil)
                }
                .disabled(!model.canUndo)
            }
            CommandGroup(after: .pasteboard) {
                Button("拷贝图片") {
                    NotificationCenter.default.post(name: .copyImageRequested, object: nil)
                }
                .disabled(model.catalog.selectedFile == nil)
                Button("拷贝路径") {
                    NotificationCenter.default.post(name: .copyPathsRequested, object: nil)
                }
                .disabled(model.catalog.selectedFile == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("放大") {
                    if model.mode == .compare {
                        model.zoomCompare(by: ZoomMath.step, screenLongEdge: screenLongEdge())
                    } else {
                        model.zoom(by: ZoomMath.step, screenLongEdge: screenLongEdge())
                    }
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(model.mode != .viewer && model.mode != .compare)
                Button("缩小") {
                    if model.mode == .compare {
                        model.zoomCompare(by: 1 / ZoomMath.step, screenLongEdge: screenLongEdge())
                    } else {
                        model.zoom(by: 1 / ZoomMath.step, screenLongEdge: screenLongEdge())
                    }
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model.mode != .viewer && model.mode != .compare)
                Button("适合窗口") {
                    if model.mode == .compare {
                        model.setCompareFit(.fit, screenLongEdge: screenLongEdge())
                    } else {
                        model.setFit(.fit, screenLongEdge: screenLongEdge())
                    }
                }
                .disabled(model.mode != .viewer && model.mode != .compare)
                Button("实际像素") {
                    if model.mode == .compare {
                        model.setCompareFit(.actual, screenLongEdge: screenLongEdge())
                    } else {
                        model.setFit(.actual, screenLongEdge: screenLongEdge())
                    }
                }
                .disabled(model.mode != .viewer && model.mode != .compare)
            }
            CommandGroup(replacing: .help) {
                Button("键盘快捷键…") { showShortcutsHelp() }
            }
        }
    }
}

private struct SingleWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SingleWindowView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SingleWindowView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.tabbingMode = .disallowed
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: BrowserModel?
    private var pendingFile: URL?

    func attach(_ model: BrowserModel) {
        self.model = model
        guard let file = pendingFile else { return }
        pendingFile = nil
        model.openImageFile(file, screenLongEdge: screenLongEdge())
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let file = urls.first else { return }
        if let model {
            model.openImageFile(file, screenLongEdge: screenLongEdge())
        } else {
            pendingFile = file
        }
    }
}

extension Notification.Name {
    static let undoTrashRequested = Notification.Name("FastImageView.undoTrashRequested")
    static let copyImageRequested = Notification.Name("FastImageView.copyImageRequested")
    static let copyPathsRequested = Notification.Name("FastImageView.copyPathsRequested")
    static let focusSearchRequested = Notification.Name("FastImageView.focusSearchRequested")
    static let toggleCaptureInfoRequested = Notification.Name("FastImageView.toggleCaptureInfoRequested")
}

@MainActor
func showShortcutsHelp() {
    let shortcuts: [(keys: String, action: String)] = [
        ("⌘O", "打开文件夹"),
        ("← →", "上一张 / 下一张"),
        ("↑ ↓", "在网格中按行移动"),
        ("⌘F", "搜索文件名"),
        ("空格", "打开 / 关闭大图"),
        ("1–5", "设置分级"),
        ("⇧1–⇧5", "切换分级筛选（仅网格）"),
        ("P", "对比选中的 2–3 张图片"),
        ("I", "显示 / 隐藏图片信息"),
        ("⌘+ / ⌘−", "放大 / 缩小"),
        ("⌘滚轮 / 捏合", "连续缩放"),
        ("拖拽", "放大后平移"),
        ("⌘点击 / ⇧点击", "多选"),
        ("Return", "打开大图"),
        ("Delete / ⌘⌫", "移到废纸篓"),
        ("⌘C", "拷贝图片"),
        ("⌘Z", "撤销移到废纸篓"),
        ("Esc", "回到网格"),
    ]

    let keyFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    // 按键列宽度取内容最宽者，保证两列对齐。
    let keyColumnWidth = shortcuts.reduce(CGFloat(0)) { width, shortcut in
        let size = (shortcut.keys as NSString).size(withAttributes: [.font: keyFont])
        return max(width, ceil(size.width))
    } + 8

    let rows = shortcuts.map { shortcut -> NSStackView in
        let keyLabel = NSTextField(labelWithString: shortcut.keys)
        keyLabel.font = keyFont
        keyLabel.textColor = .labelColor
        keyLabel.alignment = .right
        keyLabel.widthAnchor.constraint(equalToConstant: keyColumnWidth).isActive = true

        let actionLabel = NSTextField(labelWithString: shortcut.action)
        actionLabel.font = .systemFont(ofSize: 12)
        actionLabel.textColor = .secondaryLabelColor

        let row = NSStackView(views: [keyLabel, actionLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }

    let grid = NSStackView(views: rows)
    grid.orientation = .vertical
    grid.alignment = .leading
    grid.spacing = 6
    grid.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
    grid.setFrameSize(grid.fittingSize)

    let alert = NSAlert()
    alert.messageText = "键盘快捷键"
    alert.accessoryView = grid
    alert.addButton(withTitle: "好")
    alert.runModal()
}

@MainActor
func chooseFolder(_ model: BrowserModel) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "打开"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    model.open(folder: url)
}
