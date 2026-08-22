import Foundation

/// 共享错误类型。按 contracts §1 一次性定义全部 case（含 V2/V3 预留）。
/// 错误 MUST 显式传递到 UI，MUST NOT 被吞噬（宪法 V）。
// TODO: Phase 2 — add Equatable conformance after PlatformCapability isolation resolved.
enum ApiRelayError: Error {
    // MARK: - 门闩
    /// 生物识别 / 密码验证失败
    case authenticationFailed
    /// 用户取消验证
    case authenticationCancelled
    /// 设备无生物识别能力
    case biometryUnavailable

    // MARK: - 保管
    /// Keychain 操作失败
    case keychainFailure(OSStatus)
    /// 元信息存在但 Keychain 无对应条目
    case secretMissingOnDevice
    /// 免费额度超限
    case quotaExceededFreeTier(limit: Int)
    /// 输入校验失败
    case validationFailed(field: String, reason: String)

    // MARK: - 平台（V2+ 可达）
    /// 平台不支持某能力
    case capabilityUnsupported(platform: String, capability: PlatformCapability)
    /// 管理凭证缺失
    case managementCredentialMissing(accountId: UUID)
    /// 上游拒绝请求
    case upstreamRejected(status: Int, message: String?)
    /// 上游响应无法解析
    case upstreamResponseUnparsable(detail: String)
    /// 网络不可用
    case networkUnavailable

    // MARK: - 两步一致性（FR-010）
    /// 平台侧创建成功但本地保存失败。MUST NOT 自动回滚平台侧密钥。
    case createdUpstreamButLocalSaveFailed(providerKeyRef: String?, platform: String)

    // MARK: - 备份
    /// 备份口令不正确
    case backupPassphraseIncorrect
    /// 备份版本不支持
    case backupVersionUnsupported(found: Int, supported: Int)
}

extension ApiRelayError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return String(localized: "error.authenticationFailed")
        case .authenticationCancelled:
            return String(localized: "error.authenticationCancelled")
        case .biometryUnavailable:
            return String(localized: "error.biometryUnavailable")
        case .keychainFailure(let status):
            // OSStatus 默认按 %d 进 Catalog；统一走已翻译的 %lld 条目。
            return String(localized: "error.keychainFailure \(Int64(status))")
        case .secretMissingOnDevice:
            return String(localized: "error.secretMissingOnDevice")
        case .quotaExceededFreeTier:
            return String(localized: "error.quotaExceeded")
        case .validationFailed(let field, let reason):
            return String(localized: "error.validationFailed \(field) \(reason)")
        case .capabilityUnsupported(let platform, _):
            return String(localized: "error.capabilityUnsupported \(platform)")
        case .managementCredentialMissing:
            return String(localized: "error.managementCredentialMissing")
        case .upstreamRejected(let status, let message):
            if let message, !message.isEmpty {
                return String(localized: "error.upstreamRejectedDetail \(status) \(message)")
            }
            return String(localized: "error.upstreamRejected \(status)")
        case .upstreamResponseUnparsable(let detail):
            return String(localized: "error.upstreamUnparsable \(detail)")
        case .networkUnavailable:
            return String(localized: "error.networkUnavailable")
        case .createdUpstreamButLocalSaveFailed(_, let platform):
            return String(localized: "error.createdUpstreamButLocalSaveFailed \(platform)")
        case .backupPassphraseIncorrect:
            return String(localized: "error.backupPassphraseIncorrect")
        case .backupVersionUnsupported(let found, let supported):
            return String(localized: "error.backupVersionUnsupported \(found) \(supported)")
        }
    }
}

extension ApiRelayError {
    /// 明文完全相同（FR-057）时 `reason` 为 `possible_duplicate:<uuid>`。
    var possibleDuplicateKeyId: UUID? {
        guard case .validationFailed(let field, let reason) = self, field == "secret" else {
            return nil
        }
        let prefix = "possible_duplicate:"
        guard reason.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(reason.dropFirst(prefix.count)))
    }
}
