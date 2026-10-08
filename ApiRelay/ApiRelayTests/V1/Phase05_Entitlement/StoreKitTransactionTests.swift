@preconcurrency import XCTest
@testable import ApiRelay
import StoreKit
import StoreKitTest
import SwiftData

/// Runs serially: SKTestSession mutates the shared local test store.
@MainActor
#if targetEnvironment(macCatalyst)
// Xcode 27 ships no Catalyst Swift overlay for the replacement async API.
// Keep the compatibility use inside an equally deprecated declaration so the
// test target can retain warnings-as-errors everywhere else.
@available(macCatalyst, deprecated: 17.0, message: "StoreKitTest Catalyst overlay unavailable")
#elseif os(macOS)
// The Xcode 27 async StoreKitTest API returns an opaque `unknown` error on
// macOS 26.7. The external-purchase API still exercises the configured local
// store and publishes a verified StoreKit 2 entitlement.
@available(macOS, deprecated: 14.0, message: "StoreKitTest async desktop purchase unavailable")
#endif
final class StoreKitTransactionTests: XCTestCase {
    func testNativeCompletionUsesVerifiedStoreKitTransaction() async throws {
        let configuration = try XCTUnwrap(Bundle.main.url(forResource: "ApiRelay", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let transaction = try await buyUnlimitedKeys(using: session)
        let service = EntitlementService(modelContainer: try AppSchema.makeInMemoryContainer(),
                                         localStoreKitTestingAllowed: true)
        let result = Product.PurchaseResult.success(.verified(transaction))
        let tier = try await service.completePurchase(LiveStoreKitClient.outcome(result))
        XCTAssertEqual(tier, .unlimitedKeys)
        let observed = try await service.currentTier()
        XCTAssertEqual(observed, .unlimitedKeys)
    }

    func testXcodeTransactionCannotUnlockOrdinaryAppInstance() async throws {
        let configuration = try XCTUnwrap(
            Bundle.main.url(forResource: "ApiRelay", withExtension: "storekit")
        )
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        _ = try await buyUnlimitedKeys(using: session)
        let container = try AppSchema.makeInMemoryContainer()
        let testOptIn = EntitlementService(
            modelContainer: container,
            localStoreKitTestingAllowed: true
        )
        var observedTier = try await testOptIn.currentTier()
        for _ in 0..<20 where observedTier == .free {
            try await Task.sleep(for: .milliseconds(250))
            observedTier = try await testOptIn.currentTier()
        }
        XCTAssertEqual(observedTier, .unlimitedKeys)

        let ordinaryApp = EntitlementService(modelContainer: container)
        let ordinaryTier = try await ordinaryApp.currentTier()
        XCTAssertEqual(ordinaryTier, .free)
    }

    func testStoreKitEntitlementConvergesThenAllowsFourthKeyAndRefundRevokesGrant() async throws {
        let configuration = try XCTUnwrap(
            Bundle.main.url(forResource: "ApiRelay", withExtension: "storekit")
        )
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let container = try AppSchema.makeInMemoryContainer()
        let entitlements = EntitlementService(
            modelContainer: container,
            localStoreKitTestingAllowed: true
        )
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

        let transaction = try await buyUnlimitedKeys(using: session)
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

    private func buyUnlimitedKeys(using session: SKTestSession) async throws -> Transaction {
        #if os(macOS) || targetEnvironment(macCatalyst)
        // Catalyst has no Swift overlay for the async API, and the native Mac
        // implementation currently returns `unknown`. The Objective-C
        // external-purchase entry point still drives the same configured test
        // store; obtain the verified StoreKit 2 transaction from the
        // authoritative entitlement sequence instead of fabricating it.
        _ = try session.buyProduct(productIdentifier: EntitlementService.unlimitedKeysProductID)
        for _ in 0..<20 {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   transaction.productID == EntitlementService.unlimitedKeysProductID {
                    return transaction
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw ApiRelayError.validationFailed(
            field: "product",
            reason: "storekit_transaction_not_visible"
        )
        #else
        return try await session.buyProduct(
            identifier: EntitlementService.unlimitedKeysProductID
        )
        #endif
    }
}
