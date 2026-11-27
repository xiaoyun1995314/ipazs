// 软件源（AltStore / SideStore appstore.json）管理与拉取。
// 与 Apple App Store 官方搜索并列：用户添加第三方软件源 URL，本模块拉取并聚合源内应用，
// IPA 下载复用现有 DownloadManager.enqueueURL 进入下载队列。

import Foundation
import UIKit

/// 一个用户添加的软件源。
struct AppStoreSource: Codable, Identifiable, Equatable, Hashable {
    var id: String = UUID().uuidString
    /// 用户可读名称（默认取源 JSON 的 name，未取到时用主机名）。
    var title: String
    /// 软件源 JSON 地址（appstore.json）。
    var url: String
    /// 源图标地址（源 JSON 的 iconURL / sidebarIcon）。
    var iconURL: URL?
    /// 最近一次成功同步时间。
    var lastSynced: Date?
    /// 最近一次同步出错信息。
    var syncError: String?
    /// 源内应用数量（最近一次同步）。
    var appCount: Int = 0

    var normalizedURL: URL? { URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

/// 源内的一个应用条目，转换为现有 StoreApp 供下载/展示。
struct SourceApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let version: String
    let size: Int64
    let downloadURL: URL
    let iconURL: URL?
    let developer: String
    let subtitle: String
    let description: String
    let category: String
    let minimumOS: String?
    let sourceID: String
    let sourceTitle: String

    func asStoreApp() -> StoreApp {
        var app = StoreApp(id: id, name: name, bundleID: bundleID, version: version, iconURL: iconURL)
        app.description = description
        app.category = category
        app.size = size
        app.price = "免费"
        app.minimumOS = minimumOS ?? ""
        return app
    }
}

// MARK: - AltStore appstore.json 解析（宽松兼容 SideStore / Feather 等同类格式）

private struct SourceRoot: Decodable {
    let name: String?
    let identifier: String?
    let iconURL: String?
    let sidebarIcon: String?
    let apps: [SourceAppEntry]?
    let news: [SourceNewsEntry]?
}

private struct SourceAppEntry: Decodable {
    let name: String?
    let bundleIdentifier: String?
    let bundleID: String?
    let version: String?
    let versionDate: String?
    let size: Int64?
    let downloadURL: String?
    let iconURL: String?
    let developerName: String?
    let subtitle: String?
    let description: String?
    let category: String?
    let minOSVersion: String?
    let appID: String?
    let versions: [SourceVersionEntry]?
}

private struct SourceVersionEntry: Decodable {
    let version: String?
    let size: Int64?
    let downloadURL: String?
    let minOSVersion: String?
    let date: String?
}

private struct SourceNewsEntry: Decodable {
    let title: String?
    let newsID: String?
    let caption: String?
    let date: String?
    let iconURL: String?
}

enum SourceCatalogError: LocalizedError {
    case invalidURL
    case noApps
    case decode(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入有效的软件源地址"
        case .noApps: return "该源没有可用应用"
        case .decode(let msg): return "解析软件源失败：\(msg)"
        }
    }
}

/// 一次同步结果：源元信息 + 应用列表。
struct SourceSyncResult {
    let title: String
    let iconURL: URL?
    let apps: [SourceApp]
}

enum SourceCatalog {

    /// 拉取并解析一个源 URL。
    static func fetch(urlString: String) async throws -> SourceSyncResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme, ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            throw SourceCatalogError.invalidURL
        }
        let client = HTTPClient()
        let (data, response) = try await client.request(url, method: "GET", timeoutInterval: 20)
        guard response.statusCode == 200 else {
            throw SourceCatalogError.decode("HTTP \(response.statusCode)")
        }
        let root: SourceRoot
        do {
            root = try JSONDecoder().decode(SourceRoot.self, from: data)
        } catch {
            throw SourceCatalogError.decode(error.localizedDescription)
        }
        let entries = root.apps ?? []
        var apps: [SourceApp] = []
        for entry in entries {
            let bundleID = entry.bundleIdentifier ?? entry.bundleID ?? ""
            // 优先取最新版本条目的下载地址与体积，否则用顶层字段。
            let latest = entry.versions?.first
            let dlString = latest?.downloadURL ?? entry.downloadURL
            guard let dlString, let dlURL = URL(string: dlString, relativeTo: url) ?? URL(string: dlString) else { continue }
            let size = latest?.size ?? entry.size ?? 0
            let version = latest?.version ?? entry.version ?? ""
            let minOS = latest?.minOSVersion ?? entry.minOSVersion
            let appID = entry.appID ?? bundleID
            let iconURL = (entry.iconURL.flatMap { URL(string: $0, relativeTo: url) ?? URL(string: $0) })
            apps.append(SourceApp(
                id: appID.isEmpty ? dlString : appID,
                name: entry.name ?? bundleID,
                bundleID: bundleID,
                version: version,
                size: size,
                downloadURL: dlURL,
                iconURL: iconURL,
                developer: entry.developerName ?? "",
                subtitle: entry.subtitle ?? "",
                description: entry.description ?? "",
                category: entry.category ?? "",
                minimumOS: minOS,
                sourceID: root.identifier ?? host,
                sourceTitle: root.name ?? host
            ))
        }
        guard !apps.isEmpty else { throw SourceCatalogError.noApps }
        let iconURL = (root.iconURL.flatMap { URL(string: $0, relativeTo: url) ?? URL(string: $0) })
            ?? (root.sidebarIcon.flatMap { URL(string: $0, relativeTo: url) ?? URL(string: $0) })
        return SourceSyncResult(title: root.name ?? host, iconURL: iconURL, apps: apps)
    }
}
