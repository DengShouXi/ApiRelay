@preconcurrency import XCTest
@testable import ApiRelay
import LocalAuthentication

@MainActor
final class RevealGateCoordinatorTests: XCTestCase {
    func testNewRequestCancelsThePreviousOne() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let firstStarted = XCTestExpectation(description: "first-started")
        let gate = RevealGate(masterPassword: master) { reason, _ in
            if reason == "first" {
                firstStarted.fulfill()
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        async let first: Void = {
            do {
                try await gate.confirmMandatory(reason: "first", purpose: .unlockApp)
                XCTFail("first request should be cancelled")
            } catch ApiRelayError.authenticationCancelled {
            }
        }()
        await fulfillment(of: [firstStarted], timeout: 1)
        try await gate.confirmMandatory(reason: "second", purpose: .settings)
        _ = try await first
    }
}
