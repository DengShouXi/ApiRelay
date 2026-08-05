import Foundation

/// 密钥保管与分发（US1）。UI MUST NOT 直接访问 Keychain。
protocol KeyVaultServing: Actor {
    func accounts() async throws -> [UpstreamAccountDTO]
    func keys(in accountId: UUID?) async throws -> [KeyRecordDTO]
    func createAccount(_ draft: UpstreamAccountDraft) async throws -> UUID
    func deleteAccount(_ id: UUID) async throws

    func createKey(_ draft: KeyDraft, secret: String, acknowledgePossibleDuplicate: Bool) async throws -> UUID
    func updateKey(_ id: UUID, patch: KeyPatch) async throws
    func deleteKey(_ id: UUID) async throws
    /// 按用户拖拽结果重写分区内密钥顺序（`orderedIds` 为从上到下）。
    func reorderKeys(orderedIds: [UUID]) async throws

    func recentlyDeletedKeys() async throws -> [KeyRecordDTO]
    func restoreKey(_ id: UUID) async throws
    func permanentlyDeleteKey(_ id: UUID) async throws
    func purgeExpiredDeletedKeys() async throws

    func recentlyDeletedAccounts() async throws -> [UpstreamAccountDTO]
    func restoreAccount(_ id: UUID) async throws
    func permanentlyDeleteAccount(_ id: UUID) async throws
    func purgeExpiredDeletedAccounts() async throws

    func addAssignment(keyId: UUID, consumerToolId: UUID) async throws
    func removeAssignment(keyId: UUID, consumerToolId: UUID) async throws
    func assignmentKind(keyId: UUID) async throws -> AssignmentKind

    /// `masterPassword` 仅在 revealPolicy == .masterPassword 时需要。
    func revealSecret(keyId: UUID, purpose: RevealPurpose, masterPassword: String?) async throws -> String
    func copySecretToClipboard(keyId: UUID, masterPassword: String?) async throws

    func remainingFreeQuota() async throws -> Int?
    func readSecretForAutomatedUse(keyId: UUID, purpose: AutomatedSecretPurpose) async throws -> String

    /// 启动巡检：孤儿标记 + 过期回收站清除。
    func performStartupMaintenance() async throws
}

extension KeyVaultServing {
    func createKey(_ draft: KeyDraft, secret: String) async throws -> UUID {
        try await createKey(draft, secret: secret, acknowledgePossibleDuplicate: false)
    }

    func revealSecret(keyId: UUID, purpose: RevealPurpose) async throws -> String {
        try await revealSecret(keyId: keyId, purpose: purpose, masterPassword: nil)
    }

    func copySecretToClipboard(keyId: UUID) async throws {
        try await copySecretToClipboard(keyId: keyId, masterPassword: nil)
    }
}
