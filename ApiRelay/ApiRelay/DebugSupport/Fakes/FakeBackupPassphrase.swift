#if DEBUG
import Foundation
import Security

/// 假备份口令：内存明文。不碰 Keychain。
actor FakeBackupPassphrase: BackupPassphraseServing {
    var journal = FakeJournal()
    private var passphrase: String?
    nonisolated private let sessionLock: any SessionLockQuerying

    init(sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock()) {
        self.sessionLock = sessionLock
    }

    /// Test setup/inspection only. Product paths must use the lease-bound API.
    func seedForTests(_ passphrase: String?) {
        self.passphrase = passphrase
    }

    func plaintextForTests() -> String? {
        passphrase
    }

    nonisolated func captureAuthorizationLease() throws -> SessionAuthorizationLease {
        try sessionLock.captureAuthorizationLease()
    }

    nonisolated func validateAuthorizationLease(
        _ authorization: SessionAuthorizationLease
    ) throws {
        try sessionLock.validateAuthorizationLease(authorization)
    }

    nonisolated func commitAuthorizationLease(
        _ authorization: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws {
        try sessionLock.commitAuthorizationLease(authorization, operation: operation)
    }

    func isSet() async throws -> Bool {
        try journal.record("isSet")
        return passphrase != nil
    }

    func set(_ passphrase: String, authorization: SessionAuthorizationLease) async throws {
        try journal.record("set")
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else {
            throw ApiRelayError.validationFailed(field: "backupPassphrase", reason: "too_short")
        }
        try commitAuthorizationLease(authorization) {
            self.passphrase = trimmed
        }
        try validateAuthorizationLease(authorization)
    }

    func plaintext(authorization: SessionAuthorizationLease) async throws -> String {
        try journal.record("plaintext")
        try validateAuthorizationLease(authorization)
        guard let passphrase else {
            throw ApiRelayError.keychainFailure(errSecItemNotFound)
        }
        try validateAuthorizationLease(authorization)
        return passphrase
    }

    func clear(authorization: SessionAuthorizationLease) async throws {
        try journal.record("clear")
        try commitAuthorizationLease(authorization) {
            passphrase = nil
        }
        try validateAuthorizationLease(authorization)
    }
}
#endif
