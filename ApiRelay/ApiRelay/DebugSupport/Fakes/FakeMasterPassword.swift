#if DEBUG
import Foundation

/// 假主密码：内存口令。不碰 Keychain / 哈希。
actor FakeMasterPassword: MasterPasswordServing {
    var journal = FakeJournal()
    private var password: String?

    init(initialPassword: String? = nil) {
        password = initialPassword
    }
    private var revision: UInt64 = 0
    private var mutationInFlight = false
    private var statusOverride: AppPasswordMaterialStatus?
    private var beforeExclusiveResetHook: (@Sendable () async throws -> Void)?
    private var duringLeaseHook: (@Sendable () async throws -> Void)?
    private var beforeSetPasswordHook: (@Sendable () async throws -> Void)?
    private var beforeVerifyHook: (@Sendable () async throws -> Void)?

    func isSet() async throws -> Bool {
        try journal.record("isSet")
        if let statusOverride {
            switch statusOverride {
            case .set:
                return true
            case .unset:
                return false
            case .unreadable:
                throw ApiRelayError.validationFailed(
                    field: "masterPassword",
                    reason: "material_unreadable"
                )
            }
        }
        return password != nil
    }

    func materialStatus() async -> AppPasswordMaterialStatus {
        do {
            try journal.record("materialStatus")
            if let statusOverride { return statusOverride }
            return password == nil ? .unset : .set
        } catch {
            return .unreadable
        }
    }

    func materialRevision() async -> UInt64 {
        revision
    }

    func overrideMaterialStatus(_ status: AppPasswordMaterialStatus?) {
        statusOverride = status
    }

    func setBeforeExclusiveResetHook(_ hook: (@Sendable () async throws -> Void)?) {
        beforeExclusiveResetHook = hook
    }

    func setDuringLeaseHook(_ hook: (@Sendable () async throws -> Void)?) {
        duringLeaseHook = hook
    }

    func setBeforeSetPasswordHook(_ hook: (@Sendable () async throws -> Void)?) {
        beforeSetPasswordHook = hook
    }

    func setBeforeVerifyHook(_ hook: (@Sendable () async throws -> Void)?) {
        beforeVerifyHook = hook
    }

    func setPassword(_ password: String, committing: KeychainCommit) async throws {
        try journal.record("setPassword")
        if let beforeSetPasswordHook {
            try await beforeSetPasswordHook()
        }
        try mutateMaterial {
            try Self.rejectCreate(currentStatus())
            try committing {
                try writeIfValid(password)
            }
        }
    }

    func verify(_ password: String) async throws -> Bool {
        try journal.record("verify")
        if let beforeVerifyHook {
            try await beforeVerifyHook()
        }
        guard let stored = self.password else { return false }
        return stored == MasterPasswordPolicy.trimmed(password)
    }

    func changePassword(current: String, new: String, committing: KeychainCommit) async throws {
        try journal.record("changePassword")
        try mutateMaterial {
            guard let stored = password,
                  stored == MasterPasswordPolicy.trimmed(current) else {
                throw ApiRelayError.validationFailed(field: "masterPassword", reason: "incorrect")
            }
            try Self.rejectReplace(currentStatus())
            try committing {
                try writeIfValid(new)
            }
        }
    }

    func fail(_ method: String, with error: ApiRelayError) {
        journal.fail(method, with: error)
    }

    /// 测试替身：只清内存口令。限速/盐/PBKDF2 回归仍走真实 `MasterPasswordService`。
    func reset() async throws {
        try journal.record("reset")
        try mutateMaterial {
            password = nil
        }
    }

    func reset(expectedRevision: UInt64, committing: KeychainCommit) async throws {
        try journal.record("reset")
        if let beforeExclusiveResetHook {
            try await beforeExclusiveResetHook()
        }
        try mutateMaterial {
            guard revision == expectedRevision else {
                throw ApiRelayError.validationFailed(
                    field: "masterPassword",
                    reason: "stale_concurrent"
                )
            }
            try committing {
                password = nil
            }
        }
    }

    func withUnchangedSetMaterial(
        expectedRevision: UInt64,
        perform: @Sendable () async throws -> Void
    ) async throws {
        guard !mutationInFlight else {
            throw ApiRelayError.validationFailed(
                field: "masterPassword",
                reason: "stale_concurrent"
            )
        }
        mutationInFlight = true
        defer { mutationInFlight = false }
        guard revision == expectedRevision else {
            throw ApiRelayError.validationFailed(
                field: "masterPassword",
                reason: "stale_concurrent"
            )
        }
        try Self.rejectReplace(currentStatus())
        if let duringLeaseHook {
            try await duringLeaseHook()
        }
        try await perform()
    }

    private func currentStatus() -> AppPasswordMaterialStatus {
        if let statusOverride { return statusOverride }
        return password == nil ? .unset : .set
    }

    private func mutateMaterial(_ body: () throws -> Void) throws {
        guard !mutationInFlight else {
            throw ApiRelayError.validationFailed(
                field: "masterPassword",
                reason: "stale_concurrent"
            )
        }
        mutationInFlight = true
        defer { mutationInFlight = false }
        try body()
        revision += 1
    }

    private func writeIfValid(_ password: String) throws {
        let trimmed = MasterPasswordPolicy.trimmed(password)
        guard trimmed.count >= MasterPasswordPolicy.minimumLength else {
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "too_short")
        }
        self.password = trimmed
    }

    nonisolated private static func rejectCreate(_ status: AppPasswordMaterialStatus) throws {
        switch status {
        case .unset:
            return
        case .set:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "already_set")
        case .unreadable:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "material_unreadable")
        }
    }

    nonisolated private static func rejectReplace(_ status: AppPasswordMaterialStatus) throws {
        switch status {
        case .set:
            return
        case .unset:
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "master_password_not_configured"
            )
        case .unreadable:
            throw ApiRelayError.validationFailed(field: "masterPassword", reason: "material_unreadable")
        }
    }
}
#endif
