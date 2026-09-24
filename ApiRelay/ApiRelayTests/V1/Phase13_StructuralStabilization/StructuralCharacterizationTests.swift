@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class StructuralCharacterizationTests: XCTestCase {
    func testUITestSettingsFixtureUsesInMemoryServicesAndAppPasswordPolicy() async throws {
        let environment = try UITestFixture.makeEnvironment(scenario: "settings")
        XCTAssertTrue(environment.preferences is FakePreferences)
        XCTAssertTrue(environment.vault is FakeKeyVault)
        XCTAssertTrue(environment.cloudSync is FakeCloudSync)
        let preferences = try await environment.preferences.load()
        XCTAssertEqual(preferences.revealPolicy, .masterPassword)
        XCTAssertFalse(preferences.appLockEnabled)
        XCTAssertEqual(preferences.autoLockSeconds, 0)
        XCTAssertTrue(preferences.hideInAppSwitcher)
        XCTAssertEqual(environment.gate.availableBiometry(), .none)
        try await environment.gate.confirmWithMasterPassword(
            reason: "test", password: UITestFixture.password, purpose: .settings
        )
    }

    func testUITestLockFixtureStartsWithImmediateAutoLockPolicy() async throws {
        let environment = try UITestFixture.makeEnvironment(scenario: "lock")
        let preferences = try await environment.preferences.load()
        XCTAssertTrue(preferences.appLockEnabled)
        XCTAssertEqual(preferences.autoLockSeconds, 0)
        XCTAssertTrue(preferences.hideInAppSwitcher)
        XCTAssertEqual(preferences.revealPolicy, .masterPassword)
        XCTAssertTrue(environment.preferences is FakePreferences)
    }
}
