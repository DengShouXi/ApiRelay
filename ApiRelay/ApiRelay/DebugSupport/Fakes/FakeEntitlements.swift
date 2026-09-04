#if DEBUG
import Foundation

/// 假权益：内存档位。不碰 StoreKit / SwiftData。
actor FakeEntitlements: EntitlementServing {
    var journal = FakeJournal()
    private var tier: EntitlementTier

    init(tier: EntitlementTier = .free) {
        self.tier = tier
    }

    func currentTier() async throws -> EntitlementTier {
        try journal.record("currentTier")
        return tier
    }

    func refreshFromStore() async throws {
        try journal.record("refreshFromStore")
    }

    func restorePurchases() async throws {
        try journal.record("restorePurchases")
    }

    func purchaseUnlimitedKeys() async throws {
        try journal.record("purchaseUnlimitedKeys")
        tier = .unlimitedKeys
    }

    func startListening() {
        journal.recordNonThrowing("startListening")
    }

    func purgeLocalSnapshotForErase() async throws {
        try journal.record("purgeLocalSnapshotForErase")
        tier = .free
    }

    func debugOverride(tier: EntitlementTier?) async throws {
        try journal.record("debugOverride")
        self.tier = tier ?? .free
    }
}
#endif
