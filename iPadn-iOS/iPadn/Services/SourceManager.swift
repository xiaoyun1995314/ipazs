// 软件源运行时管理器：增删源、同步、聚合应用、触发下载入队。
// 源列表持久化在 ToolSettings.sources（随 settings 自动存 UserDefaults）。

import SwiftUI
import Foundation

@MainActor
final class SourceManager: ObservableObject {
    @Published var sources: [AppStoreSource] = []
    /// 所有源拉到的应用（聚合），按 sourceID 分组缓存。
    @Published var appsBySource: [String: [SourceApp]] = [:]
    @Published var syncing: Set<String> = []
    @Published var searchText = ""
    @Published private(set) var lastSyncedAt: Date?

    private weak var store: ToolStore?

    func attach(_ store: ToolStore) {
        self.store = store
        self.sources = store.settings.sources
    }

    private func persist() {
        guard let store else { return }
        store.settings.sources = sources
    }

    // MARK: - 增删

    func addSource(urlString: String) async throws -> AppStoreSource {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            throw SourceCatalogError.invalidURL
        }
        // 去重：同主机+路径不重复添加
        if sources.contains(where: { $0.normalizedURL?.absoluteString == url.absoluteString }) {
            throw SourceCatalogError.decode("该软件源已添加")
        }
        var source = AppStoreSource(title: host, url: trimmed)
        sources.append(source)
        persist()
        // 立即同步一次以拿到标题/图标/应用
        await sync(sourceID: source.id)
        guard let refreshed = sources.first(where: { $0.id == source.id }) else { throw SourceCatalogError.noApps }
        return refreshed
    }

    func removeSource(_ id: String) {
        sources.removeAll { $0.id == id }
        appsBySource.removeValue(forKey: id)
        persist()
    }

    // MARK: - 同步

    func sync(sourceID: String) async {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        syncing.insert(sourceID)
        defer { syncing.remove(sourceID) }
        let url = sources[index].url
        do {
            let result = try await SourceCatalog.fetch(urlString: url)
            sources[index].title = result.title
            sources[index].iconURL = result.iconURL
            sources[index].lastSynced = Date()
            sources[index].syncError = nil
            sources[index].appCount = result.apps.count
            appsBySource[sourceID] = result.apps
            lastSyncedAt = Date()
        } catch {
            sources[index].syncError = error.localizedDescription
        }
        persist()
    }

    func syncAll() async {
        await withTaskGroup(of: Void.self) { group in
            for s in sources {
                group.addTask { await self.sync(sourceID: s.id) }
            }
        }
    }

    // MARK: - 聚合

    var allApps: [SourceApp] {
        appsBySource.values.flatMap { $0 }
    }

    var filteredApps: [SourceApp] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = allApps
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.lowercased().contains(q) ||
            $0.bundleID.lowercased().contains(q) ||
            $0.developer.lowercased().contains(q) ||
            $0.subtitle.lowercased().contains(q)
        }
    }

    // MARK: - 下载入队

    func enqueue(_ app: SourceApp) {
        guard let store else { return }
        do {
            try store.downloads.enqueueURL(app.downloadURL)
            store.selectTab(.downloads)
            store.infoMessage = "已开始下载 \(app.name)"
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
