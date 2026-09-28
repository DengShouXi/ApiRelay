import Foundation
import StoreKit

/// The only production adapter that turns StoreKit verification into evidence.
/// Test doubles are injected in code, never selected by a production launch flag.
nonisolated struct StoreProductInfo: Sendable {
    let id: String
    let displayPrice: String
}

nonisolated struct VerifiedStoreTransaction: Sendable {
    let id: UInt64
    let productID: String
    let environment: AppStore.Environment
    let revocationDate: Date?
    let finish: @Sendable () async -> Void
}

nonisolated enum StoreTransactionObservation: Sendable {
    case verified(VerifiedStoreTransaction)
    /// Untrusted product identity is used only to report an error, never a grant.
    case unverified(productID: String)
}

nonisolated enum StorePurchaseOutcome: Sendable {
    case success(StoreTransactionObservation)
    case cancelled
    case pending
}

nonisolated protocol StoreKitClient: Sendable {
    func productInfo() async throws -> StoreProductInfo
    func purchase() async throws -> StorePurchaseOutcome
    func currentEntitlements() async throws -> [StoreTransactionObservation]
    func updates() async -> AsyncStream<StoreTransactionObservation>
    func sync() async throws
    func appEnvironment() async -> AppStore.Environment?
}

nonisolated struct LiveStoreKitClient: StoreKitClient {
    func productInfo() async throws -> StoreProductInfo {
        let product = try await product()
        return StoreProductInfo(id: product.id, displayPrice: product.displayPrice)
    }

    func purchase() async throws -> StorePurchaseOutcome {
        Self.outcome(try await product().purchase())
    }

    func currentEntitlements() async throws -> [StoreTransactionObservation] {
        var results: [StoreTransactionObservation] = []
        for await result in Transaction.currentEntitlements {
            results.append(Self.observation(result))
        }
        return results
    }

    func updates() async -> AsyncStream<StoreTransactionObservation> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    continuation.yield(Self.observation(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sync() async throws { try await AppStore.sync() }

    func appEnvironment() async -> AppStore.Environment? {
        guard case .verified(let app) = try? await AppTransaction.shared else { return nil }
        return app.environment
    }

    private func product() async throws -> Product {
        let products = try await Product.products(for: [EntitlementService.unlimitedKeysProductID])
        guard let product = products.first(where: { $0.id == EntitlementService.unlimitedKeysProductID }) else {
            throw ApiRelayError.validationFailed(field: "product", reason: "storekit_product_unavailable")
        }
        return product
    }

    static func outcome(_ result: Product.PurchaseResult) -> StorePurchaseOutcome {
        switch result {
        case .success(let verification): .success(observation(verification))
        case .userCancelled: .cancelled
        case .pending: .pending
        @unknown default: .success(.unverified(productID: EntitlementService.unlimitedKeysProductID))
        }
    }

    private static func observation(_ result: VerificationResult<Transaction>) -> StoreTransactionObservation {
        switch result {
        case .verified(let transaction):
            .verified(VerifiedStoreTransaction(
                id: transaction.id, productID: transaction.productID,
                environment: transaction.environment, revocationDate: transaction.revocationDate,
                finish: { await transaction.finish() }
            ))
        case .unverified(let transaction, _):
            .unverified(productID: transaction.productID)
        }
    }
}
