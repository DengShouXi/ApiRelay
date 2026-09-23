import Foundation
import Security

protocol BackupPassphraseServing: Actor {
    func isSet() async throws -> Bool
    nonisolated func captureAuthorizationLease() throws -> SessionAuthorizationLease
    nonisolated func validateAuthorizationLease(_ authorization: SessionAuthorizationLease) throws
    nonisolated func commitAuthorizationLease(
        _ authorization: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws
    func set(_ passphrase: String, authorization: SessionAuthorizationLease) async throws
    /// 取出明文仅用于加密/导入；调用方 MUST 放在局部作用域，不得写入可观察状态。
    func plaintext(authorization: SessionAuthorizationLease) async throws -> String
    func clear(authorization: SessionAuthorizationLease) async throws
}

extension BackupPassphraseServing {
    /// 兼容测试播种及非交互内部调用；产品认证流程必须在认证前自行捕获并贯穿同一 lease。
    func set(_ passphrase: String) async throws {
        let authorization = try captureAuthorizationLease()
        try await set(passphrase, authorization: authorization)
    }

    func plaintext() async throws -> String {
        let authorization = try captureAuthorizationLease()
        return try await plaintext(authorization: authorization)
    }

    func clear() async throws {
        let authorization = try captureAuthorizationLease()
        try await clear(authorization: authorization)
    }
}

actor BackupPassphraseService: BackupPassphraseServing {
    static let minimumLength = 4

    private let keychain: KeychainStoring
    private let account = KeychainStore.backupPassphraseAccount
    nonisolated private let sessionLock: any SessionLockQuerying
    nonisolated private let mutationGate: StorageMutationGate

    init(
        keychain: KeychainStoring,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock(),
        mutationGate: StorageMutationGate = StorageMutationGate()
    ) {
        self.keychain = keychain
        self.sessionLock = sessionLock
        self.mutationGate = mutationGate
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
        let storagePermit = try mutationGate.beginNormal(operation: "backup_passphrase_read")
        defer { storagePermit.finish() }
        do {
            _ = try await keychain.read(service: .backuppw, account: account)
            return true
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            return false
        }
    }

    func set(_ passphrase: String, authorization: SessionAuthorizationLease) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "backup_passphrase_set")
        defer { storagePermit.finish() }
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumLength else {
            throw ApiRelayError.validationFailed(field: "backupPassphrase", reason: "too_short")
        }
        try validateAuthorizationLease(authorization)
        let sessionLock = self.sessionLock
        try await keychain.save(
            trimmed,
            service: .backuppw,
            account: account,
            committing: { operation in
                try sessionLock.commitAuthorizationLease(authorization, operation: operation)
            }
        )
        try validateAuthorizationLease(authorization)
    }

    func plaintext(authorization: SessionAuthorizationLease) async throws -> String {
        let storagePermit = try mutationGate.beginNormal(operation: "backup_passphrase_plaintext")
        defer { storagePermit.finish() }
        try validateAuthorizationLease(authorization)
        let secret = try await keychain.read(service: .backuppw, account: account)
        try validateAuthorizationLease(authorization)
        return secret
    }

    func clear(authorization: SessionAuthorizationLease) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "backup_passphrase_clear")
        defer { storagePermit.finish() }
        try validateAuthorizationLease(authorization)
        let sessionLock = self.sessionLock
        try await keychain.delete(
            service: .backuppw,
            account: account,
            committing: { operation in
                try sessionLock.commitAuthorizationLease(authorization, operation: operation)
            }
        )
        try validateAuthorizationLease(authorization)
    }
}
