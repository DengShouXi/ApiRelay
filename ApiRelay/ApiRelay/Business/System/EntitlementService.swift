import Foundation
import StoreKit
import SwiftData

protocol EntitlementServing: Actor {
    func currentTier() async throws -> EntitlementTier
    func refreshFromStore() async throws
    func restorePurchases() async throws
    func purchaseUnlimitedKeys() async throws
    #if DEBUG
    func debugOverride(tier: EntitlementTier?) async throws
    #endif
}

actor EntitlementService: EntitlementServing {
    static let unlimitedKeysProductID = "com.apirelay.iap.unlimited_keys"
    /// V3 预留，V1 不创建、不展示。
    static let relayProductIDReserved = "com.apirelay.iap.relay"

    private let snapshot: EntitlementSnapshotRepository
    private var updatesTask: Task<Void, Never>?

    #if DEBUG
    private var debugTier: EntitlementTier?
    #endif

    init(modelContainer: ModelContainer) {
        self.snapshot = EntitlementSnapshotRepository(modelContainer: modelContainer)
    }

    func startListening() {
        updatesTask?.cancel()
        updatesTask = Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await handle(transaction: transaction)
                    await transaction.finish()
                }
            }
        }
    }

    func currentTier() async throws -> EntitlementTier {
        #if DEBUG
        if let debugTier { return debugTier }
        #endif
        if let live = await tierFromStoreKit() {
            try await snapshot.update(tier: live, source: "storekit")
            return live == .relay ? .unlimitedKeys : live
        }
        let snap = try await snapshot.loadOrCreate()
        return snap.tier == .relay ? .unlimitedKeys : snap.tier
    }

    func refreshFromStore() async throws {
        _ = try await currentTier()
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        _ = try await currentTier()
    }

    func purchaseUnlimitedKeys() async throws {
        guard let product = try await Product.products(for: [Self.unlimitedKeysProductID]).first else {
            throw ApiRelayError.validationFailed(field: "product", reason: "not_found")
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await handle(transaction: transaction)
                await transaction.finish()
            }
        case .userCancelled:
            throw ApiRelayError.authenticationCancelled
        case .pending:
            break
        @unknown default:
            break
        }
    }

    #if DEBUG
    func debugOverride(tier: EntitlementTier?) async throws {
        debugTier = tier
        if let tier {
            try await snapshot.update(tier: tier, source: "debugOverride")
        }
    }
    #endif

    private func tierFromStoreKit() async -> EntitlementTier? {
        var sawVerified = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                sawVerified = true
                if transaction.productID == Self.unlimitedKeysProductID {
                    return .unlimitedKeys
                }
            }
        }
        // 无已验证交易时返回 nil，让离线 snapshot 兜底（含 DEBUG / 测试写入）。
        return sawVerified ? .free : nil
    }

    private func handle(transaction: Transaction) async {
        let tier: EntitlementTier = (transaction.productID == Self.unlimitedKeysProductID)
            ? .unlimitedKeys
            : .free
        try? await snapshot.update(tier: tier, source: "storekit")
    }
}
