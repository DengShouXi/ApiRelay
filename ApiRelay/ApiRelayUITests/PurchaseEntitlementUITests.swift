import XCTest

@MainActor
final class PurchaseEntitlementUITests: XCTestCase {
    func testSettingsDistinguishesOwnedFromFree() {
        let owned = UITestSupport.launch("settings")
        UITestSupport.assertAppears("vault.tab.settings", in: owned).tap()
        UITestSupport.assertAppears("settings.entitlement.state.owned", in: owned)
        owned.terminate()

        let free = UITestSupport.launch("entitlement-free")
        UITestSupport.assertAppears("vault.tab.settings", in: free).tap()
        UITestSupport.assertAppears("settings.entitlement.state.free", in: free)
    }

    func testLookupFailureDoesNotOfferPurchaseAsKnownFree() {
        let app = launchPaywall("entitlement-failure", settingsState: "unavailable")
        UITestSupport.assertAppears("paywall.entitlement.unavailable", in: app)
        UITestSupport.assertAppears("paywall.entitlement.retry", in: app)
        let purchase = UITestSupport.assertAppears("paywall.purchase", in: app)
        XCTAssertFalse(purchase.isEnabled, "Unknown ownership must not enable purchase")
    }

    func testPendingLookupDoesNotAppearFree() {
        let app = UITestSupport.launch("entitlement-loading")
        UITestSupport.assertAppears("vault.tab.settings", in: app).tap()
        UITestSupport.assertAppears("settings.entitlement.state.checking", in: app)
    }

    func testVerifiedPurchaseWaitsForAuthoritativeQuotaBeforeClosing() {
        let app = launchPaywall("entitlement-delayed-activation", settingsState: "free")
        let purchase = UITestSupport.assertAppears("paywall.purchase", in: app)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: purchase
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        purchase.tap()
        UITestSupport.assertAppears("paywall.entitlement.activationPending", in: app)
        XCTAssertFalse(purchase.isEnabled, "Do not allow another purchase while activation is pending")

        let disappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: purchase
        )
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 10), .completed)
    }

    func testPendingPurchaseCannotBeStartedAgain() {
        let app = launchPaywall("entitlement-pending-purchase", settingsState: "free")
        let purchase = UITestSupport.assertAppears("paywall.purchase", in: app)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: purchase
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        purchase.tap()
        UITestSupport.assertAppears("paywall.purchasePending", in: app)
        XCTAssertFalse(purchase.isEnabled, "Pending approval must not start a duplicate purchase")
    }

    private func launchPaywall(_ scenario: String, settingsState: String) -> XCUIApplication {
        let app = UITestSupport.launch(scenario)
        UITestSupport.assertAppears("vault.tab.settings", in: app).tap()
        let upgrade = UITestSupport.assertAppears(
            "settings.entitlement.state.\(settingsState)", in: app
        )
        // XCTest's implicit scroll can leave this hit point underneath the tab bar.
        let settingsScroll = app.scrollViews["settings.columnScroll"]
        XCTAssertTrue(settingsScroll.exists)
        for _ in 0..<6 where upgrade.frame.midY > app.frame.maxY - 110 {
            settingsScroll.swipeUp()
        }
        XCTAssertLessThan(upgrade.frame.midY, app.frame.maxY - 110)
        upgrade.tap()
        return app
    }
}
