import Foundation
import SwiftData
import SwiftUI
import Combine

/// 组装 Data / Business 依赖。不持有明文。
@MainActor
final class AppEnvironment: ObservableObject {
    let modelContainer: ModelContainer
    /// 组合根内部能力；UI 不得拿到可绕过业务门闩的 Keychain 引用。
    private let keychain: any KeychainStoring
    let masterPassword: any MasterPasswordServing
    let gate: any RevealGateServing
    let clipboard: any ClipboardServing
    let vault: any KeyVaultServing
    let consumerTools: any ConsumerToolServing
    let trashBatch: any RecentlyDeletedBatchServing
    let entitlements: any EntitlementServing
    let preferences: any PreferencesServing
    let backups: any SecureBackupServing
    let backupPassphrase: any BackupPassphraseServing
    let dataLifecycle: any DataLifecycleServing
    let cloudSync: any CloudSyncServing
    let appPrivacy: AppPrivacyController
    /// 强持有，避免导入清扫调度被释放。测试路径为 nil。
    private let cloudImportHygiene: CloudImportIdentityHygiene?
    private let cloudImportObserver: (any NSObjectProtocol)?
    /// Raw CloudKit import capture synchronously revokes old policy leases;
    /// authoritative reload is asynchronous but cannot reopen a stale revision.
    private let securityPolicyRefreshFence: SecurityPolicyRefreshNotificationFence?
    /// Production-only crash-recovery composition. All cross-store writers and
    /// full erase share these exact instances; previews keep them nil.
    private let crossStoreJournal: (any CrossStoreTransactionJournalStoring)?
    private let storageMutationGate: StorageMutationGate?
    private let crossStoreRecoveryHandler: (@Sendable (CrossStoreTransactionRecord) async throws -> Void)?

    /// 本机外观（DevicePreferences）；驱动根视图 `preferredColorScheme`。
    @Published private(set) var appearance: AppearancePreference = .system
    @Published private(set) var isRecoveringCrossStore = false
    @Published private(set) var crossStoreRecoveryError: String?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let isTesting = AppRuntime.isRunningTests
        // 正式路径：开启 keys/admin 的 iCloud 钥匙串同步；access group 与 entitlements 对齐。
        // 单测宿主常缺 sync entitlement → 关闭 synchronizable，避免 -34018。
        let keychain = KeychainStore(
            accessGroup: isTesting ? nil : KeychainAccessGroup.resolved,
            disableSynchronizableForTesting: isTesting,
            servicePrefix: isTesting ? KeychainStore.testServicePrefix : KeychainStore.productionServicePrefix
        )
        self.keychain = keychain
        let eraseJournal = DurableDataEraseJournal()
        let crossStoreJournal = DurableCrossStoreTransactionJournal()
        let erasePending = eraseJournal.hasPendingErase()
        let mutationGate = StorageMutationGate(
            erasePending: erasePending,
            crossStoreRecoveryPending: crossStoreJournal.hasPendingTransaction()
        )
        self.crossStoreJournal = crossStoreJournal
        self.storageMutationGate = mutationGate
        let master = MasterPasswordService(
            keychain: keychain,
            mutationGate: mutationGate
        )
        self.masterPassword = master
        let gate = RevealGate(masterPassword: master)
        self.gate = gate
        let clipboard = SecureClipboard(mutationGate: mutationGate)
        self.clipboard = clipboard
        let entitlements = EntitlementService(
            modelContainer: modelContainer,
            mutationGate: mutationGate
        )
        self.entitlements = entitlements
        let sessionLock = SessionLockBox()
        // 所有会读取或改写密钥关联数据的服务共享同一设备本地隔离标记；
        // 任一跨存储补偿失败后，组合根不得留下可绕过隔离的另一条业务路径。
        let integrityQuarantine = VaultIntegrityQuarantineStore.production(
            committedEraseGate: mutationGate
        )
        let vaultService = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: modelContainer,
            entitlements: entitlements,
            sessionLock: sessionLock,
            integrityQuarantine: integrityQuarantine,
            mutationGate: mutationGate,
            crossStoreJournal: crossStoreJournal
        )
        self.vault = vaultService
        self.consumerTools = ConsumerToolService(
            modelContainer: modelContainer,
            gate: gate,
            sessionLock: sessionLock,
            integrityQuarantine: integrityQuarantine,
            mutationGate: mutationGate
        )
        self.trashBatch = RecentlyDeletedBatchService(
            vault: self.vault,
            consumerTools: self.consumerTools,
            gate: gate,
            sessionLock: sessionLock
        )
        Task {
            await entitlements.startListening()
            // 启动时纠偏：以 StoreKit currentEntitlements 为准，清掉脏的本地 unlimited 快照。
            // 本地无限权益：Debug 下走付费墙正常购买（Scheme 已挂 ApiRelay.storekit）；不要启动参数后门。
            try? await entitlements.refreshFromStore()
        }
        self.preferences = PreferencesService(
            modelContainer: modelContainer,
            mutationGate: mutationGate
        )
        let backupService = SecureBackupService(
            gate: gate,
            keychain: keychain,
            modelContainer: modelContainer,
            sessionLock: sessionLock,
            integrityQuarantine: integrityQuarantine,
            mutationGate: mutationGate,
            crossStoreJournal: crossStoreJournal
        )
        self.backups = backupService
        self.crossStoreRecoveryHandler = { record in
            switch record.kind {
            case .createKey:
                try await vaultService.recoverInterruptedCrossStoreTransaction(record)
            case .backupImport:
                try await backupService.recoverInterruptedCrossStoreTransaction(record)
            }
        }
        self.backupPassphrase = BackupPassphraseService(
            keychain: keychain,
            sessionLock: sessionLock,
            mutationGate: mutationGate
        )
        // Status UI and erase convergence must observe the exact same CloudKit
        // event stream; separate monitors can miss each other's checkpoints.
        let monitor = CloudKitSyncMonitor(
            mirroringEnabled: AppSchema.isCloudKitMirroringEnabled
        )
        let cloudEraseConvergence = CloudEraseConvergence(monitor: monitor)
        self.dataLifecycle = DataLifecycleService(
            gate: gate,
            keychain: keychain,
            modelContainer: modelContainer,
            vault: self.vault,
            consumerTools: self.consumerTools,
            backups: self.backups,
            preferences: self.preferences,
            entitlements: entitlements,
            clipboard: clipboard,
            sessionLock: sessionLock,
            eraseJournal: eraseJournal,
            crossStoreJournal: crossStoreJournal,
            mutationGate: mutationGate,
            integrityQuarantine: integrityQuarantine,
            cloudEraseConvergence: cloudEraseConvergence,
            keychainConvergenceGrace: .milliseconds(750)
        )
        self.cloudSync = CloudSyncService(monitor: monitor)
        self.appPrivacy = AppPrivacyController(
            gate: gate,
            preferences: self.preferences,
            masterPassword: master,
            windowsSnapshot: {
                AppPrivacyController.liveWindowsSnapshot(
                    authenticationInProgress: gate.isAuthenticationInProgress()
                )
            },
            sessionLockBox: sessionLock
        )
        if isTesting {
            self.cloudImportHygiene = nil
            self.cloudImportObserver = nil
            self.securityPolicyRefreshFence = nil
        } else {
            let vault = self.vault
            let tools = self.consumerTools
            let hygiene = CloudImportIdentityHygiene {
                try? await vault.pruneDuplicateIdentities()
                try? await tools.pruneDuplicateIdentities()
            }
            self.cloudImportHygiene = hygiene
            let privacy = self.appPrivacy
            self.securityPolicyRefreshFence = SecurityPolicyRefreshNotificationFence(
                notificationName: .apiRelayCloudSecurityPolicyRefreshRequired,
                sessionLock: sessionLock,
                decode: { notification in
                    guard let event = notification.object as? CloudKitPipelineEventSnapshot,
                          event.phase == .import else { return nil }
                    return event.ended ? .ended : .began
                },
                bootstrapImportInFlight: {
                    CloudKitSyncMonitor.processPipelineBootstrapState().importInFlight
                },
                reload: { token in
                    await privacy.reloadSecurityPreferencesAfterExternalImport(token)
                }
            )
            // 同步注册，避免启动瞬间通知先到、异步 for-await 后挂上。
            self.cloudImportObserver = NotificationCenter.default.addObserver(
                forName: .apiRelayCloudMetadataDidImport,
                object: nil,
                queue: nil
            ) { [hygiene] _ in
                Task { await hygiene.handleImportSucceeded() }
            }
        }
        Task { await self.refreshAppearance() }
    }

    #if DEBUG
    /// 预览 / 手工组装：全部依赖从外部注入（通常是 Fake*）。
    init(
        modelContainer: ModelContainer,
        keychain: any KeychainStoring,
        masterPassword: any MasterPasswordServing,
        gate: any RevealGateServing,
        clipboard: any ClipboardServing,
        vault: any KeyVaultServing,
        consumerTools: any ConsumerToolServing,
        trashBatch: any RecentlyDeletedBatchServing,
        entitlements: any EntitlementServing,
        preferences: any PreferencesServing,
        backups: any SecureBackupServing,
        backupPassphrase: any BackupPassphraseServing,
        dataLifecycle: any DataLifecycleServing,
        cloudSync: any CloudSyncServing,
        appPrivacy: AppPrivacyController
    ) {
        self.modelContainer = modelContainer
        self.keychain = keychain
        self.masterPassword = masterPassword
        self.gate = gate
        self.clipboard = clipboard
        self.vault = vault
        self.consumerTools = consumerTools
        self.trashBatch = trashBatch
        self.entitlements = entitlements
        self.preferences = preferences
        self.backups = backups
        self.backupPassphrase = backupPassphrase
        self.dataLifecycle = dataLifecycle
        self.cloudSync = cloudSync
        self.appPrivacy = appPrivacy
        self.cloudImportHygiene = nil
        self.cloudImportObserver = nil
        self.securityPolicyRefreshFence = nil
        self.crossStoreJournal = nil
        self.storageMutationGate = nil
        self.crossStoreRecoveryHandler = nil
        Task { await self.refreshAppearance() }
    }

    /// Xcode Preview：内存容器 + 全套 Fake，不碰真 Keychain / StoreKit / CloudKit。
    static func makePreview() -> AppEnvironment {
        let container: ModelContainer
        do {
            container = try AppSchema.makeInMemoryContainer()
        } catch {
            fatalError("Preview ModelContainer failed: \(error)")
        }
        let keychain = FakeKeychain()
        let master = FakeMasterPassword()
        let gate = FakeRevealGate()
        let clipboard = FakeClipboard()
        let entitlements = FakeEntitlements(tier: .unlimitedKeys)
        let preferences = FakePreferences()
        let vault = FakeKeyVault(seedPreviewSample: true)
        let consumerTools = FakeConsumerTools(seedPreviewSample: true)
        let trashBatch = FakeRecentlyDeletedBatch()
        let backups = FakeSecureBackup()
        let backupPassphrase = FakeBackupPassphrase()
        let dataLifecycle = FakeDataLifecycle()
        let cloudSync = FakeCloudSync()
        let privacy = AppPrivacyController(
            gate: gate,
            preferences: preferences,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: false
        )
        return AppEnvironment(
            modelContainer: container,
            keychain: keychain,
            masterPassword: master,
            gate: gate,
            clipboard: clipboard,
            vault: vault,
            consumerTools: consumerTools,
            trashBatch: trashBatch,
            entitlements: entitlements,
            preferences: preferences,
            backups: backups,
            backupPassphrase: backupPassphrase,
            dataLifecycle: dataLifecycle,
            cloudSync: cloudSync,
            appPrivacy: privacy
        )
    }
    #endif

    /// 从 DevicePreferences 重新读取外观并推到 UI（设置页改完后调用）。
    func refreshAppearance() async {
        guard let prefs = try? await preferences.load() else { return }
        appearance = prefs.appearance
    }

    /// The root privacy barrier consults this synchronously on every recovery
    /// state notification. A full-erase marker wins because that transaction
    /// intentionally supersedes the provisional cross-store operation.
    var crossStoreRecoveryRequired: Bool {
        guard !dataLifecycle.hasPendingErase(),
              let crossStoreJournal,
              let storageMutationGate else { return false }
        return crossStoreJournal.hasPendingTransaction()
            || storageMutationGate.isCrossStoreRecoverySealed()
    }

    /// Runs before privacy preferences or vault UI are allowed to load. The
    /// shared gate was constructed sealed from the durable marker, so no normal
    /// storage operation can overtake this replay.
    @discardableResult
    func prepareProtectedStorage() async -> Bool {
        if dataLifecycle.hasPendingErase() {
            crossStoreRecoveryError = nil
            return true
        }
        guard let crossStoreJournal,
              let storageMutationGate,
              let crossStoreRecoveryHandler else {
            crossStoreRecoveryError = nil
            return true
        }
        guard crossStoreJournal.hasPendingTransaction()
                || storageMutationGate.isCrossStoreRecoverySealed() else {
            crossStoreRecoveryError = nil
            return true
        }
        guard !isRecoveringCrossStore else { return false }

        isRecoveringCrossStore = true
        defer { isRecoveringCrossStore = false }
        do {
            guard let record = try crossStoreJournal.load() else {
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "cross_store_startup_recovery",
                    detail: "sealed_without_marker"
                )
            }
            try await crossStoreRecoveryHandler(record)
            crossStoreRecoveryError = nil
            return true
        } catch {
            crossStoreRecoveryError = error.localizedDescription
            return false
        }
    }

    /// 首次设密：当前方式确认（由调用方注入）→ 设备主人 → 写入复查 → persist **原目标**。
    /// 已设或读取失败 MUST NOT 覆盖。persist 失败保留材料，不删 `.masterpw`。
    func createAppPasswordMaterialThenPersist(
        password: String,
        target: RevealPolicy,
        request: AppPasswordSubmitContext,
        confirmCurrentIfNeeded: @escaping @Sendable () async throws -> Void
    ) async throws {
        let gate = self.gate
        let preferences = self.preferences
        let master = self.masterPassword
        let reason = String(localized: "gate.changeSecuritySettings")
        let opened = request.lease.openedPolicy()
        try await AppPasswordSetup.createMaterialThenPersistTarget(
            target: target,
            materialStatus: { await master.materialStatus() },
            confirmCurrentIfNeeded: confirmCurrentIfNeeded,
            confirmDeviceOwner: {
                try await gate.confirmMandatory(reason: reason, purpose: .settings)
            },
            setAndVerifyMaterial: {
                try await master.setPassword(password, committing: { operation in
                    try request.commit(.materialWrite, operation: operation)
                })
                guard await master.materialStatus() == .set else {
                    throw ApiRelayError.validationFailed(
                        field: "masterPassword",
                        reason: "material_verify_failed"
                    )
                }
            },
            persistTarget: { policy in
                try await AppPasswordRecovery.awaitPersist(
                    preferences,
                    PreferencesPatch(revealPolicy: policy),
                    authorizing: { try request.authorize(.policyPersist) },
                    committing: { operation in
                        try request.commit(.policyPersist, operation: operation)
                    },
                    expectedCurrentPolicy: opened
                )
            },
            materialRevision: {
                await master.materialRevision()
            },
            commitPersist: { policy, revision in
                try await master.withUnchangedSetMaterial(expectedRevision: revision) {
                    try await AppPasswordRecovery.awaitPersist(
                        preferences,
                        PreferencesPatch(revealPolicy: policy),
                        authorizing: { try request.authorize(.policyPersist) },
                        committing: { operation in
                            try request.commit(.policyPersist, operation: operation)
                        },
                        expectedCurrentPolicy: opened
                    )
                }
            },
            authorize: { try request.authorize(.proceed) }
        )
    }

    /// 已设材料后切到密码依赖档：只按当前方式确认并 persist 原目标。MUST NOT `setPassword`。
    func persistPasswordDependentPolicyKeepingMaterial(
        target: RevealPolicy,
        request: AppPasswordSubmitContext,
        confirmCurrentIfNeeded: @escaping @Sendable () async throws -> Void
    ) async throws {
        let preferences = self.preferences
        let master = self.masterPassword
        let opened = request.lease.openedPolicy()
        try await AppPasswordSetup.persistExistingMaterialTarget(
            target: target,
            materialStatus: { await master.materialStatus() },
            confirmCurrentIfNeeded: confirmCurrentIfNeeded,
            materialRevision: { await master.materialRevision() },
            commitPersist: { policy, revision in
                try await master.withUnchangedSetMaterial(expectedRevision: revision) {
                    try await AppPasswordRecovery.awaitPersist(
                        preferences,
                        PreferencesPatch(revealPolicy: policy),
                        authorizing: { try request.authorize(.policyPersist) },
                        committing: { operation in
                            try request.commit(.policyPersist, operation: operation)
                        },
                        expectedCurrentPolicy: opened
                    )
                }
            },
            authorize: { try request.authorize(.proceed) }
        )
    }

    /// 改密的 PBKDF/Keychain 准备可以跨 actor 挂起；最终替换必须与页面
    /// generation 在真实 Keychain 写入接缝上线性化。
    func changeAppPassword(
        current: String,
        new: String,
        request: AppPasswordSubmitContext
    ) async throws {
        try request.authorize(.proceed)
        try await masterPassword.changePassword(
            current: current,
            new: new,
            committing: { operation in
                try request.commit(.materialWrite, operation: operation)
            }
        )
        try request.authorize(.proceed)
    }

    /// 忘记/重置应用密码的唯一协调入口：设备主人 → 策略落到设备验证 → 再只清 `.masterpw`。
    /// 调用方可等待最终结果。persist 失败保留材料，MUST NOT 落到不验证。
    func resetAppPasswordAndFallToDeviceAuth(request: AppPasswordSubmitContext) async throws {
        let gate = self.gate
        let preferences = self.preferences
        let master = self.masterPassword
        let reason = String(localized: "gate.resetMasterPassword")
        let opened = request.lease.openedPolicy()
        try await AppPasswordRecovery.recoverToDeviceAuth(
            confirmMandatory: {
                try await gate.confirmMandatory(reason: reason, purpose: .recovery)
            },
            persistDeviceAuth: {
                try await AppPasswordRecovery.awaitPersist(
                    preferences,
                    AppPasswordRecovery.deviceAuthPatch,
                    authorizing: { try request.authorize(.policyPersist) },
                    committing: { operation in
                        try request.commit(.policyPersist, operation: operation)
                    },
                    expectedCurrentPolicy: opened
                )
            },
            resetIfRevision: { expected in
                try await master.reset(expectedRevision: expected, committing: { operation in
                    try request.commit(.recoveryDelete, operation: operation)
                })
            },
            snapshotRevision: {
                await master.materialRevision()
            },
            authorize: { try request.authorize(.proceed) }
        )
    }

    #if DEBUG
    /// 测试便捷入口：临时请求身份仍走同一提交接缝，不给 RELEASE 生产 UI 绕过许可。
    func createAppPasswordMaterialThenPersist(
        password: String,
        target: RevealPolicy,
        confirmCurrentIfNeeded: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await createAppPasswordMaterialThenPersist(
            password: password,
            target: target,
            request: try await makeEphemeralSubmitRequest(target: target),
            confirmCurrentIfNeeded: confirmCurrentIfNeeded
        )
    }

    func persistPasswordDependentPolicyKeepingMaterial(
        target: RevealPolicy,
        confirmCurrentIfNeeded: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await persistPasswordDependentPolicyKeepingMaterial(
            target: target,
            request: try await makeEphemeralSubmitRequest(target: target),
            confirmCurrentIfNeeded: confirmCurrentIfNeeded
        )
    }

    func resetAppPasswordAndFallToDeviceAuth() async throws {
        try await resetAppPasswordAndFallToDeviceAuth(
            request: try await makeEphemeralSubmitRequest(target: .biometricOrPasscode)
        )
    }

    private func makeEphemeralSubmitRequest(target: RevealPolicy) async throws -> AppPasswordSubmitContext {
        let current = (try? await preferences.load())?.revealPolicy ?? .biometricOrPasscode
        let lease = AppPasswordPageLease(target: target, currentPolicy: current)
        guard let token = lease.begin() else {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "stale_page_request"
            )
        }
        return AppPasswordSubmitContext(lease: lease, token: token)
    }
    #endif

    static func bootstrap() -> AppEnvironment {
        do {
            #if DEBUG
            if let scenario = AppRuntime.uiTestScenario {
                return try UITestFixture.makeEnvironment(scenario: scenario)
            }
            #endif
            // Install the process-wide raw CloudKit observer before SwiftData
            // can start mirroring. AppEnvironment is assembled later, so an
            // early import-start edge must remain buffered for its policy fence.
            if !AppRuntime.isRunningTests {
                CloudKitSyncMonitor.prepareForCloudKitContainerBootstrap()
            }
            let container = try AppSchema.makeProductionContainer()
            #if DEBUG
            // XCTest 使用内存容器，且测试宿主通常没有 CloudKit 签名能力；
            // 测试启动时不得触发真实 CKContainer 初始化。
            if !AppRuntime.isRunningTests {
                CloudKitSchemaBootstrap.runIfNeeded(container: container)
            }
            #endif
            return AppEnvironment(modelContainer: container)
        } catch {
            fatalError("ModelContainer bootstrap failed: \(error)")
        }
    }
}
