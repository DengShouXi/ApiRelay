import Foundation
import Security

protocol BackupPassphraseServing: Actor {
    func isSet() async throws -> Bool
    func set(_ passphrase: String) async throws
    /// 取出明文仅用于加密/导入；调用方 MUST 放在局部作用域，不得写入可观察状态。
    func plaintext() async throws -> String
    func clear() async throws
}

actor BackupPassphraseService: BackupPassphraseServing {
    static let minimumLength = 4

    private let keychain: KeychainStore
    private let account = KeychainStore.backupPassphraseAccount

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func isSet() async throws -> Bool {
        do {
            _ = try await keychain.read(service: .backuppw, account: account)
            return true
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            return false
        }
    }

    func set(_ passphrase: String) async throws {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumLength else {
            throw ApiRelayError.validationFailed(field: "backupPassphrase", reason: "too_short")
        }
        try await keychain.save(trimmed, service: .backuppw, account: account)
    }

    func plaintext() async throws -> String {
        try await keychain.read(service: .backuppw, account: account)
    }

    func clear() async throws {
        try await keychain.delete(service: .backuppw, account: account)
    }
}
