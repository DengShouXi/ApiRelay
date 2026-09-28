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

    func testVerifiedPurchasePublishesOwnedStateWithoutReopeningSettings() {
        let app = launchPaywall("entitlement-delayed-activation", settingsState: "free")
        let purchase = UITestSupport.assertAppears("paywall.purchase", in: app)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: purchase
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 20), .completed)
        purchase.tap()
        let disappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: purchase
        )
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 10), .completed)
        UITestSupport.assertAppears("settings.entitlement.state.owned", in: app)
    }

    func testPendingPurchaseCannotBeStartedAgain() {
        let app = launchPaywall("entitlement-pending-purchase", settingsState: "free")
        let purchase = UITestSupport.assertAppears("paywall.purchase", in: app)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: purchase
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 20), .completed)
        purchase.tap()
        UITestSupport.assertAppears("paywall.purchasePending", in: app)
        XCTAssertFalse(purchase.isEnabled, "Pending approval must not start a duplicate purchase")
        UITestSupport.assertAppears("paywall.pending.retry", in: app).tap()
        let retried = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: purchase)
        XCTAssertEqual(XCTWaiter.wait(for: [retried], timeout: 10), .completed)
    }

    func testProductFailureCanRetryOnSamePage() {
        let app = launchPaywall("entitlement-product-retry", settingsState: "free")
        UITestSupport.assertAppears("paywall.product.retry", in: app).tap()
        let purchase = UITestSupport.assertAppears("paywall.purchase", in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: purchase)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
    }

    func testCancellationKeepsPurchasePageUsable() {
        let app = launchPaywall("entitlement-cancelled", settingsState: "free")
        let purchase = UITestSupport.assertAppears("paywall.purchase", in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: purchase)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        purchase.tap()
        let readyAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: purchase)
        XCTAssertEqual(XCTWaiter.wait(for: [readyAgain], timeout: 10), .completed)
        UITestSupport.assertAppears("paywall.entitlement.state.free", in: app)
    }

    func testPurchaseFromQuotaLimitImmediatelyAllowsFourthKey() {
        let app = UITestSupport.launch("entitlement-fourth-key")
        UITestSupport.assertAppears("vault.paywall.open", in: app)
        // Exercise the actual free-tier denial before buying, then retry the
        // same add action. The fixture must not have an unlimited fake vault.
        UITestSupport.assertAppears("vault.key.add.action", in: app).tap()
        UITestSupport.assertAppears("vault.paywall.open", in: app).tap()
        let purchase = UITestSupport.assertAppears("paywall.purchase", in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: purchase)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        purchase.tap()
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: purchase)
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 10), .completed)
        // No tab switch, app relaunch or second visit to settings.
        UITestSupport.assertAppears("vault.key.add.action", in: app).tap()
        let name = UITestSupport.assertAppears("vault.key.name.input", in: app)
        name.tap()
        let oldName = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count) + "Fourth UI Key")
        let secret = UITestSupport.assertAppears("vault.key.secret.input", in: app)
        secret.tap()
        secret.typeText("sk-ui-fourth-key-test")
        UITestSupport.assertAppears("vault.key.save", in: app).tap()
        XCTAssertTrue(app.staticTexts["Fourth UI Key"].firstMatch.waitForExistence(timeout: 15))
    }

    func testSettingsRestoreReportsOwnedResult() {
        let app = launchSettings("settings", state: "owned")
        restoreFromSettings(in: app)
        let result = UITestSupport.assertAppears("settings.restorePurchases.result", in: app)
        XCTAssertTrue(["Purchases restored", "已恢复购买"].contains(result.label))
        XCTAssertTrue(result.isHittable, "Restore feedback should be visible without extra scrolling")
        UITestSupport.assertAppears("settings.entitlement.state.owned", in: app)
    }

    func testSettingsRestoreReportsNoPurchase() {
        let app = launchSettings("entitlement-free", state: "free")
        restoreFromSettings(in: app)
        let result = UITestSupport.assertAppears("settings.restorePurchases.result", in: app)
        XCTAssertTrue(["No previous purchase was found", "未找到可恢复的购买"].contains(result.label))
        XCTAssertTrue(result.isHittable, "Restore feedback should be visible without extra scrolling")
        UITestSupport.assertAppears("settings.entitlement.state.free", in: app)
    }

    private func launchSettings(_ scenario: String, state: String) -> XCUIApplication {
        let app = UITestSupport.launch(scenario)
        UITestSupport.assertAppears("vault.tab.settings", in: app).tap()
        UITestSupport.assertAppears("settings.entitlement.state.\(state)", in: app)
        return app
    }

    private func restoreFromSettings(in app: XCUIApplication) {
        let restore = app.buttons["settings.restorePurchases.action"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        let settingsScroll = app.scrollViews["settings.columnScroll"]
        XCTAssertTrue(settingsScroll.exists)
        for _ in 0..<6 where restore.frame.midY > app.frame.maxY - 110 {
            settingsScroll.swipeUp()
        }
        XCTAssertLessThan(restore.frame.midY, app.frame.maxY - 110)
        restore.tap()
    }

    private func launchPaywall(_ scenario: String, settingsState: String) -> XCUIApplication {
        let app = UITestSupport.launch(scenario)
        UITestSupport.assertAppears("vault.tab.settings", in: app).tap()
        UITestSupport.assertAppears("settings.entitlement.state.\(settingsState)", in: app)
        // Keep the action locator stable while automatic refresh changes the
        // state suffix. Do not tap the off-screen container with the same ID.
        let upgrade = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "settings.entitlement.state."
        )).firstMatch
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
