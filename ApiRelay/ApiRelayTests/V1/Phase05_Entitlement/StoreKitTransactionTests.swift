@preconcurrency import XCTest
@testable import ApiRelay
import StoreKit
import StoreKitTest
import SwiftData

/// Runs serially: SKTestSession mutates the shared local test store.
@MainActor
final class StoreKitTransactionTests: XCTestCase {
    func testStoreKitEntitlementConvergesThenAllowsFourthKeyAndRefundRevokesGrant() async throws {
        let configuration = try XCTUnwrap(
            Bundle.main.url(forResource: "ApiRelay", withExtension: "storekit")
        )
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let container = try AppSchema.makeInMemoryContainer()
        let entitlements = EntitlementService(modelContainer: container)
        let beforePurchase = try await entitlements.currentTier()
        XCTAssertEqual(beforePurchase, .free)

        let keychain = FakeKeychain()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let gate = RevealGate(masterPassword: master) { _, _ in }
        let vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: entitlements
        )
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .noVerification
        try await prefs.update(patch)
        let accountID = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "StoreKit Boundary")
        )
        for index in 1...3 {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountID, displayName: "key-\(index)"),
                secret: "sk-storekit-boundary-\(index)"
            )
        }

        let transaction = try await session.buyProduct(
            identifier: EntitlementService.unlimitedKeysProductID
        )
        let testTransaction = try XCTUnwrap(session.allTransactions().first)
        var afterPurchase = try await entitlements.currentTier()
        var purchaseWaitMs = 0
        while afterPurchase == .free && purchaseWaitMs < 5_000 {
            try await Task.sleep(for: .milliseconds(250))
            purchaseWaitMs += 250
            afterPurchase = try await entitlements.currentTier()
        }
        XCTAssertEqual(
            afterPurchase,
            .unlimitedKeys,
            "Transaction.currentEntitlements did not converge after 5 s; purchased=\(transaction.environment)"
        )
        _ = try await vault.createKey(
            KeyDraft(accountId: accountID, displayName: "key-4"),
            secret: "sk-storekit-boundary-4"
        )
        let countAfterPurchase = try await vault.keys(in: accountID).count
        XCTAssertEqual(countAfterPurchase, 4)

        try session.refundTransaction(identifier: UInt(testTransaction.identifier))
        var afterRefund = try await entitlements.currentTier()
        var refundWaitMs = 0
        while afterRefund == .unlimitedKeys && refundWaitMs < 5_000 {
            try await Task.sleep(for: .milliseconds(250))
            refundWaitMs += 250
            afterRefund = try await entitlements.currentTier()
        }
        XCTAssertEqual(afterRefund, .free)
        do {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountID, displayName: "key-5"),
                secret: "sk-storekit-boundary-5"
            )
            XCTFail("Refund must revoke the grant for new keys")
        } catch let ApiRelayError.quotaExceededFreeTier(limit) {
            XCTAssertEqual(limit, 3)
        }
        let countAfterRefund = try await vault.keys(in: accountID).count
        XCTAssertEqual(countAfterRefund, 4)
    }
}
