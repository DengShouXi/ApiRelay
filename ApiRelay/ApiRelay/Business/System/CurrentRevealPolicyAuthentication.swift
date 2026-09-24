import Foundation

/// 组合档显式应用密码：空白必须在调门闩前拒绝；取消/失败不得自动改走另一条认证路径。
enum CombinationExplicitAuth: Sendable {
    /// `nil` = 尚未提交口令，走单次系统设备主人认证。非空才走 `confirmCombinationWithAppPassword`。
    static func normalizedPassword(_ appPassword: String?) throws -> String? {
        guard let appPassword else { return nil }
        let trimmed = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "combination_password_empty"
            )
        }
        return trimmed
    }

    static func isCombination(_ policy: RevealPolicy) -> Bool {
        RevealPolicyPersistence.canonical(policy) == .biometryOrAppPassword
    }

    /// 系统认证取消或旧错误源报告生物不可用/锁定后，界面可显示「使用应用密码」，但不得自动提交应用密码路径。
    static func shouldOfferAppPassword(after error: Error) -> Bool {
        switch error as? ApiRelayError {
        case .authenticationCancelled, .biometryUnavailable, .biometryLockout, .devicePasscodeNotSet:
            return true
        default:
            return false
        }
    }

    /// 只有已经绑定当前待办时才显示入口，禁止无反馈地武装下一次操作。
    static func shouldShowExplicitEntry(hasBoundOperation: Bool, policy: RevealPolicy) -> Bool {
        hasBoundOperation && isCombination(policy)
    }
}

/// 降低或互换验证方式时，按**当前**档确认，不得一律改走设备主人。
enum CurrentRevealPolicyAuth: Sendable {
    static func confirm(
        _ policy: RevealPolicy,
        gate: any RevealGateServing,
        reason: String,
        purpose: AuthPurpose,
        appPassword: String? = nil
    ) async throws {
        switch RevealPolicyPersistence.canonical(policy) {
        case .noVerification:
            return
        case .biometricOrPasscode:
            try await gate.confirm(reason: reason, policy: .biometricOrPasscode, purpose: purpose)
        case .biometryOrAppPassword:
            if let password = try CombinationExplicitAuth.normalizedPassword(appPassword) {
                try await gate.confirmCombinationWithAppPassword(
                    reason: reason,
                    password: password,
                    purpose: purpose
                )
            } else {
                try await gate.confirm(reason: reason, policy: .biometryOrAppPassword, purpose: purpose)
            }
        case .masterPassword:
            let trimmed = appPassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                throw ApiRelayError.validationFailed(
                    field: "revealPolicy",
                    reason: "master_password_prompt_required"
                )
            }
            try await gate.confirmWithMasterPassword(
                reason: reason,
                password: trimmed,
                purpose: purpose
            )
        }
    }
}
