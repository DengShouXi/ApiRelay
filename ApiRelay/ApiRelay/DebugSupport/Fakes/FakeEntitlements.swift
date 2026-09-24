#if DEBUG
import Foundation

/// 假权益：内存档位。不碰 StoreKit / SwiftData。
actor FakeEntitlements: EntitlementServing {
    var journal = FakeJournal()
    private var tier: EntitlementTier
    private let queryFails: Bool
    private let queryDelayNanoseconds: UInt64
    private let activationDelayNanoseconds: UInt64
    private let purchaseIsPending: Bool
    private var activationReadyUptime: TimeInterval?

    init(
        tier: EntitlementTier = .free,
        queryFails: Bool = false,
        queryDelayNanoseconds: UInt64 = 0,
        activationDelayNanoseconds: UInt64 = 0,
        purchaseIsPending: Bool = false
    ) {
        self.tier = tier
        self.queryFails = queryFails
        self.queryDelayNanoseconds = queryDelayNanoseconds
        self.activationDelayNanoseconds = activationDelayNanoseconds
        self.purchaseIsPending = purchaseIsPending
    }

    func currentTier() async throws -> EntitlementTier {
        if queryDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: queryDelayNanoseconds)
        }
        try journal.record("currentTier")
        if queryFails {
            throw ApiRelayError.networkUnavailable
        }
        if let activationReadyUptime,
           ProcessInfo.processInfo.systemUptime < activationReadyUptime {
            return .free
        }
        return tier
    }

    func refreshFromStore() async throws {
        try journal.record("refreshFromStore")
    }

    func restorePurchases() async throws -> EntitlementTier {
        try journal.record("restorePurchases")
        return tier
    }

    func purchaseUnlimitedKeys() async throws -> EntitlementTier {
        try journal.record("purchaseUnlimitedKeys")
        if purchaseIsPending {
            throw ApiRelayError.validationFailed(field: "product", reason: "purchase_pending")
        }
        tier = .unlimitedKeys
        if activationDelayNanoseconds > 0 {
            activationReadyUptime = ProcessInfo.processInfo.systemUptime
                + TimeInterval(activationDelayNanoseconds) / 1_000_000_000
        }
        return tier
    }

    func startListening() {
        journal.recordNonThrowing("startListening")
    }

    func purgeLocalSnapshotForErase() async throws {
        try journal.record("purgeLocalSnapshotForErase")
        tier = .free
        activationReadyUptime = nil
    }

    func purgeLocalSnapshotForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws {
        try authorization.validate(operation: "fake_entitlement_committed_erase")
        try journal.record("purgeLocalSnapshotForErase")
        tier = .free
        activationReadyUptime = nil
    }

    func debugOverride(tier: EntitlementTier?) async throws {
        try journal.record("debugOverride")
        self.tier = tier ?? .free
        activationReadyUptime = nil
    }
}
#endif
