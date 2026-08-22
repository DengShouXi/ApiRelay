@preconcurrency import XCTest
@testable import ApiRelay
import LocalAuthentication

@MainActor
final class RevealGateTests: XCTestCase {
    func testPolicyNoneDoesNotCallLA() async throws {
        let keychain = KeychainStore.makeForTests(disableSynchronizable: false)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let flag = CallFlag()
        let gate = RevealGate(masterPassword: master) { _, _ in
            flag.mark()
        }
        try await gate.confirm(reason: "test", policy: .none)
        XCTAssertFalse(flag.called)
    }

    func testBiometricOnlyWithoutBiometryFails() async throws {
        let keychain = KeychainStore.makeForTests(disableSynchronizable: false)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        switch gate.availableBiometry() {
        case .none:
            do {
                try await gate.confirm(reason: "test", policy: .biometricOnly)
                XCTFail("expected biometryUnavailable")
            } catch ApiRelayError.biometryUnavailable {
                // expected
            }
        case .faceID, .touchID:
            break
        }
    }

    func testMasterPasswordNotSetFails() async throws {
        let keychain = KeychainStore.makeForTests(disableSynchronizable: false)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let gate = RevealGate(masterPassword: master)
        do {
            try await gate.confirm(reason: "test", policy: .masterPassword)
            XCTFail("expected validationFailed")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertTrue(reason.contains("master_password"))
        }
    }
}

private final class CallFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _called = false
    var called: Bool {
        lock.lock(); defer { lock.unlock() }
        return _called
    }
    func mark() {
        lock.lock(); defer { lock.unlock() }
        _called = true
    }
}
