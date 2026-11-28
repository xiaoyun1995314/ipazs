// 阶段三：签名页 UI。
//
// 在 SigningStore（证书/描述文件库）与 SigningEngine（签名引擎）之上，提供三个
// 最小可用界面：
//   1. SigningCertificatesView —— 证书管理（p12 导入/选中/删除、mobileprovision
//      导入/选中/删除），并列出已签名产物；
//   2. SigningSignView —— 从原始 IPA 进入的签名操作页：选证书/描述文件、勾选插件
//      注入、可选改 bundleID/显示名、一键签名（带进度条）；
//   3. 签名结果：分享 / 保存导出 / 原生安装（能力门控，不可用时隐藏）。
//
// 不引入灵动岛、OTA 自动安装、本地 HTTP 服务器、复杂历史时间线。多语言先硬编码中文。

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 证书管理页

/// 签名证书管理：导入 p12（弹密码框）、导入 mobileprovision、选中、删除；
/// 下方列出已签名产物，可分享 / 保存 / 删除。
struct SigningCertificatesView: View {
    @EnvironmentObject private var store: ToolStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var signing = SigningStore.shared

    @State private var importKind: ImportKind = .p12
    @State private var importing = false
    /// 待输入密码的 p12 原始数据（fileImporter 读到）。
    @State private var pendingP12Data: Data?
    @State private var p12Password = ""
    @State private var p12Importing = false
    @State private var issue: String?
    @State private var deletingCertificate: SigningCertificate?
    @State private var deletingProfile: SigningProfile?
    @State private var presentation: PackageFilePresentation?
    @State private var signedFiles: [SignedFile] = []

    private enum ImportKind { case p12, profile }

    var body: some View {
        NavigationStack {
            Form {
                certificateSection
                profileSection
                signedSection
            }
            .toolPage()
            .navigationTitle("签名证书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $importing) {
                PackageDocumentPicker { result in
                    handleImportResult(result)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(get: { pendingP12Data != nil },
                                        set: { if !$0 { pendingP12Data = nil; p12Password = "" } })) {
                passwordSheet
            }
            .actionConfirmation(
                isPresented: Binding(get: { deletingCertificate != nil },
                                     set: { if !$0 { deletingCertificate = nil } }),
                title: "删除证书？",
                message: "删除后该证书及其密码将从本机移除，已签名的包不受影响。",
                confirmTitle: "删除",
                destructive: true
            ) {
                if let certificate = deletingCertificate { signing.deleteCertificate(certificate) }
                deletingCertificate = nil
                store.infoMessage = AppText.text("证书已删除")
            }
            .actionConfirmation(
                isPresented: Binding(get: { deletingProfile != nil },
                                     set: { if !$0 { deletingProfile = nil } }),
                title: "删除描述文件？",
                message: "删除后该描述文件将从本机移除，已签名的包不受影响。",
                confirmTitle: "删除",
                destructive: true
            ) {
                if let profile = deletingProfile { signing.deleteProfile(profile) }
                deletingProfile = nil
                store.infoMessage = AppText.text("描述文件已删除")
            }
            .packageFilePresenter($presentation)
            .sheetNotice()
            .onAppear { refreshSigned() }
        }
    }

    // MARK: 证书 section

    private var certificateSection: some View {
        Section {
            if signing.certificates.isEmpty {
                EmptyState(title: "尚未导入证书",
                           message: "导入 p12 证书后才能对 IPA 签名。",
                           symbol: "person.badge.key")
            } else {
                ForEach(signing.certificates) { certificate in
                    certificateRow(certificate)
                }
            }
            Button {
                importKind = .p12
                importing = true
            } label: {
                Label("导入 p12 证书", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("证书（p12）")
        } footer: {
            Text("证书仅保存在这台设备上，不会上传。")
        }
    }

    private func certificateRow(_ certificate: SigningCertificate) -> some View {
        let selected = signing.selectedCertificateID == certificate.id
        return Button {
            signing.selectCertificate(certificate.id)
            UX.feedback()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: certificate.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    let detail = [
                        certificate.teamID.isEmpty ? nil : "Team \(certificate.teamID)",
                        certificate.expiresAt.map { "有效期至 \($0.formatted(date: .abbreviated, time: .omitted))" }
                    ].compactMap { $0 }.joined(separator: " · ")
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(UX.tint)
                }
                Button(role: .destructive) {
                    deletingCertificate = certificate
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: 描述文件 section

    private var profileSection: some View {
        Section {
            if signing.profiles.isEmpty {
                EmptyState(title: "尚未导入描述文件",
                           message: "导入 mobileprovision 后设备才能安装签名包。",
                           symbol: "doc.badge.ellipsis")
            } else {
                ForEach(signing.profiles) { profile in
                    profileRow(profile)
                }
            }
            Button {
                importKind = .profile
                importing = true
            } label: {
                Label("导入 mobileprovision", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("描述文件（mobileprovision）")
        }
    }

    private func profileRow(_ profile: SigningProfile) -> some View {
        let selected = signing.selectedProfileID == profile.id
        return Button {
            signing.selectProfile(profile.id)
            UX.feedback()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: profile.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    let devices = profile.provisionsAllDevices == true ? "全设备" : "\(profile.deviceCount) 台设备"
                    let detail = [
                        profile.teamID.isEmpty ? nil : "Team \(profile.teamID)",
                        devices,
                        profile.expiresAt.map { "有效期至 \($0.formatted(date: .abbreviated, time: .omitted))" }
                    ].compactMap { $0 }.joined(separator: " · ")
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(UX.tint)
                }
                Button(role: .destructive) {
                    deletingProfile = profile
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: 已签名产物 section

    private var signedSection: some View {
        Section {
            if signedFiles.isEmpty {
                EmptyState(title: "暂无已签名的包",
                           message: "签名完成后，产物会保存在这里，可直接分享或安装。",
                           symbol: "checkmark.seal")
            } else {
                ForEach(signedFiles) { file in
                    signedRow(file)
                }
            }
        } header: {
            Text("已签名的包")
        }
    }

    private func signedRow(_ file: SignedFile) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: file.url.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(verbatim: file.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("分享", systemImage: "square.and.arrow.up") {
                    export(file.url, kind: .share)
                }
                Button("保存导出", systemImage: "folder") {
                    export(file.url, kind: .save)
                }
                Button("删除", systemImage: "trash", role: .destructive) {
                    try? FileManager.default.removeItem(at: file.url)
                    refreshSigned()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: 导入处理

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            switch importKind {
            case .p12:
                pendingP12Data = data
                p12Password = ""
            case .profile:
                do {
                    try signing.importProfile(data: data, originalFileName: url.lastPathComponent)
                    store.infoMessage = AppText.text("描述文件已导入")
                } catch {
                    issue = error.localizedDescription
                    store.errorMessage = error.localizedDescription
                }
            }
        } catch {
            issue = error.localizedDescription
            store.errorMessage = error.localizedDescription
        }
    }

    private func importP12() {
        guard let data = pendingP12Data else { return }
        p12Importing = true
        let password = p12Password
        Task { @MainActor in
            defer { p12Importing = false }
            do {
                try signing.importCertificate(data: data,
                                              originalFileName: "证书.p12",
                                              password: password,
                                              displayName: "")
                pendingP12Data = nil
                p12Password = ""
                store.infoMessage = AppText.text("证书已导入")
            } catch {
                issue = error.localizedDescription
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private var passwordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("证书密码（可留空）", text: $p12Password)
                } footer: {
                    Text("证书仅保存在这台设备上。")
                }
                if let issue {
                    Section { Text(issue).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("导入证书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        pendingP12Data = nil
                        p12Password = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { importP12() }.disabled(p12Importing)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func export(_ url: URL, kind: PackageFilePresentation.Kind) {
        do {
            presentation = try PackageFileActions.prepare(url, name: url.lastPathComponent, kind: kind)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func refreshSigned() {
        let directory = signing.signedOutputDirectory
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []
        signedFiles = entries
            .filter { $0.pathExtension.lowercased() == "ipa" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(values?.fileSize ?? 0)
                let modified = values?.contentModificationDate ?? .distantPast
                return SignedFile(url: url, size: size, modified: modified)
            }
            .sorted { $0.modified > $1.modified }
    }
}

/// 已签名产物的轻量模型。
struct SignedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date

    var detail: String {
        [size > 0 ? size.byteLabel : "",
         modified.formatted(date: .abbreviated, time: .omitted)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - 签名操作页

/// 从原始 IPA 进入：自动选中该 IPA；选证书/描述文件；勾选插件注入；可选改
/// bundleID/显示名；点「开始签名」走 SigningEngine.sign，进度条回传；完成后
/// 提供分享 / 保存 / 原生安装。
struct SigningSignView: View {
    @EnvironmentObject private var store: ToolStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var manager: DownloadManager
    @ObservedObject private var signing = SigningStore.shared

    let job: DownloadJob

    @State private var selectedPluginIDs = Set<UUID>()
    @State private var customBundleID = ""
    @State private var customDisplayName = ""
    @State private var busy = false
    @State private var progress: Double = 0
    @State private var phase = ""
    @State private var detail = ""
    @State private var errorText: String?
    @State private var resultURL: URL?
    @State private var installProgress = ""
    @State private var installing = false
    @State private var presentation: PackageFilePresentation?

    /// 可注入的 dylib 插件（deb 引擎暂不解包，置灰不可选）。
    private var injectablePlugins: [DownloadJob] {
        manager.jobs.filter { candidate in
            guard candidate.rawFormat == nil, candidate.status == .completed,
                  manager.fileURL(candidate) != nil else { return false }
            let kind = PackageKind(rawValue: candidate.packageKind ?? "") ?? .app
            return kind == .dylib
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                packageHeader
                certificateSection
                profileSection
                pluginSection
                customSection
                actionSection
                if resultURL != nil {
                    resultSection
                }
            }
            .toolPage()
            .navigationTitle("签名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.disabled(busy)
                }
            }
            .packageFilePresenter($presentation)
            .sheetNotice()
        }
    }

    // MARK: 包信息

    private var packageHeader: some View {
        Section {
            HStack(spacing: 12) {
                AppIcon(url: manager.packageIconURL(job) ?? job.app.iconURL, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: PackageStage.displayName(job.app.name))
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    let meta = [
                        job.conciseVersionLabel,
                        job.app.size > 0 ? job.app.size.byteLabel : "",
                        job.app.bundleID
                    ].filter { !$0.isEmpty }.joined(separator: " · ")
                    Text(verbatim: meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 证书

    private var certificateSection: some View {
        Section {
            if signing.certificates.isEmpty {
                Text("尚未导入证书，请先在「签名证书」中导入 p12。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(signing.certificates) { certificate in
                    selectableRow(
                        selected: signing.selectedCertificateID == certificate.id,
                        title: certificate.displayName,
                        subtitle: certificate.teamID.isEmpty ? nil : "Team \(certificate.teamID)"
                    ) {
                        signing.selectCertificate(certificate.id)
                        UX.feedback()
                    }
                }
            }
        } header: {
            Text("签名证书")
        } footer: {
            Text("选择用于签名的 p12 证书。")
        }
    }

    // MARK: 描述文件

    private var profileSection: some View {
        Section {
            if signing.profiles.isEmpty {
                Text("尚未导入描述文件，请先在「签名证书」中导入 mobileprovision。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(signing.profiles) { profile in
                    selectableRow(
                        selected: signing.selectedProfileID == profile.id,
                        title: profile.displayName,
                        subtitle: profile.teamID.isEmpty ? nil : "Team \(profile.teamID)"
                    ) {
                        signing.selectProfile(profile.id)
                        UX.feedback()
                    }
                }
            }
        } header: {
            Text("描述文件")
        } footer: {
            Text("选择与证书 Team ID 匹配的描述文件。")
        }
    }

    // MARK: 插件注入

    private var pluginSection: some View {
        Section {
            if injectablePlugins.isEmpty {
                Text("插件库暂无动态库，可跳过注入。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(injectablePlugins) { plugin in
                    pluginRow(plugin)
                }
            }
        } header: {
            Text("插件注入")
        } footer: {
            Text("勾选要注入到主二进制的 dylib；deb 包暂不支持自动解包。")
        }
    }

    private func pluginRow(_ plugin: DownloadJob) -> some View {
        let kind = PackageKind(rawValue: plugin.packageKind ?? "") ?? .app
        let selectable = kind == .dylib
        let selected = selectedPluginIDs.contains(plugin.id)
        return Button {
            guard selectable else { return }
            if selected { selectedPluginIDs.remove(plugin.id) } else { selectedPluginIDs.insert(plugin.id) }
            UX.feedback()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectable ? UX.tint : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: PackageStage.displayName(plugin.app.name))
                        .font(.body.weight(.medium))
                        .foregroundStyle(selectable ? .primary : .secondary)
                    let meta = [
                        kind.label,
                        plugin.app.size > 0 ? plugin.app.size.byteLabel : ""
                    ].filter { !$0.isEmpty }.joined(separator: " · ")
                    Text(verbatim: meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .disabled(!selectable)
    }

    // MARK: 自定义

    private var customSection: some View {
        Section {
            TextField("自定义 bundleID（留空不改）", text: $customBundleID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("自定义显示名（留空不改）", text: $customDisplayName)
        } header: {
            Text("自定义（可选）")
        } footer: {
            Text("留空则保留原应用的 bundleID 与显示名。")
        }
    }

    // MARK: 开始签名

    private var actionSection: some View {
        Section {
            if busy {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(verbatim: phase)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(verbatim: "\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                startSigning()
            } label: {
                Text(busy ? "正在签名…" : "开始签名")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || !canStart)
        }
    }

    private var canStart: Bool {
        guard signing.selectedCertificate != nil,
              signing.selectedProfile != nil,
              manager.fileURL(job) != nil else { return false }
        return true
    }

    // MARK: 结果

    private var resultSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("签名完成")
                        .font(.headline)
                }
                if let resultURL {
                    Text(verbatim: resultURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("分享", systemImage: "square.and.arrow.up") {
                            share(resultURL, kind: .share)
                        }
                        Button("保存导出", systemImage: "folder") {
                            share(resultURL, kind: .save)
                        }
                        if nativeInstallAvailable {
                            Button("安装", systemImage: "arrow.down.circle") {
                                install(resultURL)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    if !installProgress.isEmpty {
                        Text(verbatim: installProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var nativeInstallAvailable: Bool {
        guard let resultURL else { return false }
        let capability = InstallCoordinator.shared.capability(for: .native,
                                                              package: resultURL,
                                                              installation: nil)
        return capability.available
    }

    // MARK: 签名执行

    private func startSigning() {
        guard let ipaURL = manager.fileURL(job),
              let certificate = signing.selectedCertificate,
              let profile = signing.selectedProfile else {
            errorText = AppText.text("缺少证书或描述文件，请先在「签名证书」中导入并选中。")
            return
        }
        let certificateURL = signing.certificateURL(for: certificate)
        let profileURL = signing.profileURL(for: profile)
        let password = signing.password(for: certificate) ?? ""

        // 收集勾选的 dylib 插件注入。
        var injections: [SigningInjection] = []
        for plugin in injectablePlugins where selectedPluginIDs.contains(plugin.id) {
            if let url = manager.fileURL(plugin) {
                injections.append(SigningInjection(fileURL: url))
            }
        }

        let bundleID = customBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)

        busy = true
        progress = 0
        phase = "准备"
        detail = ""
        errorText = nil
        resultURL = nil

        let request = SigningRequest(
            ipaURL: ipaURL,
            certificateURL: certificateURL,
            profileURL: profileURL,
            password: password,
            bundleIdentifier: bundleID,
            displayName: displayName,
            embedProvision: true,
            injections: injections,
            outputDirectory: signing.signedOutputDirectory
        )

        Task.detached(priority: .userInitiated) {
            do {
                let output = try SigningEngine.sign(request: request) { update in
                    Task { @MainActor in
                        progress = update.progress
                        phase = update.phase
                        detail = update.detail
                    }
                }
                await MainActor.run {
                    busy = false
                    resultURL = output
                    progress = 1
                    store.infoMessage = AppText.text("签名完成")
                }
            } catch {
                await MainActor.run {
                    busy = false
                    errorText = error.localizedDescription
                    store.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func install(_ url: URL) {
        installing = true
        installProgress = "正在安装…"
        let finalBundleID = customBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? job.app.bundleID
            : customBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            do {
                try await InstallCoordinator.shared.accept(
                    package: url,
                    bundleID: finalBundleID,
                    source: .local,
                    method: .native,
                    installation: nil
                ) { text in
                    installProgress = text
                }
                installing = false
                store.infoMessage = AppText.text("安装已发起")
            } catch {
                installing = false
                installProgress = ""
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func share(_ url: URL, kind: PackageFilePresentation.Kind) {
        do {
            presentation = try PackageFileActions.prepare(url, name: url.lastPathComponent, kind: kind)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

/// 通用可点选行：选中显示 checkmark。
private func selectableRow(
    selected: Bool,
    title: String,
    subtitle: String?,
    action: @escaping () -> Void
) -> some View {
    Button {
        action()
    } label: {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(UX.tint)
            }
        }
    }
}
