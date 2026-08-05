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
        self.consumerTools = ConsumerToolService(modelContainer: modelContainer)
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
    }

    static func bootstrap() -> AppEnvironment {
        do {
            return AppEnvironment(modelContainer: try AppSchema.makeProductionContainer())
        } catch {
            fatalError("ModelContainer bootstrap failed: \(error)")
        }
    }
}
