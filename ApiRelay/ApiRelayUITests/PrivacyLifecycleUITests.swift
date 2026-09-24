import XCTest

@MainActor
final class PrivacyLifecycleUITests: XCTestCase {
    func testPasswordUnlockShowsVaultAndRelaunchLocksAgain() {
        let app = UITestSupport.launch("lock")
        unlock(app)
        UITestSupport.assertAppears("vault.tab.byPlatform", in: app)
        app.terminate()
        app.launch()
        UITestSupport.assertAppears("vault.lock.password", in: app)
        let vaultInteractive = UITestSupport.element("vault.tab.byPlatform", in: app).isHittable
        XCTAssertFalse(vaultInteractive)
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    func testImmediateBackgroundLocksOnReturn() {
        let app = UITestSupport.launch("lock")
        unlock(app)
        UITestSupport.assertAppears("vault.tab.byPlatform", in: app)

        XCUIDevice.shared.press(.home)
        app.activate()

        UITestSupport.assertAppears("vault.lock.password", in: app)
        let vaultInteractive = UITestSupport.element("vault.tab.byPlatform", in: app).isHittable
        XCTAssertFalse(vaultInteractive)
    }
    #endif

    private func unlock(_ app: XCUIApplication) {
        let field = UITestSupport.assertAppears("vault.lock.password", in: app)
        field.tap()
        field.typeText(UITestSupport.fixturePassword)
        UITestSupport.assertAppears("vault.lock.unlock", in: app).tap()
    }
}
