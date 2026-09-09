import Foundation
import os

/// 身份清扫诊断。正式包可见；只记固定事件名 / 来源 / 数据类型 / 错误类型。
/// MUST NOT 写入 localizedDescription、userInfo、业务 id、名称、备注或密钥。
nonisolated enum IdentityHygieneLog: Sendable {
    enum Source: String, Sendable {
        case startup
        case cloudImport
    }

    enum Kind: String, Sendable {
        case account
        case key
        case tool
        case entitlement
        case expiredKeys
        case expiredAccounts
        case expiredTools
        case secretFragments
    }

    private static let logger = Logger(
        subsystem: "com.apirelay.ApiRelay",
        category: "IdentityHygiene"
    )

    static func failed(source: Source, kind: Kind, error: Error) {
        let errorType = typeName(error)
        logger.error(
            "event=prune.failed source=\(source.rawValue, privacy: .public) kind=\(kind.rawValue, privacy: .public) errorType=\(errorType, privacy: .public)"
        )
    }

    /// 仅类型名 + NSError domain/code，不含 userInfo 与文案。
    static func typeName(_ error: Error) -> String {
        let ns = error as NSError
        return "\(String(describing: type(of: error)))|\(ns.domain)|\(ns.code)"
    }

    /// 逐步执行；单步失败只记日志，不连累后续步骤。
    static func runIsolated(
        source: Source,
        steps: [(Kind, () async throws -> Void)]
    ) async {
        for (kind, work) in steps {
            do {
                try await work()
            } catch {
                failed(source: source, kind: kind, error: error)
            }
        }
    }
}
