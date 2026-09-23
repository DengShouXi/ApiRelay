#if DEBUG
import Foundation

/// 假加密备份：只认魔术头；导出/导入返回空壳。不碰 Crypto / SwiftData / Keychain。
actor FakeSecureBackup: SecureBackupServing {
    var journal = FakeJournal()

    func inspectProtection(_ data: Data) throws -> BackupFileProtection {
        try journal.record("inspectProtection")
        if data.starts(with: SecureBackupFile.passphraseMagic) {
            return .passphraseProtected
        }
        if data.starts(with: SecureBackupFile.unprotectedMagic) {
            return .unprotected
        }
        throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
    }

    func exportBackup(passphrase: String?, purpose: BackupPurpose, appPassword: String?) async throws -> BackupExportResult {
        _ = appPassword
        try journal.record("exportBackup")
        var out = Data()
        if let passphrase, !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(SecureBackupFile.passphraseMagic)
        } else {
            out.append(SecureBackupFile.unprotectedMagic)
        }
        out.append(Data("{\"purpose\":\"\(purpose.rawValue)\"}".utf8))
        return BackupExportResult(data: out, keysWithoutSecretCount: 0)
    }

    func importBackup(data: Data, passphrase: String?, appPassword: String?) async throws -> ImportSummary {
        _ = passphrase
        _ = appPassword
        try journal.record("importBackup")
        if data.starts(with: SecureBackupFile.passphraseMagic)
            || data.starts(with: SecureBackupFile.unprotectedMagic) {
            // ok
        } else {
            throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
        }
        return ImportSummary(
            accountCount: 0,
            keyCount: 0,
            toolCount: 0,
            skippedKeyCount: 0,
            keysWithoutSecretCount: 0,
            purpose: .fullBackup
        )
    }

    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws {
        try authorization.validate(operation: "fake_backup_committed_erase")
        try journal.record("purgeAllRecordsForCommittedErase")
    }
}
#endif
