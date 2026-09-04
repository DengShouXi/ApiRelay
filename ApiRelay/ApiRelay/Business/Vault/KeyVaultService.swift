import Foundation
import SwiftData
import Security

actor KeyVaultService: KeyVaultServing {
    static let freeTierLimit = 3

    private let keychain: KeychainStoring
    private let gate: RevealGateServing
    private let clipboard: ClipboardServing
    private let accountsRepo: UpstreamAccountRepository
    private let keysRepo: APIKeyRecordRepository
    private let assignmentsRepo: KeyAssignmentRepository
    private let userPrefsRepo: UserPreferencesRepository
    private let entitlements: EntitlementServing

    init(
        keychain: KeychainStoring,
        gate: RevealGateServing,
        clipboard: ClipboardServing,
        modelContainer: ModelContainer,
        entitlements: EntitlementServing
    ) {
        self.keychain = keychain
        self.gate = gate
        self.clipboard = clipboard
        self.accountsRepo = UpstreamAccountRepository(modelContainer: modelContainer)
        self.keysRepo = APIKeyRecordRepository(modelContainer: modelContainer)
        self.assignmentsRepo = KeyAssignmentRepository(modelContainer: modelContainer)
        self.userPrefsRepo = UserPreferencesRepository(modelContainer: modelContainer)
        self.entitlements = entitlements
    }

    func accounts() async throws -> [UpstreamAccountDTO] {
        try await accountsRepo.fetchAll()
    }

    func keys(in accountId: UUID?) async throws -> [KeyRecordDTO] {
        let records = try await keysRepo.fetch(
            accountId: accountId,
            lifecycles: [.active, .revokedUpstream]
        )
        return try await withSecretAvailability(records)
    }

    func createAccount(_ draft: UpstreamAccountDraft) async throws -> UUID {
        try await accountsRepo.insert(draft)
    }

    func updateAccount(_ id: UUID, patch: UpstreamAccountPatch) async throws {
        guard try await accountsRepo.fetch(id: id) != nil else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        if let platform = patch.platform?.trimmingCharacters(in: .whitespacesAndNewlines), platform.isEmpty {
            throw ApiRelayError.validationFailed(field: "platform", reason: "required")
        }
        if let name = patch.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), name.isEmpty {
            throw ApiRelayError.validationFailed(field: "displayName", reason: "required_1_to_64")
        }
        try await accountsRepo.update(id: id, patch: patch)
    }

    func deleteAccount(_ id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.deleteAccount"))
        let related = try await keysRepo.fetch(accountId: id, lifecycles: [.active, .revokedUpstream])
        for key in related {
            try await softDeleteKeyMetadata(key.id)
        }
        try await accountsRepo.softDelete(id: id, retainDays: 30)
    }

    func createKey(
        _ draft: KeyDraft,
        secret: String,
        acknowledgePossibleDuplicate: Bool
    ) async throws -> UUID {
        let normalized = try Self.normalizeSecret(secret)
        if let remaining = try await remainingFreeQuota(), remaining <= 0 {
            throw ApiRelayError.quotaExceededFreeTier(limit: Self.freeTierLimit)
        }

        if !acknowledgePossibleDuplicate,
           let dupId = try await existingKeyId(
            matching: normalized,
            accountId: draft.accountId
           ) {
            throw ApiRelayError.validationFailed(
                field: "secret",
                reason: "possible_duplicate:\(dupId.uuidString)"
            )
        }

        var draft = draft
        draft.maskedHint = nil
        draft.secretLength = nil
        draft.origin = .manualEntry

        let id = try await keysRepo.insert(draft)
        do {
            try await keychain.save(normalized, service: .keys, account: id)
        } catch {
            try? await keysRepo.delete(id: id)
            throw error
        }
        return id
    }

    func updateKey(_ id: UUID, patch: KeyPatch) async throws {
        try await keysRepo.update(id: id, patch: patch)
    }

    func editKey(_ id: UUID, draft: KeyEditDraft) async throws {
        guard let key = try await keysRepo.fetch(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        if key.lifecycle == .softDeleted {
            throw ApiRelayError.validationFailed(field: "id", reason: "in_recycle_bin")
        }
        guard try await accountsRepo.fetch(id: key.accountId) != nil else {
            throw ApiRelayError.validationFailed(field: "accountId", reason: "not_found")
        }

        let trimmedKeyName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyName.isEmpty else {
            throw ApiRelayError.validationFailed(field: "displayName", reason: "required_1_to_64")
        }
        let trimmedAccountName = draft.accountDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountName.isEmpty else {
            throw ApiRelayError.validationFailed(field: "accountDisplayName", reason: "required_1_to_64")
        }
        let platform = draft.platform.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !platform.isEmpty else {
            throw ApiRelayError.validationFailed(field: "platform", reason: "required")
        }

        var keyPatch = KeyPatch(displayName: trimmedKeyName)
        if let notes = draft.notes {
            keyPatch.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        keyPatch.updatesAvatar = true
        keyPatch.avatarSymbol = draft.avatarSymbol
        keyPatch.avatarColor = draft.avatarColor
        if let rawSecret = draft.secret {
            let trimmedSecret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSecret.isEmpty {
                let normalized = try Self.normalizeSecret(trimmedSecret)
                if !draft.acknowledgePossibleDuplicate,
                   let dupId = try await existingKeyId(
                    matching: normalized,
                    accountId: key.accountId,
                    excludingId: id
                   ) {
                    throw ApiRelayError.validationFailed(
                        field: "secret",
                        reason: "possible_duplicate:\(dupId.uuidString)"
                    )
                }
                try await keychain.save(normalized, service: .keys, account: id)
            }
        }
        try await keysRepo.update(id: id, patch: keyPatch)

        let isCustom = platform == PresetCatalog.customPlatformID
        let trimmedCustom = draft.customPlatformName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isCustom, trimmedCustom.isEmpty {
            throw ApiRelayError.validationFailed(field: "customPlatformName", reason: "required")
        }
        let accountPatch = UpstreamAccountPatch(
            platform: platform,
            customPlatformName: isCustom ? trimmedCustom : "",
            displayName: trimmedAccountName,
            customBaseURL: isCustom ? (draft.customBaseURL ?? "") : ""
        )
        try await accountsRepo.update(id: key.accountId, patch: accountPatch)
    }

    func reorderKeys(orderedIds: [UUID]) async throws {
        try await keysRepo.reorder(orderedIds: orderedIds)
    }

    func reorderAccounts(orderedIds: [UUID]) async throws {
        try await accountsRepo.reorder(orderedIds: orderedIds)
    }

    func deleteKey(_ id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.deleteKey"))
        try await softDeleteKeyMetadata(id)
    }

    func recentlyDeletedKeys() async throws -> [KeyRecordDTO] {
        // 回收站只展示元数据；禁止在此读 Keychain（同步钥匙串会卡住，导致 sheet 一直空白）。
        try await keysRepo.fetchSoftDeleted()
    }

    func restoreKey(_ id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.restoreKey"))
        if let remaining = try await remainingFreeQuota(), remaining <= 0 {
            throw ApiRelayError.quotaExceededFreeTier(limit: Self.freeTierLimit)
        }
        _ = try await restoreKeyAfterAuth(id, requirePresent: true)
    }

    func permanentlyDeleteKey(_ id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.permanentDelete"))
        _ = try await permanentlyDeleteKeyAfterAuth(id)
    }

    func purgeExpiredDeletedKeys() async throws {
        let deleted = try await keysRepo.fetch(lifecycles: [.softDeleted])
        let now = Date()
        for key in deleted where (key.purgeAfter ?? .distantFuture) < now {
            try await destroyKey(key.id)
        }
    }

    func recentlyDeletedAccounts() async throws -> [UpstreamAccountDTO] {
        try await accountsRepo.fetchSoftDeleted()
    }

    func restoreAccount(_ id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.restoreAccount"))
        _ = try await restoreAccountAfterAuth(id, requirePresent: true)
    }

    func permanentlyDeleteAccount(_ id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.permanentDelete"))
        _ = try await permanentlyDeleteAccountAfterAuth(id)
    }

    func purgeExpiredDeletedAccounts() async throws {
        let deleted = try await accountsRepo.fetchSoftDeleted()
        let now = Date()
        for account in deleted where (account.purgeAfter ?? .distantFuture) < now {
            let allKeys = try await keysRepo.fetch(accountId: account.id, lifecycles: nil)
            for key in allKeys {
                try await destroyKey(key.id)
            }
            try await accountsRepo.delete(id: account.id)
        }
    }

    func addAssignment(keyId: UUID, consumerToolId: UUID) async throws {
        try await assignmentsRepo.add(keyId: keyId, consumerToolId: consumerToolId)
    }

    func removeAssignment(keyId: UUID, consumerToolId: UUID) async throws {
        try await assignmentsRepo.remove(keyId: keyId, consumerToolId: consumerToolId)
    }

    func assignmentKind(keyId: UUID) async throws -> AssignmentKind {
        try await assignmentsRepo.assignmentKind(keyId: keyId)
    }

    func revealSecret(
        keyId: UUID,
        purpose: RevealPurpose,
        masterPassword: String?
    ) async throws -> String {
        _ = purpose
        try await ensureActiveForReveal(keyId)
        try await runGate(masterPassword: masterPassword)
        do {
            return try await keychain.read(service: .keys, account: keyId)
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            throw ApiRelayError.secretMissingOnDevice
        }
    }

    func copySecretToClipboard(keyId: UUID, masterPassword: String?) async throws {
        try await ensureActiveForReveal(keyId)
        try await runGate(masterPassword: masterPassword)
        let secret: String
        do {
            secret = try await keychain.read(service: .keys, account: keyId)
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            throw ApiRelayError.secretMissingOnDevice
        }
        try await writeSecretToClipboard(secret)
    }

    /// 将已通过门闩取出的明文写入剪贴板。MUST NOT 再走门闩。
    func copyRevealedSecretToClipboard(_ secret: String) async throws {
        try await writeSecretToClipboard(secret)
    }

    private func writeSecretToClipboard(_ secret: String) async throws {
        let prefs = try await userPrefsRepo.loadOrCreate()
        try await clipboard.write(
            secret,
            expiresAfter: TimeInterval(prefs.clipboardClearSeconds),
            localOnly: prefs.clipboardLocalOnly
        )
    }

    func remainingFreeQuota() async throws -> Int? {
        // 必须走 EntitlementServing（含 StoreKit 纠偏），禁止只读可能脏的本地 snapshot。
        let tier = try await entitlements.currentTier()
        if tier != .free { return nil }
        let count = try await keysRepo.countActiveNonDeleted()
        return max(0, Self.freeTierLimit - count)
    }

    func readSecretForAutomatedUse(
        keyId: UUID,
        purpose: AutomatedSecretPurpose
    ) async throws -> String {
        _ = purpose
        try await ensureActiveForReveal(keyId)
        return try await keychain.read(service: .keys, account: keyId)
    }

    func performStartupMaintenance() async throws {
        try await purgeExpiredDeletedKeys()
        try await purgeExpiredDeletedAccounts()
        try await keysRepo.clearStoredSecretFragments()
    }

    /// FR-061：物理删除本服务 ModelActor 里的账号 / 密钥 / 指派 / 安全偏好（含回收站）。
    /// 必须走这些已有仓库，另开 ModelContext 删除后主列表仍会读到旧对象。
    func purgeAllRecordsForErase() async throws {
        try await assignmentsRepo.deleteAllRecords()
        try await keysRepo.deleteAllRecords()
        try await accountsRepo.deleteAllRecords()
        try await userPrefsRepo.deleteAllRecords()
    }

    private func runGate(masterPassword: String?) async throws {
        let prefs = try await userPrefsRepo.loadOrCreate()
        switch prefs.revealPolicy {
        case .masterPassword:
            try await gate.ensureMasterPasswordConfigured()
            guard let masterPassword else {
                throw ApiRelayError.validationFailed(field: "masterPassword", reason: "required")
            }
            try await gate.confirmWithMasterPassword(
                reason: String(localized: "gate.reveal"),
                password: masterPassword
            )
        default:
            try await gate.confirm(
                reason: String(localized: "gate.reveal"),
                policy: prefs.revealPolicy
            )
        }
    }

    private func ensureActiveForReveal(_ keyId: UUID) async throws {
        guard let key = try await keysRepo.fetch(id: keyId) else {
            throw ApiRelayError.validationFailed(field: "keyId", reason: "not_found")
        }
        if key.lifecycle == .softDeleted {
            throw ApiRelayError.validationFailed(field: "keyId", reason: "in_recycle_bin")
        }
    }

    /// 批量恢复前先算额度。超出则整批拒绝，且 MUST 在门闩之前调用。
    func preflightRestoreQuota(keyIds: [UUID], accountIds: [UUID]) async throws {
        let needed = try await keysThatWouldBecomeActive(keyIds: keyIds, accountIds: accountIds).count
        guard needed > 0 else { return }
        if let remaining = try await remainingFreeQuota(), needed > remaining {
            throw ApiRelayError.quotaExceededFreeTier(limit: Self.freeTierLimit)
        }
    }

    /// 调用方 MUST 已完成 `confirmMandatory`。先账号（级联其下密钥），再处理剩余密钥。
    func restoreDeletedAfterAuthentication(
        keyIds: [UUID],
        accountIds: [UUID]
    ) async -> TrashBatchOutcome {
        var successCount = 0
        var failures: [TrashBatchItemFailure] = []
        for accountId in unique(accountIds) {
            let name = await accountDisplayName(accountId)
            do {
                if try await restoreAccountAfterAuth(accountId, requirePresent: false) {
                    successCount += 1
                }
            } catch {
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        let selectedAccounts = Set(accountIds)
        for keyId in unique(keyIds) {
            let name = await keyDisplayName(keyId)
            do {
                if let key = try await keysRepo.fetch(id: keyId),
                   selectedAccounts.contains(key.accountId),
                   key.lifecycle != .softDeleted {
                    successCount += 1
                    continue
                }
                if try await restoreKeyAfterAuth(keyId, requirePresent: false) {
                    successCount += 1
                }
            } catch {
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        return TrashBatchOutcome(successCount: successCount, failures: failures)
    }

    /// 调用方 MUST 已完成 `confirmMandatory`。先账号（会拆掉其下密钥），再删剩余密钥。
    func permanentlyDeleteDeletedAfterAuthentication(
        keyIds: [UUID],
        accountIds: [UUID]
    ) async -> TrashBatchOutcome {
        var successCount = 0
        var failures: [TrashBatchItemFailure] = []
        for accountId in unique(accountIds) {
            let name = await accountDisplayName(accountId)
            do {
                if try await permanentlyDeleteAccountAfterAuth(accountId) {
                    successCount += 1
                }
            } catch {
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        for keyId in unique(keyIds) {
            let name = await keyDisplayName(keyId)
            do {
                if try await keysRepo.fetch(id: keyId) == nil {
                    successCount += 1
                    continue
                }
                if try await permanentlyDeleteKeyAfterAuth(keyId) {
                    successCount += 1
                }
            } catch {
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        return TrashBatchOutcome(successCount: successCount, failures: failures)
    }

    private func keysThatWouldBecomeActive(keyIds: [UUID], accountIds: [UUID]) async throws -> Set<UUID> {
        var ids = Set<UUID>()
        for accountId in unique(accountIds) {
            let cascade = try await keysRepo.fetch(accountId: accountId, lifecycles: [.softDeleted])
            for key in cascade {
                ids.insert(key.id)
            }
        }
        for keyId in unique(keyIds) {
            guard let key = try await keysRepo.fetch(id: keyId), key.lifecycle == .softDeleted else {
                continue
            }
            ids.insert(key.id)
        }
        return ids
    }

    /// - Returns: 是否把一条回收站账号变成了有效（已恢复则 true，以便重试计成功）。
    @discardableResult
    private func restoreAccountAfterAuth(_ id: UUID, requirePresent: Bool) async throws -> Bool {
        guard let account = try await accountsRepo.fetch(id: id) else {
            if requirePresent {
                throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
            }
            return true
        }
        guard account.deletedAt != nil else { return true }
        let cascadeKeys = try await keysRepo.fetch(accountId: id, lifecycles: [.softDeleted])
        if let remaining = try await remainingFreeQuota(), cascadeKeys.count > remaining {
            throw ApiRelayError.quotaExceededFreeTier(limit: Self.freeTierLimit)
        }
        try await accountsRepo.clearDeletionMarks(id: id)
        for key in cascadeKeys {
            try await keysRepo.clearDeletionMarks(id: key.id)
        }
        return true
    }

    /// - Returns: 是否已不在回收站（含本来就有效、或刚恢复）。
    @discardableResult
    private func restoreKeyAfterAuth(_ id: UUID, requirePresent: Bool) async throws -> Bool {
        guard let key = try await keysRepo.fetch(id: id) else {
            if requirePresent {
                throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
            }
            return true
        }
        guard key.lifecycle == .softDeleted else { return true }
        if let remaining = try await remainingFreeQuota(), remaining <= 0 {
            throw ApiRelayError.quotaExceededFreeTier(limit: Self.freeTierLimit)
        }
        if let account = try await accountsRepo.fetch(id: key.accountId),
           account.deletedAt != nil {
            try await accountsRepo.clearDeletionMarks(id: account.id)
        }
        try await keysRepo.clearDeletionMarks(id: id)
        return true
    }

    @discardableResult
    private func permanentlyDeleteAccountAfterAuth(_ id: UUID) async throws -> Bool {
        guard try await accountsRepo.fetch(id: id) != nil else { return true }
        let allKeys = try await keysRepo.fetch(accountId: id, lifecycles: nil)
        for key in allKeys {
            try await destroyKey(key.id)
        }
        try await accountsRepo.delete(id: id)
        return true
    }

    @discardableResult
    private func permanentlyDeleteKeyAfterAuth(_ id: UUID) async throws -> Bool {
        try await destroyKey(id)
        return true
    }

    private func keyDisplayName(_ id: UUID) async -> String {
        (try? await keysRepo.fetch(id: id))?.displayName ?? id.uuidString
    }

    private func accountDisplayName(_ id: UUID) async -> String {
        (try? await accountsRepo.fetch(id: id))?.displayName ?? id.uuidString
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func softDeleteKeyMetadata(_ id: UUID) async throws {
        try await keysRepo.softDelete(id: id, retainDays: 30)
    }

    private func destroyKey(_ id: UUID) async throws {
        try await keychain.delete(service: .keys, account: id)
        try await assignmentsRepo.deleteAll(forKeyId: id)
        try await keysRepo.delete(id: id)
    }

    /// 只回答「本机钥匙串里有没有这一条」。用属性查询（`listAccounts`）而非 `read`——
    /// 列表刷新 MUST NOT 把明文读进内存，也 MUST NOT 由此得出明文长度。
    private func withSecretAvailability(_ records: [KeyRecordDTO]) async throws -> [KeyRecordDTO] {
        let storedIds = Set((try? await keychain.listAccounts(service: .keys)) ?? [])
        var result: [KeyRecordDTO] = []
        for record in records {
            result.append(KeyRecordDTO(
                id: record.id,
                accountId: record.accountId,
                consumerToolIds: record.consumerToolIds,
                displayName: record.displayName,
                maskedHint: nil,
                origin: record.origin,
                providerKeyRef: record.providerKeyRef,
                lifecycle: record.lifecycle,
                health: record.health,
                deletedAt: record.deletedAt,
                purgeAfter: record.purgeAfter,
                spendLimit: record.spendLimit,
                notes: record.notes,
                secretAvailable: storedIds.contains(record.id),
                sortOrder: record.sortOrder,
                avatarSymbol: record.avatarSymbol,
                avatarColor: record.avatarColor
            ))
        }
        return result
    }

    nonisolated static func normalizeSecret(_ secret: String) throws -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ApiRelayError.validationFailed(field: "secret", reason: "empty")
        }
        if trimmed.contains(where: { $0.isWhitespace }) {
            throw ApiRelayError.validationFailed(field: "secret", reason: "contains_whitespace")
        }
        return trimmed
    }

    /// 录入查重：对本机 Keychain 已有明文做相等比较。MUST NOT 走门闩——明文未交给用户。
    private func existingKeyId(
        matching secret: String,
        accountId: UUID,
        excludingId: UUID? = nil
    ) async throws -> UUID? {
        let records = try await keysRepo.fetch(
            accountId: accountId,
            lifecycles: [.active, .revokedUpstream]
        )
        for record in records {
            if record.id == excludingId { continue }
            let existing: String
            do {
                existing = try await keychain.read(service: .keys, account: record.id)
            } catch {
                continue
            }
            if existing == secret {
                return record.id
            }
        }
        return nil
    }
}
