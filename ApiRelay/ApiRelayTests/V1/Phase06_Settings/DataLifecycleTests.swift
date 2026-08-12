@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class DataLifecycleTests: XCTestCase {
    func testEraseClearsKeysAndKeychain() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore(accessGroup: nil, disableSynchronizableForTesting: true)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        let vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: EntitlementService(modelContainer: container)
        )
        var patch = PreferencesPatch()
        patch.revealPolicy = .none
        try await UserPreferencesRepository(modelContainer: container).update(patch)

        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-erase-test-1111"
        )

        let lifecycle = DataLifecycleService(gate: gate, keychain: keychain, modelContainer: container)
        try await lifecycle.eraseAllUserData()

        let accounts = try await vault.accounts()
        XCTAssertTrue(accounts.isEmpty)
        do {
            _ = try await keychain.read(service: .keys, account: keyId)
            XCTFail("expected missing")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, errSecItemNotFound)
        }
    }
}
