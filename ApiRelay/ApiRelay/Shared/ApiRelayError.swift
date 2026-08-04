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
