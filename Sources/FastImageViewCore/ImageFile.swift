import Foundation

public enum ImageFormat: String, CaseIterable, Equatable, Sendable {
    case jpeg, png, heic, gif, tiff, webp, bmp
    case nef, cr2, cr3, arw, raf, orf, rw2, dng, pef

    public var isRaw: Bool {
        switch self {
        case .nef, .cr2, .cr3, .arw, .raf, .orf, .rw2, .dng, .pef:
            return true
        case .jpeg, .png, .heic, .gif, .tiff, .webp, .bmp:
            return false
        }
    }

    private static let byExtension: [String: ImageFormat] = [
        "jpg": .jpeg, "jpeg": .jpeg, "png": .png, "heic": .heic, "heif": .heic,
        "gif": .gif, "tif": .tiff, "tiff": .tiff, "webp": .webp, "bmp": .bmp,
        "nef": .nef, "cr2": .cr2, "cr3": .cr3, "arw": .arw, "raf": .raf,
        "orf": .orf, "rw2": .rw2, "dng": .dng, "pef": .pef
    ]

    public static func from(filename: String) -> ImageFormat? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return byExtension[ext]
    }
}

public enum ICloudState: Equatable, Sendable {
    case notCloud
    case downloaded
    case notDownloaded

    public static func map(isUbiquitous: Bool, status: URLUbiquitousItemDownloadingStatus?) -> ICloudState {
        guard isUbiquitous else { return .notCloud }
        if status == .notDownloaded { return .notDownloaded }
        return .downloaded
    }
}

public struct ImageFile: Equatable, Identifiable, Sendable {
    public var id: URL { url }
    public var url: URL
    public var filename: String
    public var format: ImageFormat
    public var modificationDate: Date
    public var iCloudState: ICloudState

    public init(url: URL, filename: String, format: ImageFormat, modificationDate: Date, iCloudState: ICloudState) {
        self.url = url
        self.filename = filename
        self.format = format
        self.modificationDate = modificationDate
        self.iCloudState = iCloudState
    }
}
