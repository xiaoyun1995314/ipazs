// 单个软件源详情页：进入该源后只浏览本源应用。
// 顶部统计卡（应用数/同步时间）+ 公告(message) + 静态 banner + 按分类平铺应用（描述全展开）。

import SwiftUI

struct SourceDetailView: View {
    @EnvironmentObject private var store: ToolStore
    let sources: SourceManager
    let source: AppStoreSource
    let sourceID: String
    let isBuiltin: Bool
    let onRefresh: () -> Void
    var onDelete: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    let openLink: (SourceApp) -> Void

    @State private var browsing: BrowserLink?
    @State private var confirmDelete = false

    private var apps: [SourceApp] { sources.apps(forSourceID: sourceID) }
    private var extra: SourceExtra? { sources.extras(forSourceID: sourceID) }
    private var busy: Bool { sources.syncing.contains(sourceID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statCard
                if let msg = extra?.message, !msg.isEmpty {
                    announcementCard(msg)
                }
                if let banners = extra?.banners, !banners.isEmpty {
                    bannerSection(banners)
                }
                appsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { onRefresh() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(busy)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isBuiltin {
                    Button { onSettings?() } label: { Image(systemName: "gearshape") }
                } else {
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                }
            }
        }
        .sheet(item: $browsing) { link in
            WebBrowserView(url: link.url)
        }
        .alert("删除软件源", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { onDelete?() }
        } message: {
            Text("确定删除 \(source.title) 吗？")
        }
    }

    // MARK: - 统计卡

    private var statCard: some View {
        HStack(spacing: 0) {
            statBlock("应用", "\(apps.count)")
            Divider().frame(height: 44)
            statBlock("同步", source.lastSynced.map { relative($0) } ?? (busy ? "同步中…" : "未同步"))
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.85), Color.purple.opacity(0.85)],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func statBlock(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 公告

    private func announcementCard(_ message: String) -> some View {
        VStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "megaphone.fill").foregroundStyle(.orange)
                Text("公告").font(.headline)
            }
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 静态 banner

    private func bannerSection(_ banners: [SourceBannerEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("推荐").font(.headline)
            ForEach(Array(banners.enumerated()), id: \.offset) { _, item in
                BannerRow(item: item) {
                    openBanner(item)
                }
            }
        }
    }

    private func openBanner(_ item: SourceBannerEntry) {
        guard let raw = item.url, let url = URL(string: raw) else { return }
        if url.scheme == "http" || url.scheme == "https" {
            browsing = BrowserLink(url: url)
        }
    }

    // MARK: - 应用列表（按分类平铺）

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("全部应用").font(.headline)
                Spacer()
                Text("共 \(apps.count) 个软件").font(.subheadline).foregroundStyle(.secondary)
            }
            let grouped = groupedApps
            ForEach(grouped.keys.sorted(), id: \.self) { cat in
                Section {
                    ForEach(grouped[cat] ?? []) { app in
                        SourceDetailAppRow(app: app) { openLink(app) }
                    }
                } header: {
                    Text(cat).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            if apps.isEmpty {
                Text(busy ? "正在同步应用…" : "该源暂无应用")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }

    /// 按分类分组；无分类归入「未分类」，组内保持源顺序平铺。
    private var groupedApps: [String: [SourceApp]] {
        var map: [String: [SourceApp]] = [:]
        for app in apps {
            let cat = app.category.isEmpty ? "未分类" : app.category
            map[cat, default: []].append(app)
        }
        // 优先按源声明的分类顺序排列。
        if let order = extra?.categories, !order.isEmpty {
            let sortedKeys = map.keys.sorted { a, b in
                let ia = order.firstIndex(of: a) ?? Int.max
                let ib = order.firstIndex(of: b) ?? Int.max
                return ia < ib
            }
            var reordered: [String: [SourceApp]] = [:]
            for k in sortedKeys { reordered[k] = map[k] }
            return reordered
        }
        return map
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 静态 banner 行

private struct BannerRow: View {
    let item: SourceBannerEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let icon = item.icon, let url = URL(string: icon) {
                    AppIcon(url: url, size: 36)
                }
                Text(item.text ?? "").font(.subheadline).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 详情页应用行（描述全展开）

private struct SourceDetailAppRow: View {
    let app: SourceApp
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    AppIcon(url: app.iconURL, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.headline).foregroundStyle(.primary)
                        if !app.developer.isEmpty {
                            Text(app.developer).font(.caption).foregroundStyle(.secondary)
                        }
                        if !app.versionDate.isEmpty {
                            Text(app.versionDate).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    actionButton
                }
                if !app.description.isEmpty {
                    Text(app.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var actionButton: some View {
        switch app.linkKind {
        case .directIPA:
            VStack(spacing: 2) {
                Image(systemName: "arrow.down.circle.fill").font(.title3).foregroundStyle(.tint)
                Text("下载").font(.caption2).foregroundStyle(.secondary)
            }
        case .webpage:
            VStack(spacing: 2) {
                Image(systemName: "globe").font(.title3).foregroundStyle(.tint)
                Text("访问").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
