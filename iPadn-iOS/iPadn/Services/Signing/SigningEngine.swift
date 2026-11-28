// 阶段二：精简签名引擎。
// 在 SigningGateway（zsign 通路）与 SigningStore（证书/描述文件库）之上，
// 实现闭环：解包 IPA → 定位 Payload/*.app → 复制并注入 dylib/framework →
// Zsign.sign → 重打包为 signed.ipa。
//
// 刻意砍掉訫云大杂烩里的：多扩展 target 扫描与逐 target 签名、Watch App 删除、
// 嵌套描述文件嵌入、自定义 entitlements 编辑、安装器 / OTA / 历史 / 灵动岛 /
// 本地 HTTP 服务器（这些属阶段三或不做）。deb 插件的解包留到阶段三。

import Foundation
import ZIPFoundation

/// 一条待注入插件：文件 URL + 是否 framework 包 + 是否 weak 链接。
struct SigningInjection: Identifiable, Hashable, Sendable {
    let id = UUID()
    let fileURL: URL
    let isFramework: Bool
    let weak: Bool

    /// 单文件 dylib 用；framework 包由调用方按目录判定。
    init(fileURL: URL, isFramework: Bool = false, weak: Bool = true) {
        self.fileURL = fileURL
        self.isFramework = isFramework
        self.weak = weak
    }
}

/// 一次签名任务的输入。
struct SigningRequest: Sendable {
    let ipaURL: URL
    let certificateURL: URL
    let profileURL: URL
    let password: String
    /// 自定义主应用 bundleID；空串表示不改。
    var bundleIdentifier: String = ""
    /// 自定义显示名；空串表示不改。
    var displayName: String = ""
    /// 自定义版本号；空串表示不改。
    var version: String = ""
    /// 是否移除描述文件（false = zsign 内嵌描述文件，设备可直接装）。
    var embedProvision: Bool = true
    var injections: [SigningInjection] = []
    let outputDirectory: URL
}

enum SigningEngineError: LocalizedError {
    case missingInput(String)
    case noPayload
    case unpackFailed(String)
    case packFailed(String)
    case injectionFailed(String)
    case signFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .missingInput(let name): return "缺少输入文件：\(name)"
        case .noPayload: return "安装包内未找到 Payload/*.app"
        case .unpackFailed(let msg): return "解包失败：\(msg)"
        case .packFailed(let msg): return "打包失败：\(msg)"
        case .injectionFailed(let msg): return "注入失败：\(msg)"
        case .signFailed(let msg): return "签名失败：\(msg)"
        case .outputMissing: return "签名产物缺失"
        }
    }
}

/// 进度回调（任意队列）。phase 为中文阶段名，progress 0~1。
struct SigningProgress: Sendable {
    let phase: String
    let progress: Double
    let detail: String
}

enum SigningEngine {

    /// 同步执行签名（阻塞调用方线程，建议放后台队列）。返回签名后的 IPA URL。
    static func sign(request: SigningRequest,
                     onUpdate: @escaping @Sendable (SigningProgress) -> Void = { _ in }) throws -> URL {
        let fm = FileManager.default

        for url in [request.ipaURL, request.certificateURL, request.profileURL]
        where !fm.fileExists(atPath: url.path) {
            throw SigningEngineError.missingInput(url.lastPathComponent)
        }
        try fm.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)

        let tempRoot = fm.temporaryDirectory
            .appendingPathComponent("Signing-\(UUID().uuidString)", isDirectory: true)
        let workRoot = tempRoot.appendingPathComponent("work", isDirectory: true)
        let outputTemp = tempRoot.appendingPathComponent("signed.ipa")
        try fm.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        onUpdate(SigningProgress(phase: "解包", progress: 0.10, detail: request.ipaURL.lastPathComponent))
        do {
            try fm.unzipItem(at: request.ipaURL, to: workRoot)
        } catch {
            throw SigningEngineError.unpackFailed(error.localizedDescription)
        }

        let payload = workRoot.appendingPathComponent("Payload", isDirectory: true)
        let entries = (try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? []
        guard let appURL = entries.first(where: { $0.pathExtension == "app" }) else {
            throw SigningEngineError.noPayload
        }
        onUpdate(SigningProgress(phase: "定位", progress: 0.30, detail: appURL.lastPathComponent))

        // 注入插件（主 bundle）。
        if !request.injections.isEmpty {
            try applyInjections(request.injections, to: appURL, onUpdate: onUpdate)
        }

        onUpdate(SigningProgress(phase: "签名", progress: 0.45, detail: request.certificateURL.lastPathComponent))
        try signMainApp(appURL: appURL, request: request)
        onUpdate(SigningProgress(phase: "签名完成", progress: 0.72, detail: request.bundleIdentifier.isEmpty ? appURL.lastPathComponent : request.bundleIdentifier))

        onUpdate(SigningProgress(phase: "打包", progress: 0.82, detail: "IPA"))
        do {
            try pack(workRoot, to: outputTemp)
        } catch {
            throw SigningEngineError.packFailed(error.localizedDescription)
        }
        guard fm.fileExists(atPath: outputTemp.path) else {
            throw SigningEngineError.outputMissing
        }

        let stem = request.ipaURL.deletingPathExtension().lastPathComponent
        var outputURL = request.outputDirectory.appendingPathComponent("\(stem)-signed.ipa")
        if fm.fileExists(atPath: outputURL.path) {
            outputURL = request.outputDirectory
                .appendingPathComponent("\(stem)-signed-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).ipa")
        }
        try? fm.removeItem(at: outputURL)
        try fm.moveItem(at: outputTemp, to: outputURL)

        onUpdate(SigningProgress(phase: "完成", progress: 1.0, detail: outputURL.lastPathComponent))
        return outputURL
    }

    // MARK: - 注入

    private static func applyInjections(_ injections: [SigningInjection],
                                        to appURL: URL,
                                        onUpdate: @escaping @Sendable (SigningProgress) -> Void) throws {
        let fm = FileManager.default

        let infoURL = appURL.appendingPathComponent("Info.plist")
        guard let infoData = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              let executableName = info["CFBundleExecutable"] as? String,
              !executableName.isEmpty else {
            throw SigningEngineError.injectionFailed("CFBundleExecutable")
        }
        let executable = appURL.appendingPathComponent(executableName)

        let frameworks = appURL.appendingPathComponent("Frameworks", isDirectory: true)
        try? fm.createDirectory(at: frameworks, withIntermediateDirectories: true)

        for injection in injections {
            let destinationName = injection.fileURL.lastPathComponent
            let destination = frameworks.appendingPathComponent(destinationName)
            try? fm.removeItem(at: destination)
            do {
                try fm.copyItem(at: injection.fileURL, to: destination)
            } catch {
                throw SigningEngineError.injectionFailed("\(destinationName) · \(error.localizedDescription)")
            }

            let loadPath: String
            if injection.isFramework {
                let frameworkInfo = (try? Data(contentsOf: destination.appendingPathComponent("Info.plist")))
                    .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
                let binaryName = (frameworkInfo?["CFBundleExecutable"] as? String)
                    ?? destination.deletingPathExtension().lastPathComponent
                loadPath = "@executable_path/Frameworks/\(destinationName)/\(binaryName)"
            } else {
                loadPath = "@executable_path/Frameworks/\(destinationName)"
            }

            let injected = SigningGateway.injectDyLib(executablePath: executable.path,
                                                     loadPath: loadPath,
                                                     weak: injection.weak)
            guard injected else {
                throw SigningEngineError.injectionFailed(destinationName)
            }
            onUpdate(SigningProgress(phase: "注入", progress: 0.38, detail: loadPath))
        }
    }

    // MARK: - 主签名

    private static func signMainApp(appURL: URL, request: SigningRequest) throws {
        try SigningGateway.signBundle(
            appPath: appURL.path,
            profilePath: request.profileURL.path,
            p12Path: request.certificateURL.path,
            password: request.password,
            entitlementsPath: "",
            customIdentifier: request.bundleIdentifier,
            customName: request.displayName,
            customVersion: request.version,
            removeProvision: !request.embedProvision
        )
    }

    // MARK: - 打包（ZIPFoundation，递归加文件条目；目录由文件条目隐含）

    private static func pack(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        let archive = try Archive(url: destination, accessMode: .create)
        try addFiles(in: source, relativeTo: source, archive: archive, fm: fm)
    }

    private static func addFiles(in dir: URL,
                                 relativeTo root: URL,
                                 archive: Archive,
                                 fm: FileManager) throws {
        let children = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try addFiles(in: child, relativeTo: root, archive: archive, fm: fm)
            } else {
                let relative = child.path.replacingOccurrences(of: root.path + "/", with: "")
                try archive.addEntry(with: relative, relativeTo: root, compressionMethod: .deflate)
            }
        }
    }
}
