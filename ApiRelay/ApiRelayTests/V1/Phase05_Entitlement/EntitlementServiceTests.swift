@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class EntitlementServiceTests: XCTestCase {
    func testRelayTierUnreachableInV1() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sut = EntitlementService(modelContainer: container)
        let snap = EntitlementSnapshotRepository(modelContainer: container)
        try await snap.update(tier: .relay, source: "test")
        let tier = try await sut.currentTier()
        XCTAssertNotEqual(tier, .relay)
        XCTAssertEqual(tier, .unlimitedKeys)
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
    #endif
}
