import Foundation

/// 密钥保管与分发（US1）。UI MUST NOT 直接访问 Keychain。
protocol KeyVaultServing: Actor {
    func accounts() async throws -> [UpstreamAccountDTO]
    func keys(in accountId: UUID?) async throws -> [KeyRecordDTO]
    func createAccount(_ draft: UpstreamAccountDraft) async throws -> UUID
    /// 更新上游账号（平台 / 显示名 / 自定义 Base URL）。
    func updateAccount(_ id: UUID, patch: UpstreamAccountPatch) async throws
    func deleteAccount(_ id: UUID) async throws

    /// 同账号下本机 Keychain 明文完全相同则抛 `possible_duplicate`；该比对 MUST NOT 走门闩。
    func createKey(_ draft: KeyDraft, secret: String, acknowledgePossibleDuplicate: Bool) async throws -> UUID
    func updateKey(_ id: UUID, patch: KeyPatch) async throws
    /// 编辑已有密钥：名称、可选换密文、备注、所属上游账号的平台与显示名。
    /// 换密文时不触发门闩（写入而非取出明文）；留空 `draft.secret` 则不碰 Keychain。
    func editKey(_ id: UUID, draft: KeyEditDraft) async throws
    func deleteKey(_ id: UUID) async throws
    /// 按用户拖拽结果重写分区内密钥顺序（`orderedIds` 为从上到下）。
    func reorderKeys(orderedIds: [UUID]) async throws
    /// 按用户拖拽结果重写上游账号分区顺序（`orderedIds` 为从上到下）。不改 `updatedAt`。
    func reorderAccounts(orderedIds: [UUID]) async throws

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
    /// 将已通过门闩取出的明文写入剪贴板。MUST NOT 再走门闩。
    func copyRevealedSecretToClipboard(_ secret: String) async throws

    func remainingFreeQuota() async throws -> Int?
    func readSecretForAutomatedUse(keyId: UUID, purpose: AutomatedSecretPurpose) async throws -> String

    /// 启动巡检：孤儿标记 + 过期回收站清除。
    func performStartupMaintenance() async throws

    /// FR-061：物理删除本服务持有的账号 / 密钥 / 指派 / 安全偏好（含回收站）。
    func purgeAllRecordsForErase() async throws
    /// 批量恢复前先算额度。超出则整批拒绝，且 MUST 在门闩之前调用。
    func preflightRestoreQuota(keyIds: [UUID], accountIds: [UUID]) async throws
    /// 调用方 MUST 已完成 `confirmMandatory`。
    func restoreDeletedAfterAuthentication(keyIds: [UUID], accountIds: [UUID]) async -> TrashBatchOutcome
    /// 调用方 MUST 已完成 `confirmMandatory`。
    func permanentlyDeleteDeletedAfterAuthentication(keyIds: [UUID], accountIds: [UUID]) async -> TrashBatchOutcome
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
