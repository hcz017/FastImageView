import AppKit
import UniformTypeIdentifiers

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
