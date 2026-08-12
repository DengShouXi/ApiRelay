@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class KeyVaultServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var keychain: KeychainStore!
    private var vault: KeyVaultService!

    override func setUp() async throws {
        container = try AppSchema.makeInMemoryContainer()
        keychain = KeychainStore(accessGroup: nil, disableSynchronizableForTesting: true)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let gate = RevealGate(masterPassword: master) { _, _ in /* always succeed */ }
        let clipboard = SecureClipboard()
        let entitlements = EntitlementService(modelContainer: container)
        vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: entitlements
        )
        // Ensure free tier
        let entitlement = EntitlementSnapshotRepository(modelContainer: container)
        try await entitlement.update(tier: .free, source: "test")
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .none
        try await prefs.update(patch)
    }

    func testQuotaThirdSucceedsFourthFails() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        for i in 1...3 {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "k\(i)"),
                secret: "sk-test-secret-\(i)aaa"
            )
        }
        do {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "k4"),
                secret: "sk-test-secret-4aaa"
            )
            XCTFail("expected quotaExceeded")
        } catch let ApiRelayError.quotaExceededFreeTier(limit) {
            XCTAssertEqual(limit, 3)
        }
    }

    func testStaleUnlimitedSnapshotStillEnforcesFreeQuota() async throws {
        let entitlement = EntitlementSnapshotRepository(modelContainer: container)
        try await entitlement.update(tier: .unlimitedKeys, source: "stale")

        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "B")
        )
        for i in 1...3 {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "s\(i)"),
                secret: "sk-stale-secret-\(i)aaa"
            )
        }
        do {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "s4"),
                secret: "sk-stale-secret-4aaa"
            )
            XCTFail("expected quotaExceeded despite stale unlimited snapshot")
        } catch let ApiRelayError.quotaExceededFreeTier(limit) {
            XCTAssertEqual(limit, 3)
        }
    }

    func testSoftDeleteKeepsKeychainAndRestoreWorks() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-keep-me-xxxx"
        )
        try await vault.deleteKey(keyId)
        let still = try await keychain.read(service: .keys, account: keyId)
        XCTAssertEqual(still, "sk-keep-me-xxxx")

        let trash = try await vault.recentlyDeletedKeys()
        XCTAssertEqual(trash.map(\.id), [keyId])
        XCTAssertEqual(trash.first?.lifecycle, .softDeleted)
        XCTAssertNotNil(trash.first?.deletedAt)
        XCTAssertNotNil(trash.first?.purgeAfter)

        try await vault.restoreKey(keyId)
        let revealed = try await vault.revealSecret(keyId: keyId, purpose: .display, masterPassword: nil)
        XCTAssertEqual(revealed, "sk-keep-me-xxxx")
        let afterRestore = try await vault.recentlyDeletedKeys()
        XCTAssertTrue(afterRestore.isEmpty)
    }

    func testPermanentDeleteRemovesKeychain() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-remove-me-yyyy"
        )
        try await vault.deleteKey(keyId)
        try await vault.permanentlyDeleteKey(keyId)
        do {
            _ = try await keychain.read(service: .keys, account: keyId)
            XCTFail("expected missing")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, errSecItemNotFound)
        }
    }

    func testAutomatedReadSkipsGate() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        // Force biometric policy — automated path still works without LA
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOnly
        try await prefs.update(patch)

        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-auto-zzzzzzzz"
        )
        let secret = try await vault.readSecretForAutomatedUse(keyId: keyId, purpose: .healthCheck)
        XCTAssertEqual(secret, "sk-auto-zzzzzzzz")
    }

    func testRevealRequiresGateWhenNotNone() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-gated-wwwwww"
        )
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .none
        try await prefs.update(patch)
        let secret = try await vault.revealSecret(keyId: keyId, purpose: .display, masterPassword: nil)
        XCTAssertEqual(secret, "sk-gated-wwwwww")
    }

    func testEditKeyUpdatesNameSecretPlatformAndAccount() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Acct Old")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "Key Old"),
            secret: "sk-old-secret-aaaa"
        )

        try await vault.editKey(
            keyId,
            draft: KeyEditDraft(
                displayName: "Key New",
                secret: "sk-new-secret-bbbb",
                notes: "team laptop",
                accountDisplayName: "Acct New",
                platform: "anthropic"
            )
        )

        let keys = try await vault.keys(in: accountId)
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].displayName, "Key New")
        XCTAssertEqual(keys[0].maskedHint, "bbbb")
        XCTAssertEqual(keys[0].notes, "team laptop")
        let revealed = try await vault.revealSecret(keyId: keyId, purpose: .display, masterPassword: nil)
        XCTAssertEqual(revealed, "sk-new-secret-bbbb")

        let accounts = try await vault.accounts()
        let account = try XCTUnwrap(accounts.first { $0.id == accountId })
        XCTAssertEqual(account.displayName, "Acct New")
        XCTAssertEqual(account.platform, "anthropic")
    }

    func testUpdateAccountChangesPlatformAndDisplayName() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Old")
        )
        try await vault.updateAccount(
            accountId,
            patch: UpstreamAccountPatch(
                platform: "deepseek",
                displayName: "New",
                notes: "work laptop"
            )
        )
        let accounts = try await vault.accounts()
        let account = try XCTUnwrap(accounts.first { $0.id == accountId })
        XCTAssertEqual(account.platform, "deepseek")
        XCTAssertEqual(account.displayName, "New")
        XCTAssertEqual(account.notes, "work laptop")
    }

    func testEditKeyKeepsSecretWhenBlank() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-keep-zzzzzzzz"
        )
        try await vault.editKey(
            keyId,
            draft: KeyEditDraft(
                displayName: "k1-renamed",
                secret: "   ",
                accountDisplayName: "A",
                platform: "openai"
            )
        )
        let revealed = try await vault.revealSecret(keyId: keyId, purpose: .display, masterPassword: nil)
        XCTAssertEqual(revealed, "sk-keep-zzzzzzzz")
        let keys = try await vault.keys(in: accountId)
        XCTAssertEqual(keys.first?.displayName, "k1-renamed")
    }
}
