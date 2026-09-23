import Foundation
import SwiftData
import Security

actor KeyVaultService: KeyVaultServing, AutomatedSecretReading {
    static let freeTierLimit = 3

    private enum SecretStorageSnapshot: Sendable {
        case absent
        case present(String)
    }

    private struct KeyDestructionSnapshot: Sendable {
        let id: UUID
        let metadata: APIKeyRecordStorageSnapshot?
        let consumerToolIds: [UUID]
        let secret: SecretStorageSnapshot
    }

    private let keychain: KeychainStoring
    private let gate: RevealGateServing
    private let clipboard: ClipboardServing
    private let accountsRepo: UpstreamAccountRepository
    private let keysRepo: APIKeyRecordRepository
    private let assignmentsRepo: KeyAssignmentRepository
    private let userPrefsRepo: UserPreferencesRepository
    private let entitlements: EntitlementServing
    private let sessionLock: any SessionLockQuerying
    private let integrityQuarantine: VaultIntegrityQuarantineStore
    private let mutationGate: StorageMutationGate
    private let crossStoreJournal: any CrossStoreTransactionJournalStoring
    private struct RevealReuseGrant: Sendable {
        let keyId: UUID
        let authorization: SessionAuthorizationLease
        let sequence: UInt64
    }
    /// 一次性 token 只留在业务 actor 内；UI 不持有也不回传明文。
    private var revealReuseGrants: [SecretRevealReuseToken: RevealReuseGrant] = [:]
    private var nextRevealReuseSequence: UInt64 = 0
    private static let revealReuseGrantLimit = 64
    /// 跨 actor 的补偿事务必须串行，避免一个回滚覆盖另一个已提交的写入。
    private var activationMutationLocked = false
    private var activationMutationWaiters: [CheckedContinuation<Void, Never>] = []
    private var activeStoragePermit: StorageMutationPermit?
    private var activeExclusiveStoragePermit: StorageExclusiveMutationPermit?
    private var activationMutationGateFailure: ApiRelayError?

    init(
        keychain: KeychainStoring,
        gate: RevealGateServing,
        clipboard: ClipboardServing,
        modelContainer: ModelContainer,
        entitlements: EntitlementServing,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock(),
        integrityQuarantine: VaultIntegrityQuarantineStore = .shared,
        mutationGate: StorageMutationGate = StorageMutationGate(),
        crossStoreJournal: any CrossStoreTransactionJournalStoring = DurableCrossStoreTransactionJournal()
    ) {
        self.keychain = keychain
        self.gate = gate
        self.clipboard = clipboard
        self.accountsRepo = UpstreamAccountRepository(modelContainer: modelContainer)
        self.keysRepo = APIKeyRecordRepository(modelContainer: modelContainer)
        self.assignmentsRepo = KeyAssignmentRepository(modelContainer: modelContainer)
        self.userPrefsRepo = UserPreferencesRepository(modelContainer: modelContainer)
        self.entitlements = entitlements
        self.sessionLock = sessionLock
        self.integrityQuarantine = integrityQuarantine
        self.mutationGate = mutationGate
        self.crossStoreJournal = crossStoreJournal
    }

    private func captureSessionAuthorization() throws -> SessionAuthorizationLease {
        try ensureStorageIntegrity()
        return try sessionLock.captureAuthorizationLease()
    }

    private func validateSessionAuthorization(_ authorization: SessionAuthorizationLease) throws {
        try ensureStorageIntegrity()
        try sessionLock.validateAuthorizationLease(authorization)
    }

    /// Bind the concrete SwiftData/Keychain mutation to the same session
    /// generation captured before authentication. A check merely before an
    /// actor hop is insufficient: focus can be lost while the repository is
    /// preparing its ModelContext save.
    private func repositoryCommit(
        _ authorization: SessionAuthorizationLease
    ) -> RepositoryCommit {
        let storagePermitted = activeStoragePermit != nil || activeExclusiveStoragePermit != nil
        return { [sessionLock] operation in
            guard storagePermitted else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "vault_repository_commit",
                    detail: "erase_in_progress"
                )
            }
            try sessionLock.commitAuthorizationLease(authorization, operation: operation)
        }
    }

    private func keychainCommit(
        _ authorization: SessionAuthorizationLease
    ) -> KeychainCommit {
        let storagePermitted = activeStoragePermit != nil || activeExclusiveStoragePermit != nil
        return { [sessionLock] operation in
            guard storagePermitted else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "vault_keychain_commit",
                    detail: "erase_in_progress"
                )
            }
            try sessionLock.commitAuthorizationLease(authorization, operation: operation)
        }
    }

    private func ensureStorageIntegrity() throws {
        if let activationMutationGateFailure {
            throw activationMutationGateFailure
        }
        if let incident = integrityQuarantine.currentIncident() {
            throw ApiRelayError.storageIntegrityQuarantined(
                operation: incident.operation,
                detail: incident.detail
            )
        }
    }

    private func captureSecretSnapshot(for id: UUID) async throws -> SecretStorageSnapshot {
        do {
            return .present(try await keychain.read(service: .keys, account: id))
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            return .absent
        }
    }

    private func restoreSecretSnapshot(_ snapshot: SecretStorageSnapshot, for id: UUID) async throws {
        switch snapshot {
        case .absent:
            try await keychain.delete(service: .keys, account: id)
        case .present(let secret):
            try await keychain.save(secret, service: .keys, account: id)
        }
    }

    private func freshCrossStoreKeyID() async throws -> UUID {
        for _ in 0..<16 {
            let candidate = UUID()
            guard try await keysRepo.storageSnapshot(id: candidate) == nil else { continue }
            do {
                _ = try await keychain.read(service: .keys, account: candidate)
            } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
                return candidate
            }
        }
        throw ApiRelayError.storageRecoveryFailed(
            operation: "create_key_identifier",
            detail: "unable_to_allocate_clean_identifier"
        )
    }

    /// Idempotent durable rollback. Metadata is removed before a newly-created
    /// secret, so a failed delete can leave at worst an unreachable Keychain
    /// orphan rather than a visible record with no secret.
    private func rollbackInterruptedCreateKey(
        _ record: CrossStoreTransactionRecord
    ) async throws {
        try record.validateForRecovery()
        guard record.kind == .createKey, record.phase == .applying else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "create_key_recovery",
                detail: "unexpected_transaction_kind"
            )
        }
        for plan in record.insertedKeys.reversed() {
            _ = try await keysRepo.deleteIfCreatedAtMatches(
                id: plan.id,
                createdAt: plan.createdAt
            )
            // The exact tag is part of the atomic SecItemAdd. This remains safe
            // even if the process died immediately after the add and before any
            // second journal write.
            _ = try await keychain.deleteIfTransactionTagMatches(
                service: .keys,
                account: plan.id,
                transactionTag: record.transactionId
            )
        }
    }

    private func finalizeCommittedCreateKey(
        _ record: CrossStoreTransactionRecord
    ) async throws {
        try record.validateForRecovery()
        guard record.kind == .createKey, record.phase == .commitDecided else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "create_key_finalize",
                detail: "unexpected_transaction_state"
            )
        }
        for plan in record.insertedKeys {
            try await keychain.finalizeTransactionTagIfMatches(
                service: .keys,
                account: plan.id,
                transactionTag: record.transactionId
            )
        }
    }

    /// Called once at startup when the shared gate was constructed sealed from
    /// this journal. It uses this service's long-lived repository actor so no
    /// stale pre-recovery context can later expose the provisional record.
    func recoverInterruptedCrossStoreTransaction(
        _ record: CrossStoreTransactionRecord
    ) async throws {
        guard record.kind == .createKey else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "create_key_recovery",
                detail: "unexpected_transaction_kind"
            )
        }
        await acquireActivationSerialization()
        activeStoragePermit = nil
        activeExclusiveStoragePermit = nil
        activationMutationGateFailure = nil
        do {
            activeExclusiveStoragePermit = try await mutationGate.beginCrossStoreRecoveryExclusive(
                operation: "create_key_recovery"
            )
            guard let currentRecord = try crossStoreJournal.load(),
                  currentRecord == record else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "create_key_recovery",
                    detail: "stale_recovery_record"
                )
            }
            switch currentRecord.phase {
            case .applying:
                try await rollbackInterruptedCreateKey(currentRecord)
            case .commitDecided:
                try await finalizeCommittedCreateKey(currentRecord)
            case .completed:
                break
            }
            try crossStoreJournal.clear(transactionId: currentRecord.transactionId)
            activeExclusiveStoragePermit?.finish()
            activeExclusiveStoragePermit = nil
            try mutationGate.completeCrossStoreRecoveryAndReopen()
            releaseActivationMutation()
        } catch {
            mutationGate.sealForCrossStoreRecovery()
            releaseActivationMutation()
            let detail = "cause=\(IdentityHygieneLog.typeName(error))"
            throw ApiRelayError.storageRecoveryFailed(
                operation: "create_key_startup_recovery",
                detail: detail
            )
        }
    }

    private func diagnosticCode(for error: Error) -> String {
        switch error as? ApiRelayError {
        case .sessionLocked:
            return "session_locked"
        case .keychainFailure(let status):
            return "keychain_status_\(status)"
        case .validationFailed:
            return "validation_failure"
        case .storageRecoveryFailed(let operation, _):
            return "nested_recovery_\(operation)"
        case .storageIntegrityQuarantined(let operation, _):
            return "nested_quarantine_\(operation)"
        case .secretMissingOnDevice:
            return "secret_missing"
        case .none:
            return String(reflecting: type(of: error))
        default:
            return String(reflecting: type(of: error))
        }
    }

    private func recoveryError(
        operation: String,
        primary: Error,
        failures: [(String, Error)],
        quarantine: Bool
    ) -> ApiRelayError {
        let recovery = failures
            .map { "\($0.0)=\(diagnosticCode(for: $0.1))" }
            .joined(separator: ",")
        let detail = "primary=\(diagnosticCode(for: primary));recovery=\(recovery)"
        if quarantine {
            integrityQuarantine.quarantine(operation: operation, detail: detail)
            return .storageIntegrityQuarantined(operation: operation, detail: detail)
        }
        return .storageRecoveryFailed(operation: operation, detail: detail)
    }

    func accounts() async throws -> [UpstreamAccountDTO] {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        let records = try await accountsRepo.fetchAll()
        try ensureStorageIntegrity()
        return records
    }

    func keys(in accountId: UUID?) async throws -> [KeyRecordDTO] {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        let records = try await keysRepo.fetch(
            accountId: accountId,
            lifecycles: [.active, .revokedUpstream]
        )
        let available = try await withSecretAvailability(records)
        try ensureStorageIntegrity()
        return available
    }

    func createAccount(_ draft: UpstreamAccountDraft) async throws -> UUID {
        let authorization = try captureSessionAuthorization()
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        let id = UUID()
        do {
            _ = try await accountsRepo.insert(
                draft,
                id: id,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
            return id
        } catch let primary {
            do {
                try await accountsRepo.delete(id: id)
            } catch {
                throw recoveryError(
                    operation: "create_account",
                    primary: primary,
                    failures: [("delete_metadata", error)],
                    quarantine: true
                )
            }
            throw primary
        }
    }

    func updateAccount(_ id: UUID, patch: UpstreamAccountPatch, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        guard try await accountsRepo.fetch(id: id) != nil else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        if let platform = patch.platform?.trimmingCharacters(in: .whitespacesAndNewlines), platform.isEmpty {
            throw ApiRelayError.validationFailed(field: "platform", reason: "required")
        }
        if let name = patch.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), name.isEmpty {
            throw ApiRelayError.validationFailed(field: "displayName", reason: "required_1_to_64")
        }
        if Self.accountPatchRequiresIdentity(patch) {
            try await confirmCurrent(
                reason: String(localized: "vault.account.edit"),
                purpose: .settings,
                appPassword: appPassword
            )
        }
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        guard let snapshot = try await accountsRepo.storageSnapshot(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        try validateSessionAuthorization(authorization)
        do {
            try await accountsRepo.update(
                id: id,
                patch: patch,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            do {
                try await accountsRepo.restoreStorageSnapshot(snapshot)
            } catch {
                throw recoveryError(
                    operation: "update_account",
                    primary: primary,
                    failures: [("restore_metadata", error)],
                    quarantine: true
                )
            }
            throw primary
        }
    }

    func deleteAccount(_ id: UUID, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "gate.deleteAccount"),
            purpose: .destructive,
            appPassword: appPassword
        )
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        guard let account = try await accountsRepo.storageSnapshot(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        let related = try await keysRepo.fetch(accountId: id, lifecycles: [.active, .revokedUpstream])
        var keySnapshots: [APIKeyRecordStorageSnapshot] = []
        for key in related {
            if let snapshot = try await keysRepo.storageSnapshot(id: key.id) {
                keySnapshots.append(snapshot)
            }
        }
        var touchedKeys: [APIKeyRecordStorageSnapshot] = []
        var accountTouched = false
        do {
            for key in keySnapshots {
                try validateSessionAuthorization(authorization)
                touchedKeys.append(key)
                try await keysRepo.softDelete(
                    id: key.id,
                    retainDays: 30,
                    committing: repositoryCommit(authorization)
                )
                try validateSessionAuthorization(authorization)
            }
            try validateSessionAuthorization(authorization)
            accountTouched = true
            try await accountsRepo.softDelete(
                id: id,
                retainDays: 30,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            var failures: [(String, Error)] = []
            if accountTouched {
                do {
                    try await accountsRepo.restoreStorageSnapshot(account)
                } catch {
                    failures.append(("restore_account", error))
                }
            }
            for key in touchedKeys.reversed() {
                do {
                    try await keysRepo.restoreStorageSnapshot(key)
                } catch {
                    failures.append(("restore_key_\(key.id.uuidString)", error))
                }
            }
            guard !failures.isEmpty else { throw primary }
            throw recoveryError(
                operation: "soft_delete_account",
                primary: primary,
                failures: failures,
                quarantine: true
            )
        }
    }

    func createKey(
        _ draft: KeyDraft,
        secret: String,
        acknowledgePossibleDuplicate: Bool
    ) async throws -> UUID {
        let authorization = try captureSessionAuthorization()
        let normalized = try Self.normalizeSecret(secret)
        await acquireExclusiveActivationMutation(operation: "create_key")
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        try validateSessionAuthorization(authorization)
        try await ensureCanActivateKeys(1)

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

        // A fresh identifier whose Keychain account is also absent makes
        // crash recovery unambiguous without ever persisting plaintext in the
        // transaction journal.
        let id = try await freshCrossStoreKeyID()
        let createdAt = Date()
        let rollbackPlan = CrossStoreKeyRollbackPlan(
            id: id,
            accountId: draft.accountId,
            createdAt: createdAt
        )
        var transactionId: UUID?
        do {
            let begunTransactionId = try crossStoreJournal.begin(.createKey)
            transactionId = begunTransactionId
            try validateSessionAuthorization(authorization)
            let authorizedCommit = repositoryCommit(authorization)
            _ = try await keysRepo.insert(
                draft,
                id: id,
                createdAt: createdAt,
                committing: { [crossStoreJournal] operation in
                    try authorizedCommit {
                        try crossStoreJournal.planInsertedKey(
                            rollbackPlan,
                            transactionId: begunTransactionId
                        )
                        try operation()
                    }
                }
            )
            try validateSessionAuthorization(authorization)
            let insertedSecret = try await keychain.insertIfAbsent(
                normalized,
                service: .keys,
                account: id,
                transactionTag: begunTransactionId,
                committing: keychainCommit(authorization)
            )
            guard insertedSecret else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "create_key",
                    detail: "keychain_account_raced"
                )
            }
            try validateSessionAuthorization(authorization)
            try crossStoreJournal.decideCommit(transactionId: begunTransactionId)
            guard let committedRecord = try crossStoreJournal.load(),
                  committedRecord.transactionId == begunTransactionId,
                  committedRecord.phase == .commitDecided else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "create_key_commit",
                    detail: "commit_decision_unavailable"
                )
            }
            try await finalizeCommittedCreateKey(committedRecord)
            try crossStoreJournal.clear(transactionId: begunTransactionId)
            return id
        } catch let primary {
            if transactionId == nil {
                do {
                    // `begin` may have atomically renamed its empty applying
                    // marker before directory fsync failed. No protected write
                    // has run yet, so clearing that exact empty marker is safe.
                    if let record = try crossStoreJournal.load() {
                        guard record.kind == .createKey,
                              record.phase == .applying,
                              record.insertedKeys.isEmpty else {
                            throw ApiRelayError.storageRecoveryFailed(
                                operation: "create_key_begin_recovery",
                                detail: "unexpected_marker"
                            )
                        }
                        try crossStoreJournal.clear(transactionId: record.transactionId)
                    }
                } catch let cleanupFailure {
                    mutationGate.sealForCrossStoreRecovery()
                    throw recoveryError(
                        operation: "create_key_begin",
                        primary: primary,
                        failures: [("journal_cleanup", cleanupFailure)],
                        quarantine: (try? crossStoreJournal.load()) == nil
                    )
                }
                throw primary
            }
            do {
                guard let transactionId else { preconditionFailure("checked above") }
                guard let record = try crossStoreJournal.load(),
                      record.transactionId == transactionId,
                      record.kind == .createKey else {
                    throw ApiRelayError.storageRecoveryFailed(
                        operation: "create_key_recovery",
                        detail: "journal_unavailable"
                    )
                }
                switch record.phase {
                case .applying:
                    try await rollbackInterruptedCreateKey(record)
                    try crossStoreJournal.clear(transactionId: transactionId)
                case .commitDecided:
                    try await finalizeCommittedCreateKey(record)
                    try crossStoreJournal.clear(transactionId: transactionId)
                    return id
                case .completed:
                    // The business outcome was already resolved and only the
                    // durable tombstone survived an interrupted unlink.
                    try crossStoreJournal.clear(transactionId: transactionId)
                    return id
                }
            } catch let compensation {
                mutationGate.sealForCrossStoreRecovery()
                let markerMissing = (try? crossStoreJournal.load()) == nil
                throw recoveryError(
                    operation: "create_key",
                    primary: primary,
                    failures: [("durable_rollback", compensation)],
                    quarantine: markerMissing
                )
            }
            throw primary
        }
    }

    func updateKey(_ id: UUID, patch: KeyPatch, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        if Self.keyPatchRequiresIdentity(patch) {
            try await confirmCurrent(
                reason: String(localized: "vault.key.edit"),
                purpose: .settings,
                appPassword: appPassword
            )
        }
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        guard let snapshot = try await keysRepo.storageSnapshot(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        try validateSessionAuthorization(authorization)
        do {
            try await keysRepo.update(
                id: id,
                patch: patch,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            do {
                try await keysRepo.restoreStorageSnapshot(snapshot)
            } catch {
                throw recoveryError(
                    operation: "update_key",
                    primary: primary,
                    failures: [("restore_metadata", error)],
                    quarantine: true
                )
            }
            throw primary
        }
    }

    func editKey(_ id: UUID, draft: KeyEditDraft, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "vault.key.edit"),
            purpose: .settings,
            appPassword: appPassword
        )
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)

        guard let key = try await keysRepo.storageSnapshot(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        if key.lifecycle == .softDeleted {
            throw ApiRelayError.validationFailed(field: "id", reason: "in_recycle_bin")
        }
        guard let account = try await accountsRepo.storageSnapshot(id: key.accountId) else {
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
        let isCustom = platform == PresetCatalog.customPlatformID
        let trimmedCustom = draft.customPlatformName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isCustom, trimmedCustom.isEmpty {
            throw ApiRelayError.validationFailed(field: "customPlatformName", reason: "required")
        }

        var keyPatch = KeyPatch(displayName: trimmedKeyName)
        if let notes = draft.notes {
            keyPatch.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        keyPatch.updatesAvatar = true
        keyPatch.avatarSymbol = draft.avatarSymbol
        keyPatch.avatarColor = draft.avatarColor
        var replacementSecret: String?
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
                replacementSecret = normalized
            }
        }

        let accountPatch = UpstreamAccountPatch(
            platform: platform,
            customPlatformName: isCustom ? trimmedCustom : "",
            displayName: trimmedAccountName,
            customBaseURL: isCustom ? (draft.customBaseURL ?? "") : ""
        )

        let oldSecret: SecretStorageSnapshot?
        if replacementSecret != nil {
            try validateSessionAuthorization(authorization)
            oldSecret = try await captureSecretSnapshot(for: id)
            try validateSessionAuthorization(authorization)
        } else {
            oldSecret = nil
        }

        var secretTouched = false
        var keyMetadataTouched = false
        var accountMetadataTouched = false
        do {
            if let replacementSecret {
                try validateSessionAuthorization(authorization)
                try await keychain.save(
                    replacementSecret,
                    service: .keys,
                    account: id,
                    committing: keychainCommit(authorization)
                )
                secretTouched = true
                try validateSessionAuthorization(authorization)
            }

            try validateSessionAuthorization(authorization)
            keyMetadataTouched = true
            try await keysRepo.update(
                id: id,
                patch: keyPatch,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)

            try validateSessionAuthorization(authorization)
            accountMetadataTouched = true
            try await accountsRepo.update(
                id: key.accountId,
                patch: accountPatch,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            var failures: [(String, Error)] = []
            if accountMetadataTouched {
                do {
                    try await accountsRepo.restoreStorageSnapshot(account)
                } catch {
                    failures.append(("restore_account_metadata", error))
                }
            }
            if keyMetadataTouched {
                do {
                    try await keysRepo.restoreStorageSnapshot(key)
                } catch {
                    failures.append(("restore_key_metadata", error))
                }
            }
            if secretTouched, let oldSecret {
                do {
                    try await restoreSecretSnapshot(oldSecret, for: id)
                } catch {
                    failures.append(("restore_secret", error))
                }
            }
            guard !failures.isEmpty else { throw primary }
            throw recoveryError(
                operation: "edit_key",
                primary: primary,
                failures: failures,
                quarantine: true
            )
        }
    }

    func reorderKeys(orderedIds: [UUID]) async throws {
        let authorization = try captureSessionAuthorization()
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        var snapshots: [APIKeyRecordStorageSnapshot] = []
        for id in unique(orderedIds) {
            if let snapshot = try await keysRepo.storageSnapshot(id: id) {
                snapshots.append(snapshot)
            }
        }
        do {
            try validateSessionAuthorization(authorization)
            try await keysRepo.reorder(
                orderedIds: orderedIds,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            var failures: [(String, Error)] = []
            for snapshot in snapshots {
                do {
                    try await keysRepo.restoreStorageSnapshot(snapshot)
                } catch {
                    failures.append(("restore_key_\(snapshot.id.uuidString)", error))
                }
            }
            guard !failures.isEmpty else { throw primary }
            throw recoveryError(
                operation: "reorder_keys",
                primary: primary,
                failures: failures,
                quarantine: true
            )
        }
    }

    func reorderAccounts(orderedIds: [UUID]) async throws {
        let authorization = try captureSessionAuthorization()
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        var snapshots: [UpstreamAccountStorageSnapshot] = []
        for id in unique(orderedIds) {
            if let snapshot = try await accountsRepo.storageSnapshot(id: id) {
                snapshots.append(snapshot)
            }
        }
        do {
            try validateSessionAuthorization(authorization)
            try await accountsRepo.reorder(
                orderedIds: orderedIds,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            var failures: [(String, Error)] = []
            for snapshot in snapshots {
                do {
                    try await accountsRepo.restoreStorageSnapshot(snapshot)
                } catch {
                    failures.append(("restore_account_\(snapshot.id.uuidString)", error))
                }
            }
            guard !failures.isEmpty else { throw primary }
            throw recoveryError(
                operation: "reorder_accounts",
                primary: primary,
                failures: failures,
                quarantine: true
            )
        }
    }

    func deleteKey(_ id: UUID, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "gate.deleteKey"),
            purpose: .destructive,
            appPassword: appPassword
        )
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        guard let snapshot = try await keysRepo.storageSnapshot(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        do {
            try validateSessionAuthorization(authorization)
            try await keysRepo.softDelete(
                id: id,
                retainDays: 30,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            do {
                try await keysRepo.restoreStorageSnapshot(snapshot)
            } catch {
                throw recoveryError(
                    operation: "soft_delete_key",
                    primary: primary,
                    failures: [("restore_metadata", error)],
                    quarantine: true
                )
            }
            throw primary
        }
    }

    func recentlyDeletedKeys() async throws -> [KeyRecordDTO] {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        // 回收站只展示元数据；禁止在此读 Keychain（同步钥匙串会卡住，导致 sheet 一直空白）。
        let records = try await keysRepo.fetchSoftDeleted()
        try ensureStorageIntegrity()
        return records
    }

    func restoreKey(_ id: UUID, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "gate.restoreKey"),
            purpose: .destructive,
            appPassword: appPassword
        )
        _ = try await restoreKeyAfterAuth(id, requirePresent: true, authorization: authorization)
    }

    func permanentlyDeleteKey(_ id: UUID, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "gate.permanentDelete"),
            purpose: .destructive,
            appPassword: appPassword
        )
        _ = try await permanentlyDeleteKeyAfterAuth(id, authorization: authorization)
    }

    func purgeExpiredDeletedKeys() async throws {
        try ensureStorageIntegrity()
        guard let authorization = try? sessionLock.captureAuthorizationLease() else { return }
        try validateSessionAuthorization(authorization)
        let deleted = try await keysRepo.fetch(lifecycles: [.softDeleted])
        try validateSessionAuthorization(authorization)
        let now = Date()
        for key in deleted where (key.purgeAfter ?? .distantFuture) < now {
            _ = try await permanentlyDeleteKeyAfterAuth(key.id, authorization: authorization)
        }
    }

    func recentlyDeletedAccounts() async throws -> [UpstreamAccountDTO] {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        let records = try await accountsRepo.fetchSoftDeleted()
        try ensureStorageIntegrity()
        return records
    }

    func restoreAccount(_ id: UUID, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "gate.restoreAccount"),
            purpose: .destructive,
            appPassword: appPassword
        )
        _ = try await restoreAccountAfterAuth(id, requirePresent: true, authorization: authorization)
    }

    func permanentlyDeleteAccount(_ id: UUID, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "gate.permanentDelete"),
            purpose: .destructive,
            appPassword: appPassword
        )
        _ = try await permanentlyDeleteAccountAfterAuth(id, authorization: authorization)
    }

    func purgeExpiredDeletedAccounts() async throws {
        try ensureStorageIntegrity()
        guard let authorization = try? sessionLock.captureAuthorizationLease() else { return }
        try validateSessionAuthorization(authorization)
        let deleted = try await accountsRepo.fetchSoftDeleted()
        try validateSessionAuthorization(authorization)
        let now = Date()
        for account in deleted where (account.purgeAfter ?? .distantFuture) < now {
            _ = try await permanentlyDeleteAccountAfterAuth(account.id, authorization: authorization)
        }
    }

    func addAssignment(keyId: UUID, consumerToolId: UUID) async throws {
        let authorization = try captureSessionAuthorization()
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        let oldIDs = try await assignmentsRepo.fetchConsumerToolIDs(keyId: keyId)
        do {
            try validateSessionAuthorization(authorization)
            try await assignmentsRepo.add(
                keyId: keyId,
                consumerToolId: consumerToolId,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            do {
                try await assignmentsRepo.replaceConsumerToolIDs(
                    keyId: keyId,
                    consumerToolIds: oldIDs
                )
            } catch {
                throw recoveryError(
                    operation: "add_assignment",
                    primary: primary,
                    failures: [("restore_assignments", error)],
                    quarantine: true
                )
            }
            throw primary
        }
    }

    func removeAssignment(keyId: UUID, consumerToolId: UUID) async throws {
        let authorization = try captureSessionAuthorization()
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        let oldIDs = try await assignmentsRepo.fetchConsumerToolIDs(keyId: keyId)
        do {
            try validateSessionAuthorization(authorization)
            try await assignmentsRepo.remove(
                keyId: keyId,
                consumerToolId: consumerToolId,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            do {
                try await assignmentsRepo.replaceConsumerToolIDs(
                    keyId: keyId,
                    consumerToolIds: oldIDs
                )
            } catch {
                throw recoveryError(
                    operation: "remove_assignment",
                    primary: primary,
                    failures: [("restore_assignments", error)],
                    quarantine: true
                )
            }
            throw primary
        }
    }

    func assignmentKind(keyId: UUID) async throws -> AssignmentKind {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        let kind = try await assignmentsRepo.assignmentKind(keyId: keyId)
        try ensureStorageIntegrity()
        return kind
    }

    func revealSecretWithEvidence(
        keyId: UUID,
        purpose: RevealPurpose,
        masterPassword: String?
    ) async throws -> SecretRevealResult {
        let authorization = try captureSessionAuthorization()
        _ = purpose
        try await ensureActiveForReveal(keyId)
        let authentication = try await confirmRevealIfNeeded(appPassword: masterPassword)
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        do {
            try validateSessionAuthorization(authorization)
            try await ensureActiveForReveal(keyId)
            try validateSessionAuthorization(authorization)
            let secret = try await keychain.read(service: .keys, account: keyId)
            try validateSessionAuthorization(authorization)
            let reuseToken: SecretRevealReuseToken?
            if authentication == .verified {
                reuseToken = issueRevealReuseToken(
                    keyId: keyId,
                    authorization: authorization
                )
            } else {
                reuseToken = nil
            }
            return SecretRevealResult(
                secret: secret,
                authentication: authentication,
                reuseToken: reuseToken
            )
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            throw ApiRelayError.secretMissingOnDevice
        }
    }

    func copySecretToClipboard(keyId: UUID, masterPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await ensureActiveForReveal(keyId)
        _ = try await confirmRevealIfNeeded(appPassword: masterPassword)
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        let secret: String
        do {
            try validateSessionAuthorization(authorization)
            try await ensureActiveForReveal(keyId)
            try validateSessionAuthorization(authorization)
            secret = try await keychain.read(service: .keys, account: keyId)
            try validateSessionAuthorization(authorization)
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            throw ApiRelayError.secretMissingOnDevice
        }
        try await writeSecretToClipboard(secret, authorization: authorization)
    }

    /// 消费与「已验证查看」同一会话的一次性 token。MUST NOT 再走门闩。
    func copyRevealedSecretToClipboard(
        keyId: UUID,
        token: SecretRevealReuseToken
    ) async throws {
        // 先消费再校验：跨 key、过期和剪贴板失败都不得重放。
        guard let grant = revealReuseGrants.removeValue(forKey: token) else {
            throw ApiRelayError.authenticationFailed
        }
        guard grant.keyId == keyId else {
            throw ApiRelayError.authenticationFailed
        }
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(grant.authorization)
        try await ensureActiveForReveal(keyId)
        try validateSessionAuthorization(grant.authorization)
        let secret: String
        do {
            secret = try await keychain.read(service: .keys, account: keyId)
            try validateSessionAuthorization(grant.authorization)
        } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
            throw ApiRelayError.secretMissingOnDevice
        }
        try await writeSecretToClipboard(secret, authorization: grant.authorization)
    }

    private func issueRevealReuseToken(
        keyId: UUID,
        authorization: SessionAuthorizationLease
    ) -> SecretRevealReuseToken? {
        // 离开前台/锁定换代后的 token 永远无法再用，签发新 token 时顺手回收。
        revealReuseGrants = revealReuseGrants.filter { _, grant in
            (try? validateSessionAuthorization(grant.authorization)) != nil
        }

        // 禁止序号回绕后复活旧顺序。真达到上限时安全降级为不再发行复用 token。
        guard nextRevealReuseSequence < UInt64.max else {
            revealReuseGrants.removeAll(keepingCapacity: false)
            return nil
        }
        nextRevealReuseSequence += 1

        if revealReuseGrants.count >= Self.revealReuseGrantLimit,
           let oldest = revealReuseGrants.min(by: { $0.value.sequence < $1.value.sequence })?.key {
            revealReuseGrants.removeValue(forKey: oldest)
        }

        let issued = SecretRevealReuseToken.issueForVault()
        revealReuseGrants[issued] = RevealReuseGrant(
            keyId: keyId,
            authorization: authorization,
            sequence: nextRevealReuseSequence
        )
        return issued
    }

    #if DEBUG
    func revealReuseGrantCountForTesting() -> Int {
        revealReuseGrants.count
    }
    #endif

    private func writeSecretToClipboard(
        _ secret: String,
        authorization: SessionAuthorizationLease
    ) async throws {
        let prefs = try await userPrefsRepo.loadOrCreate()
        let expires: TimeInterval? = prefs.clipboardClearEnabled
            ? TimeInterval(prefs.clipboardClearSeconds)
            : nil
        try validateSessionAuthorization(authorization)
        let sessionLock = self.sessionLock
        try await clipboard.write(
            secret,
            expiresAfter: expires,
            localOnly: prefs.clipboardLocalOnly,
            committing: { operation in
                try sessionLock.commitAuthorizationLease(
                    authorization,
                    operation: operation
                )
            }
        )
        try validateSessionAuthorization(authorization)
    }

    func remainingFreeQuota() async throws -> Int? {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        // 必须走 EntitlementServing（含 StoreKit 纠偏），禁止只读可能脏的本地 snapshot。
        let tier = try await entitlements.currentTier()
        try ensureStorageIntegrity()
        if tier != .free { return nil }
        let count = try await keysRepo.countActiveNonDeleted()
        try ensureStorageIntegrity()
        return max(0, Self.freeTierLimit - count)
    }

    /// 免费额度内的核心操作只查本机计数；只有即将超过 3 把时才向 StoreKit 确认会员。
    /// 这不会把 snapshot 当授权依据：超过免费线时仍必须拿到权威权益。
    private func ensureCanActivateKeys(_ additionalCount: Int) async throws {
        guard additionalCount > 0 else { return }
        let activeCount = try await keysRepo.countActiveNonDeleted()
        guard activeCount + additionalCount > Self.freeTierLimit else { return }
        let tier = try await entitlements.currentTier()
        guard tier != .free else {
            throw ApiRelayError.quotaExceededFreeTier(limit: Self.freeTierLimit)
        }
    }

    private func acquireActivationSerialization() async {
        if !activationMutationLocked {
            activationMutationLocked = true
        } else {
            await withCheckedContinuation { continuation in
                activationMutationWaiters.append(continuation)
            }
        }
    }

    private func acquireActivationMutation() async {
        await acquireActivationSerialization()
        activeStoragePermit = nil
        activeExclusiveStoragePermit = nil
        activationMutationGateFailure = nil
        do {
            activeStoragePermit = try mutationGate.beginNormal(operation: "vault_mutation")
        } catch let error as ApiRelayError {
            activationMutationGateFailure = error
        } catch {
            activationMutationGateFailure = .storageRecoveryFailed(
                operation: "vault_mutation",
                detail: "gate_failure"
            )
        }
    }

    /// Cross-store Keychain + SwiftData operations use the process-wide
    /// exclusive permit. It blocks new ordinary mutations before waiting for
    /// already-admitted ones to drain, so rollback cannot erase another
    /// service's later commit.
    private func acquireExclusiveActivationMutation(operation: String) async {
        await acquireActivationSerialization()
        activeStoragePermit = nil
        activeExclusiveStoragePermit = nil
        activationMutationGateFailure = nil
        do {
            activeExclusiveStoragePermit = try await mutationGate.beginExclusive(
                operation: operation
            )
        } catch let error as ApiRelayError {
            activationMutationGateFailure = error
        } catch {
            activationMutationGateFailure = .storageRecoveryFailed(
                operation: operation,
                detail: "gate_failure"
            )
        }
    }

    /// The sole path that can enter the activation serializer without a normal
    /// write permit. Its type makes the committed-erase authority mandatory;
    /// the shared gate additionally rejects a token from any other generation.
    private func acquireCommittedEraseMutation(
        _ authorization: CommittedEraseToken
    ) async throws {
        await acquireActivationSerialization()
        activeStoragePermit = nil
        activeExclusiveStoragePermit = nil
        activationMutationGateFailure = nil
        do {
            try mutationGate.validateCommittedEraseToken(
                authorization,
                operation: "vault_committed_erase"
            )
        } catch {
            releaseActivationMutation()
            throw error
        }
    }

    private func releaseActivationMutation() {
        activeStoragePermit?.finish()
        activeStoragePermit = nil
        activeExclusiveStoragePermit?.finish()
        activeExclusiveStoragePermit = nil
        activationMutationGateFailure = nil
        guard !activationMutationWaiters.isEmpty else {
            activationMutationLocked = false
            return
        }
        activationMutationWaiters.removeFirst().resume()
    }

    func readSecretForAutomatedUse(
        keyId: UUID,
        purpose: AutomatedSecretPurpose
    ) async throws -> String {
        let authorization = try captureSessionAuthorization()
        _ = purpose
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try await ensureActiveForReveal(keyId)
        try validateSessionAuthorization(authorization)
        let secret = try await keychain.read(service: .keys, account: keyId)
        try validateSessionAuthorization(authorization)
        return secret
    }

    func performStartupMaintenance() async throws {
        try ensureStorageIntegrity()
        await IdentityHygieneLog.runIsolated(source: .startup, steps: [
            (.expiredKeys, { try await self.purgeExpiredDeletedKeys() }),
            (.expiredAccounts, { try await self.purgeExpiredDeletedAccounts() }),
            (.secretFragments, { try await self.clearStoredSecretFragmentsForMaintenance() }),
        ])
        await pruneDuplicateIdentities(source: .startup)
    }

    func pruneDuplicateIdentities() async throws {
        try ensureStorageIntegrity()
        await pruneDuplicateIdentities(source: .cloudImport)
    }

    /// 账号 / 密钥可按 `updatedAt` 清扫。安全偏好无 `updatedAt`，13.5 只读折叠、写打全，不物理删。
    private func pruneDuplicateIdentities(source: IdentityHygieneLog.Source) async {
        await IdentityHygieneLog.runIsolated(source: source, steps: [
            (.account, { try await self.pruneAccountDuplicatesForMaintenance() }),
            (.key, { try await self.pruneKeyDuplicatesForMaintenance() }),
        ])
    }

    private func clearStoredSecretFragmentsForMaintenance() async throws {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        try await keysRepo.clearStoredSecretFragments()
        try ensureStorageIntegrity()
    }

    private func pruneAccountDuplicatesForMaintenance() async throws {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        try await accountsRepo.pruneDuplicateIdentities()
        try ensureStorageIntegrity()
    }

    private func pruneKeyDuplicatesForMaintenance() async throws {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        try await keysRepo.pruneDuplicateIdentities()
        try ensureStorageIntegrity()
    }

    /// FR-061：物理删除本服务 ModelActor 里的账号 / 密钥 / 指派 / 安全偏好（含回收站）。
    /// 必须走这些已有仓库，另开 ModelContext 删除后主列表仍会读到旧对象。
    func purgeAllRecordsForErase(authorization: SessionAuthorizationLease) async throws {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        try await assignmentsRepo.deleteAllRecords()
        try validateSessionAuthorization(authorization)
        try await keysRepo.deleteAllRecords()
        try validateSessionAuthorization(authorization)
        try await accountsRepo.deleteAllRecords()
        try validateSessionAuthorization(authorization)
        try await userPrefsRepo.deleteAllRecords()
        try validateSessionAuthorization(authorization)
    }

    /// `DataLifecycleService` has already committed the irreversible erase
    /// transaction and persisted its journal before entering this method.
    /// Session invalidation must not interrupt the transaction into a silent
    /// half-erased state; storage errors still propagate and keep the journal.
    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws {
        try await acquireCommittedEraseMutation(authorization)
        defer { releaseActivationMutation() }
        try await assignmentsRepo.deleteAllRecords()
        try await keysRepo.deleteAllRecords()
        try await accountsRepo.deleteAllRecords()
        try await userPrefsRepo.deleteAllRecords()
    }

    func currentRevealPolicy() async throws -> RevealPolicy {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        let policy = try await userPrefsRepo.loadOrCreate().revealPolicy
        try ensureStorageIntegrity()
        return policy
    }

    private func confirmCurrent(
        reason: String,
        purpose: AuthPurpose,
        appPassword: String?
    ) async throws {
        let policy: RevealPolicy
        do {
            let storagePermit = try mutationGate.beginNormal(
                operation: "vault_auth_policy_read"
            )
            defer { storagePermit.finish() }
            policy = try await userPrefsRepo.loadOrCreate().revealPolicy
        }
        try await CurrentRevealPolicyAuth.confirm(
            policy,
            gate: gate,
            reason: reason,
            purpose: purpose,
            appPassword: appPassword
        )
    }

    /// 查看 / 复制：只受取用验证开关约束，不得关掉编辑、回收站、备份等固定门闩。
    private func confirmRevealIfNeeded(
        appPassword: String?
    ) async throws -> RevealAuthenticationEvidence {
        let security: (policy: RevealPolicy, enabled: Bool)
        do {
            let storagePermit = try mutationGate.beginNormal(
                operation: "vault_reveal_policy_read"
            )
            defer { storagePermit.finish() }
            let prefs = try await userPrefsRepo.loadOrCreate()
            security = (
                RevealPolicyPersistence.canonical(prefs.revealPolicy),
                prefs.revealAuthEnabled
            )
        }
        guard security.enabled, security.policy != .noVerification else {
            return .notRequired
        }
        try await CurrentRevealPolicyAuth.confirm(
            security.policy,
            gate: gate,
            reason: String(localized: "gate.reveal"),
            purpose: .revealSecret,
            appPassword: appPassword
        )
        return .verified
    }

    private static func keyPatchRequiresIdentity(_ patch: KeyPatch) -> Bool {
        patch.displayName != nil || patch.notes != nil || patch.spendLimit != nil
    }

    private static func accountPatchRequiresIdentity(_ patch: UpstreamAccountPatch) -> Bool {
        patch.platform != nil
            || patch.customPlatformName != nil
            || patch.displayName != nil
            || patch.customBaseURL != nil
            || patch.hasManagementCredential != nil
            || patch.notes != nil
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
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try ensureStorageIntegrity()
        let needed = try await keysThatWouldBecomeActive(keyIds: keyIds, accountIds: accountIds).count
        try await ensureCanActivateKeys(needed)
        try ensureStorageIntegrity()
    }

    /// 调用方 MUST 已按当前验证方式完成确认。先账号（级联其下密钥），再处理剩余密钥。
    func restoreDeletedAfterAuthentication(
        keyIds: [UUID],
        accountIds: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome {
        try validateSessionAuthorization(authorization)
        var successCount = 0
        var failures: [TrashBatchItemFailure] = []
        for accountId in unique(accountIds) {
            let name = try await accountDisplayName(accountId, authorization: authorization)
            do {
                if try await restoreAccountAfterAuth(
                    accountId,
                    requirePresent: false,
                    authorization: authorization
                ) {
                    successCount += 1
                }
            } catch {
                try rethrowIfFailClosed(error)
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        let selectedAccounts = Set(accountIds)
        for keyId in unique(keyIds) {
            let name = try await keyDisplayName(keyId, authorization: authorization)
            do {
                try validateSessionAuthorization(authorization)
                let selectedKey = try await keysRepo.fetch(id: keyId)
                try validateSessionAuthorization(authorization)
                if let key = selectedKey,
                   selectedAccounts.contains(key.accountId),
                   key.lifecycle != .softDeleted {
                    successCount += 1
                    continue
                }
                if try await restoreKeyAfterAuth(
                    keyId,
                    requirePresent: false,
                    authorization: authorization
                ) {
                    successCount += 1
                }
            } catch {
                try rethrowIfFailClosed(error)
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        try validateSessionAuthorization(authorization)
        return TrashBatchOutcome(successCount: successCount, failures: failures)
    }

    /// 调用方 MUST 已按当前验证方式完成确认。先账号（会拆掉其下密钥），再删剩余密钥。
    func permanentlyDeleteDeletedAfterAuthentication(
        keyIds: [UUID],
        accountIds: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome {
        try validateSessionAuthorization(authorization)
        var successCount = 0
        var failures: [TrashBatchItemFailure] = []
        for accountId in unique(accountIds) {
            let name = try await accountDisplayName(accountId, authorization: authorization)
            do {
                if try await permanentlyDeleteAccountAfterAuth(
                    accountId,
                    authorization: authorization
                ) {
                    successCount += 1
                }
            } catch {
                try rethrowIfFailClosed(error)
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        for keyId in unique(keyIds) {
            let name = try await keyDisplayName(keyId, authorization: authorization)
            do {
                try validateSessionAuthorization(authorization)
                let selectedKey = try await keysRepo.fetch(id: keyId)
                try validateSessionAuthorization(authorization)
                if selectedKey == nil {
                    successCount += 1
                    continue
                }
                if try await permanentlyDeleteKeyAfterAuth(
                    keyId,
                    authorization: authorization
                ) {
                    successCount += 1
                }
            } catch {
                try rethrowIfFailClosed(error)
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        try validateSessionAuthorization(authorization)
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
    private func restoreAccountAfterAuth(
        _ id: UUID,
        requirePresent: Bool,
        authorization: SessionAuthorizationLease
    ) async throws -> Bool {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        guard let account = try await accountsRepo.storageSnapshot(id: id) else {
            if requirePresent {
                throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
            }
            return true
        }
        guard account.deletedAt != nil else { return true }
        let cascadeKeys = try await keysRepo.fetch(accountId: id, lifecycles: [.softDeleted])
        try await ensureCanActivateKeys(cascadeKeys.count)
        var keySnapshots: [APIKeyRecordStorageSnapshot] = []
        for key in cascadeKeys {
            if let snapshot = try await keysRepo.storageSnapshot(id: key.id) {
                keySnapshots.append(snapshot)
            }
        }

        var accountTouched = false
        var touchedKeys: [APIKeyRecordStorageSnapshot] = []
        do {
            try validateSessionAuthorization(authorization)
            accountTouched = true
            try await accountsRepo.clearDeletionMarks(
                id: id,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
            for key in keySnapshots {
                try validateSessionAuthorization(authorization)
                touchedKeys.append(key)
                try await keysRepo.clearDeletionMarks(
                    id: key.id,
                    committing: repositoryCommit(authorization)
                )
                try validateSessionAuthorization(authorization)
            }
        } catch let primary {
            var failures: [(String, Error)] = []
            for key in touchedKeys.reversed() {
                do {
                    try await keysRepo.restoreStorageSnapshot(key)
                } catch {
                    failures.append(("restore_key_\(key.id.uuidString)", error))
                }
            }
            if accountTouched {
                do {
                    try await accountsRepo.restoreStorageSnapshot(account)
                } catch {
                    failures.append(("restore_account", error))
                }
            }
            guard !failures.isEmpty else { throw primary }
            throw recoveryError(
                operation: "restore_account",
                primary: primary,
                failures: failures,
                quarantine: true
            )
        }
        return true
    }

    /// - Returns: 是否已不在回收站（含本来就有效、或刚恢复）。
    @discardableResult
    private func restoreKeyAfterAuth(
        _ id: UUID,
        requirePresent: Bool,
        authorization: SessionAuthorizationLease
    ) async throws -> Bool {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        guard let key = try await keysRepo.storageSnapshot(id: id) else {
            if requirePresent {
                throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
            }
            return true
        }
        guard key.lifecycle == .softDeleted else { return true }
        try await ensureCanActivateKeys(1)
        let account = try await accountsRepo.storageSnapshot(id: key.accountId)
        var accountTouched = false
        var keyTouched = false
        do {
            if let account, account.deletedAt != nil {
                try validateSessionAuthorization(authorization)
                accountTouched = true
                try await accountsRepo.clearDeletionMarks(
                    id: account.id,
                    committing: repositoryCommit(authorization)
                )
                try validateSessionAuthorization(authorization)
            }
            try validateSessionAuthorization(authorization)
            keyTouched = true
            try await keysRepo.clearDeletionMarks(
                id: id,
                committing: repositoryCommit(authorization)
            )
            try validateSessionAuthorization(authorization)
        } catch let primary {
            var failures: [(String, Error)] = []
            if keyTouched {
                do {
                    try await keysRepo.restoreStorageSnapshot(key)
                } catch {
                    failures.append(("restore_key", error))
                }
            }
            if accountTouched, let account {
                do {
                    try await accountsRepo.restoreStorageSnapshot(account)
                } catch {
                    failures.append(("restore_account", error))
                }
            }
            guard !failures.isEmpty else { throw primary }
            throw recoveryError(
                operation: "restore_key",
                primary: primary,
                failures: failures,
                quarantine: true
            )
        }
        return true
    }

    @discardableResult
    private func permanentlyDeleteAccountAfterAuth(
        _ id: UUID,
        authorization: SessionAuthorizationLease
    ) async throws -> Bool {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        guard let account = try await accountsRepo.storageSnapshot(id: id) else { return true }
        let allKeys = try await keysRepo.fetch(accountId: id, lifecycles: nil)
        try await destroyKeysAndAccountAtomically(
            keyIds: allKeys.map(\.id),
            account: account,
            authorization: authorization,
            operation: "permanent_delete_account"
        )
        return true
    }

    @discardableResult
    private func permanentlyDeleteKeyAfterAuth(
        _ id: UUID,
        authorization: SessionAuthorizationLease
    ) async throws -> Bool {
        await acquireActivationMutation()
        defer { releaseActivationMutation() }
        try validateSessionAuthorization(authorization)
        try await destroyKeysAndAccountAtomically(
            keyIds: [id],
            account: nil,
            authorization: authorization,
            operation: "permanent_delete_key"
        )
        return true
    }

    private func captureKeyDestructionSnapshot(
        _ id: UUID,
        authorization: SessionAuthorizationLease
    ) async throws -> KeyDestructionSnapshot {
        try validateSessionAuthorization(authorization)
        let metadata = try await keysRepo.storageSnapshot(id: id)
        try validateSessionAuthorization(authorization)
        let consumerToolIds = try await assignmentsRepo.fetchConsumerToolIDs(keyId: id)
        try validateSessionAuthorization(authorization)
        let secret = try await captureSecretSnapshot(for: id)
        try validateSessionAuthorization(authorization)
        return KeyDestructionSnapshot(
            id: id,
            metadata: metadata,
            consumerToolIds: consumerToolIds,
            secret: secret
        )
    }

    /// 调用方持有 mutation lock。账号级永久删除把全部子密钥视为一个补偿事务。
    private func destroyKeysAndAccountAtomically(
        keyIds: [UUID],
        account: UpstreamAccountStorageSnapshot?,
        authorization: SessionAuthorizationLease,
        operation: String
    ) async throws {
        var snapshots: [KeyDestructionSnapshot] = []
        for id in unique(keyIds) {
            snapshots.append(try await captureKeyDestructionSnapshot(id, authorization: authorization))
        }

        var touchedKeys: [KeyDestructionSnapshot] = []
        var accountTouched = false
        do {
            for snapshot in snapshots {
                try validateSessionAuthorization(authorization)
                touchedKeys.append(snapshot)
                try await assignmentsRepo.deleteAll(
                    forKeyId: snapshot.id,
                    committing: repositoryCommit(authorization)
                )
                try validateSessionAuthorization(authorization)
                try await keysRepo.delete(
                    id: snapshot.id,
                    committing: repositoryCommit(authorization)
                )
                try validateSessionAuthorization(authorization)
                try await keychain.delete(
                    service: .keys,
                    account: snapshot.id,
                    committing: keychainCommit(authorization)
                )
                try validateSessionAuthorization(authorization)
            }
            if let account {
                try validateSessionAuthorization(authorization)
                accountTouched = true
                try await accountsRepo.delete(
                    id: account.id,
                    committing: repositoryCommit(authorization)
                )
                try validateSessionAuthorization(authorization)
            }
        } catch let primary {
            var failures: [(String, Error)] = []
            if accountTouched, let account {
                do {
                    try await accountsRepo.restoreStorageSnapshot(account)
                } catch {
                    failures.append(("restore_account", error))
                }
            }
            for snapshot in touchedKeys.reversed() {
                do {
                    try await restoreSecretSnapshot(snapshot.secret, for: snapshot.id)
                } catch {
                    failures.append(("restore_secret_\(snapshot.id.uuidString)", error))
                }
                if let metadata = snapshot.metadata {
                    do {
                        try await keysRepo.restoreStorageSnapshot(metadata)
                    } catch {
                        failures.append(("restore_key_\(snapshot.id.uuidString)", error))
                    }
                }
                do {
                    try await assignmentsRepo.replaceConsumerToolIDs(
                        keyId: snapshot.id,
                        consumerToolIds: snapshot.consumerToolIds
                    )
                } catch {
                    failures.append(("restore_assignments_\(snapshot.id.uuidString)", error))
                }
            }
            guard !failures.isEmpty else { throw primary }
            throw recoveryError(
                operation: operation,
                primary: primary,
                failures: failures,
                quarantine: true
            )
        }
    }

    private func rethrowIfFailClosed(_ error: Error) throws {
        guard let apiError = error as? ApiRelayError else { return }
        switch apiError {
        case .sessionLocked, .storageRecoveryFailed, .storageIntegrityQuarantined:
            throw apiError
        default:
            return
        }
    }

    private func keyDisplayName(
        _ id: UUID,
        authorization: SessionAuthorizationLease
    ) async throws -> String {
        try validateSessionAuthorization(authorization)
        let name = try await keysRepo.fetch(id: id)?.displayName ?? id.uuidString
        try validateSessionAuthorization(authorization)
        return name
    }

    private func accountDisplayName(
        _ id: UUID,
        authorization: SessionAuthorizationLease
    ) async throws -> String {
        try validateSessionAuthorization(authorization)
        let name = try await accountsRepo.fetch(id: id)?.displayName ?? id.uuidString
        try validateSessionAuthorization(authorization)
        return name
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// 只回答「本机钥匙串里有没有这一条」。用属性查询（`listAccounts`）而非 `read`——
    /// 列表刷新 MUST NOT 把明文读进内存，也 MUST NOT 由此得出明文长度。
    private func withSecretAvailability(_ records: [KeyRecordDTO]) async throws -> [KeyRecordDTO] {
        // An unavailable/denied Keychain is not the same state as an absent
        // item. Propagate infrastructure failures instead of falsely labelling
        // every credential as missing on this device.
        let storedIds = Set(try await keychain.listAccounts(service: .keys))
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
            } catch ApiRelayError.keychainFailure(let status) where status == errSecItemNotFound {
                continue
            }
            if existing == secret {
                return record.id
            }
        }
        return nil
    }
}
