import Foundation
import LocalAuthentication

/// 身份确认门闩（FR-003）。实现 MUST NOT 跨操作缓存确认结果。
enum AuthPurpose: Sendable {
    case unlockApp
    case revealSecret
    case destructive
    case settings
    case recovery
}

protocol RevealGateServing: Actor {
    func confirm(reason: String, policy: RevealPolicy, purpose: AuthPurpose) async throws
    /// 主密码档：由 UI 采集口令后校验；不经系统「本机密码」框。
    func confirmWithMasterPassword(reason: String, password: String) async throws
    /// 破坏性操作强制设备主人认证（忽略用户 revealPolicy）。
    func confirmMandatory(reason: String, purpose: AuthPurpose) async throws
    /// 选用主密码门闩前确认本机已设密。
    func ensureMasterPasswordConfigured() async throws
    /// 取消进行中的系统验证。人已离开本 App 时 MUST 调用，否则触控 ID 框会盖在别的软件上。
    nonisolated func cancelCurrentAuthentication()
    /// 系统验证框正在前：同组失焦不得当成闲置去 cancel（FR-072）。
    nonisolated func isAuthenticationInProgress() -> Bool
    nonisolated func availableBiometry() -> BiometryKind
}

extension RevealGateServing {
    func confirm(reason: String, policy: RevealPolicy) async throws {
        try await confirm(reason: reason, policy: policy, purpose: .revealSecret)
    }

    func confirmMandatory(reason: String) async throws {
        try await confirmMandatory(reason: reason, purpose: .destructive)
    }
}
