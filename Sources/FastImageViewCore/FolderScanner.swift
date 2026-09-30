import Foundation

public struct FolderScanner: Sendable {
    public init() {}

    public func scan(folder: URL) throws -> [ImageFile] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isHiddenKey, .contentModificationDateKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        var files: [ImageFile] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isHidden == true || values.isRegularFile != true { continue }
            let filename = url.lastPathComponent
            guard let format = ImageFormat.from(filename: filename) else { continue }
            let date = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
            let cloud = ICloudState.map(
                isUbiquitous: values.isUbiquitousItem == true,
                status: values.ubiquitousItemDownloadingStatus
            )
            files.append(ImageFile(url: url, filename: filename, format: format, modificationDate: date, iCloudState: cloud))
        }
        files.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        return files
    }
}

extension FolderScanner: FolderScanning {}
