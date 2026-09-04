import Foundation
import SwiftData
import SwiftUI
import Combine

/// 组装 Data / Business 依赖。不持有明文。
@MainActor
final class AppEnvironment: ObservableObject {
    let modelContainer: ModelContainer
    let keychain: any KeychainStoring
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

    /// 本机外观（DevicePreferences）；驱动根视图 `preferredColorScheme`。
    @Published private(set) var appearance: AppearancePreference = .system

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
        let master = MasterPasswordService(keychain: keychain)
        self.masterPassword = master
        let gate = RevealGate(masterPassword: master)
        self.gate = gate
        let clipboard = SecureClipboard()
        self.clipboard = clipboard
        let entitlements = EntitlementService(modelContainer: modelContainer)
        self.entitlements = entitlements
        self.vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: modelContainer,
            entitlements: entitlements
        )
        self.consumerTools = ConsumerToolService(modelContainer: modelContainer, gate: gate)
        self.trashBatch = RecentlyDeletedBatchService(
            vault: self.vault,
            consumerTools: self.consumerTools,
            gate: gate
        )
        Task {
            await entitlements.startListening()
            // 启动时纠偏：以 StoreKit currentEntitlements 为准，清掉脏的本地 unlimited 快照。
            // 本地无限权益：Debug 下走付费墙正常购买（Scheme 已挂 ApiRelay.storekit）；不要启动参数后门。
            try? await entitlements.refreshFromStore()
        }
        self.preferences = PreferencesService(modelContainer: modelContainer)
        self.backups = SecureBackupService(
            gate: gate,
            keychain: keychain,
            modelContainer: modelContainer
        )
        self.backupPassphrase = BackupPassphraseService(keychain: keychain)
        self.dataLifecycle = DataLifecycleService(
            gate: gate,
            keychain: keychain,
            modelContainer: modelContainer,
            vault: self.vault,
            consumerTools: self.consumerTools,
            preferences: self.preferences,
            entitlements: entitlements
        )
        let monitor = CloudKitSyncMonitor(mirroringEnabled: AppSchema.isCloudKitMirroringEnabled)
        self.cloudSync = CloudSyncService(monitor: monitor)
        self.appPrivacy = AppPrivacyController(
            gate: gate,
            preferences: self.preferences,
            masterPassword: master
        )
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
            enablesUnlockPrompt: false
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

    static func bootstrap() -> AppEnvironment {
        do {
            let container = try AppSchema.makeProductionContainer()
            #if DEBUG
            CloudKitSchemaBootstrap.runIfNeeded(container: container)
            #endif
            return AppEnvironment(modelContainer: container)
        } catch {
            fatalError("ModelContainer bootstrap failed: \(error)")
        }
    }
}
