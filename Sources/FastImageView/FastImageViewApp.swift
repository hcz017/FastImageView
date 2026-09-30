import AppKit
import SwiftUI
import FastImageViewCore

@main
struct FastImageViewApp: App {
    @State private var model = BrowserModel.live()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件夹") { chooseFolder(model) }
                    .keyboardShortcut("o")
            }
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
