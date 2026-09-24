import Foundation
import CryptoKit
import CommonCrypto
import SwiftData

actor SecureBackupService: SecureBackupServing {
    private let gate: RevealGateServing
    private let keychain: KeychainStoring
    private let accounts: UpstreamAccountRepository
    private let keys: APIKeyRecordRepository
    private let tools: ConsumerToolRepository
    private let assignments: KeyAssignmentRepository
    private let userPrefs: UserPreferencesRepository
    private let sessionLock: any SessionLockQuerying
    private let integrityQuarantine: VaultIntegrityQuarantineStore
    private let mutationGate: StorageMutationGate
    private let crossStoreJournal: any CrossStoreTransactionJournalStoring
    private let importMutationObserver: @Sendable (SecureBackupImportMutation) throws -> Void
    /// Actor methods are re-entrant at every repository/Keychain await. Keep
    /// backup export/import from observing one another's provisional state.
    private var backupMutationLocked = false
    private var backupMutationWaiters: [CheckedContinuation<Void, Never>] = []
    private var activeStoragePermit: StorageMutationPermit?
    private var activeExclusiveStoragePermit: StorageExclusiveMutationPermit?
    private var backupMutationGateFailure: ApiRelayError?

    init(
        gate: RevealGateServing,
        keychain: KeychainStoring,
        modelContainer: ModelContainer,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock(),
        integrityQuarantine: VaultIntegrityQuarantineStore = .shared,
        mutationGate: StorageMutationGate = StorageMutationGate(),
        crossStoreJournal: any CrossStoreTransactionJournalStoring = DurableCrossStoreTransactionJournal(),
        importMutationObserver: @escaping @Sendable (SecureBackupImportMutation) throws -> Void = { _ in }
    ) {
        self.gate = gate
        self.keychain = keychain
        self.accounts = UpstreamAccountRepository(modelContainer: modelContainer)
        self.keys = APIKeyRecordRepository(modelContainer: modelContainer)
        self.tools = ConsumerToolRepository(modelContainer: modelContainer)
        self.assignments = KeyAssignmentRepository(modelContainer: modelContainer)
        self.userPrefs = UserPreferencesRepository(modelContainer: modelContainer)
        self.sessionLock = sessionLock
        self.integrityQuarantine = integrityQuarantine
        self.mutationGate = mutationGate
        self.crossStoreJournal = crossStoreJournal
        self.importMutationObserver = importMutationObserver
    }

    private func ensureStorageIntegrity() throws {
        if let backupMutationGateFailure {
            throw backupMutationGateFailure
        }
        if let incident = integrityQuarantine.currentIncident() {
            throw ApiRelayError.storageIntegrityQuarantined(
                operation: incident.operation,
                detail: incident.detail
            )
        }
    }

    private func repositoryCommit(
        _ authorization: SessionAuthorizationLease,
        mutation: SecureBackupImportMutation
    ) -> RepositoryCommit {
        let storagePermitted = activeStoragePermit != nil || activeExclusiveStoragePermit != nil
        return { [sessionLock, integrityQuarantine, importMutationObserver] operation in
            guard storagePermitted else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "backup_repository_commit",
                    detail: "erase_in_progress"
                )
            }
            if let incident = integrityQuarantine.currentIncident() {
                throw ApiRelayError.storageIntegrityQuarantined(
                    operation: incident.operation,
                    detail: incident.detail
                )
            }
            try importMutationObserver(mutation)
            try sessionLock.commitAuthorizationLease(authorization, operation: operation)
        }
    }

    /// Compensation must survive a session-lock transition that invalidated the
    /// forward lease. It is still serialized under the same backup mutation
    /// permit and may only restore/delete objects created by this import.
    private func compensationRepositoryCommit(
        _ mutation: SecureBackupImportMutation
    ) -> RepositoryCommit {
        let storagePermitted = activeStoragePermit != nil || activeExclusiveStoragePermit != nil
        return { [importMutationObserver] operation in
            guard storagePermitted else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "backup_import_compensation",
                    detail: "erase_in_progress"
                )
            }
            try importMutationObserver(mutation)
            try operation()
        }
    }

    private func keychainCommit(
        _ authorization: SessionAuthorizationLease
    ) -> KeychainCommit {
        let storagePermitted = activeStoragePermit != nil || activeExclusiveStoragePermit != nil
        return { [sessionLock, integrityQuarantine] operation in
            guard storagePermitted else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "backup_keychain_commit",
                    detail: "erase_in_progress"
                )
            }
            if let incident = integrityQuarantine.currentIncident() {
                throw ApiRelayError.storageIntegrityQuarantined(
                    operation: incident.operation,
                    detail: incident.detail
                )
            }
            try sessionLock.commitAuthorizationLease(authorization, operation: operation)
        }
    }

    private func journaledRepositoryCommit(
        _ authorization: SessionAuthorizationLease,
        mutation: SecureBackupImportMutation,
        plan: @escaping @Sendable () throws -> Void
    ) -> RepositoryCommit {
        let authorizedCommit = repositoryCommit(authorization, mutation: mutation)
        return { operation in
            try authorizedCommit {
                try plan()
                try operation()
            }
        }
    }

    private func acquireBackupSerialization() async {
        if !backupMutationLocked {
            backupMutationLocked = true
        } else {
            await withCheckedContinuation { continuation in
                backupMutationWaiters.append(continuation)
            }
        }
    }

    private func acquireBackupMutation() async {
        await acquireBackupSerialization()
        activeStoragePermit = nil
        activeExclusiveStoragePermit = nil
        backupMutationGateFailure = nil
        do {
            activeStoragePermit = try mutationGate.beginNormal(operation: "secure_backup")
        } catch let error as ApiRelayError {
            backupMutationGateFailure = error
        } catch {
            backupMutationGateFailure = .storageRecoveryFailed(
                operation: "secure_backup",
                detail: "gate_failure"
            )
        }
    }

    private func acquireExclusiveBackupMutation(operation: String) async {
        await acquireBackupSerialization()
        activeStoragePermit = nil
        activeExclusiveStoragePermit = nil
        backupMutationGateFailure = nil
        do {
            activeExclusiveStoragePermit = try await mutationGate.beginExclusive(
                operation: operation
            )
        } catch let error as ApiRelayError {
            backupMutationGateFailure = error
        } catch {
            backupMutationGateFailure = .storageRecoveryFailed(
                operation: operation,
                detail: "gate_failure"
            )
        }
    }

    /// The only backup serializer entry that bypasses a normal write permit.
    /// It cannot be invoked without a live capability from this shared gate.
    private func acquireCommittedEraseMutation(
        _ authorization: CommittedEraseToken
    ) async throws {
        await acquireBackupSerialization()
        activeStoragePermit = nil
        activeExclusiveStoragePermit = nil
        backupMutationGateFailure = nil
        do {
            try mutationGate.validateCommittedEraseToken(
                authorization,
                operation: "secure_backup_committed_erase"
            )
        } catch {
            releaseBackupMutation()
            throw error
        }
    }

    private func releaseBackupMutation() {
        activeStoragePermit?.finish()
        activeStoragePermit = nil
        activeExclusiveStoragePermit?.finish()
        activeExclusiveStoragePermit = nil
        backupMutationGateFailure = nil
        guard !backupMutationWaiters.isEmpty else {
            backupMutationLocked = false
            return
        }
        backupMutationWaiters.removeFirst().resume()
    }

    func inspectProtection(_ data: Data) throws -> BackupFileProtection {
        if data.starts(with: SecureBackupFile.passphraseMagic) {
            return .passphraseProtected
        }
        if data.starts(with: SecureBackupFile.unprotectedMagic) {
            return .unprotected
        }
        throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
    }

    func exportBackup(passphrase: String? = nil, purpose: BackupPurpose = .fullBackup, appPassword: String? = nil) async throws -> BackupExportResult {
        try ensureStorageIntegrity()
        let authorization = try sessionLock.captureAuthorizationLease()
        try await confirmCurrent(
            reason: String(localized: "gate.exportBackup"),
            purpose: .destructive,
            appPassword: appPassword
        )
        await acquireBackupMutation()
        defer { releaseBackupMutation() }
        try ensureStorageIntegrity()
        try sessionLock.validateAuthorizationLease(authorization)
        let encoded = try await encodeVaultJSON(purpose: purpose, authorization: authorization)
        let data: Data
        if let passphrase {
            let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ApiRelayError.validationFailed(field: "backupPassphrase", reason: "empty")
            }
            data = try Self.encrypt(encoded.json, passphrase: trimmed)
        } else {
            var out = Data()
            out.append(SecureBackupFile.unprotectedMagic)
            out.append(encoded.json)
            data = out
        }
        try ensureStorageIntegrity()
        try sessionLock.validateAuthorizationLease(authorization)
        return BackupExportResult(
            data: data,
            keysWithoutSecretCount: encoded.keysWithoutSecretCount
        )
    }

    func importBackup(data: Data, passphrase: String?, appPassword: String? = nil) async throws -> ImportSummary {
        try ensureStorageIntegrity()
        let authorization = try sessionLock.captureAuthorizationLease()
        try await confirmCurrent(
            reason: String(localized: "gate.importBackup"),
            purpose: .destructive,
            appPassword: appPassword
        )
        let json: Data
        switch try inspectProtection(data) {
        case .unprotected:
            json = Data(data.dropFirst(SecureBackupFile.unprotectedMagic.count))
        case .passphraseProtected:
            let trimmed = passphrase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                throw ApiRelayError.backupPassphraseIncorrect
            }
            json = try Self.decrypt(data, passphrase: trimmed)
        }
        await acquireExclusiveBackupMutation(operation: "backup_import")
        defer { releaseBackupMutation() }
        try ensureStorageIntegrity()
        try sessionLock.validateAuthorizationLease(authorization)
        var transactionId: UUID?
        var completedSummary: ImportSummary?
        do {
            let begunTransactionId = try crossStoreJournal.begin(.backupImport)
            transactionId = begunTransactionId
            let summary = try await applyVaultJSON(
                json,
                authorization: authorization,
                transactionId: begunTransactionId
            )
            completedSummary = summary
            let notificationCommit = repositoryCommit(
                authorization,
                mutation: .notification
            )
            try notificationCommit {}
            try crossStoreJournal.decideCommit(transactionId: begunTransactionId)
            guard let committedRecord = try crossStoreJournal.load(),
                  committedRecord.transactionId == begunTransactionId,
                  committedRecord.phase == .commitDecided else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "backup_import_commit",
                    detail: "commit_decision_unavailable"
                )
            }
            try await finalizeCommittedBackupImport(committedRecord)
            try crossStoreJournal.clear(transactionId: begunTransactionId)
            await MainActor.run {
                NotificationCenter.default.post(name: .vaultDidImportBackup, object: nil)
            }
            return summary
        } catch let primary {
            if transactionId == nil {
                do {
                    if let record = try crossStoreJournal.load() {
                        guard record.kind == .backupImport,
                              record.phase == .applying,
                              record.insertedAccounts.isEmpty,
                              record.insertedTools.isEmpty,
                              record.insertedKeys.isEmpty,
                              record.insertedAssignments.isEmpty else {
                            throw ApiRelayError.storageRecoveryFailed(
                                operation: "backup_import_begin_recovery",
                                detail: "unexpected_marker"
                            )
                        }
                        try crossStoreJournal.clear(transactionId: record.transactionId)
                    }
                } catch let cleanupFailure {
                    mutationGate.sealForCrossStoreRecovery()
                    let detail = "primary=\(IdentityHygieneLog.typeName(primary));cleanup=\(IdentityHygieneLog.typeName(cleanupFailure))"
                    if (try? crossStoreJournal.load()) == nil {
                        integrityQuarantine.quarantine(
                            operation: "backup_import_begin",
                            detail: detail
                        )
                    }
                    throw ApiRelayError.storageRecoveryFailed(
                        operation: "backup_import_begin",
                        detail: detail
                    )
                }
                throw primary
            }
            do {
                guard let transactionId else { preconditionFailure("checked above") }
                guard let record = try crossStoreJournal.load(),
                      record.transactionId == transactionId,
                      record.kind == .backupImport else {
                    throw ApiRelayError.storageRecoveryFailed(
                        operation: "backup_import_recovery",
                        detail: "journal_unavailable"
                    )
                }
                switch record.phase {
                case .applying:
                    try await rollbackInterruptedBackupImport(record)
                    try crossStoreJournal.clear(transactionId: transactionId)
                case .commitDecided:
                    try await finalizeCommittedBackupImport(record)
                    try crossStoreJournal.clear(transactionId: transactionId)
                    guard let completedSummary else {
                        throw ApiRelayError.storageRecoveryFailed(
                            operation: "backup_import_commit",
                            detail: "summary_unavailable"
                        )
                    }
                    await MainActor.run {
                        NotificationCenter.default.post(name: .vaultDidImportBackup, object: nil)
                    }
                    return completedSummary
                case .completed:
                    // The import or its compensation already reached its
                    // durable outcome; only the tombstone unlink was pending.
                    try crossStoreJournal.clear(transactionId: transactionId)
                    guard let completedSummary else {
                        throw ApiRelayError.storageRecoveryFailed(
                            operation: "backup_import_commit",
                            detail: "summary_unavailable"
                        )
                    }
                    await MainActor.run {
                        NotificationCenter.default.post(name: .vaultDidImportBackup, object: nil)
                    }
                    return completedSummary
                }
            } catch let compensation {
                mutationGate.sealForCrossStoreRecovery()
                let detail = "primary=\(IdentityHygieneLog.typeName(primary));compensation=\(IdentityHygieneLog.typeName(compensation))"
                if (try? crossStoreJournal.load()) == nil {
                    integrityQuarantine.quarantine(
                        operation: "backup_import",
                        detail: detail
                    )
                }
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "backup_import",
                    detail: detail
                )
            }
            throw primary
        }
    }

    /// Full erase has already crossed its single authorization boundary and
    /// sealed the shared mutation gate before entering here. Serialize behind
    /// any earlier backup transaction, then purge through the exact ModelActors
    /// this service will keep using after erase. Opening a fresh ModelContext is
    /// insufficient because these actors may otherwise continue serving their
    /// registered pre-erase objects.
    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws {
        try await acquireCommittedEraseMutation(authorization)
        defer { releaseBackupMutation() }
        try await assignments.deleteAllRecords()
        try await keys.deleteAllRecords()
        try await accounts.deleteAllRecords()
        try await tools.deleteAllRecords()
        try await userPrefs.deleteAllRecords()
    }

    private func encodeVaultJSON(
        purpose: BackupPurpose,
        authorization: SessionAuthorizationLease
    ) async throws -> (json: Data, keysWithoutSecretCount: Int) {
        try ensureStorageIntegrity()
        let accountDTOs = try await accounts.fetchAll()
        let keyDTOs = try await keys.fetch(lifecycles: [.active, .revokedUpstream])
        let toolDTOs = try await tools.fetchAll(includeHidden: true, includeDeleted: false)
        try ensureStorageIntegrity()

        var keyPayloads: [[String: Any]] = []
        var assignmentPayloads: [[String: Any]] = []
        var keysWithoutSecretCount = 0
        for key in keyDTOs {
            try ensureStorageIntegrity()
            try sessionLock.validateAuthorizationLease(authorization)
            let secret: String
            do {
                secret = try await keychain.read(service: .keys, account: key.id)
            } catch ApiRelayError.keychainFailure(let status) where status == errSecItemNotFound {
                // Metadata can legitimately outlive its synchronised Keychain item on this
                // device. Preserve that established, visible "missing secret" representation.
                secret = ""
            }
            try ensureStorageIntegrity()
            try sessionLock.validateAuthorizationLease(authorization)
            if secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                keysWithoutSecretCount += 1
            }
            keyPayloads.append(
                Self.compact([
                    "id": key.id.uuidString,
                    "accountId": key.accountId.uuidString,
                    "displayName": key.displayName,
                    "secret": secret,
                    "lifecycle": key.lifecycle.rawValue,
                    "origin": key.origin.rawValue,
                    "notes": key.notes,
                    "sortOrder": key.sortOrder,
                    "avatarSymbol": key.avatarSymbol,
                    "avatarColor": key.avatarColor,
                ])
            )
            for toolId in key.consumerToolIds {
                assignmentPayloads.append([
                    "keyId": key.id.uuidString,
                    "consumerToolId": toolId.uuidString,
                ])
            }
        }

        let plaintext: [String: Any] = [
            "version": 1,
            "purpose": purpose.rawValue,
            "scope": ["keyIds": keyDTOs.map(\.id.uuidString)],
            "accounts": accountDTOs.map {
                Self.compact([
                    "id": $0.id.uuidString,
                    "platform": $0.platform,
                    "customPlatformName": $0.customPlatformName,
                    "displayName": $0.displayName,
                    "customBaseURL": $0.customBaseURL,
                    "notes": $0.notes,
                    "sortOrder": $0.sortOrder,
                    "avatarSymbol": $0.avatarSymbol,
                    "avatarColor": $0.avatarColor,
                ])
            },
            "keys": keyPayloads,
            "tools": toolDTOs.map {
                Self.compact([
                    "id": $0.id.uuidString,
                    "name": $0.name,
                    "iconSymbol": $0.iconSymbol,
                    "avatarSymbol": $0.avatarSymbol,
                    "avatarColor": $0.avatarColor,
                    "isPreset": $0.isPreset,
                    "isHidden": $0.isHidden,
                    "notes": $0.notes,
                    "sortOrder": $0.sortOrder,
                ])
            },
            "assignments": assignmentPayloads,
        ]
        let json = try JSONSerialization.data(withJSONObject: plaintext, options: [.sortedKeys])
        try ensureStorageIntegrity()
        try sessionLock.validateAuthorizationLease(authorization)
        return (json, keysWithoutSecretCount)
    }

    private func applyVaultJSON(
        _ json: Data,
        authorization: SessionAuthorizationLease,
        transactionId: UUID
    ) async throws -> ImportSummary {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let version = root["version"] as? Int,
              version == 1,
              let purposeRaw = root["purpose"] as? String,
              let purpose = BackupPurpose(rawValue: purposeRaw),
              let accountsArr = root["accounts"] as? [[String: Any]],
              let keysArr = root["keys"] as? [[String: Any]] else {
            let found = (try? JSONSerialization.jsonObject(with: json) as? [String: Any])
                .flatMap { $0["version"] as? Int } ?? 0
            throw ApiRelayError.backupVersionUnsupported(found: found, supported: 1)
        }
        let toolsArr = root["tools"] as? [[String: Any]] ?? []
        let assignmentsArr = root["assignments"] as? [[String: Any]] ?? []

        try ensureStorageIntegrity()
        var importedAccounts = 0
        var importedTools = 0
        var importedKeys = 0
        var skippedKeys = 0
        var keysWithoutSecret = 0

        for account in accountsArr {
            try ensureStorageIntegrity()
            guard let id = Self.uuid(account["id"]),
                  let platform = account["platform"] as? String,
                  let displayName = account["displayName"] as? String else { continue }
            let draft = UpstreamAccountDraft(
                platform: platform,
                customPlatformName: account["customPlatformName"] as? String,
                displayName: displayName,
                customBaseURL: account["customBaseURL"] as? String,
                notes: account["notes"] as? String,
                sortOrder: account["sortOrder"] as? Int ?? 0,
                avatarSymbol: account["avatarSymbol"] as? String,
                avatarColor: account["avatarColor"] as? String
            )
            let createdAt = Date()
            let plan = CrossStoreInsertedRecordPlan(id: id, createdAt: createdAt)
            if try await accounts.insertIfAbsent(
                draft,
                id: id,
                createdAt: createdAt,
                committing: journaledRepositoryCommit(
                    authorization,
                    mutation: .accountInsert,
                    plan: { [crossStoreJournal] in
                        try crossStoreJournal.planInsertedAccount(
                            plan,
                            transactionId: transactionId
                        )
                    }
                )
            ) {
                importedAccounts += 1
            }
        }

        for tool in toolsArr {
            try ensureStorageIntegrity()
            guard let id = Self.uuid(tool["id"]),
                  let name = tool["name"] as? String else { continue }
            let draft = ConsumerToolDraft(
                name: name,
                iconSymbol: tool["iconSymbol"] as? String,
                isPreset: false,
                notes: tool["notes"] as? String,
                sortOrder: tool["sortOrder"] as? Int ?? 0,
                avatarSymbol: tool["avatarSymbol"] as? String,
                avatarColor: tool["avatarColor"] as? String
            )
            let createdAt = Date()
            let plan = CrossStoreInsertedRecordPlan(id: id, createdAt: createdAt)
            guard try await tools.insertIfAbsent(
                draft,
                id: id,
                createdAt: createdAt,
                committing: journaledRepositoryCommit(
                    authorization,
                    mutation: .toolInsert,
                    plan: { [crossStoreJournal] in
                        try crossStoreJournal.planInsertedTool(
                            plan,
                            transactionId: transactionId
                        )
                    }
                )
            ) else { continue }
            if tool["isHidden"] as? Bool == true {
                try await tools.update(
                    id: id,
                    patch: ConsumerToolPatch(isHidden: true),
                    committing: repositoryCommit(authorization, mutation: .toolUpdate)
                )
            }
            importedTools += 1
        }

        for key in keysArr {
            try ensureStorageIntegrity()
            guard let id = Self.uuid(key["id"]),
                  let accountId = Self.uuid(key["accountId"]),
                  let displayName = key["displayName"] as? String else {
                skippedKeys += 1
                continue
            }
            guard try await accounts.fetch(id: accountId) != nil else {
                skippedKeys += 1
                continue
            }
            guard try await keys.storageSnapshot(id: id) == nil else {
                skippedKeys += 1
                continue
            }
            let secret = (key["secret"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Metadata-absent + Keychain-present is an orphan or a remote item
            // still converging. Restore metadata only when a non-empty backup
            // secret proves it is the same logical key. An empty or conflicting
            // payload must not make an otherwise unreachable local secret
            // visible merely by supplying its UUID.
            var secretAlreadyPresent = false
            do {
                let existingSecret = try await keychain.read(service: .keys, account: id)
                guard !secret.isEmpty, existingSecret == secret else {
                    skippedKeys += 1
                    continue
                }
                secretAlreadyPresent = true
            } catch let ApiRelayError.keychainFailure(status) where status == errSecItemNotFound {
                // Safe to attempt the later atomic add when the backup contains
                // plaintext, or to restore metadata as explicitly secret-less.
            }
            let origin = (key["origin"] as? String)
                .flatMap(KeyOrigin.init(rawValue:)) ?? .manualEntry
            let draft = KeyRecordDraft(
                accountId: accountId,
                displayName: displayName,
                origin: origin,
                notes: key["notes"] as? String,
                sortOrder: key["sortOrder"] as? Int ?? 0,
                avatarSymbol: key["avatarSymbol"] as? String,
                avatarColor: key["avatarColor"] as? String
            )
            let createdAt = Date()
            let plan = CrossStoreKeyRollbackPlan(
                id: id,
                accountId: accountId,
                createdAt: createdAt
            )
            guard try await keys.insertIfAbsent(
                draft,
                id: id,
                createdAt: createdAt,
                committing: journaledRepositoryCommit(
                    authorization,
                    mutation: .keyInsert,
                    plan: { [crossStoreJournal] in
                        try crossStoreJournal.planInsertedKey(
                            plan,
                            transactionId: transactionId
                        )
                    }
                )
            ) else {
                skippedKeys += 1
                continue
            }
            if let lifecycleRaw = key["lifecycle"] as? String,
               let lifecycle = KeyLifecycle.init(rawValue: lifecycleRaw),
               lifecycle != .active {
                try await keys.update(
                    id: id,
                    patch: KeyRecordPatch(lifecycle: lifecycle),
                    committing: repositoryCommit(authorization, mutation: .keyUpdate)
                )
            }
            if secret.isEmpty {
                keysWithoutSecret += 1
            } else if !secretAlreadyPresent {
                let inserted = try await keychain.insertIfAbsent(
                    secret,
                    service: .keys,
                    account: id,
                    transactionTag: transactionId,
                    committing: keychainCommit(authorization)
                )
                if !inserted {
                    // A synchronised item won the race after the preflight.
                    // Accept it only if it is byte-for-byte the same logical
                    // secret. Otherwise rollback the metadata rather than bind
                    // a conflicting orphan to this record.
                    let racedSecret = try await keychain.read(service: .keys, account: id)
                    guard racedSecret == secret else {
                        throw ApiRelayError.storageRecoveryFailed(
                            operation: "backup_import",
                            detail: "keychain_account_conflict"
                        )
                    }
                }
            }
            try ensureStorageIntegrity()
            try sessionLock.validateAuthorizationLease(authorization)
            importedKeys += 1
        }

        for row in assignmentsArr {
            try ensureStorageIntegrity()
            guard let keyId = Self.uuid(row["keyId"]),
                  let toolId = Self.uuid(row["consumerToolId"]) else { continue }
            guard try await keys.fetch(id: keyId) != nil else { continue }
            guard try await tools.fetch(id: toolId) != nil else { continue }
            let createdAt = Date()
            let plan = CrossStoreAssignmentRollbackPlan(
                keyId: keyId,
                consumerToolId: toolId,
                createdAt: createdAt
            )
            _ = try await assignments.add(
                keyId: keyId,
                consumerToolId: toolId,
                createdAt: createdAt,
                committing: journaledRepositoryCommit(
                    authorization,
                    mutation: .assignmentAdd,
                    plan: { [crossStoreJournal] in
                        try crossStoreJournal.planInsertedAssignment(
                            plan,
                            transactionId: transactionId
                        )
                    }
                )
            )
        }
        try ensureStorageIntegrity()
        return ImportSummary(
            accountCount: importedAccounts,
            keyCount: importedKeys,
            toolCount: importedTools,
            skippedKeyCount: skippedKeys,
            keysWithoutSecretCount: keysWithoutSecret,
            purpose: purpose
        )
    }

    /// Idempotent WAL rollback. Ownership timestamps ensure a same-id CloudKit
    /// replica is never deleted, and Keychain plaintext is removed only when
    /// the item still carries this transaction's tag.
    private func rollbackInterruptedBackupImport(
        _ record: CrossStoreTransactionRecord
    ) async throws {
        try record.validateForRecovery()
        guard record.kind == .backupImport, record.phase == .applying else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "backup_import_recovery",
                detail: "unexpected_transaction_kind"
            )
        }
        for plan in record.insertedAssignments.reversed() {
            _ = try await assignments.removeIfCreatedAtMatches(
                keyId: plan.keyId,
                consumerToolId: plan.consumerToolId,
                createdAt: plan.createdAt,
                committing: compensationRepositoryCommit(.assignmentCompensation)
            )
        }
        for plan in record.insertedKeys.reversed() {
            _ = try await keys.deleteIfCreatedAtMatches(
                id: plan.id,
                createdAt: plan.createdAt,
                committing: compensationRepositoryCommit(.keyCompensation)
            )
            _ = try await keychain.deleteIfTransactionTagMatches(
                service: .keys,
                account: plan.id,
                transactionTag: record.transactionId
            )
        }
        for plan in record.insertedTools.reversed() {
            _ = try await tools.deleteIfCreatedAtMatches(
                id: plan.id,
                createdAt: plan.createdAt,
                committing: compensationRepositoryCommit(.toolCompensation)
            )
        }
        for plan in record.insertedAccounts.reversed() {
            _ = try await accounts.deleteIfCreatedAtMatches(
                id: plan.id,
                createdAt: plan.createdAt,
                committing: compensationRepositoryCommit(.accountCompensation)
            )
        }
    }

    private func finalizeCommittedBackupImport(
        _ record: CrossStoreTransactionRecord
    ) async throws {
        try record.validateForRecovery()
        guard record.kind == .backupImport, record.phase == .commitDecided else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "backup_import_finalize",
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

    /// Startup-only replay while the composition-root gate is pre-sealed.
    func recoverInterruptedCrossStoreTransaction(
        _ record: CrossStoreTransactionRecord
    ) async throws {
        guard record.kind == .backupImport else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "backup_import_recovery",
                detail: "unexpected_transaction_kind"
            )
        }
        await acquireBackupSerialization()
        activeStoragePermit = nil
        activeExclusiveStoragePermit = nil
        backupMutationGateFailure = nil
        do {
            activeExclusiveStoragePermit = try await mutationGate.beginCrossStoreRecoveryExclusive(
                operation: "backup_import_recovery"
            )
            guard let currentRecord = try crossStoreJournal.load(),
                  currentRecord == record else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "backup_import_recovery",
                    detail: "stale_recovery_record"
                )
            }
            switch currentRecord.phase {
            case .applying:
                try await rollbackInterruptedBackupImport(currentRecord)
            case .commitDecided:
                try await finalizeCommittedBackupImport(currentRecord)
            case .completed:
                break
            }
            try crossStoreJournal.clear(transactionId: currentRecord.transactionId)
            activeExclusiveStoragePermit?.finish()
            activeExclusiveStoragePermit = nil
            try mutationGate.completeCrossStoreRecoveryAndReopen()
            releaseBackupMutation()
            await MainActor.run {
                NotificationCenter.default.post(name: .vaultDidImportBackup, object: nil)
            }
        } catch {
            mutationGate.sealForCrossStoreRecovery()
            releaseBackupMutation()
            throw ApiRelayError.storageRecoveryFailed(
                operation: "backup_import_startup_recovery",
                detail: "cause=\(IdentityHygieneLog.typeName(error))"
            )
        }
    }

    private static func compact(_ pairs: [String: Any?]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in pairs {
            if let value {
                out[key] = value
            }
        }
        return out
    }

    private static func uuid(_ value: Any?) -> UUID? {
        guard let raw = value as? String else { return nil }
        return UUID(uuidString: raw)
    }

    private static func encrypt(_ data: Data, passphrase: String) throws -> Data {
        let salt = try randomSalt()
        let iterations = SecureBackupFile.kdfIterations
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw ApiRelayError.validationFailed(field: "backup", reason: "seal_failed")
        }
        var out = Data()
        out.append(SecureBackupFile.passphraseMagic)
        out.append(salt)
        var iterationsBE = iterations.bigEndian
        withUnsafeBytes(of: &iterationsBE) { out.append(contentsOf: $0) }
        out.append(combined)
        return out
    }

    private static func decrypt(_ data: Data, passphrase: String) throws -> Data {
        let magic = SecureBackupFile.passphraseMagic
        let headerCount = magic.count + 16 + 4
        guard data.count > headerCount + 28, data.prefix(magic.count) == magic else {
            throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
        }
        let salt = data.subdata(in: magic.count..<(magic.count + 16))
        let iterationsRange = (magic.count + 16)..<(magic.count + 20)
        var iterationsBE: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &iterationsBE) { buffer in
            data.copyBytes(to: buffer, from: iterationsRange)
        }
        let iterations = UInt32(bigEndian: iterationsBE)
        guard iterations >= 10_000, iterations <= 2_000_000 else {
            throw ApiRelayError.backupVersionUnsupported(found: 0, supported: 1)
        }
        let sealedData = data.subdata(in: headerCount..<data.count)
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: sealedData)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw ApiRelayError.backupPassphraseIncorrect
        }
    }

    private func confirmCurrent(
        reason: String,
        purpose: AuthPurpose,
        appPassword: String?
    ) async throws {
        let policy: RevealPolicy
        do {
            let storagePermit = try mutationGate.beginNormal(
                operation: "backup_auth_policy_read"
            )
            defer { storagePermit.finish() }
            policy = try await userPrefs.loadOrCreate().revealPolicy
        }
        try await CurrentRevealPolicyAuth.confirm(
            policy,
            gate: gate,
            reason: reason,
            purpose: purpose,
            appPassword: appPassword
        )
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordData = Data(passphrase.utf8)
        var derived = Data(count: 32)
        let result = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                passwordData.withUnsafeBytes { passPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedPtr.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        guard result == kCCSuccess else {
            throw ApiRelayError.validationFailed(field: "backup", reason: "pbkdf2_failed")
        }
        return SymmetricKey(data: derived)
    }

    private static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw ApiRelayError.keychainFailure(status)
        }
        return Data(bytes)
    }
}
