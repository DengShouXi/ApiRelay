#if DEBUG
import Foundation
import Security

/// 假备份口令：内存明文。不碰 Keychain。
actor FakeBackupPassphrase: BackupPassphraseServing {
    var journal = FakeJournal()
    private var passphrase: String?

    func isSet() async throws -> Bool {
        try journal.record("isSet")
        return passphrase != nil
    }

    func set(_ passphrase: String) async throws {
        try journal.record("set")
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else {
            throw ApiRelayError.validationFailed(field: "backupPassphrase", reason: "too_short")
        }
        self.passphrase = trimmed
    }

    func plaintext() async throws -> String {
        try journal.record("plaintext")
        guard let passphrase else {
            throw ApiRelayError.keychainFailure(errSecItemNotFound)
        }
        return passphrase
    }

    func clear() async throws {
        try journal.record("clear")
        passphrase = nil
    }
}
#endif
