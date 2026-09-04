@testable import ApiRelay

/// 把 StoreKit 挡在测试之外的权益替身。
///
/// 真 `EntitlementService.currentTier()` 要遍历 `Transaction.currentEntitlements`；
/// 模拟器上没有可用的 App Store，每次调用都得等约 60 秒超时才拿到空序列。
/// 密钥库、回收站、备份这些套件本来就不考 StoreKit，配额只关心「当前是哪一档」，
/// 用这个桩既快又更准（想测免费档就一定是免费档，不看运行环境脸色）。
///
/// MUST NOT 用它替换「本地快照说 unlimited、StoreKit 说没买，以谁为准」这类对账用例的真服务，
/// 那正是 `EntitlementService` 自己的职责，换成桩就测了个空。
actor StubEntitlements: EntitlementServing {
    private var tier: EntitlementTier
    private(set) var currentTierCallCount = 0

    init(tier: EntitlementTier = .free) {
        self.tier = tier
    }

    func currentTier() async throws -> EntitlementTier {
        currentTierCallCount += 1
        return tier
    }

    func refreshFromStore() async throws {}

    func restorePurchases() async throws {}

    func purchaseUnlimitedKeys() async throws {
        tier = .unlimitedKeys
    }

    func startListening() {}

    func purgeLocalSnapshotForErase() async throws {}

    #if DEBUG
    func debugOverride(tier: EntitlementTier?) async throws {
        self.tier = tier ?? .free
    }
    #endif
}
