import Foundation

/// 按需下载云盘上尚未物化的文件（iCloud Drive 与 OneDrive 等 File Provider 网盘均适用）。
public protocol CloudDownloading: AnyObject {
    /// 发起下载请求；返回是否成功交给系统。
    func requestDownload(url: URL) -> Bool
    /// 复查当前下载状态；查询失败时返回 nil。
    func state(of url: URL) -> ICloudState?
}

public final class UbiquitousDownloader: CloudDownloading, @unchecked Sendable {
    private static let keys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
    ]

    public init() {}

    public func requestDownload(url: URL) -> Bool {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return true
        } catch {
            return false
        }
    }

    public func state(of url: URL) -> ICloudState? {
        guard let values = try? url.resourceValues(forKeys: Self.keys) else { return nil }
        return ICloudState.map(
            isUbiquitous: values.isUbiquitousItem == true,
            status: values.ubiquitousItemDownloadingStatus
        )
    }
}
