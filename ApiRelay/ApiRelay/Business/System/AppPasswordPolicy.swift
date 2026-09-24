import Foundation

/// 应用密码档与组合档：未配置或材料不可读都不得当成可 persist 的当前策略。
enum AppPasswordPolicyGate: Sendable {
    nonisolated static func requiresMaterial(_ policy: RevealPolicy) -> Bool {
        AppPasswordSetup.requiresMaterial(policy)
    }

    nonisolated static func canPersistAsCurrentPolicy(
        _ policy: RevealPolicy,
        material: AppPasswordMaterialStatus
    ) -> Bool {
        guard requiresMaterial(policy) else { return true }
        return material == .set
    }

    nonisolated static func canPersistAsCurrentPolicy(
        _ policy: RevealPolicy,
        materialIsSet: Bool
    ) -> Bool {
        canPersistAsCurrentPolicy(policy, material: materialIsSet ? .set : .unset)
    }

    nonisolated static func canUseAppPasswordEntry(material: AppPasswordMaterialStatus) -> Bool {
        material == .set
    }

    nonisolated static func canUseAppPasswordEntry(materialIsSet: Bool) -> Bool {
        canUseAppPasswordEntry(material: materialIsSet ? .set : .unset)
    }

    /// Only a patch that is about to make an app-password-dependent policy
    /// current needs a Keychain material read. Ordinary security changes (for
    /// example 60 seconds -> immediately) must not await that unrelated read:
    /// the settings scene can become inactive in the gap and cancel a change
    /// the user already selected.
    nonisolated static func requiresMaterialLookup(for patch: PreferencesPatch) -> Bool {
        guard let policy = patch.revealPolicy else { return false }
        return requiresMaterial(policy)
    }

    /// 普通解锁/取用/编辑/删除/备份/降低安全入口不得 `setPassword`。
    nonisolated static func ordinaryEntryMissingMaterialMessage() -> String {
        String(localized: "appLock.combination.notSet")
    }

    /// 普通入口必须保留材料三态。Keychain 暂时不可读不是“从未设置”，
    /// 否则用户会被误导去重复设密或把存储故障当成自己的操作问题。
    nonisolated static func ordinaryEntryUnavailableMessage(
        material: AppPasswordMaterialStatus
    ) -> String {
        switch material {
        case .unreadable:
            String(localized: "settings.appPassword.status.unreadable")
        case .unset, .set:
            ordinaryEntryMissingMaterialMessage()
        }
    }

    nonisolated static func persistRejection(
        _ patch: PreferencesPatch,
        material: AppPasswordMaterialStatus
    ) -> ApiRelayError? {
        guard let policy = patch.revealPolicy else { return nil }
        guard canPersistAsCurrentPolicy(policy, material: material) else {
            if material == .unreadable {
                return ApiRelayError.validationFailed(
                    field: "masterPassword",
                    reason: "material_unreadable"
                )
            }
            return ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "master_password_not_configured"
            )
        }
        return nil
    }

    nonisolated static func persistRejection(
        _ patch: PreferencesPatch,
        materialIsSet: Bool
    ) -> ApiRelayError? {
        persistRejection(patch, material: materialIsSet ? .set : .unset)
    }
}
