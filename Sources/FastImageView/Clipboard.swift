import AppKit
import ImageIO
import UniformTypeIdentifiers
import FastImageViewCore

enum Clipboard {
    @discardableResult
    static func copyImage(at url: URL) -> Bool {
        copyImages(at: [url])
    }

    /// 每张图各写一个剪贴板项：文件 URL（可粘贴到访达）+ PNG/TIFF（可粘贴到文档/对话）。
    @discardableResult
    static func copyImages(at urls: [URL]) -> Bool {
        let existing = urls
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return false }

        let items = existing.compactMap(pasteboardItem(for:))
        guard !items.isEmpty else { return false }

        let board = NSPasteboard.general
        board.clearContents()
        return board.writeObjects(items)
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

    private static func pasteboardItem(for url: URL) -> NSPasteboardItem? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)

        if let image = image(at: url),
           let tiff = image.tiffRepresentation,
           !tiff.isEmpty {
            item.setData(tiff, forType: .tiff)
            if let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]),
               !png.isEmpty {
                item.setData(png, forType: .png)
            }
        }

        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .image),
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }

        return item
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
