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
            CommandGroup(after: .toolbar) {
                Button("放大") {
                    model.zoom(by: ZoomMath.step, screenLongEdge: screenLongEdge())
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(model.mode != .viewer)
                Button("缩小") {
                    model.zoom(by: 1 / ZoomMath.step, screenLongEdge: screenLongEdge())
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model.mode != .viewer)
                Button("适合窗口") {
                    model.setFit(.fit, screenLongEdge: screenLongEdge())
                }
                .keyboardShortcut("0")
                .disabled(model.mode != .viewer)
                Button("实际像素") {
                    model.setFit(.actual, screenLongEdge: screenLongEdge())
                }
                .keyboardShortcut("1")
                .disabled(model.mode != .viewer)
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
}

@MainActor
func showShortcutsHelp() {
    let alert = NSAlert()
    alert.messageText = "键盘快捷键"
    alert.informativeText = """
    ⌘O  打开文件夹
    ← →  上一张 / 下一张
    ↑ ↓  在网格中移动选中项
    空格  打开 / 关闭大图
    0 / 1  适合窗口 / 实际像素
    ⌘+ / ⌘−  放大 / 缩小
    ⌘滚轮 / 捏合  连续缩放
    拖拽  放大后平移
    Return  打开大图
    Delete / ⌘⌫  移到废纸篓
    ⌘Z  撤销移到废纸篓
    Esc  回到网格
    """
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
