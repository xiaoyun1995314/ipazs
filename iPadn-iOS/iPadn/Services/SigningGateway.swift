// 阶段一：zsign 签名引擎薄封装。
// 仅打通 ZsignSwift 调用通路：p12 DER 解析、证书吊销检查、整包签名。
// 这里不做导入 UI、不解包、不注入；解包/注入/选 target 在阶段二的 SigningService。

import Foundation
import ZsignSwift

/// zsign 调用错误。
enum SigningGatewayError: LocalizedError {
    case badPassword
    case invalidCertificate(String)
    case signFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .badPassword: return "p12 密码错误或证书无效"
        case .invalidCertificate(let msg): return "证书解析失败：\(msg)"
        case .signFailed(let msg): return "签名失败：\(msg)"
        case .cancelled: return "已取消"
        }
    }
}

/// 证书吊销检查结果状态（沿用 zsign 的 Int32 状态码语义）。
struct RevocationStatus: Equatable {
    let code: Int32
    let expiration: Date?
    let message: String?

    var isValid: Bool { code == 0 }
}

enum SigningGateway {

    /// 用 OpenSSL 解析 p12，返回证书 DER 数据；失败返回错误描述。
    static func certificateDER(p12Data: Data, password: String) throws -> Data {
        let result = Zsign.certificateDERWithError(p12Data: p12Data, password: password)
        guard let der = result.data else {
            let msg = result.error.isEmpty ? "unknown" : result.error
            // OpenSSL 未给出明确密码错误时，交由上层按无效证书处理。
            throw SigningGatewayError.invalidCertificate(msg)
        }
        return der
    }

    /// 检查证书 + 描述文件是否吊销/过期。路径式，回调在任意队列。
    static func checkRevokage(p12Path: String, profilePath: String, password: String,
                              completion: @escaping (RevocationStatus) -> Void) {
        Zsign.checkRevokage(
            provisionPath: profilePath,
            p12Path: p12Path,
            p12Password: password
        ) { code, expiration, message in
            completion(RevocationStatus(code: code, expiration: expiration, message: message))
        }
    }

    /// 对已解包的 App 目录执行签名（同步阻塞，建议放在后台队列）。
    /// - Parameters:
    ///   - appPath: 解包后的 .app 目录路径（或待签 bundle）
    ///   - profilePath: mobileprovision 路径
    ///   - p12Path: p12 路径
    ///   - password: p12 密码
    ///   - entitlementsPath: entitlements plist 路径，可空
    ///   - customIdentifier: 自定义 bundleID，可空
    ///   - customName: 自定义显示名，可空
    ///   - customVersion: 自定义版本号，可空
    ///   - removeProvision: true 剔除内嵌 mobileprovision；设备安装一般用 false（内嵌）。
    static func signBundle(appPath: String,
                           profilePath: String,
                           p12Path: String,
                           password: String,
                           entitlementsPath: String = "",
                           customIdentifier: String = "",
                           customName: String = "",
                           customVersion: String = "",
                           removeProvision: Bool = false) throws {
        let box = ErrorBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Zsign.sign(
                appPath: appPath,
                provisionPath: profilePath,
                p12Path: p12Path,
                p12Password: password,
                entitlementsPath: entitlementsPath,
                customIdentifier: customIdentifier,
                customName: customName,
                customVersion: customVersion,
                adhoc: false,
                removeProvision: removeProvision,
                completion: { _, error in
                    box.set(error)
                }
            )
            if !ok {
                box.set(box.get() ?? SigningGatewayError.signFailed("Zsign returned false"))
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = box.get() {
            throw error
        }
    }

    /// 列出可执行文件当前的动态库 load command（阶段二注入前用于查重）。
    static func listDylibs(executablePath: String) -> [String] {
        Zsign.listDylibs(appExecutable: executablePath)
    }

    /// 向可执行文件注入动态库 load command（阶段二使用）。
    @discardableResult
    static func injectDyLib(executablePath: String, loadPath: String, weak: Bool = true) -> Bool {
        Zsign.injectDyLib(appExecutable: executablePath, with: loadPath, weak: weak)
    }
}

/// 在闭包内传递异步错误的简单盒子。
private final class ErrorBox: @unchecked Sendable {
    private var _error: Error?
    private let lock = NSLock()

    func set(_ error: Error?) {
        lock.lock(); _error = error; lock.unlock()
    }

    func get() -> Error? {
        lock.lock(); defer { lock.unlock() }; return _error
    }
}
