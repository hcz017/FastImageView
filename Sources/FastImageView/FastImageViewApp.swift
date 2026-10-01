import AppKit
import SwiftUI
import FastImageViewCore

@main
struct FastImageViewApp: App {
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
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件夹") { chooseFolder(model) }
                    .keyboardShortcut("o")
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
func chooseFolder(_ model: BrowserModel) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "打开"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    model.open(folder: url)
}
