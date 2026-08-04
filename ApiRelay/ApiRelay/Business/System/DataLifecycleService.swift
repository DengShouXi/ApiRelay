import Foundation
import SwiftData

protocol DataLifecycleServing: Actor {
    func eraseAllUserData() async throws
}

actor DataLifecycleService: DataLifecycleServing {
    private let gate: RevealGate
    private let keychain: KeychainStore
    private let modelContainer: ModelContainer

    init(gate: RevealGate, keychain: KeychainStore, modelContainer: ModelContainer) {
        self.gate = gate
        self.keychain = keychain
        self.modelContainer = modelContainer
    }

    func eraseAllUserData() async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.eraseAll"))
        // 清 Keychain 三类
        for service: KeychainService in [.keys, .admin, .masterpw] {
            let accounts = (try? await keychain.listAccounts(service: service)) ?? []
            for account in accounts {
                try? await keychain.delete(service: service, account: account)
            }
        }
        // 清 SwiftData 用户实体（保留 schema）；不碰 StoreKit。
        let context = ModelContext(modelContainer)
        try deleteAll(UpstreamAccount.self, in: context)
        try deleteAll(APIKeyRecord.self, in: context)
        try deleteAll(ConsumerTool.self, in: context)
        try deleteAll(KeyAssignment.self, in: context)
        try deleteAll(UserPreferences.self, in: context)
        try deleteAll(DevicePreferences.self, in: context)
        try deleteAll(EntitlementSnapshot.self, in: context)
        try deleteAll(UsageSnapshot.self, in: context)
        try deleteAll(BalanceSnapshot.self, in: context)
        try deleteAll(PricingRule.self, in: context)
        try context.save()
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        for item in items {
            context.delete(item)
        }
    }
}
