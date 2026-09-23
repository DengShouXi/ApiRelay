import Foundation
import SwiftData

protocol DataLifecycleServing: Actor {
    nonisolated func hasPendingErase() -> Bool
    func eraseAllUserData(appPassword: String?) async throws
    /// Last-resort recovery for a durable cross-store marker that cannot be
    /// replayed. The implementation must require device-owner authentication
    /// before allowing the committed erase to supersede that marker.
    func eraseAllUserDataForStorageRecovery() async throws
}

extension DataLifecycleServing {
    func eraseAllUserData() async throws {
        try await eraseAllUserData(appPassword: nil)
    }
}

extension Notification.Name {
    /// 持久清除事务开始、失败保持 pending，或最终完成时发出。根视图据此立即
    /// 重读 journal/gate 并切换不透明恢复层，不能等普通业务页面恰好刷新。
    static let userDataEraseRecoveryStateDidChange = Notification.Name(
        "com.apirelay.userDataEraseRecoveryStateDidChange"
    )
    /// 「清除全部数据」完成后发出；主列表 / 回收站据此丢掉内存缓存。
    static let userDataDidErase = Notification.Name("com.apirelay.userDataDidErase")
}

actor DataLifecycleService: DataLifecycleServing {
    private let gate: RevealGateServing
    private let keychain: KeychainStoring
    private let modelContainer: ModelContainer
    private let vault: KeyVaultServing
    private let consumerTools: ConsumerToolServing
    private let backups: any SecureBackupServing
    private let preferences: PreferencesServing
    private let entitlements: EntitlementServing
    private let clipboard: (any ClipboardServing)?
    private let sessionLock: any SessionLockQuerying
    private let eraseJournal: any DataEraseJournalStoring
    private let crossStoreJournal: any CrossStoreTransactionJournalStoring
    private let mutationGate: StorageMutationGate
    private let integrityQuarantine: VaultIntegrityQuarantineStore
    private let cloudEraseConvergence: (any CloudEraseConverging)?
    private let keychainConvergenceGrace: Duration
    private let maxKeychainConvergencePasses: Int
    private var eraseInFlight = false

    init(
        gate: RevealGateServing,
        keychain: KeychainStoring,
        modelContainer: ModelContainer,
        vault: KeyVaultServing,
        consumerTools: ConsumerToolServing,
        backups: any SecureBackupServing,
        preferences: PreferencesServing,
        entitlements: EntitlementServing,
        clipboard: (any ClipboardServing)? = nil,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock(),
        eraseJournal: any DataEraseJournalStoring = DurableDataEraseJournal(),
        crossStoreJournal: any CrossStoreTransactionJournalStoring = DurableCrossStoreTransactionJournal(),
        mutationGate: StorageMutationGate = StorageMutationGate(),
        integrityQuarantine: VaultIntegrityQuarantineStore = .shared,
        cloudEraseConvergence: (any CloudEraseConverging)? = nil,
        keychainConvergenceGrace: Duration = .zero,
        maxKeychainConvergencePasses: Int = 8
    ) {
        precondition(maxKeychainConvergencePasses >= 2)
        self.gate = gate
        self.keychain = keychain
        self.modelContainer = modelContainer
        self.vault = vault
        self.consumerTools = consumerTools
        self.backups = backups
        self.preferences = preferences
        self.entitlements = entitlements
        self.clipboard = clipboard
        self.sessionLock = sessionLock
        self.eraseJournal = eraseJournal
        self.crossStoreJournal = crossStoreJournal
        self.mutationGate = mutationGate
        self.integrityQuarantine = integrityQuarantine
        self.cloudEraseConvergence = cloudEraseConvergence
        self.keychainConvergenceGrace = keychainConvergenceGrace
        self.maxKeychainConvergencePasses = maxKeychainConvergencePasses
    }

    nonisolated func hasPendingErase() -> Bool {
        eraseJournal.hasPendingErase() || mutationGate.isEraseSealed()
    }

    func eraseAllUserData(appPassword: String?) async throws {
        try await eraseAllUserData(
            appPassword: appPassword,
            supersedingCrossStoreRecovery: false
        )
    }

    func eraseAllUserDataForStorageRecovery() async throws {
        try await eraseAllUserData(
            appPassword: nil,
            supersedingCrossStoreRecovery: true
        )
    }

    private func eraseAllUserData(
        appPassword: String?,
        supersedingCrossStoreRecovery: Bool
    ) async throws {
        guard !eraseInFlight else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "erase_all_user_data",
                detail: "erase_already_running"
            )
        }
        eraseInFlight = true
        defer { eraseInFlight = false }

        // A journal-clear fsync failure can leave this process sealed even when
        // the marker is currently absent. Treat either signal as recovery work;
        // replaying every idempotent stage is safer than reopening around an
        // uncertain on-disk state.
        let isResumingInterruptedErase = hasPendingErase()
        let crossStoreRecoveryPending = crossStoreJournal.hasPendingTransaction()
            || mutationGate.isCrossStoreRecoverySealed()
        if supersedingCrossStoreRecovery,
           !isResumingInterruptedErase,
           !crossStoreRecoveryPending {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "erase_all_user_data",
                detail: "cross_store_recovery_not_pending"
            )
        }
        let usesRecoveryAuthorization = isResumingInterruptedErase
            || supersedingCrossStoreRecovery
        let authorization = try usesRecoveryAuthorization
            ? sessionLock.captureEraseRecoveryLease()
            : sessionLock.captureAuthorizationLease()
        if usesRecoveryAuthorization {
            // An earlier pass may already have deleted masterpw/backuppw. The
            // synced reveal policy can still say "app password"; a broken
            // cross-store marker can also prevent reading that policy. Recovery
            // therefore uses device-owner authentication rather than an
            // unavailable application credential.
            try await gate.confirmMandatory(
                reason: String(localized: "gate.eraseAll"),
                purpose: .recovery
            )
        } else {
            let prefs = try await preferences.load()
            try await CurrentRevealPolicyAuth.confirm(
                prefs.revealPolicy,
                gate: gate,
                reason: String(localized: "gate.eraseAll"),
                purpose: .destructive,
                appPassword: appPassword
            )
        }
        // This is the transaction's single authorization boundary. If a
        // background/lock event wins first, no journal or deletion is written.
        // If this commit wins first, erase is intentionally irreversible and
        // continues despite later session invalidation. A crash/storage error
        // leaves the persistent stage for an authenticated, idempotent retry.
        var createdEraseSeal = false
        let commitAuthorization: (_ operation: () throws -> Void) throws -> Void = { operation in
            if usesRecoveryAuthorization {
                try self.sessionLock.commitEraseRecoveryLease(
                    authorization,
                    operation: operation
                )
            } else {
                try self.sessionLock.commitAuthorizationLease(
                    authorization,
                    operation: operation
                )
            }
        }
        do {
            try commitAuthorization {
                createdEraseSeal = try mutationGate.sealForErase(
                    resumingInterruptedErase: usesRecoveryAuthorization
                )
                do {
                    try eraseJournal.mark(.authorized)
                } catch {
                    // Atomic rename may already have committed the marker before a
                    // directory-fsync error was reported. Only reopen if absence is
                    // positively observable; otherwise recovery must remain sealed.
                    if !eraseJournal.hasPendingErase() {
                        mutationGate.abortNewSealAfterJournalFailure(createdEraseSeal)
                    }
                    throw error
                }
            }
        } catch {
            if hasPendingErase() {
                await publishEraseRecoveryStateChange()
            }
            throw error
        }
        // From this point on the app must be opaque even if a later storage or
        // CloudKit step fails. Publish before the first suspended deletion.
        await publishEraseRecoveryStateChange()
        // The capability is intentionally unavailable until both the session
        // authorization boundary and the durable erase marker have committed.
        // Every service-level write-fence bypass below must present this exact
        // gate/generation token.
        let committedEraseAuthorization = try mutationGate.mintCommittedEraseToken()
        // A writer that began before the seal may still be finishing a
        // cross-store compensation. Wait for that whole transaction before the
        // first deletion; writers that start after the seal are rejected.
        await mutationGate.waitUntilNormalMutationsDrain()

        do {
            try eraseJournal.mark(.keychain)
            for service: KeychainService in [.keys, .admin, .masterpw, .backuppw] {
                let accounts = try await keychain.listAccounts(service: service)
                for account in accounts {
                    try await keychain.delete(service: service, account: account)
                }
            }

            // 必须走各服务已持有的 ModelActor。另开 ModelContext 删除后，
            // 「按平台 / 按使用方」仍从旧上下文读出活跃密钥，看起来像只清了回收站。
            try eraseJournal.mark(.vault)
            try await vault.purgeAllRecordsForCommittedErase(
                authorization: committedEraseAuthorization
            )

            try eraseJournal.mark(.consumerTools)
            try await consumerTools.purgeAllRecordsForCommittedErase(
                authorization: committedEraseAuthorization
            )

            // SecureBackup owns its own long-lived repository actors. Purging
            // only the vault/tool services leaves those actors able to export a
            // stale pre-erase snapshot, so clear the exact contexts here too.
            try eraseJournal.mark(.backupContexts)
            try await backups.purgeAllRecordsForCommittedErase(
                authorization: committedEraseAuthorization
            )

            try eraseJournal.mark(.preferences)
            try await preferences.purgeAllRecordsForCommittedErase(
                authorization: committedEraseAuthorization
            )

            try eraseJournal.mark(.entitlements)
            try await entitlements.purgeLocalSnapshotForCommittedErase(
                authorization: committedEraseAuthorization
            )

            try eraseJournal.mark(.localSnapshots)
            let context = ModelContext(modelContainer)
            try context.deleteAllRecords(UsageSnapshot.self)
            try context.deleteAllRecords(BalanceSnapshot.self)
            try context.deleteAllRecords(PricingRule.self)

            try eraseJournal.mark(.clipboard)
            await clipboard?.clearIfStillOurs()

            if let cloudEraseConvergence {
                try eraseJournal.mark(.cloudConvergence)
                try await cloudEraseConvergence.finishAfterInitialPurge {
                    try await self.repurgeCloudSyncedRecords(
                        authorization: committedEraseAuthorization
                    )
                }
            }

            // iCloud Keychain is independent from SwiftData/CloudKit and has
            // no application-visible sync checkpoint. Re-enumerate every
            // service until the current device reports two consecutive empty
            // snapshots. An arrival during this bounded window is deleted by
            // the next pass; errors or sustained arrivals leave the durable
            // erase journal and mutation seal in place for authenticated retry.
            try eraseJournal.mark(.keychainConvergence)
            try await convergeCurrentlyVisibleKeychainItems()

            // A committed full erase supersedes any interrupted provisional
            // create/import transaction. Remove its marker only after every
            // protected store and both sync convergence passes are empty.
            try eraseJournal.mark(.crossStoreJournal)
            try crossStoreJournal.discardForCommittedErase(
                authorization: committedEraseAuthorization
            )

            try eraseJournal.mark(.notifying)
            // Quarantine survives every partial failure. Only a fully purged,
            // authenticated reset may reopen the application as clean state.
            try integrityQuarantine.clearAfterCommittedFullEraseDurably(
                authorization: committedEraseAuthorization
            )
            // Reopen only after the durable recovery marker is gone. If any
            // previous step fails, the gate remains sealed and the next launch
            // requires authenticated idempotent recovery.
            try eraseJournal.clear()
            try mutationGate.completeEraseAndReopen()
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .userDataEraseRecoveryStateDidChange,
                    object: nil
                )
                NotificationCenter.default.post(name: .userDataDidErase, object: nil)
            }
        } catch {
            let stage = eraseJournal.currentStage()?.rawValue ?? "unknown"
            throw ApiRelayError.storageRecoveryFailed(
                operation: "erase_all_user_data",
                detail: "stage=\(stage);cause=\(String(describing: type(of: error)))"
            )
        }
    }

    /// Re-sweep every long-lived ModelActor that can observe CloudKit-backed
    /// models. A new throwaway context cannot invalidate registered objects in
    /// the vault, tool, backup, or preferences actors.
    private func repurgeCloudSyncedRecords(
        authorization: CommittedEraseToken
    ) async throws {
        try await vault.purgeAllRecordsForCommittedErase(authorization: authorization)
        try await consumerTools.purgeAllRecordsForCommittedErase(authorization: authorization)
        try await backups.purgeAllRecordsForCommittedErase(authorization: authorization)
        try await preferences.purgeAllRecordsForCommittedErase(authorization: authorization)

        let context = ModelContext(modelContainer)
        try context.deleteAllRecords(UsageSnapshot.self)
        try context.deleteAllRecords(BalanceSnapshot.self)
        try context.deleteAllRecords(PricingRule.self)
    }

    /// Converges only entries that this device can currently enumerate. The
    /// platform exposes no iCloud Keychain quiescence primitive, so an offline
    /// peer can still publish an older synchronizable entry in the future. A
    /// cross-device permanent reset requires the V2 erase-generation/envelope
    /// design; this V1 fence must not be described as a distributed guarantee.
    private func convergeCurrentlyVisibleKeychainItems() async throws {
        var consecutiveEmptyPasses = 0

        for pass in 0..<maxKeychainConvergencePasses {
            var foundAny = false
            for service: KeychainService in [.keys, .admin, .masterpw, .backuppw] {
                let accounts = try await keychain.listAccounts(service: service)
                if !accounts.isEmpty { foundAny = true }
                for account in accounts {
                    try await keychain.delete(service: service, account: account)
                }
            }

            if foundAny {
                consecutiveEmptyPasses = 0
            } else {
                consecutiveEmptyPasses += 1
                if consecutiveEmptyPasses >= 2 { return }
            }

            if pass + 1 < maxKeychainConvergencePasses,
               keychainConvergenceGrace > .zero {
                try await Task.sleep(for: keychainConvergenceGrace)
            } else {
                await Task.yield()
            }
        }

        throw ApiRelayError.storageRecoveryFailed(
            operation: "erase_keychain_convergence",
            detail: "visible_items_did_not_quiesce"
        )
    }

    private func publishEraseRecoveryStateChange() async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .userDataEraseRecoveryStateDidChange,
                object: nil
            )
        }
    }
}
