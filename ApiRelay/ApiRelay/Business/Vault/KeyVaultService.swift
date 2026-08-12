import Foundation
import SwiftData

actor KeyVaultService: KeyVaultServing {
    static let freeTierLimit = 3

    private let keychain: KeychainStore
    private let gate: RevealGate
    private let clipboard: ClipboardServing
    private let accountsRepo: UpstreamAccountRepository
    private let keysRepo: APIKeyRecordRepository
    private let assignmentsRepo: KeyAssignmentRepository
    private let userPrefsRepo: UserPreferencesRepository
    private let entitlements: EntitlementServing

    init(
        keychain: KeychainStore,
        gate: RevealGate,
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

        let last4 = Self.last4(of: normalized)
        if !acknowledgePossibleDuplicate,
           let dupId = try await keysRepo.findWeakDuplicate(
            accountId: draft.accountId,
            last4: last4,
            length: normalized.count
           ) {
            throw ApiRelayError.validationFailed(
                field: "secret",
                reason: "possible_duplicate:\(dupId.uuidString)"
            )
        }

        var draft = draft
        draft.maskedHint = last4
        draft.secretLength = normalized.count
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
        if let rawSecret = draft.secret {
            let trimmedSecret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSecret.isEmpty {
                let normalized = try Self.normalizeSecret(trimmedSecret)
                let last4 = Self.last4(of: normalized)
                if !draft.acknowledgePossibleDuplicate,
                   let dupId = try await keysRepo.findWeakDuplicate(
                    accountId: key.accountId,
                    last4: last4,
                    length: normalized.count,
                    excludingId: id
                   ) {
                    throw ApiRelayError.validationFailed(
                        field: "secret",
                        reason: "possible_duplicate:\(dupId.uuidString)"
                    )
                }
                try await keychain.save(normalized, service: .keys, account: id)
                keyPatch.maskedHint = last4
                keyPatch.secretLength = normalized.count
            }
        }
        try await keysRepo.update(id: id, patch: keyPatch)

        let isCustom = platform == PresetCatalog.customPlatformID
        let accountPatch = UpstreamAccountPatch(
            platform: platform,
            customPlatformName: isCustom ? trimmedAccountName : "",
            displayName: trimmedAccountName,
            customBaseURL: isCustom ? (draft.customBaseURL ?? "") : ""
        )
        try await accountsRepo.update(id: key.accountId, patch: accountPatch)
    }

    func reorderKeys(orderedIds: [UUID]) async throws {
        try await keysRepo.reorder(orderedIds: orderedIds)
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
        if let key = try await keysRepo.fetch(id: id),
           let account = try await accountsRepo.fetch(id: key.accountId),
           account.deletedAt != nil {
            try await accountsRepo.clearDeletionMarks(id: account.id)
        }
        try await keysRepo.clearDeletionMarks(id: id)
    }

    func permanentlyDeleteKey(_ id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.permanentDelete"))
        try await destroyKey(id)
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
        guard let account = try await accountsRepo.fetch(id: id), account.deletedAt != nil else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        let cascadeKeys = try await keysRepo.fetch(accountId: id, lifecycles: [.softDeleted])
        if let remaining = try await remainingFreeQuota(), cascadeKeys.count > remaining {
            throw ApiRelayError.quotaExceededFreeTier(limit: Self.freeTierLimit)
        }
        try await accountsRepo.clearDeletionMarks(id: id)
        for key in cascadeKeys {
            try await keysRepo.clearDeletionMarks(id: key.id)
        }
    }

    func permanentlyDeleteAccount(_ id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.permanentDelete"))
        let allKeys = try await keysRepo.fetch(accountId: id, lifecycles: nil)
        for key in allKeys {
            try await destroyKey(key.id)
        }
        try await accountsRepo.delete(id: id)
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
        return try await keychain.read(service: .keys, account: keyId)
    }

    func copySecretToClipboard(keyId: UUID, masterPassword: String?) async throws {
        try await ensureActiveForReveal(keyId)
        try await runGate(masterPassword: masterPassword)
        let secret = try await keychain.read(service: .keys, account: keyId)
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

    private func softDeleteKeyMetadata(_ id: UUID) async throws {
        try await keysRepo.softDelete(id: id, retainDays: 30)
    }

    private func destroyKey(_ id: UUID) async throws {
        try await keychain.delete(service: .keys, account: id)
        try await assignmentsRepo.deleteAll(forKeyId: id)
        try await keysRepo.delete(id: id)
    }

    private func withSecretAvailability(_ records: [KeyRecordDTO]) async throws -> [KeyRecordDTO] {
        var result: [KeyRecordDTO] = []
        for record in records {
            let available: Bool
            do {
                _ = try await keychain.read(service: .keys, account: record.id)
                available = true
            } catch {
                available = false
            }
            result.append(KeyRecordDTO(
                id: record.id,
                accountId: record.accountId,
                consumerToolIds: record.consumerToolIds,
                displayName: record.displayName,
                maskedHint: record.maskedHint,
                origin: record.origin,
                providerKeyRef: record.providerKeyRef,
                lifecycle: record.lifecycle,
                health: record.health,
                deletedAt: record.deletedAt,
                purgeAfter: record.purgeAfter,
                spendLimit: record.spendLimit,
                notes: record.notes,
                secretAvailable: available,
                sortOrder: record.sortOrder
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

    nonisolated static func last4(of secret: String) -> String {
        String(secret.suffix(4))
    }
}
