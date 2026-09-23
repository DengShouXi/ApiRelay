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
        private var activeOwner: AuthenticationRequestOwner?
        private var cancelCount = 0

        func setInProgress(_ value: Bool, owner: AuthenticationRequestOwner) {
            lock.lock()
            activeOwner = value ? owner : nil
            lock.unlock()
        }

        func isInProgress(owner: AuthenticationRequestOwner?) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard let activeOwner else { return false }
            return owner == nil || owner == activeOwner
        }

        func noteCancel(owner: AuthenticationRequestOwner?) {
            lock.lock()
            cancelCount += 1
            if owner == nil || owner == activeOwner { activeOwner = nil }
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

    func setAuthenticationInProgress(
        _ value: Bool,
        owner: AuthenticationRequestOwner = .content
    ) {
        authBox.setInProgress(value, owner: owner)
    }

    func cancelCallCount() -> Int {
        authBox.cancelCallCount()
    }

    func confirm(reason: String, policy: RevealPolicy, purpose: AuthPurpose) async throws {
        _ = reason
        _ = policy
        _ = purpose
        try journal.record("confirm")
        if let afterConfirmHook {
            try await afterConfirmHook()
        }
    }

    func confirmWithMasterPassword(
        reason: String,
        password: String,
        purpose: AuthPurpose
    ) async throws {
        _ = reason
        _ = password
        _ = purpose
        try journal.record("confirmWithMasterPassword")
        if let afterConfirmHook {
            try await afterConfirmHook()
        }
    }

    func confirmCombinationWithAppPassword(reason: String, password: String, purpose: AuthPurpose) async throws {
        _ = reason
        _ = password
        _ = purpose
        try journal.record("confirmCombinationWithAppPassword")
        if let afterConfirmHook {
            try await afterConfirmHook()
        }
    }

    private var afterConfirmHook: (@Sendable () async throws -> Void)?

    func setAfterConfirmHook(_ hook: (@Sendable () async throws -> Void)?) {
        afterConfirmHook = hook
    }

    private var confirmMandatoryHook: (@Sendable () async throws -> Void)?

    func setConfirmMandatoryHook(_ hook: (@Sendable () async throws -> Void)?) {
        confirmMandatoryHook = hook
    }

    func confirmMandatory(reason: String, purpose: AuthPurpose) async throws {
        _ = reason
        _ = purpose
        try journal.record("confirmMandatory")
        if let confirmMandatoryHook {
            try await confirmMandatoryHook()
        }
    }

    func ensureMasterPasswordConfigured() async throws {
        try journal.record("ensureMasterPasswordConfigured")
    }

    private var appPasswordMaterialStatusValue: AppPasswordMaterialStatus = .unset

    func setAppPasswordMaterialSet(_ value: Bool) {
        appPasswordMaterialStatusValue = value ? .set : .unset
    }

    func setAppPasswordMaterialStatus(_ value: AppPasswordMaterialStatus) {
        appPasswordMaterialStatusValue = value
    }

    func isAppPasswordMaterialSet() async throws -> Bool {
        try journal.record("isAppPasswordMaterialSet")
        switch appPasswordMaterialStatusValue {
        case .set:
            return true
        case .unset:
            return false
        case .unreadable:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "material_unreadable")
        }
    }

    func appPasswordMaterialStatus() async -> AppPasswordMaterialStatus {
        do {
            try journal.record("appPasswordMaterialStatus")
            return appPasswordMaterialStatusValue
        } catch {
            return .unreadable
        }
    }

    func fail(_ method: String, with error: ApiRelayError) {
        journal.fail(method, with: error)
    }

    func clearFailure(_ method: String) {
        journal.clearFailure(method)
    }

    nonisolated func cancelAuthentication(owner: AuthenticationRequestOwner) {
        authBox.noteCancel(owner: owner)
    }

    nonisolated func cancelAllAuthentication() {
        authBox.noteCancel(owner: nil)
    }

    nonisolated func isAuthenticationInProgress(owner: AuthenticationRequestOwner?) -> Bool {
        authBox.isInProgress(owner: owner)
    }

    nonisolated func availableBiometry() -> BiometryKind {
        biometryBox.value
    }
}
#endif
