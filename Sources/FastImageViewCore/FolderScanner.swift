import Foundation

public struct FolderScanner: Sendable {
    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isHiddenKey, .contentModificationDateKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
    ]

    public init() {}

    public func scan(folder: URL) throws -> [ImageFile] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Self.keys,
            options: [.skipsHiddenFiles]
        )
        var files: [ImageFile] = []
        files.reserveCapacity(urls.count)
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { continue }
            if let file = Self.file(url: url, values: values) {
                files.append(file)
            }
        }
        files.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        return files
    }

    /// 只读取一个文件的元数据，用于从访达打开单图时先显示，不必等目录扫描完成。
    public static func file(url: URL) -> ImageFile? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        return file(url: url, values: values)
    }

    private static func file(url: URL, values: URLResourceValues) -> ImageFile? {
        if values.isHidden == true || values.isRegularFile != true { return nil }
        let filename = url.lastPathComponent
        guard let format = ImageFormat.from(filename: filename) else { return nil }
        let date = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        let cloud = ICloudState.map(
            isUbiquitous: values.isUbiquitousItem == true,
            status: values.ubiquitousItemDownloadingStatus
        )
        return ImageFile(url: url, filename: filename, format: format, modificationDate: date, iCloudState: cloud)
    }
}

extension FolderScanner: FolderScanning {}
