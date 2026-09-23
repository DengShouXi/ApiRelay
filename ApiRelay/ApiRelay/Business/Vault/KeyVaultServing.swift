import Foundation

/// 身份验证证据与本次明文读取绑定，调用方不得在读取后重新查询偏好来猜测
/// “刚才是否验证过”。这能阻止设置同步/生命周期 await 造成伪授权复活。
nonisolated enum RevealAuthenticationEvidence: Equatable, Sendable {
    case verified
    case notRequired
}

/// 详情页已验证查看后的一次性复用凭证。
/// 调用方只能原样传回 `KeyVaultServing`，不能从中取出明文或会话信息。
nonisolated struct SecretRevealReuseToken: Hashable, Sendable {
    private let id: UUID

    private init(id: UUID) {
        self.id = id
    }

    /// 只允许密钥库实现与测试替身发行；UI MUST NOT 主动创建。
    static func issueForVault() -> SecretRevealReuseToken {
        SecretRevealReuseToken(id: UUID())
    }

    #if DEBUG
    /// 仅用于证明服务端会拒绝未发行的伪 token。
    static func unissuedForTesting() -> SecretRevealReuseToken {
        SecretRevealReuseToken(id: UUID())
    }
    #endif
}

nonisolated struct SecretRevealResult: Equatable, Sendable {
    let secret: String
    let authentication: RevealAuthenticationEvidence
    /// 只有本次查看确实完成身份验证才会发行。
    let reuseToken: SecretRevealReuseToken?

    init(
        secret: String,
        authentication: RevealAuthenticationEvidence,
        reuseToken: SecretRevealReuseToken? = nil
    ) {
        self.secret = secret
        self.authentication = authentication
        self.reuseToken = authentication == .verified ? reuseToken : nil
    }
}

/// 密钥保管与分发（US1）。UI MUST NOT 直接访问 Keychain。
protocol KeyVaultServing: Actor {
    func accounts() async throws -> [UpstreamAccountDTO]
    func keys(in accountId: UUID?) async throws -> [KeyRecordDTO]
    func createAccount(_ draft: UpstreamAccountDraft) async throws -> UUID
    /// 更新上游账号（平台 / 显示名 / 自定义 Base URL）。
    func updateAccount(_ id: UUID, patch: UpstreamAccountPatch, appPassword: String?) async throws
    func deleteAccount(_ id: UUID, appPassword: String?) async throws

    /// 同账号下本机 Keychain 明文完全相同则抛 `possible_duplicate`；该比对 MUST NOT 走门闩。
    func createKey(_ draft: KeyDraft, secret: String, acknowledgePossibleDuplicate: Bool) async throws -> UUID
    func updateKey(_ id: UUID, patch: KeyPatch, appPassword: String?) async throws
    /// 编辑已有密钥：名称、可选换密文、备注、所属上游账号的平台与显示名。
    /// 换密文时不触发取出明文；敏感字段走当前验证方式。留空 `draft.secret` 则不碰 Keychain。
    func editKey(_ id: UUID, draft: KeyEditDraft, appPassword: String?) async throws
    func deleteKey(_ id: UUID, appPassword: String?) async throws
    /// 按用户拖拽结果重写分区内密钥顺序（`orderedIds` 为从上到下）。
    func reorderKeys(orderedIds: [UUID]) async throws
    /// 按用户拖拽结果重写上游账号分区顺序（`orderedIds` 为从上到下）。不改 `updatedAt`。
    func reorderAccounts(orderedIds: [UUID]) async throws

    func recentlyDeletedKeys() async throws -> [KeyRecordDTO]
    func restoreKey(_ id: UUID, appPassword: String?) async throws
    func permanentlyDeleteKey(_ id: UUID, appPassword: String?) async throws
    func purgeExpiredDeletedKeys() async throws

    func recentlyDeletedAccounts() async throws -> [UpstreamAccountDTO]
    func restoreAccount(_ id: UUID, appPassword: String?) async throws
    func permanentlyDeleteAccount(_ id: UUID, appPassword: String?) async throws
    func purgeExpiredDeletedAccounts() async throws

    func addAssignment(keyId: UUID, consumerToolId: UUID) async throws
    func removeAssignment(keyId: UUID, consumerToolId: UUID) async throws
    func assignmentKind(keyId: UUID) async throws -> AssignmentKind

    /// `masterPassword` 仅在 revealPolicy == .masterPassword 时需要。
    /// 返回值携带同一份偏好快照下产生的验证证据；UI MUST NOT 再读偏好推断。
    func revealSecretWithEvidence(
        keyId: UUID,
        purpose: RevealPurpose,
        masterPassword: String?
    ) async throws -> SecretRevealResult
    func copySecretToClipboard(keyId: UUID, masterPassword: String?) async throws
    /// 消费已验证查看发行的一次性 token，重新从 Keychain 读取并写剪贴板。
    /// MUST NOT 接受 UI 传入的明文，MUST NOT 再走门闩。
    func copyRevealedSecretToClipboard(
        keyId: UUID,
        token: SecretRevealReuseToken
    ) async throws

    func remainingFreeQuota() async throws -> Int?

    /// 启动巡检：过期回收站清除、末四位纠偏、同业务 id 重复行卫生清扫。
    /// 各步 best-effort，失败不抛给首页。
    func performStartupMaintenance() async throws
    /// CloudKit 导入成功后的身份清扫（账号 / 密钥；不含安全偏好物理删除）。
    /// 各类型独立捕获，失败不抛。
    func pruneDuplicateIdentities() async throws

    /// FR-061：物理删除本服务持有的账号 / 密钥 / 指派 / 安全偏好（含回收站）。
    func purgeAllRecordsForErase(authorization: SessionAuthorizationLease) async throws
    /// 仅供已经在线性化起点完成身份授权并写入持久 journal 的全量清除事务调用。
    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws
    /// 批量恢复前先算额度。超出则整批拒绝，且 MUST 在门闩之前调用。
    func preflightRestoreQuota(keyIds: [UUID], accountIds: [UUID]) async throws
    /// 调用方 MUST 已按当前验证方式完成确认，并传入认证前捕获的同一会话租约。
    func restoreDeletedAfterAuthentication(
        keyIds: [UUID],
        accountIds: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome
    /// 调用方 MUST 已按当前验证方式完成确认，并传入认证前捕获的同一会话租约。
    func permanentlyDeleteDeletedAfterAuthentication(
        keyIds: [UUID],
        accountIds: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome

    /// 当前同步偏好里的验证方式。批量操作用来按当前档只验一次。
    func currentRevealPolicy() async throws -> RevealPolicy
}

/// 后台自动化读取是独立能力，不能随用户界面使用的完整密钥库协议一起注入 UI。
/// 当前 V1 没有生产调用方；V2 消费方必须显式依赖这个窄协议。
protocol AutomatedSecretReading: Actor {
    func readSecretForAutomatedUse(
        keyId: UUID,
        purpose: AutomatedSecretPurpose
    ) async throws -> String
}

extension KeyVaultServing {
    func createKey(_ draft: KeyDraft, secret: String) async throws -> UUID {
        try await createKey(draft, secret: secret, acknowledgePossibleDuplicate: false)
    }

    func revealSecret(
        keyId: UUID,
        purpose: RevealPurpose,
        masterPassword: String?
    ) async throws -> String {
        try await revealSecretWithEvidence(
            keyId: keyId,
            purpose: purpose,
            masterPassword: masterPassword
        ).secret
    }

    func revealSecret(keyId: UUID, purpose: RevealPurpose) async throws -> String {
        try await revealSecret(keyId: keyId, purpose: purpose, masterPassword: nil)
    }

    func copySecretToClipboard(keyId: UUID) async throws {
        try await copySecretToClipboard(keyId: keyId, masterPassword: nil)
    }

    func updateAccount(_ id: UUID, patch: UpstreamAccountPatch) async throws {
        try await updateAccount(id, patch: patch, appPassword: nil)
    }

    func deleteAccount(_ id: UUID) async throws {
        try await deleteAccount(id, appPassword: nil)
    }

    func updateKey(_ id: UUID, patch: KeyPatch) async throws {
        try await updateKey(id, patch: patch, appPassword: nil)
    }

    func editKey(_ id: UUID, draft: KeyEditDraft) async throws {
        try await editKey(id, draft: draft, appPassword: nil)
    }

    func deleteKey(_ id: UUID) async throws {
        try await deleteKey(id, appPassword: nil)
    }

    func restoreKey(_ id: UUID) async throws {
        try await restoreKey(id, appPassword: nil)
    }

    func permanentlyDeleteKey(_ id: UUID) async throws {
        try await permanentlyDeleteKey(id, appPassword: nil)
    }

    func restoreAccount(_ id: UUID) async throws {
        try await restoreAccount(id, appPassword: nil)
    }

    func permanentlyDeleteAccount(_ id: UUID) async throws {
        try await permanentlyDeleteAccount(id, appPassword: nil)
    }
}
