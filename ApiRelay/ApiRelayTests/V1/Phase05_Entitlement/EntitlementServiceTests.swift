@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class EntitlementServiceTests: XCTestCase {
    func testRelayTierUnreachableInV1() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = EntitlementService(modelContainer: container)
        #if DEBUG
        try await sut.debugOverride(tier: .relay)
        let tier = try await sut.currentTier()
        XCTAssertNotEqual(tier, .relay)
        XCTAssertEqual(tier, .unlimitedKeys)
        #else
        let snap = EntitlementSnapshotRepository(modelContainer: container)
        try await snap.update(tier: .relay, source: "test")
        // Release：无 StoreKit 买断交易时纠回 free，不得因脏 snapshot 放行。
        let tier = try await sut.currentTier()
        XCTAssertEqual(tier, .free)
        #endif
    }

    func testStaleUnlimitedSnapshotReconcilesToFreeWithoutPurchase() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = EntitlementService(modelContainer: container)
        let snap = EntitlementSnapshotRepository(modelContainer: container)
        try await snap.update(tier: .unlimitedKeys, source: "stale")
        let tier = try await sut.currentTier()
        XCTAssertEqual(tier, .free)
        let after = try await snap.loadOrCreate()
        XCTAssertEqual(after.tier, .free)
    }

    func testProductIdentifiersMatchPlan() {
        XCTAssertEqual(EntitlementService.unlimitedKeysProductID, "com.apirelay.iap.unlimited_keys")
        XCTAssertEqual(EntitlementService.relayProductIDReserved, "com.apirelay.iap.relay")
    }

    #if DEBUG
    func testDebugOverrideUnlimited() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = EntitlementService(modelContainer: container)
        try await sut.debugOverride(tier: .unlimitedKeys)
        let tier = try await sut.currentTier()
        XCTAssertEqual(tier, .unlimitedKeys)
    }

    func testDebugOverrideClearResyncsFromStore() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = EntitlementService(modelContainer: container)
        try await sut.debugOverride(tier: .unlimitedKeys)
        try await sut.debugOverride(tier: nil)
        let tier = try await sut.currentTier()
        XCTAssertEqual(tier, .free)
    }
    #endif
}
