import XCTest

@MainActor
final class SecuritySettingsUITests: XCTestCase {
    func testWrongAppPasswordKeepsPolicyAndAllowsRetryOnCurrentPage() {
        let app = UITestSupport.launch("settings")
        UITestSupport.assertAppears("vault.tab.settings", in: app).tap()
        UITestSupport.assertAppears("settings.revealPolicy.entry", in: app).tap()

        let appPolicy = UITestSupport.assertAppears("settings.policy.masterPassword", in: app)
        let devicePolicy = UITestSupport.assertAppears("settings.policy.biometricOrPasscode", in: app)
        XCTAssertTrue(appPolicy.isSelected)

        devicePolicy.tap()
        let passwordField = app.secureTextFields.firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 15))
        passwordField.tap()
        passwordField.typeText("wrong-UI-test-password")
        UITestSupport.assertAppears("settings.passwordConfirmation.submit", in: app).tap()

        let failureAlert = UITestSupport.securityErrorPresentation(in: app)
        XCTAssertTrue(failureAlert.waitForExistence(timeout: 15), "Wrong password must show an error")
        failureAlert.buttons.firstMatch.tap()
        XCTAssertTrue(appPolicy.isSelected, "Failed authorization must not change the committed policy")
        XCTAssertFalse(devicePolicy.isSelected)
        XCTAssertTrue(devicePolicy.exists, "The policy page must remain visible for retry")

        devicePolicy.tap()
        XCTAssertTrue(passwordField.waitForExistence(timeout: 15))
        passwordField.tap()
        passwordField.typeText(UITestSupport.fixturePassword)
        UITestSupport.assertAppears("settings.passwordConfirmation.submit", in: app).tap()

        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: devicePolicy)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(devicePolicy.isSelected)
        XCTAssertFalse(appPolicy.isSelected)
    }

    func testAppPasswordToDevicePolicyCompletesOnCurrentPage() {
        let app = UITestSupport.launch("settings")
        let settingsTab = UITestSupport.assertAppears("vault.tab.settings", in: app)
        settingsTab.tap()

        let policyEntry = UITestSupport.assertAppears("settings.revealPolicy.entry", in: app)
        policyEntry.tap()

        let appPolicy = UITestSupport.assertAppears("settings.policy.masterPassword", in: app)
        let initiallySelected = appPolicy.isSelected
        XCTAssertTrue(initiallySelected, "The fixture must begin on app-password verification")

        let devicePolicy = UITestSupport.assertAppears("settings.policy.biometricOrPasscode", in: app)
        devicePolicy.tap()

        // SwiftUI alert content is hosted by UIKit, which does not retain the
        // custom identifier on its secure field. The alert is the only secure
        // input in this fixture, so query its native accessibility type.
        let passwordField = app.secureTextFields.firstMatch
        let fieldAppeared = passwordField.waitForExistence(timeout: 15)
        XCTAssertTrue(fieldAppeared, "The password confirmation must appear on this page")
        passwordField.tap()
        passwordField.typeText(UITestSupport.fixturePassword)
        UITestSupport.assertAppears("settings.passwordConfirmation.submit", in: app).tap()

        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: devicePolicy)
        waitForExpectations(timeout: 15)
        let deviceSelected = devicePolicy.isSelected
        let appSelected = appPolicy.isSelected
        XCTAssertTrue(deviceSelected, "Policy must update without navigating back to Settings")
        XCTAssertFalse(appSelected)
    }
}
