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
    /// 生物识别被锁定。与不可用区分，供组合档提示；文案暂复用不可用句，W5 再分键。
    case biometryLockout
    /// 系统验证框失败（非用户取消、非口令错误）。文案暂复用验证失败句，W5 再分键。
    case systemAuthenticationFailed
    /// 设备尚未设置系统密码，系统无法执行设备主人认证。
    case devicePasscodeNotSet
    /// 当前环境不允许显示系统认证界面（例如应用不在可交互前台）。
    case authenticationNotInteractive
    /// LAContext 已失效或请求上下文过期。
    case authenticationContextInvalid
    /// 系统因应用切换等原因中断认证；不同于用户主动取消或凭据错误。
    case authenticationInterrupted
    /// 会话锁未解开，敏感动作被业务闸拒绝。
    case sessionLocked
    /// 主密码连续错误后的等待；`secondsRemaining` 供界面倒计时。
    case masterPasswordRetryDelayed(secondsRemaining: Int)
    /// 本机应用密码连续错误达到上限；必须走现有设备主人恢复流程重新设置。
    case masterPasswordLocked

    // MARK: - 保管
    /// Keychain 操作失败
    case keychainFailure(OSStatus)
    /// 元信息存在但 Keychain 无对应条目
    case secretMissingOnDevice
    /// 跨存储写入未能完整补偿，但剩余状态不会被正常业务路径引用（例如仅遗留孤儿密文）。
    case storageRecoveryFailed(operation: String, detail: String)
    /// 跨存储写入补偿失败且完整性未知；后续敏感读写必须 fail-closed。
    case storageIntegrityQuarantined(operation: String, detail: String)
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
        case .biometryLockout:
            return String(localized: "error.biometryUnavailable")
        case .systemAuthenticationFailed:
            return String(localized: "error.authenticationFailed")
        case .devicePasscodeNotSet:
            return String(localized: "error.devicePasscodeNotSet")
        case .authenticationNotInteractive:
            return String(localized: "error.authenticationNotInteractive")
        case .authenticationContextInvalid:
            return String(localized: "error.authenticationContextInvalid")
        case .authenticationInterrupted:
            return String(localized: "error.authenticationInterrupted")
        case .sessionLocked:
            return String(localized: "error.sessionLocked")
        case .masterPasswordRetryDelayed(let seconds):
            return String(localized: "error.masterPasswordRetryDelayed \(Int64(seconds))")
        case .masterPasswordLocked:
            return String(localized: "error.masterPasswordLocked")
        case .keychainFailure(let status):
            // OSStatus 默认按 %d 进 Catalog；统一走已翻译的 %lld 条目。
            return String(localized: "error.keychainFailure \(Int64(status))")
        case .secretMissingOnDevice:
            return String(localized: "error.secretMissingOnDevice")
        case .storageRecoveryFailed:
            return String(localized: "error.storageRecoveryFailed")
        case .storageIntegrityQuarantined:
            return String(localized: "error.storageIntegrityQuarantined")
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
