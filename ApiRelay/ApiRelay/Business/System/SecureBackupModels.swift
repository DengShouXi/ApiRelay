import Foundation

protocol SecureBackupServing: Actor {
    func inspectProtection(_ data: Data) throws -> BackupFileProtection
    func exportBackup(passphrase: String?, purpose: BackupPurpose, appPassword: String?) async throws -> BackupExportResult
    func importBackup(data: Data, passphrase: String?, appPassword: String?) async throws -> ImportSummary
    /// Only the already-authorized, durably journaled full-erase transaction
    /// may call this. It deliberately bypasses the normal write fence so the
    /// service's long-lived ModelActors cannot retain pre-erase snapshots.
    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws
}

extension SecureBackupServing {
    func exportBackup(passphrase: String?, purpose: BackupPurpose) async throws -> BackupExportResult {
        try await exportBackup(passphrase: passphrase, purpose: purpose, appPassword: nil)
    }

    func importBackup(data: Data, passphrase: String?) async throws -> ImportSummary {
        try await importBackup(data: data, passphrase: passphrase, appPassword: nil)
    }
}

struct BackupExportResult: Sendable {
    let data: Data
    /// 元信息在备份里、但本机 Keychain 已无对应条目的密钥数。导出仍会带上空字符串，导入后须明示。
    /// 其他 Keychain 读取错误不会计入这里，而会使导出失败关闭。
    let keysWithoutSecretCount: Int
}

struct ImportSummary: Sendable {
    let accountCount: Int
    let keyCount: Int
    let toolCount: Int
    let skippedKeyCount: Int
    /// 已写入元信息、但备份里明文为空、本机也没有写入 Keychain 的密钥数。
    let keysWithoutSecretCount: Int
    let purpose: BackupPurpose
}

enum SecureBackupFile: Sendable {
    nonisolated static var passphraseMagic: Data { Data("ARBK1".utf8) }
    nonisolated static var unprotectedMagic: Data { Data("ARBN1".utf8) }
    nonisolated static var pathExtension: String { "apirelaybackup" }
    nonisolated static var uti: String { "com.apirelay.backup" }
    /// New backups use the same PBKDF2-HMAC-SHA256 floor as newly enrolled app
    /// passwords. The count is serialized in every file, so older 210k backups
    /// remain readable and this value can be raised again without a format break.
    nonisolated static var kdfIterations: UInt32 { 600_000 }
}

extension Notification.Name {
    /// 加密备份导入完成后发出；主列表据此刷新。
    static let vaultDidImportBackup = Notification.Name("com.apirelay.vaultDidImportBackup")
}

/// Fine-grained import commit points used by the transaction coordinator and
/// deterministic fault-injection tests. This is deliberately internal: normal
/// callers use the no-op observer supplied by `SecureBackupService.init`.
nonisolated enum SecureBackupImportMutation: Sendable, Equatable {
    case accountInsert
    case toolInsert
    case toolUpdate
    case keyInsert
    case keyUpdate
    case assignmentAdd
    case notification
    case assignmentCompensation
    case keyCompensation
    case toolCompensation
    case accountCompensation
}
