import AppKit
import ImageIO
import UniformTypeIdentifiers
import FastImageViewCore

enum Clipboard {
    @discardableResult
    static func copyImage(at url: URL) -> Bool {
        copyImages(at: [url])
    }

    /// 把图片文件放进剪贴板：可粘贴到访达文件夹；单张时额外提供 PNG/TIFF 方便贴进对话或文档。
    @discardableResult
    static func copyImages(at urls: [URL]) -> Bool {
        let existing = urls
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return false }

        let board = NSPasteboard.general
        board.clearContents()
        // 文件 URL（含 NSFilenamesPboardType）才能粘贴到访达。
        guard board.writeObjects(existing as [NSURL]) else { return false }

        if existing.count == 1, let url = existing.first {
            attachBitmapRepresentations(of: url, to: board)
        }
        return true
    }

    static func copyPaths(_ paths: [String]) {
        copyLines(paths)
    }

    static func copyFilenames(_ names: [String]) {
        copyLines(names)
    }

    private static func copyLines(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private static func attachBitmapRepresentations(of url: URL, to board: NSPasteboard) {
        guard let image = image(at: url),
              let tiff = image.tiffRepresentation,
              !tiff.isEmpty else { return }
        _ = board.setData(tiff, forType: .tiff)
        if let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           !png.isEmpty {
            _ = board.setData(png, forType: .png)
        }
        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .image),
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            _ = board.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
    }

    private static func image(at url: URL) -> NSImage? {
        if let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0 {
            return image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = ImageIOThumbnailOptions.dictionary(maxPixelSize: 4096) as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

enum FileDrop {
    static func load(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let type = UTType.fileURL.identifier
            guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
            if let url = await itemURL(provider, type: type) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func itemURL(_ provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
