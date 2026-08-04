import Foundation

/// 诊断上报 hook 点（架构预留，不在 V1 项目范围实现上报服务）。
/// MUST 内置明文过滤，禁止任何凭证进入上报内容。
enum DiagnosticsReporting {

    /// 注册最终的诊断上报触发者。V1 仅预留接口，不连接任何 SDK。
    /// 调用方 MUST 在调用前确保 `data` 不含明文凭证。
    static var reporter: ((DiagnosticsLevel, String, [String: Any]) -> Void)?

    /// 诊断级别
    enum DiagnosticsLevel: Sendable {
        case debug
        case info
        case warning
        case error
    }

    /// 上报一条诊断事件。内部不自动过滤明文——调用方 MUST 先自行清洗。
    /// - Parameters:
    ///   - level: 事件级别
    ///   - message: 人类可读摘要。MUST NOT 包含密钥明文或其片段。
    ///   - data: 附加结构化数据。MUST NOT 包含密钥明文、哈希或任何派生物。
    static func report(
        level: DiagnosticsLevel,
        message: String,
        data: [String: Any] = [:]
    ) {
        #if DEBUG
        // DEBUG 下输出到控制台以便开发调试，但 MUST NOT 输出明文
        print("[Diagnostics][\(level)] \(message)")
        #endif
        reporter?(level, message, data)
    }

    /// 清洗字典：递归移除所有值中以 "sk-"、"sk-ant-"、"sk-or-" 等
    /// 常见 API 密钥前缀开头的字符串，替换为 "<REDACTED>"。
    /// 调用方在传入 report() 前 SHOULD 先调用此方法。
    static func sanitize(_ dict: [String: Any]) -> [String: Any] {
        var result = dict
        for (key, value) in result {
            if let stringValue = value as? String,
               stringValue.isPotentialSecret {
                result[key] = "<REDACTED>"
            } else if let nestedDict = value as? [String: Any] {
                result[key] = sanitize(nestedDict)
            } else if let array = value as? [Any] {
                result[key] = array.map { element in
                    if let str = element as? String, str.isPotentialSecret {
                        return "<REDACTED>" as Any
                    } else if let nested = element as? [String: Any] {
                        return sanitize(nested)
                    }
                    return element
                }
            }
        }
        return result
    }
}

private extension String {
    /// 启发式检测：以常见 API 密钥前缀开头，且长度 ≥ 20
    var isPotentialSecret: Bool {
        let lowercased = lowercased()
        let prefixes = ["sk-", "sk-ant-", "sk-or-", "sk-", "org-", "fp-"]
        guard prefixes.contains(where: { lowercased.hasPrefix($0) }) else { return false }
        return count >= 20
    }
}
