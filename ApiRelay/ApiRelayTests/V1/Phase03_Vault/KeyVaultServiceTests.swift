@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class KeyVaultServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var keychain: KeychainStore!
    private var gate: RevealGate!
    private var clipboard: SecureClipboard!
    private var vault: KeyVaultService!

    override func setUp() async throws {
        container = try AppSchema.makeInMemoryContainer()
        keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        gate = RevealGate(masterPassword: master) { _, _ in /* always succeed */ }
        clipboard = SecureClipboard()
        // 本套件考的是密钥库，不是 StoreKit：走桩，免去每次配额检查 60 秒的商店超时。
        vault = makeVault(entitlements: StubEntitlements(tier: .free))
        // Ensure free tier
        let entitlement = EntitlementSnapshotRepository(modelContainer: container)
        try await entitlement.update(tier: .free, source: "test")
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .none
        try await prefs.update(patch)
    }

    private func makeVault(entitlements: EntitlementServing) -> KeyVaultService {
        KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: entitlements
        )
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

        // 前三把只是把额度铺满，不是被考的对象，用桩建。
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "B")
        )
        for i in 1...3 {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "s\(i)"),
                secret: "sk-stale-secret-\(i)aaa"
            )
        }

        // 第四把才是本条的题眼：快照说 unlimited，但真服务问过 StoreKit 后仍应拦下。
        // 这一步必须用真服务，换成桩就测了个空；代价是等一次商店超时。
        vault = makeVault(entitlements: EntitlementService(modelContainer: container))
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
        XCTAssertNil(keys[0].maskedHint)
        // 换密文后本机有明文，但 DTO MUST NOT 暴露真实长度。
        XCTAssertTrue(keys[0].secretAvailable)
        XCTAssertFalse(
            Set(Mirror(reflecting: keys[0]).children.compactMap(\.label)).contains("secretLength")
        )
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

    func testCreateCustomAccountKeepsPlatformNameSeparateFromDisplayName() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(
                platform: PresetCatalog.customPlatformID,
                customPlatformName: "Warp Gateway",
                displayName: "Warp Gateway 账号 1",
                customBaseURL: "https://example.invalid/v1"
            )
        )
        let accounts = try await vault.accounts()
        let account = try XCTUnwrap(accounts.first { $0.id == accountId })
        XCTAssertEqual(account.platform, PresetCatalog.customPlatformID)
        XCTAssertEqual(account.customPlatformName, "Warp Gateway")
        XCTAssertEqual(account.displayName, "Warp Gateway 账号 1")
        XCTAssertEqual(account.customBaseURL, "https://example.invalid/v1")
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

    func testExactDuplicateBlocksThenAllowsAfterAck() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Dup")
        )
        let firstId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "Existing"),
            secret: "sk-same-secret-value"
        )
        do {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "Copy"),
                secret: "sk-same-secret-value"
            )
            XCTFail("expected possible duplicate")
        } catch let error as ApiRelayError {
            XCTAssertEqual(error.possibleDuplicateKeyId, firstId)
        }
        let secondId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "Copy"),
            secret: "sk-same-secret-value",
            acknowledgePossibleDuplicate: true
        )
        let keys = try await vault.keys(in: accountId)
        XCTAssertEqual(Set(keys.map(\.id)), [firstId, secondId])
        XCTAssertTrue(keys.allSatisfy { $0.maskedHint == nil })
    }

    func testSimilarSuffixDoesNotCountAsDuplicate() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Suffix")
        )
        _ = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "A1"),
            secret: "xxxxxxxxxxxxxxxxxxxxabcd"
        )
        let otherId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "A2"),
            secret: "yyyyyyyyyyyyyyyyyyyyabcd"
        )
        let keys = try await vault.keys(in: accountId)
        XCTAssertEqual(keys.count, 2)
        XCTAssertTrue(keys.contains { $0.id == otherId })
    }

    func testExactDuplicateDoesNotTriggerAcrossAccounts() async throws {
        let accountA = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let accountB = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "B")
        )
        _ = try await vault.createKey(
            KeyDraft(accountId: accountA, displayName: "A1"),
            secret: "sk-shared-across-accounts"
        )
        let otherId = try await vault.createKey(
            KeyDraft(accountId: accountB, displayName: "B1"),
            secret: "sk-shared-across-accounts"
        )
        let keysB = try await vault.keys(in: accountB)
        XCTAssertEqual(keysB.map(\.id), [otherId])
    }

    func testEditKeyExactDuplicateBlocksUntilAck() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "EditDup")
        )
        let firstId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "Keep"),
            secret: "sk-keep-original-secret"
        )
        let secondId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "Change"),
            secret: "sk-other-original-secret"
        )
        do {
            try await vault.editKey(
                secondId,
                draft: KeyEditDraft(
                    displayName: "Change",
                    secret: "sk-keep-original-secret",
                    accountDisplayName: "EditDup",
                    platform: "openai"
                )
            )
            XCTFail("expected possible duplicate")
        } catch let error as ApiRelayError {
            XCTAssertEqual(error.possibleDuplicateKeyId, firstId)
        }
        try await vault.editKey(
            secondId,
            draft: KeyEditDraft(
                displayName: "Change",
                secret: "sk-keep-original-secret",
                acknowledgePossibleDuplicate: true,
                accountDisplayName: "EditDup",
                platform: "openai"
            )
        )
        let revealed = try await vault.revealSecret(keyId: secondId, purpose: .display, masterPassword: nil)
        XCTAssertEqual(revealed, "sk-keep-original-secret")
    }

    func testStartupClearsLegacySecretFragments() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Legacy")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-legacy-fragment-zzzz"
        )
        let repo = APIKeyRecordRepository(modelContainer: container)
        try await repo.plantLegacySecretFragments(id: keyId, hint: "zzzz", length: 24)
        let planted = try await repo.storedSecretFragments(id: keyId)
        XCTAssertEqual(planted.hint, "zzzz")
        XCTAssertEqual(planted.length, 24)
        try await vault.performStartupMaintenance()
        let cleared = try await repo.storedSecretFragments(id: keyId)
        XCTAssertNil(cleared.hint)
        XCTAssertNil(cleared.length)
        let keys = try await vault.keys(in: accountId)
        XCTAssertEqual(keys.count, 1)
        XCTAssertNil(keys[0].maskedHint)
    }

    func testCreateAccountAppendsSortOrder() async throws {
        let first = try await vault.createAccount(UpstreamAccountDraft(platform: "openai", displayName: "A"))
        let second = try await vault.createAccount(UpstreamAccountDraft(platform: "openai", displayName: "B"))
        let accounts = try await vault.accounts()
        let a = try XCTUnwrap(accounts.first { $0.id == first })
        let b = try XCTUnwrap(accounts.first { $0.id == second })
        XCTAssertEqual(a.sortOrder, 0)
        XCTAssertEqual(b.sortOrder, 1)
    }

    func testReorderAccountsDoesNotChangeUpdatedAt() async throws {
        let first = try await vault.createAccount(UpstreamAccountDraft(platform: "openai", displayName: "A"))
        let second = try await vault.createAccount(UpstreamAccountDraft(platform: "openai", displayName: "B"))
        let before = try await vault.accounts()
        let beforeA = try XCTUnwrap(before.first { $0.id == first })
        let beforeB = try XCTUnwrap(before.first { $0.id == second })
        try await vault.reorderAccounts(orderedIds: [second, first])
        let after = try await vault.accounts()
        let afterA = try XCTUnwrap(after.first { $0.id == first })
        let afterB = try XCTUnwrap(after.first { $0.id == second })
        XCTAssertEqual(afterA.sortOrder, 1)
        XCTAssertEqual(afterB.sortOrder, 0)
        XCTAssertEqual(afterA.updatedAt, beforeA.updatedAt)
        XCTAssertEqual(afterB.updatedAt, beforeB.updatedAt)
    }
}
