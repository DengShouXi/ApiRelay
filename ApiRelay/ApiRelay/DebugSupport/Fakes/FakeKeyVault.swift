#if DEBUG
import Foundation

/// 假密钥库：内存账号 / 密钥 / 明文 / 指派。不碰 Keychain / SwiftData / 门闩。
actor FakeKeyVault: KeyVaultServing {
    var journal = FakeJournal()

    /// `nil` = 不限额（等同付费档）。
    var freeQuotaRemaining: Int? = nil

    private var accountsById: [UUID: UpstreamAccountDTO] = [:]
    private var keysById: [UUID: KeyRecordDTO] = [:]
    private var secrets: [UUID: String] = [:]

    /// Preview 用：预置一个账号 + 一把密钥（明文假值，仅内存）。
    init(seedPreviewSample: Bool = false) {
        guard seedPreviewSample else { return }
        let accountId = UUID()
        accountsById[accountId] = .fake(
            id: accountId,
            platform: "openai",
            displayName: "Preview OpenAI"
        )
        let keyId = UUID()
        keysById[keyId] = .fake(
            id: keyId,
            accountId: accountId,
            displayName: "Preview Key",
            secretAvailable: true
        )
        secrets[keyId] = "sk-preview-not-a-real-key"
    }

    // MARK: - Accounts

    func accounts() async throws -> [UpstreamAccountDTO] {
        try journal.record("accounts")
        return accountsById.values
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func keys(in accountId: UUID?) async throws -> [KeyRecordDTO] {
        try journal.record("keys")
        return keysById.values
            .filter { $0.deletedAt == nil }
            .filter { accountId == nil || $0.accountId == accountId }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func createAccount(_ draft: UpstreamAccountDraft) async throws -> UUID {
        try journal.record("createAccount")
        let id = UUID()
        let now = Date()
        accountsById[id] = UpstreamAccountDTO(
            id: id,
            platform: draft.platform,
            customPlatformName: draft.customPlatformName,
            displayName: draft.displayName,
            customBaseURL: draft.customBaseURL,
            hasManagementCredential: false,
            notes: draft.notes,
            createdAt: now,
            updatedAt: now,
            sortOrder: draft.sortOrder,
            deletedAt: nil,
            purgeAfter: nil,
            avatarSymbol: draft.avatarSymbol,
            avatarColor: draft.avatarColor
        )
        return id
    }

    func updateAccount(_ id: UUID, patch: UpstreamAccountPatch) async throws {
        try journal.record("updateAccount")
        guard let account = accountsById[id], account.deletedAt == nil else {
            throw ApiRelayError.validationFailed(field: "account", reason: "not_found")
        }
        accountsById[id] = UpstreamAccountDTO(
            id: account.id,
            platform: patch.platform ?? account.platform,
            customPlatformName: patch.customPlatformName ?? account.customPlatformName,
            displayName: patch.displayName ?? account.displayName,
            customBaseURL: patch.customBaseURL ?? account.customBaseURL,
            hasManagementCredential: patch.hasManagementCredential ?? account.hasManagementCredential,
            notes: patch.notes ?? account.notes,
            createdAt: account.createdAt,
            updatedAt: Date(),
            sortOrder: patch.sortOrder ?? account.sortOrder,
            deletedAt: account.deletedAt,
            purgeAfter: account.purgeAfter,
            avatarSymbol: patch.updatesAvatar ? patch.avatarSymbol : account.avatarSymbol,
            avatarColor: patch.updatesAvatar ? patch.avatarColor : account.avatarColor
        )
    }

    func deleteAccount(_ id: UUID) async throws {
        try journal.record("deleteAccount")
        guard softDeleteAccount(id) else {
            throw ApiRelayError.validationFailed(field: "account", reason: "not_found")
        }
    }

    // MARK: - Keys

    func createKey(
        _ draft: KeyDraft,
        secret: String,
        acknowledgePossibleDuplicate: Bool
    ) async throws -> UUID {
        try journal.record("createKey")
        if !acknowledgePossibleDuplicate {
            for (existingId, existingSecret) in secrets {
                guard let key = keysById[existingId],
                      key.deletedAt == nil,
                      key.accountId == draft.accountId,
                      existingSecret == secret else { continue }
                throw ApiRelayError.validationFailed(field: "secret", reason: "possible_duplicate")
            }
        }
        let id = UUID()
        keysById[id] = KeyRecordDTO.fake(
            id: id,
            accountId: draft.accountId,
            displayName: draft.displayName,
            lifecycle: .active,
            secretAvailable: true,
            sortOrder: draft.sortOrder
        ).with(
            spendLimit: draft.spendLimit,
            notes: draft.notes,
            origin: draft.origin,
            providerKeyRef: draft.providerKeyRef,
            avatarSymbol: draft.avatarSymbol,
            avatarColor: draft.avatarColor
        )
        secrets[id] = secret
        return id
    }

    func updateKey(_ id: UUID, patch: KeyPatch) async throws {
        try journal.record("updateKey")
        guard let key = keysById[id], key.deletedAt == nil else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
        keysById[id] = key.with(
            displayName: patch.displayName,
            lifecycle: patch.lifecycle,
            spendLimit: patch.spendLimit,
            notes: patch.notes,
            deletedAt: patch.deletedAt,
            purgeAfter: patch.purgeAfter,
            sortOrder: patch.sortOrder,
            healthState: patch.healthState,
            lastCheckedAt: patch.lastCheckedAt,
            lastCheckNote: patch.lastCheckNote,
            avatarSymbol: patch.updatesAvatar ? patch.avatarSymbol : nil,
            avatarColor: patch.updatesAvatar ? patch.avatarColor : nil,
            forceAvatar: patch.updatesAvatar
        )
    }

    func editKey(_ id: UUID, draft: KeyEditDraft) async throws {
        try journal.record("editKey")
        guard let key = keysById[id], key.deletedAt == nil else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
        if let raw = draft.secret?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if !draft.acknowledgePossibleDuplicate {
                for (existingId, existingSecret) in secrets {
                    guard existingId != id,
                          let other = keysById[existingId],
                          other.deletedAt == nil,
                          other.accountId == key.accountId,
                          existingSecret == raw else { continue }
                    throw ApiRelayError.validationFailed(field: "secret", reason: "possible_duplicate")
                }
            }
            secrets[id] = raw
        }
        keysById[id] = key.with(
            displayName: draft.displayName,
            notes: draft.notes,
            avatarSymbol: draft.avatarSymbol,
            avatarColor: draft.avatarColor,
            forceAvatar: true
        )
        if var account = accountsById[key.accountId] {
            account = UpstreamAccountDTO(
                id: account.id,
                platform: draft.platform,
                customPlatformName: draft.customPlatformName,
                displayName: draft.accountDisplayName,
                customBaseURL: draft.customBaseURL ?? account.customBaseURL,
                hasManagementCredential: account.hasManagementCredential,
                notes: account.notes,
                createdAt: account.createdAt,
                updatedAt: Date(),
                sortOrder: account.sortOrder,
                deletedAt: account.deletedAt,
                purgeAfter: account.purgeAfter,
                avatarSymbol: account.avatarSymbol,
                avatarColor: account.avatarColor
            )
            accountsById[key.accountId] = account
        }
    }

    func deleteKey(_ id: UUID) async throws {
        try journal.record("deleteKey")
        guard softDeleteKey(id) else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
    }

    func reorderKeys(orderedIds: [UUID]) async throws {
        try journal.record("reorderKeys")
        for (index, id) in orderedIds.enumerated() {
            guard let key = keysById[id] else { continue }
            keysById[id] = key.with(sortOrder: index)
        }
    }

    func reorderAccounts(orderedIds: [UUID]) async throws {
        try journal.record("reorderAccounts")
        for (index, id) in orderedIds.enumerated() {
            guard let account = accountsById[id] else { continue }
            accountsById[id] = UpstreamAccountDTO(
                id: account.id,
                platform: account.platform,
                customPlatformName: account.customPlatformName,
                displayName: account.displayName,
                customBaseURL: account.customBaseURL,
                hasManagementCredential: account.hasManagementCredential,
                notes: account.notes,
                createdAt: account.createdAt,
                updatedAt: account.updatedAt,
                sortOrder: index,
                deletedAt: account.deletedAt,
                purgeAfter: account.purgeAfter,
                avatarSymbol: account.avatarSymbol,
                avatarColor: account.avatarColor
            )
        }
    }

    // MARK: - Trash (keys)

    func recentlyDeletedKeys() async throws -> [KeyRecordDTO] {
        try journal.record("recentlyDeletedKeys")
        return keysById.values
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    func restoreKey(_ id: UUID) async throws {
        try journal.record("restoreKey")
        guard restoreOneKey(id) else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
    }

    func permanentlyDeleteKey(_ id: UUID) async throws {
        try journal.record("permanentlyDeleteKey")
        keysById[id] = nil
        secrets[id] = nil
    }

    func purgeExpiredDeletedKeys() async throws {
        try journal.record("purgeExpiredDeletedKeys")
        let now = Date()
        for (id, key) in keysById {
            if let purge = key.purgeAfter, purge <= now {
                keysById[id] = nil
                secrets[id] = nil
            }
        }
    }

    // MARK: - Trash (accounts)

    func recentlyDeletedAccounts() async throws -> [UpstreamAccountDTO] {
        try journal.record("recentlyDeletedAccounts")
        return accountsById.values
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    func restoreAccount(_ id: UUID) async throws {
        try journal.record("restoreAccount")
        guard restoreOneAccount(id) else {
            throw ApiRelayError.validationFailed(field: "account", reason: "not_found")
        }
    }

    func permanentlyDeleteAccount(_ id: UUID) async throws {
        try journal.record("permanentlyDeleteAccount")
        accountsById[id] = nil
        let orphanKeys = keysById.filter { $0.value.accountId == id }.map(\.key)
        for keyId in orphanKeys {
            keysById[keyId] = nil
            secrets[keyId] = nil
        }
    }

    func purgeExpiredDeletedAccounts() async throws {
        try journal.record("purgeExpiredDeletedAccounts")
        let now = Date()
        for (id, account) in accountsById {
            if let purge = account.purgeAfter, purge <= now {
                accountsById[id] = nil
            }
        }
    }

    // MARK: - Assignments

    func addAssignment(keyId: UUID, consumerToolId: UUID) async throws {
        try journal.record("addAssignment")
        guard let key = keysById[keyId], key.deletedAt == nil else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
        var ids = key.consumerToolIds
        if !ids.contains(consumerToolId) {
            ids.append(consumerToolId)
        }
        keysById[keyId] = key.with(consumerToolIds: ids)
    }

    func removeAssignment(keyId: UUID, consumerToolId: UUID) async throws {
        try journal.record("removeAssignment")
        guard let key = keysById[keyId] else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
        keysById[keyId] = key.with(consumerToolIds: key.consumerToolIds.filter { $0 != consumerToolId })
    }

    func assignmentKind(keyId: UUID) async throws -> AssignmentKind {
        try journal.record("assignmentKind")
        guard let key = keysById[keyId] else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
        switch key.consumerToolIds.count {
        case 0: return .unassigned
        case 1: return .exclusive(key.consumerToolIds[0])
        default: return .shared(key.consumerToolIds)
        }
    }

    // MARK: - Secrets

    func revealSecret(keyId: UUID, purpose: RevealPurpose, masterPassword: String?) async throws -> String {
        _ = purpose
        _ = masterPassword
        try journal.record("revealSecret")
        guard keysById[keyId]?.deletedAt == nil else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
        guard let secret = secrets[keyId] else {
            throw ApiRelayError.secretMissingOnDevice
        }
        return secret
    }

    func copySecretToClipboard(keyId: UUID, masterPassword: String?) async throws {
        _ = masterPassword
        try journal.record("copySecretToClipboard")
        guard keysById[keyId]?.deletedAt == nil else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
        guard secrets[keyId] != nil else {
            throw ApiRelayError.secretMissingOnDevice
        }
    }

    func copyRevealedSecretToClipboard(_ secret: String) async throws {
        _ = secret
        try journal.record("copyRevealedSecretToClipboard")
    }

    func remainingFreeQuota() async throws -> Int? {
        try journal.record("remainingFreeQuota")
        return freeQuotaRemaining
    }

    func readSecretForAutomatedUse(keyId: UUID, purpose: AutomatedSecretPurpose) async throws -> String {
        _ = purpose
        try journal.record("readSecretForAutomatedUse")
        guard keysById[keyId]?.deletedAt == nil else {
            throw ApiRelayError.validationFailed(field: "key", reason: "not_found")
        }
        guard let secret = secrets[keyId] else {
            throw ApiRelayError.secretMissingOnDevice
        }
        return secret
    }

    func performStartupMaintenance() async throws {
        try journal.record("performStartupMaintenance")
        try await purgeExpiredDeletedKeys()
        try await purgeExpiredDeletedAccounts()
    }

    func pruneDuplicateIdentities() async throws {
        try journal.record("pruneDuplicateIdentities")
    }

    func purgeAllRecordsForErase() async throws {
        try journal.record("purgeAllRecordsForErase")
        accountsById.removeAll()
        keysById.removeAll()
        secrets.removeAll()
    }

    func preflightRestoreQuota(keyIds: [UUID], accountIds: [UUID]) async throws {
        try journal.record("preflightRestoreQuota")
        guard let remaining = freeQuotaRemaining else { return }
        var wouldActivate = Set<UUID>()
        for id in keyIds where keysById[id]?.deletedAt != nil {
            wouldActivate.insert(id)
        }
        for accountId in accountIds {
            for (keyId, key) in keysById where key.accountId == accountId && key.deletedAt != nil {
                wouldActivate.insert(keyId)
            }
        }
        if wouldActivate.count > remaining {
            throw ApiRelayError.quotaExceededFreeTier(limit: remaining)
        }
    }

    func restoreDeletedAfterAuthentication(keyIds: [UUID], accountIds: [UUID]) async -> TrashBatchOutcome {
        journal.recordNonThrowing("restoreDeletedAfterAuthentication")
        var success = 0
        var failures: [TrashBatchItemFailure] = []
        for id in accountIds {
            if restoreOneAccount(id) { success += 1 }
            else { failures.append(TrashBatchItemFailure(name: id.uuidString, detail: "restore_failed")) }
        }
        for id in keyIds {
            if restoreOneKey(id) { success += 1 }
            else { failures.append(TrashBatchItemFailure(name: id.uuidString, detail: "restore_failed")) }
        }
        return TrashBatchOutcome(successCount: success, failures: failures)
    }

    func permanentlyDeleteDeletedAfterAuthentication(
        keyIds: [UUID],
        accountIds: [UUID]
    ) async -> TrashBatchOutcome {
        journal.recordNonThrowing("permanentlyDeleteDeletedAfterAuthentication")
        var success = 0
        for id in accountIds where accountsById[id] != nil {
            accountsById[id] = nil
            success += 1
        }
        for id in keyIds where keysById[id] != nil {
            keysById[id] = nil
            secrets[id] = nil
            success += 1
        }
        return TrashBatchOutcome(successCount: success, failures: [])
    }

    // MARK: - Private

    @discardableResult
    private func softDeleteKey(_ id: UUID) -> Bool {
        guard let key = keysById[id], key.deletedAt == nil else { return false }
        let now = Date()
        keysById[id] = key.with(
            lifecycle: .softDeleted,
            deletedAt: now,
            purgeAfter: now.addingTimeInterval(30 * 24 * 3600)
        )
        return true
    }

    @discardableResult
    private func softDeleteAccount(_ id: UUID) -> Bool {
        guard let account = accountsById[id], account.deletedAt == nil else { return false }
        let now = Date()
        accountsById[id] = UpstreamAccountDTO(
            id: account.id,
            platform: account.platform,
            customPlatformName: account.customPlatformName,
            displayName: account.displayName,
            customBaseURL: account.customBaseURL,
            hasManagementCredential: account.hasManagementCredential,
            notes: account.notes,
            createdAt: account.createdAt,
            updatedAt: now,
            sortOrder: account.sortOrder,
            deletedAt: now,
            purgeAfter: now.addingTimeInterval(30 * 24 * 3600),
            avatarSymbol: account.avatarSymbol,
            avatarColor: account.avatarColor
        )
        for (keyId, key) in keysById where key.accountId == id && key.deletedAt == nil {
            _ = softDeleteKey(keyId)
        }
        return true
    }

    @discardableResult
    private func restoreOneKey(_ id: UUID) -> Bool {
        guard let key = keysById[id], key.deletedAt != nil else { return false }
        keysById[id] = key.with(lifecycle: .active, deletedAt: nil as Date?, purgeAfter: nil as Date?, clearTrash: true)
        return true
    }

    @discardableResult
    private func restoreOneAccount(_ id: UUID) -> Bool {
        guard let account = accountsById[id], account.deletedAt != nil else { return false }
        accountsById[id] = UpstreamAccountDTO(
            id: account.id,
            platform: account.platform,
            customPlatformName: account.customPlatformName,
            displayName: account.displayName,
            customBaseURL: account.customBaseURL,
            hasManagementCredential: account.hasManagementCredential,
            notes: account.notes,
            createdAt: account.createdAt,
            updatedAt: Date(),
            sortOrder: account.sortOrder,
            deletedAt: nil,
            purgeAfter: nil,
            avatarSymbol: account.avatarSymbol,
            avatarColor: account.avatarColor
        )
        for (keyId, key) in keysById where key.accountId == id && key.deletedAt != nil {
            _ = restoreOneKey(keyId)
        }
        return true
    }
}

private extension KeyRecordDTO {
    nonisolated func with(
        consumerToolIds: [UUID]? = nil,
        displayName: String? = nil,
        lifecycle: KeyLifecycle? = nil,
        spendLimit: Decimal? = nil,
        notes: String? = nil,
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil,
        sortOrder: Int? = nil,
        healthState: KeyHealthState? = nil,
        lastCheckedAt: Date? = nil,
        lastCheckNote: String? = nil,
        origin: KeyOrigin? = nil,
        providerKeyRef: String? = nil,
        avatarSymbol: String? = nil,
        avatarColor: String? = nil,
        forceAvatar: Bool = false,
        clearTrash: Bool = false
    ) -> KeyRecordDTO {
        KeyRecordDTO(
            id: id,
            accountId: accountId,
            consumerToolIds: consumerToolIds ?? self.consumerToolIds,
            displayName: displayName ?? self.displayName,
            maskedHint: maskedHint,
            origin: origin ?? self.origin,
            providerKeyRef: providerKeyRef ?? self.providerKeyRef,
            lifecycle: lifecycle ?? self.lifecycle,
            health: KeyHealthDTO(
                state: healthState ?? health.state,
                lastCheckedAt: lastCheckedAt ?? health.lastCheckedAt,
                lastCheckNote: lastCheckNote ?? health.lastCheckNote
            ),
            deletedAt: clearTrash ? nil : (deletedAt ?? self.deletedAt),
            purgeAfter: clearTrash ? nil : (purgeAfter ?? self.purgeAfter),
            spendLimit: spendLimit ?? self.spendLimit,
            notes: notes ?? self.notes,
            secretAvailable: secretAvailable,
            sortOrder: sortOrder ?? self.sortOrder,
            avatarSymbol: forceAvatar ? avatarSymbol : (avatarSymbol ?? self.avatarSymbol),
            avatarColor: forceAvatar ? avatarColor : (avatarColor ?? self.avatarColor)
        )
    }
}
#endif
