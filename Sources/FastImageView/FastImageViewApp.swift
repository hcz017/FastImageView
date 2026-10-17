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
