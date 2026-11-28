// 下载文件类型识别：按文件头魔数 / ZIP 中央目录判定是 APP、dylib 插件、deb 插件还是未知压缩包。
// 纯读取嗅探，不解包、不签名。网盘网页类链接在源层已归为“访问”，不在此处理。

import Foundation

/// 识别出的文件种类。
enum PackageKind: String, Equatable {
    /// IPA 应用（.ipa 或 zip 内含 Payload/*.app）。
    case app
    /// Mach-O 动态库 / framework，可作为注入插件。
    case dylib
    /// Cydia ar 归档插件包（.deb）。
    case deb
    /// 普通 zip，内容无法明确归类。
    case zip
    /// 无法识别。
    case unknown

    /// 列表上显示的中文标签。
    var label: String {
        switch self {
        case .app: return "应用"
        case .dylib: return "插件·动态库"
        case .deb: return "插件·Deb"
        case .zip: return "压缩包"
        case .unknown: return "未知"
        }
    }

    /// 是否属于可勾选注入的插件。
    var isPlugin: Bool { self == .dylib || self == .deb }
}

enum PackageKindInspector {

    /// 读取文件前若干字节判定类型。优先看扩展名，再用文件头魔数确认。
    static func inspect(url: URL) -> PackageKind {
        let ext = url.pathExtension.lowercased()
        // 扩展名快速分流，但最终仍以文件头为准。
        let header = readHeader(url, count: 16)

        // deb: ar 归档魔数 "!<arch>\n" (0x213C617263683E0A)。
        if header.starts(with: Data("!<arch>".utf8)) { return .deb }

        // Mach-O：thin/fat magic。
        if let magic = magicLE(header) {
            switch magic {
            case 0xFEEDFACF, 0xFEEDFACE, 0xCAFEBABE, 0xCAFEBABF:
                // .dylib / .framework 明确按插件；其他可执行仍交回 zip/payload 判断。
                if ext == "dylib" || ext == "framework" || ext == "so" { return .dylib }
            default: break
            }
        }

        // ZIP / IPA：魔数 PK\x03\x04（或空包 PK\x05\x06）。
        if header.starts(with: Data("PK".utf8)) {
            if zipContainsPayload(url) { return .app }
            // zip 内若打包了 deb / dylib / framework / 越狱插件目录，归为插件。
            if let kind = zipPluginKind(url) { return kind }
            // 单文件 dylib 不会进这里；zip 内既无 Payload 也无插件，归为普通压缩包。
            return .zip
        }

        // 扩展名兜底：能直接确认的类型直接归类。
        switch ext {
        case "ipa": return .app
        case "dylib", "framework", "so": return .dylib
        case "deb": return .deb
        case "zip": return .zip
        default: break
        }
        return .unknown
    }

    // MARK: - 私有读取

    private static func readHeader(_ url: URL, count: Int) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: count)) ?? Data()
    }

    /// 读取前 4 字节小端作为 magic。
    private static func magicLE(_ data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        return UInt32(data[0])
            | (UInt32(data[1]) << 8)
            | (UInt32(data[2]) << 16)
            | (UInt32(data[3]) << 24)
    }

    /// 复用工程内 ZipDirectory 的中央目录，判断是否含 Payload/*.app。
    private static func zipContainsPayload(_ url: URL) -> Bool {
        guard let archive = ZipDirectory(url: url) else { return false }
        return archive.entries.contains { $0.hasPayloadApp }
    }

    /// zip 内打包的插件种类：含 deb 条目归 .deb，其余动态库类归 .dylib；无插件返回 nil。
    private static func zipPluginKind(_ url: URL) -> PackageKind? {
        guard let archive = ZipDirectory(url: url) else { return nil }
        var hasDylib = false
        for entry in archive.entries {
            let lower = entry.name.lowercased()
            if lower.hasSuffix(".deb") { return .deb }
            if entry.hasPluginContent { hasDylib = true }
        }
        return hasDylib ? .dylib : nil
    }
}

private extension ZipEntry {
    /// 条目路径是否指向 Payload 下的 .app 主包。
    var hasPayloadApp: Bool {
        guard name.hasPrefix("Payload/") else { return false }
        let parts = name.split(separator: "/")
        // Payload/xxx.app/... 第二段以 .app 结尾。
        guard parts.count >= 2 else { return false }
        return String(parts[1]).hasSuffix(".app")
    }

    /// 条目是否是插件内容：独立 dylib、.framework 包、或越狱插件常见目录。
    var hasPluginContent: Bool {
        let lower = name.lowercased()
        // 直接出现动态库文件。
        if lower.hasSuffix(".dylib") { return true }
        // .framework/xxx 包体目录。
        if lower.contains(".framework/") { return true }
        // 越狱插件 / Substrate / ElleKit 等安装目录里的文件。
        let pluginDirs = [
            "/library/mobilesubstrate/",
            "/library/substrate/",
            "/library/ellekit/",
            "/library/libhooker/",
            "/library/preferencebundles/",
            "/library/extensions/",
            "/.theos/"
        ]
        if pluginDirs.contains(where: { lower.contains($0) }) { return true }
        return false
    }
}
