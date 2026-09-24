import Foundation

/// 清空全部数据的界面顺序。设置页必须走这里；测试可直接驱动，观察
/// 「破坏性确认 → 身份验证 → 删除」且应用密码档在口令前不得调用删除。
enum SettingsEraseAllFlow: Sendable {
    enum Command: Equatable, Sendable {
        case none
        case promptAppPassword
        case erase(appPassword: String?)
    }

    struct Trace: Equatable, Sendable {
        var steps: [String] = []
    }

    static func isPasswordPrompt(_ error: ApiRelayError) -> Bool {
        if case .validationFailed(_, let reason) = error {
            return reason == "master_password_prompt_required" || reason == "required"
        }
        return false
    }

    static func afterDestructiveConfirm(
        policy: RevealPolicy,
        trace: inout Trace
    ) -> Command {
        trace.steps.append("destructiveConfirmed")
        switch RevealPolicyPersistence.canonical(policy) {
        case .masterPassword:
            trace.steps.append("identityPrompt")
            return .promptAppPassword
        case .noVerification, .biometricOrPasscode, .biometryOrAppPassword:
            trace.steps.append("identityStarted")
            return .erase(appPassword: nil)
        }
    }

    static func afterCombinationBiometricEnded(trace: inout Trace) -> Command {
        trace.steps.append("combinationOffer")
        return .promptAppPassword
    }

    static func afterAppPasswordEntry(_ password: String, trace: inout Trace) -> Command {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            trace.steps.append("identityRejected.empty")
            return .none
        }
        trace.steps.append("identityStarted")
        return .erase(appPassword: trimmed)
    }

    static func afterAppPasswordCancel(trace: inout Trace) -> Command {
        trace.steps.append("identityCancelled")
        return .none
    }

    static func noteEraseStarted(trace: inout Trace) {
        trace.steps.append("eraseStarted")
    }
}
