import AppKit
import ImageIO
import UniformTypeIdentifiers
import FastImageViewCore

enum Clipboard {
    @discardableResult
    static func copyImage(at url: URL) -> Bool {
        guard let image = image(at: url) else { return false }
        guard let tiff = image.tiffRepresentation, !tiff.isEmpty else { return false }

        let board = NSPasteboard.general
        board.clearContents()
        // 不要用 writeObjects([NSImage])：它通常只放 TIFF，很多应用粘贴需要 PNG。
        var wrote = board.setData(tiff, forType: .tiff)
        if let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           !png.isEmpty {
            wrote = board.setData(png, forType: .png) || wrote
        }
        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .image),
           let data = try? Data(contentsOf: url),
           !data.isEmpty {
            let pasteType = NSPasteboard.PasteboardType(type.identifier)
            wrote = board.setData(data, forType: pasteType) || wrote
        }
        return wrote
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
