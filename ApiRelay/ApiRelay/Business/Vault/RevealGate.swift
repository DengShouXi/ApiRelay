import Foundation
import LocalAuthentication

/// 四档门闩实现。每次 confirm 新建 LAContext，不缓存成功态。
actor RevealGate: RevealGateServing {
    private let masterPassword: MasterPasswordServing
    /// 测试可注入：跳过真实 LA。
    private let authenticateDeviceOwner: (@Sendable (String, LAPolicy) async throws -> Void)?

    init(
        masterPassword: MasterPasswordServing,
        authenticateDeviceOwner: (@Sendable (String, LAPolicy) async throws -> Void)? = nil
    ) {
        self.masterPassword = masterPassword
        self.authenticateDeviceOwner = authenticateDeviceOwner
    }

    nonisolated func availableBiometry() -> BiometryKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    func confirm(reason: String, policy: RevealPolicy) async throws {
        switch policy {
        case .none:
            return
        case .biometricOrPasscode:
            try await evaluate(reason: reason, policy: .deviceOwnerAuthentication)
        case .biometricOnly:
            switch availableBiometry() {
            case .none:
                throw ApiRelayError.biometryUnavailable
            case .faceID, .touchID:
                break
            }
            try await evaluate(reason: reason, policy: .deviceOwnerAuthenticationWithBiometrics)
        case .masterPassword:
            guard try await masterPassword.isSet() else {
                throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "master_password_not_set")
            }
            // UI 负责采集口令并调用 verify；此处要求调用方先经 MasterPasswordPrompt。
            // KeyVault 在 masterPassword 档时改走 confirmWithMasterPassword。
            throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "master_password_prompt_required")
        }
    }

    /// 主密码档：由 UI 传入口令，服务内校验；不经 LA。
    func confirmWithMasterPassword(reason: String, password: String) async throws {
        _ = reason
        let ok = try await masterPassword.verify(password)
        guard ok else { throw ApiRelayError.authenticationFailed }
    }

    func confirmMandatory(reason: String) async throws {
        try await evaluate(reason: reason, policy: .deviceOwnerAuthentication)
    }

    private func evaluate(reason: String, policy: LAPolicy) async throws {
        if let authenticateDeviceOwner {
            try await authenticateDeviceOwner(reason, policy)
            return
        }
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "gate.cancel")
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            if !success { throw ApiRelayError.authenticationFailed }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                throw ApiRelayError.authenticationCancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                throw ApiRelayError.biometryUnavailable
            default:
                throw ApiRelayError.authenticationFailed
            }
        } catch let error as ApiRelayError {
            throw error
        } catch {
            throw ApiRelayError.authenticationFailed
        }
    }
}
