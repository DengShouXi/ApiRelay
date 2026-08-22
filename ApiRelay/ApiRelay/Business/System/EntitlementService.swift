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
        if let debugTier {
            return Self.canonicalize(debugTier)
        }
        #endif
        // StoreKit currentEntitlements 含本地缓存；空序列 = 未购，须写回 snapshot，避免脏 unlimited 永久放行。
        let live = Self.canonicalize(await tierFromStoreKit())
        try await snapshot.update(tier: live, source: "storekit")
        return live
    }

    func refreshFromStore() async throws {
        _ = try await currentTier()
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        _ = try await currentTier()
    }

    func purchaseUnlimitedKeys() async throws {
        let products = try await Product.products(for: [Self.unlimitedKeysProductID])
        guard let product = products.first else {
            // StoreKit 拉不到商品：常见于 ASC 未建 IAP / 未就绪 / 未用沙盒账号（TestFlight）。
            throw ApiRelayError.validationFailed(field: "product", reason: "storekit_product_unavailable")
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await handle(transaction: transaction)
                await transaction.finish()
            } else {
                throw ApiRelayError.validationFailed(field: "product", reason: "unverified_transaction")
            }
        case .userCancelled:
            throw ApiRelayError.authenticationCancelled
        case .pending:
            throw ApiRelayError.validationFailed(field: "product", reason: "purchase_pending")
        @unknown default:
            throw ApiRelayError.validationFailed(field: "product", reason: "purchase_unknown")
        }
    }

    #if DEBUG
    func debugOverride(tier: EntitlementTier?) async throws {
        debugTier = tier.map(Self.canonicalize)
        if let tier {
            try await snapshot.update(tier: Self.canonicalize(tier), source: "debugOverride")
        } else {
            let live = Self.canonicalize(await tierFromStoreKit())
            try await snapshot.update(tier: live, source: "storekit")
        }
    }
    #endif

    /// 无有效买断交易 → `.free`（不得返回 nil 去「信脏 snapshot」）。
    private func tierFromStoreKit() async -> EntitlementTier {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.unlimitedKeysProductID {
                return .unlimitedKeys
            }
        }
        return .free
    }

    private func handle(transaction: Transaction) async {
        let tier: EntitlementTier = (transaction.productID == Self.unlimitedKeysProductID)
            ? .unlimitedKeys
            : .free
        try? await snapshot.update(tier: Self.canonicalize(tier), source: "storekit")
    }

    /// V1 不暴露 `.relay`：一律视为无限密钥档。
    private static func canonicalize(_ tier: EntitlementTier) -> EntitlementTier {
        tier == .relay ? .unlimitedKeys : tier
    }

    /// FR-061：清本地权益快照；不吊销 StoreKit。
    func purgeLocalSnapshotForErase() async throws {
        try await snapshot.deleteAllRecords()
    }
}
