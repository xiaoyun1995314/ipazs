// 「发现软件」软件源主页：源管理界面。
// 顶部统计卡片 + 全部软件源列表（添加/刷新/删除）+ 聚合搜索；
// 点源行进入该源专属详情页（公告/静态banner/按分类平铺应用）。

import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var store: ToolStore
    @ObservedObject var sources: SourceManager
    @State private var showingAdd = false
    @State private var addURL = ""
    @State private var addError: String?
    @State private var adding = false
    @State private var browsing: BrowserLink?
    @State private var showingBuiltinSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    sourcesSection
                    appsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("发现软件")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                addSourceSheet
            }
            .sheet(item: $browsing) { link in
                WebBrowserView(url: link.url)
            }
            .sheet(isPresented: $showingBuiltinSettings) {
                BuiltinSourceSettingsView()
            }
            .onAppear {
                if !sources.sources.isEmpty {
                    Task { await sources.syncAll() }
                }
            }
        }
    }

    // MARK: - 顶部统计卡片

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("发现软件").font(.title2.weight(.bold))
                    Text("搜索所有已同步的软件源，也可以进入单个源浏览。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await sources.syncAll() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .disabled(!sources.syncing.isEmpty)
            }
            HStack(spacing: 0) {
                statBlock(sources.sources.count + (sources.builtin != nil ? 1 : 0), "订阅")
                Divider().frame(height: 34)
                statBlock((sources.sources + (sources.builtin.map { [$0] } ?? [])).filter { $0.lastSynced != nil }.count, "已同步")
                Divider().frame(height: 34)
                statBlock(sources.allApps.count, "应用")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func statBlock(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 软件源列表（点行进详情页）

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("全部软件源").font(.headline)
                Spacer()
                Text("\(sources.sources.count + (sources.builtin != nil ? 1 : 0)) 个").font(.subheadline).foregroundStyle(.secondary)
            }
            // 内置软件源置顶
            if let builtin = sources.builtin {
                NavigationLink {
                    SourceDetailView(
                        sources: sources,
                        source: builtin,
                        sourceID: SourceManager.builtinID,
                        isBuiltin: true,
                        onRefresh: { Task { await sources.syncBuiltin() } },
                        onSettings: { showingBuiltinSettings = true },
                        openLink: openLink
                    )
                } label: {
                    SourceRowLabel(source: builtin, busy: sources.syncing.contains(SourceManager.builtinID))
                }
                .buttonStyle(.plain)
            }
            if sources.sources.isEmpty && sources.builtin == nil {
                emptySources
            } else {
                ForEach(sources.sources) { source in
                    NavigationLink {
                        SourceDetailView(
                            sources: sources,
                            source: source,
                            sourceID: source.id,
                            isBuiltin: false,
                            onRefresh: { Task { await sources.sync(sourceID: source.id) } },
                            onDelete: { sources.removeSource(source.id) },
                            openLink: openLink
                        )
                    } label: {
                        SourceRowLabel(source: source, busy: sources.syncing.contains(source.id))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptySources: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.largeTitle).foregroundStyle(.tertiary)
            Text("还没有添加软件源").font(.subheadline).foregroundStyle(.secondary)
            Button { showingAdd = true } label: {
                Text("添加软件源").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - 聚合应用列表

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !sources.allApps.isEmpty {
                SearchInput(text: $sources.searchText, placeholder: "搜索所有软件源", capsule: true)
            }
            let list = sources.filteredApps
            if list.isEmpty {
                Text(sources.searchText.isEmpty ? "正在同步应用…" : "没有匹配的应用")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(list) { app in
                    SourceAppRow(app: app) { openLink(app) }
                }
            }
        }
    }

    // MARK: - 链接打开 / 下载

    private func openLink(_ app: SourceApp) {
        switch app.linkKind {
        case .directIPA: sources.enqueue(app)
        case .webpage:
            if let url = app.resolvedWebURL {
                browsing = BrowserLink(url: url)
            } else {
                store.errorMessage = "该链接类型无法在应用内打开：\(app.downloadURL.absoluteString)"
            }
        }
    }

    // MARK: - 添加源弹窗

    private var addSourceSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("软件源地址（appstore.json）", text: $addURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("软件源 URL")
                } footer: {
                    Text("粘贴 AltStore / SideStore 软件源的 appstore.json 地址，添加后自动同步应用列表。")
                }
                if let addError {
                    Section {
                        Text(addError).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .navigationTitle("添加软件源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingAdd = false; addURL = ""; addError = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { Task { await addSource() } }
                        .disabled(adding || addURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if adding {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView().controlSize(.large)
                }
            }
        }
    }

    private func addSource() async {
        adding = true; addError = nil
        do {
            _ = try await sources.addSource(urlString: addURL)
            showingAdd = false
            addURL = ""
        } catch {
            addError = error.localizedDescription
        }
        adding = false
    }
}

// MARK: - 源行标签（不再展开，整行是进入详情页的入口）

private struct SourceRowLabel: View {
    let source: AppStoreSource
    let busy: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(url: source.iconURL, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.title).font(.headline).foregroundStyle(.primary)
                if busy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("同步中…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let err = source.syncError {
                    Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else {
                    Text(source.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("\(source.appCount) 个应用" + (source.lastSynced.map { " · \(relative($0))" } ?? ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 聚合列表应用行（发现页所有源平铺）

private struct SourceAppRow: View {
    let app: SourceApp
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AppIcon(url: app.iconURL, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.headline).foregroundStyle(.primary)
                    if !app.developer.isEmpty {
                        Text(app.developer).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        if !app.version.isEmpty { Text("v\(app.version)").font(.caption2) }
                        if app.size > 0 { Text(app.size.byteLabel).font(.caption2) }
                        Text(app.sourceTitle).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 网页链接的 Identifiable 包装，供 sheet(item:) 使用。
struct BrowserLink: Identifiable {
    let id = UUID()
    let url: URL
}
