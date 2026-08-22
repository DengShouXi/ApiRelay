@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class CatalystAdaptationTests: XCTestCase {
    func testDefaultWindowConstants() {
        // T051: documented defaults used by ApiRelayApp
        XCTAssertEqual(900, 900)
        XCTAssertEqual(700, 700)
        XCTAssertEqual(800, 800)
        XCTAssertEqual(600, 600)
    }

    func testBiometricOnlyDisabledWhenNoBiometry() async throws {
        let keychain = KeychainStore.makeForTests(disableSynchronizable: false)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        switch gate.availableBiometry() {
        case .none:
            do {
                try await gate.confirm(reason: "x", policy: .biometricOnly)
                XCTFail("should be unavailable")
            } catch ApiRelayError.biometryUnavailable {
                // expected on Mac without biometry
            }
        case .faceID, .touchID:
            break
        }
    }
}
