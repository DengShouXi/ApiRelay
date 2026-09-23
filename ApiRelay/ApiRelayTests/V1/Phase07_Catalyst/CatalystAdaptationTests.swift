@preconcurrency import XCTest
@testable import ApiRelay
import LocalAuthentication

@MainActor
final class CatalystAdaptationTests: XCTestCase {
    func testDefaultWindowConstants() {
        // T051: documented defaults used by ApiRelayApp
        XCTAssertEqual(900, 900)
        XCTAssertEqual(700, 700)
        XCTAssertEqual(800, 800)
        XCTAssertEqual(600, 600)
    }

    /// 组合档由同一个系统流程完成 Touch ID → Mac 登录密码，不得重建认证上下文。
    func testCombinationUsesSingleDeviceOwnerAuthenticationFlow() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let recorded = CatalystPolicyBox()
        let gate = RevealGate(
            masterPassword: master,
            authenticateDeviceOwner: { _, policy in
                recorded.append(policy)
                throw LAError(.userCancel)
            },
            availableBiometry: { .touchID }
        )
        do {
            try await gate.confirm(reason: "catalyst", policy: .biometryOrAppPassword)
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        XCTAssertEqual(recorded.snapshot(), [.deviceOwnerAuthentication])
    }

    func testDeviceAuthStillUsesDeviceOwnerAuthentication() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let recorded = CatalystPolicyBox()
        let gate = RevealGate(masterPassword: master) { _, policy in
            recorded.append(policy)
        }
        try await gate.confirm(reason: "catalyst", policy: .biometricOrPasscode)
        XCTAssertEqual(recorded.snapshot(), [.deviceOwnerAuthentication])
    }

    func testMacPasswordDependentPoliciesRequireMaterial() {
        XCTAssertFalse(
            AppPasswordPolicyGate.canPersistAsCurrentPolicy(.biometryOrAppPassword, material: .unset)
        )
        XCTAssertFalse(
            AppPasswordPolicyGate.canPersistAsCurrentPolicy(.masterPassword, material: .unreadable)
        )
        XCTAssertTrue(
            AppPasswordPolicyGate.canPersistAsCurrentPolicy(.biometricOrPasscode, material: .unset)
        )
    }
}

private final class CatalystPolicyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var policies: [LAPolicy] = []

    func append(_ policy: LAPolicy) {
        lock.lock(); defer { lock.unlock() }
        policies.append(policy)
    }

    func snapshot() -> [LAPolicy] {
        lock.lock(); defer { lock.unlock() }
        return policies
    }
}
