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
        XCTAssertTrue(purchase.label.contains("$4.99"),
                      "The UI-test catalog price must match the approved US price")
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
        let quotaPrompt = presentedQuotaPrompt(in: app)
        XCTAssertTrue(quotaPrompt.waitForExistence(timeout: 10), "The free-tier denial must be presented")
        let identifiedPaywall = quotaPrompt.descendants(matching: .any)
            .matching(identifier: "vault.paywall.open").firstMatch
        let openPaywall: XCUIElement
        if identifiedPaywall.exists {
            openPaywall = identifiedPaywall
        } else {
            // Catalyst's AppKit-hosted SwiftUI alert replaces the supplied
            // accessibility identifier with a private action-button ID.
            let labels = ["Unlock Unlimited Keys", "解锁无限密钥"]
            openPaywall = quotaPrompt.buttons.matching(NSPredicate(
                format: "label IN %@ OR title IN %@", labels, labels
            )).firstMatch
        }
        XCTAssertTrue(openPaywall.waitForExistence(timeout: 10))
        openPaywall.tap()
        let purchase = UITestSupport.assertAppears("paywall.purchase", in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: purchase)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        purchase.tap()
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: purchase)
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 10), .completed)
        // No tab switch, app relaunch or second visit to settings.
        UITestSupport.assertAppears("vault.key.add.action", in: app).tap()
        let name = UITestSupport.assertAppears("vault.key.name.input", in: app)
        let expectedName: String
        #if os(macOS) || targetEnvironment(macCatalyst)
        // Synthesized typing into a normal macOS text field triggers a
        // Security-framework runtime warning inside the system text service.
        // The generated fourth-key name is sufficient for this quota test and
        // avoids mutating the user's pasteboard as a workaround.
        expectedName = name.value as? String ?? ""
        XCTAssertFalse(expectedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #else
        name.tap()
        expectedName = "Fourth UI Key"
        let oldName = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count) + expectedName)
        XCTAssertEqual(name.value as? String, expectedName, "The key name must be complete before saving")
        #endif
        let secret = UITestSupport.assertAppears("vault.key.secret.input", in: app)
        secret.tap()
        secret.typeText("sk-ui-fourth-key-test")
        UITestSupport.assertAppears("vault.key.save", in: app).tap()
        XCTAssertTrue(app.staticTexts[expectedName].firstMatch.waitForExistence(timeout: 15))
    }

    func testCancellingQuotaAlertKeepsFreeLimitAndAllowsAnotherAttempt() {
        let app = UITestSupport.launch("entitlement-fourth-key")
        for _ in 0..<2 {
            UITestSupport.assertAppears("vault.key.add.action", in: app).tap()
            let prompt = presentedQuotaPrompt(in: app)
            XCTAssertTrue(prompt.waitForExistence(timeout: 10))
            let cancel = prompt.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label IN %@ OR title IN %@",
                "gate.cancel", ["Cancel", "取消"], ["Cancel", "取消"]
            )).firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            let dismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in !prompt.exists }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
            if prompt.exists {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "quota-cancel-hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "quota-cancel-screen"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            XCTAssertFalse(prompt.exists, "The quota prompt must actually be dismissed")
            XCTAssertFalse(UITestSupport.element("vault.key.name.input", in: app).exists,
                           "Cancelling must not bypass the free-tier write gate")
            XCTAssertFalse(UITestSupport.element("paywall.purchase", in: app).exists,
                           "Cancelling must not open the purchase page")
        }
    }

    private func presentedQuotaPrompt(in app: XCUIApplication) -> XCUIElement {
        #if os(macOS) || targetEnvironment(macCatalyst)
        return app.sheets.firstMatch
        #else
        // The security cover also exposes an alert accessibility trait, even
        // while not covering the UI. It is not a purchase quota presentation.
        return app.alerts.matching(NSPredicate(
            format: "identifier != %@", "vault.lock.cover"
        )).firstMatch
        #endif
    }

    func testSettingsRestoreReportsOwnedResult() {
        let app = launchSettings("settings", state: "owned")
        restoreFromSettings(in: app)
        let result = UITestSupport.assertAppears("settings.restorePurchases.result", in: app)
        XCTAssertTrue(["Purchases restored", "已恢复购买"].contains(displayedText(of: result)))
        assertVisible(result, in: app, message: "Restore feedback should be visible without extra scrolling")
        UITestSupport.assertAppears("settings.entitlement.state.owned", in: app)
    }

    func testSettingsRestoreReportsNoPurchase() {
        let app = launchSettings("entitlement-free", state: "free")
        restoreFromSettings(in: app)
        let result = UITestSupport.assertAppears("settings.restorePurchases.result", in: app)
        XCTAssertTrue(["No previous purchase was found", "未找到可恢复的购买"].contains(displayedText(of: result)))
        assertVisible(result, in: app, message: "Restore feedback should be visible without extra scrolling")
        UITestSupport.assertAppears("settings.entitlement.state.free", in: app)
    }

    private func assertVisible(_ element: XCUIElement, in app: XCUIApplication, message: String) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "The app window must exist")
        XCTAssertFalse(element.frame.isEmpty, message)
        XCTAssertTrue(window.frame.intersects(element.frame), message)
    }

    private func displayedText(of element: XCUIElement) -> String {
        if !element.label.isEmpty {
            return element.label
        }
        return element.value as? String ?? ""
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
