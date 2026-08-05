import Foundation
import SwiftData
import SwiftUI
import Combine

/// 组装 Data / Business 依赖。不持有明文。
@MainActor
final class AppEnvironment: ObservableObject {
    let modelContainer: ModelContainer
    let keychain: KeychainStore
    let masterPassword: MasterPasswordService
    let gate: RevealGate
    let clipboard: SecureClipboard
    let vault: KeyVaultService
    let consumerTools: ConsumerToolService
    let entitlements: EntitlementService
    let preferences: PreferencesService
    let backups: SecureBackupService
    let dataLifecycle: DataLifecycleService

    /// 本机外观（DevicePreferences）；驱动根视图 `preferredColorScheme`。
    @Published private(set) var appearance: AppearancePreference = .system

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // 正式路径：开启 keys/admin 的 iCloud 钥匙串同步；access group 与 entitlements 对齐。
        // 单测宿主常缺 sync entitlement → 关闭 synchronizable，避免 -34018。
        let keychain = KeychainStore(
            accessGroup: isTesting ? nil : KeychainAccessGroup.resolved,
            disableSynchronizableForTesting: isTesting
        )
        self.keychain = keychain
        let master = MasterPasswordService(keychain: keychain)
        self.masterPassword = master
        let gate = RevealGate(masterPassword: master)
        self.gate = gate
        let clipboard = SecureClipboard()
        self.clipboard = clipboard
        self.vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: modelContainer
        )
        self.consumerTools = ConsumerToolService(modelContainer: modelContainer, gate: gate)
        let entitlements = EntitlementService(modelContainer: modelContainer)
        self.entitlements = entitlements
        Task { await entitlements.startListening() }
        self.preferences = PreferencesService(modelContainer: modelContainer)
        self.backups = SecureBackupService(
            gate: gate,
            keychain: keychain,
            modelContainer: modelContainer
        )
        self.dataLifecycle = DataLifecycleService(
            gate: gate,
            keychain: keychain,
            modelContainer: modelContainer
        )
        Task { await self.refreshAppearance() }
    }

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
