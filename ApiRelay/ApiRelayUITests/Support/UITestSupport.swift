import XCTest

@MainActor
enum UITestSupport {
    static let fixturePassword = "UITestPass123"

    static func securityErrorPresentation(in app: XCUIApplication) -> XCUIElement {
        #if os(macOS) || targetEnvironment(macCatalyst)
        app.sheets.firstMatch
        #else
        app.alerts.firstMatch
        #endif
    }

    static func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["APIRELAY_UI_TEST_SCENARIO"] = scenario
        app.launch()
        #if os(macOS) || targetEnvironment(macCatalyst)
        // Launching a desktop app from the UI runner can leave its window
        // inactive. The app correctly installs its privacy cover on resign;
        // bring it user-facing before attempting to interact with Settings.
        app.activate()
        #endif
        return app
    }

    static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @discardableResult
    static func assertAppears(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let element = element(identifier, in: app)
        let appeared = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(appeared, "Missing \(identifier)", file: file, line: line)
        return element
    }
}
