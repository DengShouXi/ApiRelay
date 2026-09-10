#if DEBUG
import Foundation

/// 假门闩：默认一律放行。不碰 LA / 主密码。
actor FakeRevealGate: RevealGateServing {
    var journal = FakeJournal()
    private let biometryBox = BiometryBox()
    private let authBox = AuthBox()

    private final class BiometryBox: @unchecked Sendable {
        var value: BiometryKind = .none
    }

    private final class AuthBox: @unchecked Sendable {
        private let lock = NSLock()
        private var inProgress = false
        private var cancelCount = 0

        func setInProgress(_ value: Bool) {
            lock.lock()
            inProgress = value
            lock.unlock()
        }

        func isInProgress() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return inProgress
        }

        func noteCancel() {
            lock.lock()
            cancelCount += 1
            lock.unlock()
        }

        func cancelCallCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return cancelCount
        }
    }

    /// 测试可改；默认无生物识别。
    func setAvailableBiometry(_ kind: BiometryKind) {
        biometryBox.value = kind
    }

    func setAuthenticationInProgress(_ value: Bool) {
        authBox.setInProgress(value)
    }

    func cancelCallCount() -> Int {
        authBox.cancelCallCount()
    }

    func confirm(reason: String, policy: RevealPolicy, purpose: AuthPurpose) async throws {
        _ = reason
        _ = policy
        _ = purpose
        try journal.record("confirm")
    }

    func confirmWithMasterPassword(reason: String, password: String) async throws {
        _ = reason
        _ = password
        try journal.record("confirmWithMasterPassword")
    }

    func confirmMandatory(reason: String, purpose: AuthPurpose) async throws {
        _ = reason
        _ = purpose
        try journal.record("confirmMandatory")
    }

    func ensureMasterPasswordConfigured() async throws {
        try journal.record("ensureMasterPasswordConfigured")
    }

    nonisolated func cancelCurrentAuthentication() {
        authBox.noteCancel()
    }

    nonisolated func isAuthenticationInProgress() -> Bool {
        authBox.isInProgress()
    }

    nonisolated func availableBiometry() -> BiometryKind {
        biometryBox.value
    }
}
#endif
