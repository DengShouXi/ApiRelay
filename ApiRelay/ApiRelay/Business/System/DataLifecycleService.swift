import Foundation
import SwiftData

protocol DataLifecycleServing: Actor {
    func eraseAllUserData() async throws
}

extension Notification.Name {
    /// 「清除全部数据」完成后发出；主列表 / 回收站据此丢掉内存缓存。
    static let userDataDidErase = Notification.Name("com.apirelay.userDataDidErase")
}

actor DataLifecycleService: DataLifecycleServing {
    private let gate: RevealGateServing
    private let keychain: KeychainStoring
    private let modelContainer: ModelContainer
    private let vault: KeyVaultServing
    private let consumerTools: ConsumerToolServing
    private let preferences: PreferencesServing
    private let entitlements: EntitlementServing
    private let sessionLock: any SessionLockQuerying

    init(
        gate: RevealGateServing,
        keychain: KeychainStoring,
        modelContainer: ModelContainer,
        vault: KeyVaultServing,
        consumerTools: ConsumerToolServing,
        preferences: PreferencesServing,
        entitlements: EntitlementServing,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock()
    ) {
        self.gate = gate
        self.keychain = keychain
        self.modelContainer = modelContainer
        self.vault = vault
        self.consumerTools = consumerTools
        self.preferences = preferences
        self.entitlements = entitlements
        self.sessionLock = sessionLock
    }

    func eraseAllUserData() async throws {
        if sessionLock.isSessionLocked() { throw ApiRelayError.sessionLocked }
        try await gate.confirmMandatory(reason: String(localized: "gate.eraseAll"))
        for service: KeychainService in [.keys, .admin, .masterpw, .backuppw] {
            let accounts = try await keychain.listAccounts(service: service)
            for account in accounts {
                try await keychain.delete(service: service, account: account)
            }
        }
        // 必须走各服务已持有的 ModelActor。另开 ModelContext 删除后，
        // 「按平台 / 按使用方」仍从旧上下文读出活跃密钥，看起来像只清了回收站。
        try await vault.purgeAllRecordsForErase()
        try await consumerTools.purgeAllRecordsForErase()
        try await preferences.purgeAllRecordsForErase()
        try await entitlements.purgeLocalSnapshotForErase()
        // 尚无独立仓库的用量类实体
        let context = ModelContext(modelContainer)
        try context.deleteAllRecords(UsageSnapshot.self)
        try context.deleteAllRecords(BalanceSnapshot.self)
        try context.deleteAllRecords(PricingRule.self)
        await MainActor.run {
            NotificationCenter.default.post(name: .userDataDidErase, object: nil)
        }
    }
}
