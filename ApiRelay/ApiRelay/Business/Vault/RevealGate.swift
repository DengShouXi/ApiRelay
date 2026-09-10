import Foundation
import LocalAuthentication

/// 四档门闩实现。每次 confirm 新建 LAContext，不缓存成功态。
actor RevealGate: RevealGateServing {
    private let masterPassword: MasterPasswordServing
    /// 测试可注入：跳过真实 LA。
    private let authenticateDeviceOwner: (@Sendable (String, LAPolicy) async throws -> Void)?
    private let contextBox = ContextBox()

    init(
        masterPassword: MasterPasswordServing,
        authenticateDeviceOwner: (@Sendable (String, LAPolicy) async throws -> Void)? = nil
    ) {
        self.masterPassword = masterPassword
        self.authenticateDeviceOwner = authenticateDeviceOwner
    }

    nonisolated func cancelCurrentAuthentication() {
        contextBox.invalidate()
    }

    nonisolated func isAuthenticationInProgress() -> Bool {
        contextBox.isActive()
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

    func confirm(reason: String, policy: RevealPolicy, purpose: AuthPurpose) async throws {
        _ = purpose
        switch policy {
        case .noVerification:
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
        guard try await masterPassword.isSet() else {
            throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "master_password_not_set")
        }
        let ok = try await masterPassword.verify(password)
        guard ok else { throw ApiRelayError.authenticationFailed }
    }

    /// 选用主密码门闩前确认本机已设密（防策略已写、密未设的卡死态）。
    func ensureMasterPasswordConfigured() async throws {
        guard try await masterPassword.isSet() else {
            throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "master_password_not_set")
        }
    }

    func confirmMandatory(reason: String, purpose: AuthPurpose) async throws {
        _ = purpose
        try await evaluate(reason: reason, policy: .deviceOwnerAuthentication)
    }

    private func evaluate(reason: String, policy: LAPolicy) async throws {
        let requestID = UUID()
        contextBox.begin(requestID)
        defer { contextBox.clearIfCurrent(requestID) }
        if let authenticateDeviceOwner {
            try await authenticateDeviceOwner(reason, policy)
            try contextBox.throwIfCancelled(requestID)
            return
        }
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "gate.cancel")
        contextBox.replace(context, requestID: requestID)
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            if !success { throw ApiRelayError.authenticationFailed }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                throw ApiRelayError.authenticationCancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                // deviceOwnerAuthentication 本应回落本机密码；仅 biometricOnly 才报 biometryUnavailable。
                if policy == .deviceOwnerAuthenticationWithBiometrics {
                    throw ApiRelayError.biometryUnavailable
                }
                throw ApiRelayError.authenticationFailed
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

/// `evaluatePolicy` 进行中离开 App 时必须能从任意隔离域取消，否则系统框会盖在别的软件上。
/// 工程默认 MainActor；本类型持有锁，MUST 显式非隔离，否则 `RevealGate` actor 调不了。
nonisolated private final class ContextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var context: LAContext?
    private var requestID: UUID?

    func isActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return requestID != nil
    }

    func begin(_ requestID: UUID) {
        lock.lock()
        let previous = context
        context = nil
        self.requestID = requestID
        lock.unlock()
        previous?.invalidate()
    }

    func replace(_ next: LAContext?, requestID: UUID) {
        lock.lock()
        let previous = context
        context = next
        self.requestID = requestID
        lock.unlock()
        previous?.invalidate()
    }

    func clearIfCurrent(_ requestID: UUID) {
        lock.lock()
        if self.requestID == requestID {
            context = nil
            self.requestID = nil
        }
        lock.unlock()
    }

    func throwIfCancelled(_ requestID: UUID) throws {
        lock.lock()
        let current = self.requestID
        lock.unlock()
        if current != requestID {
            throw ApiRelayError.authenticationCancelled
        }
    }

    func invalidate() {
        lock.lock()
        let current = context
        context = nil
        requestID = nil
        lock.unlock()
        current?.invalidate()
    }
}
