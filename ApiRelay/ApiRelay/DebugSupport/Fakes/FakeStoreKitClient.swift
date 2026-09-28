#if DEBUG
import Foundation
import StoreKit

/// Apple boundary only. EntitlementService, shared UI state and vault quota stay real.
actor FakeStoreKitClient: StoreKitClient {
    private var observations: [StoreTransactionObservation]
    private var outcome: StorePurchaseOutcome
    private var continuation: AsyncStream<StoreTransactionObservation>.Continuation?
    private var productFailures: Int
    private let queryFails: Bool
    private let queryDelay: Duration
    private let purchaseDelay: Duration
    private let purchaseVisibleInQueries: Bool
    private(set) var purchaseCount = 0
    private(set) var productLoadCount = 0

    init(owned: Bool = false, pending: Bool = false, cancelled: Bool = false,
         productFailures: Int = 0, queryFails: Bool = false, queryDelay: Duration = .zero,
         purchaseDelay: Duration = .zero, purchaseVisibleInQueries: Bool = true) {
        self.observations = owned ? [.verified(Self.transaction(id: 1))] : []
        self.outcome = pending ? .pending : cancelled ? .cancelled : .success(.verified(Self.transaction(id: 2)))
        self.productFailures = productFailures
        self.queryFails = queryFails
        self.queryDelay = queryDelay
        self.purchaseDelay = purchaseDelay
        self.purchaseVisibleInQueries = purchaseVisibleInQueries
    }

    static func transaction(id: UInt64 = 2, revoked: Bool = false,
                            environment: AppStore.Environment = .sandbox,
                            productID: String = EntitlementService.unlimitedKeysProductID) -> VerifiedStoreTransaction {
        VerifiedStoreTransaction(id: id, productID: productID, environment: environment,
                                 revocationDate: revoked ? Date() : nil, finish: {})
    }

    func productInfo() async throws -> StoreProductInfo {
        productLoadCount += 1
        if productFailures > 0 {
            productFailures -= 1
            throw ApiRelayError.networkUnavailable
        }
        return StoreProductInfo(id: EntitlementService.unlimitedKeysProductID, displayPrice: "$0.99")
    }

    func purchase() async throws -> StorePurchaseOutcome {
        purchaseCount += 1
        if purchaseDelay != .zero { try await Task.sleep(for: purchaseDelay) }
        if purchaseVisibleInQueries, case .success(let observation) = outcome { observations = [observation] }
        return outcome
    }

    func currentEntitlements() async throws -> [StoreTransactionObservation] {
        let captured = observations
        if queryDelay != .zero { try await Task.sleep(for: queryDelay) }
        if queryFails { throw ApiRelayError.networkUnavailable }
        return captured
    }

    func updates() async -> AsyncStream<StoreTransactionObservation> {
        let (stream, continuation) = AsyncStream<StoreTransactionObservation>.makeStream()
        self.continuation = continuation
        return stream
    }
    func sync() async throws {}
    var isListening: Bool { continuation != nil }
    func appEnvironment() async -> AppStore.Environment? { .sandbox }
    func setObservations(_ values: [StoreTransactionObservation]) { observations = values }
    func setOutcome(_ value: StorePurchaseOutcome) { outcome = value }
    func send(_ value: StoreTransactionObservation) {
        observations = [value]
        continuation?.yield(value)
    }
}
#endif
