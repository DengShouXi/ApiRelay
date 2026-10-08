import Foundation
import StoreKit
import SwiftData

nonisolated struct EntitlementChange: Sendable {
    nonisolated enum Source: Sendable {
        case purchaseCompleted
        case transactionUpdate
        case bridgeExpired
    }

    let revision: UInt64
    let source: Source
}

protocol EntitlementServing: Actor {
    func currentTier() async throws -> EntitlementTier
    func refreshFromStore() async throws
    func restorePurchases() async throws -> EntitlementTier
    func purchaseUnlimitedKeys() async throws -> EntitlementTier
    /// Completes a purchase after the StoreKit boundary has translated it into
    /// the app's verified, platform-independent outcome.
    func completePurchase(_ result: StorePurchaseOutcome) async throws -> EntitlementTier
    /// Typed, instance-scoped changes; consumers do not listen to a global,
    /// payload-free NotificationCenter broadcast.
    func changes() -> AsyncStream<EntitlementChange>
    /// 监听 StoreKit `Transaction.updates`。
    func startListening()
    /// FR-061：清本地权益快照；不吊销 StoreKit。
    func purgeLocalSnapshotForErase() async throws
    /// 仅供持久化、已授权的全量清除事务绕过正常写入闸门。
    func purgeLocalSnapshotForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws
    #if DEBUG
    func debugOverride(tier: EntitlementTier?) async throws
    #endif
}

actor EntitlementService: EntitlementServing {
    static let unlimitedKeysProductID = "com.apirelay.iap.unlimited_keys"
    /// V3 预留，V1 不创建、不展示。
    static let relayProductIDReserved = "com.apirelay.iap.relay"

    private let snapshot: EntitlementSnapshotRepository
    private let mutationGate: StorageMutationGate
    /// Never set by the app. The StoreKit transaction unit test opts in explicitly.
    private let localStoreKitTestingAllowed: Bool
    private let store: any StoreKitClient
    private let bridgeDuration: Duration
    private var recentPurchase: (id: UInt64, expires: ContinuousClock.Instant)?
    private var bridgeExpiryTask: Task<Void, Never>?
    private var handledPurchaseIDs: Set<UInt64> = []
    private var revokedIDs: Set<UInt64> = []
    private var eventRevision: UInt64 = 0
    private var changeRevision: UInt64 = 0
    private var latestChange: EntitlementChange?
    private var changeContinuations: [UUID: AsyncStream<EntitlementChange>.Continuation] = [:]
    private var verificationFailurePending = false
    private var purchaseInFlight = false
    private var updatesTask: Task<Void, Never>?
    /// 验过签的 App 包环境；失败不缓存，下次再问。
    private var cachedAppEnvironment: AppStore.Environment?

    #if DEBUG
    private var debugTier: EntitlementTier?
    #endif

    init(
        modelContainer: ModelContainer,
        mutationGate: StorageMutationGate = StorageMutationGate(),
        localStoreKitTestingAllowed: Bool = false,
        store: any StoreKitClient = LiveStoreKitClient(),
        bridgeDuration: Duration = .seconds(5)
    ) {
        self.snapshot = EntitlementSnapshotRepository(modelContainer: modelContainer)
        self.mutationGate = mutationGate
        self.localStoreKitTestingAllowed = localStoreKitTestingAllowed
        self.store = store
        self.bridgeDuration = max(.zero, min(bridgeDuration, .seconds(5)))
    }

    func startListening() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self, store] in
            let updates = await store.updates()
            for await update in updates {
                guard !Task.isCancelled, let self else { break }
                await self.processUpdate(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
        bridgeExpiryTask?.cancel()
    }

    private func beginBridge(for id: UInt64) {
        let expires = ContinuousClock.now.advanced(by: bridgeDuration)
        recentPurchase = (id, expires)
        bridgeExpiryTask?.cancel()
        bridgeExpiryTask = Task { [weak self] in
            do { try await Task.sleep(until: expires, clock: .continuous) }
            catch { return }
            await self?.expireBridge(id: id, expires: expires)
        }
    }

    private func expireBridge(id: UInt64, expires: ContinuousClock.Instant) async {
        guard recentPurchase?.id == id, recentPurchase?.expires == expires else { return }
        recentPurchase = nil
        // Do not leave the UI indefinitely owned after a temporary proof ends.
        publishChange(source: .bridgeExpired)
    }

    private func processUpdate(_ update: StoreTransactionObservation) async {
        // Direct purchases may never appear in Transaction.updates. Both paths
        // must publish; a revoked transaction also invalidates any short bridge.
        if case .verified(let transaction) = update,
           transaction.productID != Self.unlimitedKeysProductID { return }
        do { _ = try await accept(update) } catch { /* refresh reports unknown */ }
        publishChange(source: .transactionUpdate)
    }

    func changes() -> AsyncStream<EntitlementChange> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            changeContinuations[id] = continuation
            if let latestChange { continuation.yield(latestChange) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeChangeContinuation(id) }
            }
        }
    }

    private func removeChangeContinuation(_ id: UUID) {
        changeContinuations[id] = nil
    }

    private func publishChange(source: EntitlementChange.Source) {
        changeRevision &+= 1
        let change = EntitlementChange(revision: changeRevision, source: source)
        latestChange = change
        for continuation in changeContinuations.values {
            continuation.yield(change)
        }
    }

    func currentTier() async throws -> EntitlementTier {
        #if DEBUG
        if let debugTier {
            return Self.canonicalize(debugTier)
        }
        #endif
        // StoreKit currentEntitlements 含本地缓存；空序列 = 未购，须写回 snapshot，避免脏 unlimited 永久放行。
        let live = Self.canonicalize(try await tierFromStoreKit())
        // snapshot 只是本机观测缓存，不是授权依据；落盘失败不得推翻 StoreKit 的权威结果。
        try? await persistSnapshot(tier: live, source: "storekit")
        return live
    }

    func refreshFromStore() async throws {
        await IdentityHygieneLog.runIsolated(source: .startup, steps: [
            (.entitlement, { try await self.pruneSnapshotDuplicates() }),
        ])
        _ = try await currentTier()
    }

    func restorePurchases() async throws -> EntitlementTier {
        recentPurchase = nil
        eventRevision &+= 1
        try await store.sync()
        verificationFailurePending = false
        return try await currentTier()
    }

    func purchaseUnlimitedKeys() async throws -> EntitlementTier {
        guard !purchaseInFlight else {
            throw ApiRelayError.validationFailed(field: "product", reason: "purchase_in_progress")
        }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        return try await complete(try await store.purchase())
    }

    func completePurchase(_ result: StorePurchaseOutcome) async throws -> EntitlementTier {
        try await complete(result)
    }

    private func complete(_ result: StorePurchaseOutcome) async throws -> EntitlementTier {
        switch result {
        case .success(let observation):
            let tier = try await accept(observation)
            publishChange(source: .purchaseCompleted)
            return tier
        case .cancelled:
            throw ApiRelayError.authenticationCancelled
        case .pending:
            throw ApiRelayError.validationFailed(field: "product", reason: "purchase_pending")
        }
    }

    private func accept(_ observation: StoreTransactionObservation) async throws -> EntitlementTier {
        eventRevision &+= 1
        switch observation {
        case .unverified(let productID, _):
            if productID == Self.unlimitedKeysProductID {
                recentPurchase = nil
                verificationFailurePending = true
            }
            throw ApiRelayError.validationFailed(field: "product", reason: "unverified_transaction")
        case .verified(let transaction):
            if transaction.revocationDate != nil, transaction.productID == Self.unlimitedKeysProductID {
                revokedIDs.insert(transaction.id)
                if recentPurchase?.id == transaction.id { recentPurchase = nil }
                await transaction.finish()
                return .free
            }
            guard await grants(transaction) else {
                throw ApiRelayError.validationFailed(field: "product", reason: "transaction_not_eligible")
            }
            verificationFailurePending = false
            // A verified purchase is itself authoritative. The short, in-memory
            // bridge serves the exact same write gate while currentEntitlements
            // catches up; replays never extend its deadline. No snapshot grant.
            if handledPurchaseIDs.insert(transaction.id).inserted {
                beginBridge(for: transaction.id)
            }
            try? await persistSnapshot(tier: .unlimitedKeys, source: "storekit")
            await transaction.finish()
            guard !revokedIDs.contains(transaction.id) else { return try await currentTier() }
            return .unlimitedKeys
        }
    }

    #if DEBUG
    func debugOverride(tier: EntitlementTier?) async throws {
        debugTier = tier.map(Self.canonicalize)
        if let tier {
            try await persistSnapshot(tier: Self.canonicalize(tier), source: "debugOverride")
        } else {
            let live = Self.canonicalize(try await tierFromStoreKit())
            try await persistSnapshot(tier: live, source: "storekit")
        }
    }
    #endif

    /// 无有效买断交易 → `.free`（不得返回 nil 去「信脏 snapshot」）。
    private func tierFromStoreKit() async throws -> EntitlementTier {
        for _ in 0..<3 {
            let revision = eventRevision
            let observations = try await store.currentEntitlements()
            var unknown = false
            var ownedIDs: Set<UInt64> = []
            for observation in observations {
                switch observation {
                case .unverified(let productID, _):
                    unknown = unknown || productID == Self.unlimitedKeysProductID
                case .verified(let transaction):
                    if transaction.productID == Self.unlimitedKeysProductID, transaction.revocationDate != nil {
                        revokedIDs.insert(transaction.id)
                        if recentPurchase?.id == transaction.id { recentPurchase = nil }
                    }
                    if await grants(transaction) { ownedIDs.insert(transaction.id) }
                }
            }
            guard revision == eventRevision else { continue }
            if !ownedIDs.subtracting(revokedIDs).isEmpty {
                verificationFailurePending = false
                return .unlimitedKeys
            }
            if unknown || verificationFailurePending {
                throw ApiRelayError.validationFailed(field: "product", reason: "unverified_transaction")
            }
            if let recentPurchase, !revokedIDs.contains(recentPurchase.id), .now < recentPurchase.expires {
                return .unlimitedKeys
            }
            recentPurchase = nil
            return .free
        }
        throw ApiRelayError.validationFailed(field: "product", reason: "entitlement_changed_during_query")
    }

    private func grants(_ transaction: VerifiedStoreTransaction) async -> Bool {
        let appEnvironment = await resolvedAppEnvironment()
        guard !revokedIDs.contains(transaction.id) else { return false }
        return EntitlementGrantPolicy.grantsUnlimitedKeys(
            productID: transaction.productID, environment: transaction.environment,
            revocationDate: transaction.revocationDate, appEnvironment: appEnvironment,
            localStoreKitTestingAllowed: localStoreKitTestingAllowed
        )
    }

    private func resolvedAppEnvironment() async -> AppStore.Environment? {
        if let cachedAppEnvironment { return cachedAppEnvironment }
        guard let environment = await store.appEnvironment() else { return nil }
        cachedAppEnvironment = environment
        return environment
    }

    /// V1 不暴露 `.relay`：一律视为无限密钥档。
    private static func canonicalize(_ tier: EntitlementTier) -> EntitlementTier {
        tier == .relay ? .unlimitedKeys : tier
    }

    private func persistSnapshot(tier: EntitlementTier, source: String) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "entitlement_snapshot_update")
        defer { storagePermit.finish() }
        try await snapshot.update(tier: tier, source: source)
    }

    private func pruneSnapshotDuplicates() async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "entitlement_snapshot_prune")
        defer { storagePermit.finish() }
        try await snapshot.pruneDuplicateIdentities()
    }

    /// FR-061：清本地权益快照；不吊销 StoreKit。
    func purgeLocalSnapshotForErase() async throws {
        let storagePermit = try mutationGate.beginNormal(
            operation: "entitlement_legacy_erase"
        )
        defer { storagePermit.finish() }
        try await snapshot.deleteAllRecords()
    }

    func purgeLocalSnapshotForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws {
        try mutationGate.validateCommittedEraseToken(
            authorization,
            operation: "entitlement_committed_erase"
        )
        try await snapshot.deleteAllRecords()
    }
}
