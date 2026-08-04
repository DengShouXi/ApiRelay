import Foundation
import LocalAuthentication

/// 身份确认门闩（FR-003）。实现 MUST NOT 跨操作缓存确认结果。
protocol RevealGateServing: Actor {
    func confirm(reason: String, policy: RevealPolicy) async throws
    /// 破坏性操作强制设备主人认证（忽略用户 revealPolicy）。
    func confirmMandatory(reason: String) async throws
    func availableBiometry() -> BiometryKind
}
