import Foundation
import StoreKit
import SwiftData

protocol EntitlementServing: Actor {
    func currentTier() async throws -> EntitlementTier
    func refreshFromStore() async throws
    func restorePurchases() async throws -> EntitlementTier
    func purchaseUnlimitedKeys() async throws -> EntitlementTier
    /// 监听 StoreKit `Transaction.updates`。
    func startListening()
    /// FR-061：清本地权益快照；不吊销 StoreKit。
    func purgeLocalSnapshotForErase() async throws
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
    /// 验过签的 App 包环境；失败不缓存，下次再问。
    private var cachedAppEnvironment: AppStore.Environment?

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
                switch update {
                case .verified(let transaction):
                    await transaction.finish()
                    _ = try? await currentTier()
                case .unverified:
                    // 不放行，也不 finish：保留 StoreKit 后续重新验签 / 重放的机会。
                    continue
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
        // snapshot 只是本机观测缓存，不是授权依据；落盘失败不得推翻 StoreKit 的权威结果。
        try? await snapshot.update(tier: live, source: "storekit")
        return live
    }

    func refreshFromStore() async throws {
        _ = try await currentTier()
    }

    func restorePurchases() async throws -> EntitlementTier {
        try await AppStore.sync()
        return try await currentTier()
    }

    func purchaseUnlimitedKeys() async throws -> EntitlementTier {
        let products = try await Product.products(for: [Self.unlimitedKeysProductID])
        guard let product = products.first else {
            // StoreKit 拉不到商品：常见于 ASC 未建 IAP、商品未就绪或付费协议未生效。
            // TestFlight 会自动使用沙盒环境，不要求普通测试员更换 Apple ID。
            throw ApiRelayError.validationFailed(field: "product", reason: "storekit_product_unavailable")
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                let appEnvironment = await resolvedAppEnvironment()
                guard EntitlementGrantPolicy.grantsUnlimitedKeys(
                    productID: transaction.productID,
                    environment: transaction.environment,
                    revocationDate: transaction.revocationDate,
                    appEnvironment: appEnvironment
                ) else {
                    await transaction.finish()
                    throw ApiRelayError.validationFailed(
                        field: "product",
                        reason: "transaction_not_eligible"
                    )
                }
                // 本次 verified 交易足以确认刚完成的购买；不再依赖 currentEntitlements 立刻刷新。
                await transaction.finish()
                try? await snapshot.update(tier: .unlimitedKeys, source: "storekit")
                return .unlimitedKeys
            case .unverified:
                // 不 finish，保留暂时性验签失败后的重试机会。
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
        var appEnvironment: AppStore.Environment?
        var didResolveAppEnvironment = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if !didResolveAppEnvironment {
                appEnvironment = await resolvedAppEnvironment()
                didResolveAppEnvironment = true
            }
            if EntitlementGrantPolicy.grantsUnlimitedKeys(
                productID: transaction.productID,
                environment: transaction.environment,
                revocationDate: transaction.revocationDate,
                appEnvironment: appEnvironment
            ) {
                return .unlimitedKeys
            }
        }
        return .free
    }

    private func resolvedAppEnvironment() async -> AppStore.Environment? {
        if let cachedAppEnvironment { return cachedAppEnvironment }
        guard case .verified(let app) = try? await AppTransaction.shared else {
            return nil
        }
        cachedAppEnvironment = app.environment
        return app.environment
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
