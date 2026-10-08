@preconcurrency import XCTest
@testable import ApiRelay
import StoreKit
import SwiftData

@MainActor
final class EntitlementFlowTests: XCTestCase {
    func testStoreUpdateDuringNativePaymentIsNotLostOnCancel() async throws {
        let client = FakeStoreKitClient()
        let model = EntitlementStore(service: try makeService(client), storeKit: client)
        await model.refresh()
        model.beginNativePurchase()
        await client.setObservations([.verified(FakeStoreKitClient.transaction())])
        await model.refresh() // A transaction notification arrives while busy.
        await model.completeNativePurchase(.success(.userCancelled))
        for _ in 0..<60 where model.state != .owned {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.state, .owned)
    }

    func testProductReloadCannotErasePendingPurchaseMessage() async throws {
        let client = FakeStoreKitClient(pending: true)
        let model = EntitlementStore(service: try makeService(client), storeKit: client)
        await model.refresh()
        await model.loadProduct()
        await model.purchase()
        let pendingMessage = model.message
        XCTAssertFalse(pendingMessage.isEmpty)
        await model.loadProduct()
        XCTAssertEqual(model.message, pendingMessage)
        XCTAssertTrue(model.approvalPending)
    }

    func testBridgeExpiryRefreshesSharedUIWithoutAnotherUserAction() async throws {
        let client = FakeStoreKitClient(purchaseVisibleInQueries: false)
        let service = try makeService(client, bridge: .milliseconds(100))
        let model = EntitlementStore(service: service, storeKit: client)
        await model.refresh()
        await model.loadProduct()
        await model.purchase()
        XCTAssertEqual(model.state, .owned)
        for _ in 0..<60 where model.state != .free {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.state, .free, "Temporary proof must not leave an owned UI indefinitely")
    }

    func testOnlyOneServicePurchaseCanBeInFlight() async throws {
        let client = FakeStoreKitClient(purchaseDelay: .milliseconds(150))
        let service = try makeService(client)
        let first = Task { try await service.purchaseUnlimitedKeys() }
        for _ in 0..<40 where await client.purchaseCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        do {
            _ = try await service.purchaseUnlimitedKeys()
            XCTFail("A reentrant actor must not start a second payment")
        } catch ApiRelayError.validationFailed(let field, let reason) {
            XCTAssertEqual(field, "product")
            XCTAssertEqual(reason, "purchase_in_progress")
        }
        let tier = try await first.value
        XCTAssertEqual(tier, .unlimitedKeys)
        let calls = await client.purchaseCount
        XCTAssertEqual(calls, 1)
    }

    func testExternalApprovalAndRevocationRefreshSharedState() async throws {
        let client = FakeStoreKitClient(pending: true)
        let service = try makeService(client)
        let model = EntitlementStore(service: service, storeKit: client)
        await model.refresh()
        await model.loadProduct()
        await model.purchase()
        XCTAssertTrue(model.approvalPending)
        await service.startListening()
        for _ in 0..<40 where !(await client.isListening) {
            try await Task.sleep(for: .milliseconds(5))
        }
        let listening = await client.isListening
        XCTAssertTrue(listening)
        await client.send(.verified(FakeStoreKitClient.transaction()))
        for _ in 0..<60 where model.state != .owned {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.state, .owned)
        XCTAssertFalse(model.approvalPending)
        await client.send(.verified(FakeStoreKitClient.transaction(revoked: true)))
        for _ in 0..<60 where model.state != .free {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.state, .free)
        let tier = try await service.currentTier()
        XCTAssertEqual(tier, .free)
    }

    func testNativePendingAndCancelShareTheSameStateMachine() async throws {
        let client = FakeStoreKitClient()
        let store = EntitlementStore(service: try makeService(client), storeKit: client)
        await store.refresh()
        await store.loadProduct()
        store.beginNativePurchase()
        await store.completeNativePurchase(.success(.pending))
        XCTAssertTrue(store.approvalPending)
        XCTAssertFalse(store.isBusy)
        await store.retryPendingPurchase()
        store.beginNativePurchase()
        await store.completeNativePurchase(.success(.userCancelled))
        XCTAssertEqual(store.state, .free)
        XCTAssertTrue(store.canPurchase)
    }

    func testSameTransactionRevocationWinsRegardlessOfQueryOrder() async throws {
        let client = FakeStoreKitClient()
        await client.setObservations([
            .verified(FakeStoreKitClient.transaction()),
            .verified(FakeStoreKitClient.transaction(revoked: true))
        ])
        let tier = try await makeService(client).currentTier()
        XCTAssertEqual(tier, .free)
    }

    private func makeService(_ client: FakeStoreKitClient, bridge: Duration = .seconds(5)) throws -> EntitlementService {
        EntitlementService(modelContainer: try AppSchema.makeInMemoryContainer(), store: client, bridgeDuration: bridge)
    }

    func testRelevantUnverifiedQueryIsUnknownNotFree() async throws {
        let client = FakeStoreKitClient()
        await client.setObservations([.unverified(
            productID: EntitlementService.unlimitedKeysProductID,
            failure: .verificationFailed
        )])
        let store = EntitlementStore(service: try makeService(client), storeKit: client)
        await store.refresh()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertFalse(store.canPurchase)
    }

    func testUnrelatedUnverifiedProductDoesNotBlockFreeTier() async throws {
        let client = FakeStoreKitClient()
        await client.setObservations([.unverified(
            productID: "unrelated.product",
            failure: .verificationFailed
        )])
        let tier = try await makeService(client).currentTier()
        XCTAssertEqual(tier, .free)
    }

    func testProductLoadFailureRetriesOnSameStore() async throws {
        let client = FakeStoreKitClient(productFailures: 1)
        let store = EntitlementStore(service: try makeService(client), storeKit: client)
        await store.refresh()
        await store.loadProduct()
        XCTAssertNil(store.product)
        XCTAssertFalse(store.canPurchase)
        await store.loadProduct()
        XCTAssertNotNil(store.product)
        XCTAssertTrue(store.canPurchase)
        let loads = await client.productLoadCount
        XCTAssertEqual(loads, 2)
    }

    func testCancelLeavesSamePageReadyForAnotherPurchase() async throws {
        let client = FakeStoreKitClient(cancelled: true)
        let store = EntitlementStore(service: try makeService(client), storeKit: client)
        await store.refresh()
        await store.loadProduct()
        await store.purchase()
        XCTAssertEqual(store.state, .free)
        XCTAssertTrue(store.canPurchase)
        XCTAssertTrue(store.message.isEmpty)
        await client.setOutcome(.success(.verified(FakeStoreKitClient.transaction())))
        await store.purchase()
        XCTAssertEqual(store.state, .owned)
    }

    func testPendingRequiresExplicitRetryButDoesNotPermanentlyDisablePage() async throws {
        let client = FakeStoreKitClient(pending: true)
        let store = EntitlementStore(service: try makeService(client), storeKit: client)
        await store.refresh()
        await store.loadProduct()
        await store.purchase()
        await store.purchase()
        let calls = await client.purchaseCount
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(store.approvalPending)
        await store.refresh()
        XCTAssertTrue(store.approvalPending, "Empty entitlements cannot prove an Ask-to-Buy denial")
        await store.retryPendingPurchase()
        XCTAssertTrue(store.canPurchase)
        XCTAssertFalse(store.approvalPending)
    }

    func testUnverifiedPurchaseDoesNotGrantAndShowsUnknown() async throws {
        let client = FakeStoreKitClient()
        await client.setOutcome(.success(.unverified(
            productID: EntitlementService.unlimitedKeysProductID,
            failure: .verificationFailed
        )))
        let store = EntitlementStore(service: try makeService(client), storeKit: client)
        await store.refresh()
        await store.loadProduct()
        await store.purchase()
        XCTAssertEqual(store.state, .unavailable)
        XCTAssertFalse(store.canPurchase)
    }

    func testVerifiedPurchaseBridgeExpiresAndDoesNotTrustSnapshot() async throws {
        let client = FakeStoreKitClient()
        let service = try makeService(client, bridge: .milliseconds(30))
        let bought = try await service.purchaseUnlimitedKeys()
        XCTAssertEqual(bought, .unlimitedKeys)
        await client.setObservations([])
        let bridged = try await service.currentTier()
        XCTAssertEqual(bridged, .unlimitedKeys)
        try await Task.sleep(for: .milliseconds(60))
        let expired = try await service.currentTier()
        XCTAssertEqual(expired, .free)
    }

    func testRepeatedPurchaseResultCannotExtendBridge() async throws {
        let client = FakeStoreKitClient()
        let service = try makeService(client, bridge: .milliseconds(30))
        _ = try await service.purchaseUnlimitedKeys()
        try await Task.sleep(for: .milliseconds(60))
        _ = try await service.purchaseUnlimitedKeys()
        await client.setObservations([])
        let tier = try await service.currentTier()
        XCTAssertEqual(tier, .free)
    }

    func testExplicitRestoreEndsBridgeImmediately() async throws {
        let client = FakeStoreKitClient()
        let service = try makeService(client)
        _ = try await service.purchaseUnlimitedKeys()
        await client.setObservations([])
        let tier = try await service.restorePurchases()
        XCTAssertEqual(tier, .free)
    }

    func testRevokedQueryEndsBridgeImmediately() async throws {
        let client = FakeStoreKitClient()
        let service = try makeService(client)
        _ = try await service.purchaseUnlimitedKeys()
        await client.setObservations([.verified(FakeStoreKitClient.transaction(revoked: true))])
        let tier = try await service.currentTier()
        XCTAssertEqual(tier, .free)
    }

    func testLateFreeQueryCannotOverwriteVerifiedPurchase() async throws {
        let client = FakeStoreKitClient(queryDelay: .milliseconds(100))
        let service = try makeService(client)
        let store = EntitlementStore(service: service, storeKit: client)
        await store.refresh()
        await store.loadProduct()
        let stale = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(20))
        // Simulates ProductView starting after its product was displayed.
        store.beginNativePurchase()
        _ = try await service.purchaseUnlimitedKeys()
        await stale.value
        await store.completeNativePurchase(.success(.userCancelled))
        await store.refresh()
        for _ in 0..<60 where store.state == .checking {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.state, .owned)
    }

    func testPurchaseUpdatesSharedStateWithoutDependingOnTransactionUpdates() async throws {
        let client = FakeStoreKitClient()
        let service = try makeService(client)
        let store = EntitlementStore(service: service, storeKit: client)
        await store.refresh()
        _ = try await service.purchaseUnlimitedKeys()
        for _ in 0..<40 where store.state != .owned {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.state, .owned)
    }

    func testLateSubscriberReplaysLatestEntitlementChange() async throws {
        let client = FakeStoreKitClient()
        let service = try makeService(client)
        _ = try await service.purchaseUnlimitedKeys()
        let store = EntitlementStore(service: service, storeKit: client)
        for _ in 0..<40 where store.state != .owned {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.state, .owned)
    }

    func testFourthKeyUsesRealServiceThenRefundPreservesExistingKeys() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let client = FakeStoreKitClient()
        let service = EntitlementService(modelContainer: container, store: client)
        let keychain = FakeKeychain()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        let vault = KeyVaultService(keychain: keychain, gate: gate, clipboard: FakeClipboard(),
                                    modelContainer: container, entitlements: service)
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .noVerification
        try await prefs.update(patch)
        let account = try await vault.createAccount(UpstreamAccountDraft(platform: "openai", displayName: "Flow"))
        for index in 1...3 {
            _ = try await vault.createKey(KeyDraft(accountId: account, displayName: "k\(index)"),
                                          secret: "sk-purchase-flow-\(index)")
        }
        let model = EntitlementStore(service: service, storeKit: client)
        await model.refresh()
        await model.loadProduct()
        await model.purchase()
        await client.setObservations([]) // Verified callback may precede cache.
        _ = try await vault.createKey(KeyDraft(accountId: account, displayName: "k4"), secret: "sk-purchase-flow-4")
        XCTAssertEqual(model.state, .owned)
        await client.setObservations([.verified(FakeStoreKitClient.transaction(revoked: true))])
        _ = try await service.restorePurchases()
        do {
            _ = try await vault.createKey(KeyDraft(accountId: account, displayName: "k5"), secret: "sk-purchase-flow-5")
            XCTFail("Refund must prevent extra writes")
        } catch ApiRelayError.quotaExceededFreeTier(let limit) {
            XCTAssertEqual(limit, 3)
        }
        let keys = try await vault.keys(in: account)
        XCTAssertEqual(keys.count, 4)
        let secret = try await keychain.read(service: .keys, account: keys.last!.id)
        XCTAssertFalse(secret.isEmpty)
    }
}
