#if DEBUG
import Foundation

/// 假门闩：默认一律放行。不碰 LA / 主密码。
actor FakeRevealGate: RevealGateServing {
    var journal = FakeJournal()
    private let biometryBox = BiometryBox()

    private final class BiometryBox: @unchecked Sendable {
        var value: BiometryKind = .none
    }

    /// 测试可改；默认无生物识别。
    func setAvailableBiometry(_ kind: BiometryKind) {
        biometryBox.value = kind
    }

    func confirm(reason: String, policy: RevealPolicy) async throws {
        _ = reason
        _ = policy
        try journal.record("confirm")
    }

    func confirmWithMasterPassword(reason: String, password: String) async throws {
        _ = reason
        _ = password
        try journal.record("confirmWithMasterPassword")
    }

    func confirmMandatory(reason: String) async throws {
        _ = reason
        try journal.record("confirmMandatory")
    }

    func ensureMasterPasswordConfigured() async throws {
        try journal.record("ensureMasterPasswordConfigured")
    }

    nonisolated func availableBiometry() -> BiometryKind {
        biometryBox.value
    }
}
#endif
