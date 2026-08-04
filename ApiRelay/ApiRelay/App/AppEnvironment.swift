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

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        // 无付费开发者账号 / 未开 iCloud Keychain 时，synchronizable 会返回 -34018。
        // 开通账号并配好 entitlement 后改为 disableSynchronizableForTesting: false。
        let keychain = KeychainStore(accessGroup: nil, disableSynchronizableForTesting: true)
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
    }

    static func bootstrap() -> AppEnvironment {
        let container: ModelContainer
        do {
            container = try AppSchema.makeProductionContainer()
        } catch {
            fatalError("ModelContainer bootstrap failed: \(error)")
        }
        return AppEnvironment(modelContainer: container)
    }
}
