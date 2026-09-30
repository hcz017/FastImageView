import AppKit
import Combine
import SwiftUI
import FastImageViewCore

struct ContentView: View {
    @Bindable var model: BrowserModel
    @FocusState private var keywordFocused: Bool

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
                    Text(file.filename).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
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
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            model.syncPreviewGeneration()
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
        .onTapGesture { select(file) }
        .onTapGesture(count: 2) {
            select(file)
            model.openViewer(screenLongEdge: screenLongEdge())
        }
        .onAppear { model.thumbnailRequest(file) }
    }

    private func select(_ file: ImageFile) {
        model.select(url: file.url)
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
