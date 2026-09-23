@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

/// Deterministically models focus loss immediately after a selected concrete
/// repository/Keychain commit has completed, but before the business operation
/// can perform its next post-commit lease validation.
///
/// This deliberately invalidates only after `SessionLockBox` has released its
/// commit mutex. Blocking a fake storage call inside that mutex and then trying
/// to invalidate the same box would deadlock and would contradict the exact
/// commit contract: once a commit owns the mutex, that synchronous side effect
/// is allowed to finish before invalidation wins.
nonisolated private final class PostCommitInvalidatingSessionLock: SessionLockQuerying, @unchecked Sendable {
    private let box = SessionLockBox()
    private let planLock = NSLock()
    private var successfulCommitsToSkip: Int?
    private var beforeInvalidation: (@Sendable () -> Void)?

    func invalidateAfterSuccessfulCommit(
        skipping precedingSuccessfulCommits: Int,
        beforeInvalidation: (@Sendable () -> Void)? = nil
    ) {
        precondition(precedingSuccessfulCommits >= 0)
        planLock.lock()
        successfulCommitsToSkip = precedingSuccessfulCommits
        self.beforeInvalidation = beforeInvalidation
        planLock.unlock()
    }

    nonisolated func isSessionLocked() -> Bool {
        box.isSessionLocked()
    }

    nonisolated func captureAuthorizationLease() throws -> SessionAuthorizationLease {
        try box.captureAuthorizationLease()
    }

    nonisolated func validateAuthorizationLease(_ lease: SessionAuthorizationLease) throws {
        try box.validateAuthorizationLease(lease)
    }

    nonisolated func commitAuthorizationLease(
        _ lease: SessionAuthorizationLease,
        operation: () throws -> Void
    ) throws {
        var shouldInvalidate = false
        var hook: (@Sendable () -> Void)?
        try box.commitAuthorizationLease(lease) {
            try operation()

            // Count only successful concrete commits. This runs while the base
            // commit mutex still serializes commit order, but the hook and the
            // invalidation themselves run only after that mutex is released.
            planLock.lock()
            if let remaining = successfulCommitsToSkip {
                if remaining == 0 {
                    shouldInvalidate = true
                    hook = beforeInvalidation
                    successfulCommitsToSkip = nil
                    beforeInvalidation = nil
                } else {
                    successfulCommitsToSkip = remaining - 1
                }
            }
            planLock.unlock()
        }
        if shouldInvalidate {
            hook?()
            box.invalidateAuthorizationLeases()
        }
    }
}

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
        patch.revealPolicy = .noVerification
        try await prefs.update(patch)
    }

    private func makeVault(
        entitlements: EntitlementServing,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock()
    ) -> KeyVaultService {
        KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: entitlements,
            sessionLock: sessionLock
        )
    }

    private func makeIsolatedIntegrityQuarantine() -> VaultIntegrityQuarantineStore {
        let suiteName = "com.apirelay.tests.vault-integrity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return VaultIntegrityQuarantineStore(defaults: defaults)
    }

    func testQuotaThirdSucceedsFourthFails() async throws {
        let entitlements = StubEntitlements(tier: .free)
        vault = makeVault(entitlements: entitlements)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        for i in 1...3 {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "k\(i)"),
                secret: "sk-test-secret-\(i)aaa"
            )
        }
        let callsBeforeFourth = await entitlements.currentTierCallCount
        XCTAssertEqual(callsBeforeFourth, 0)
        do {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "k4"),
                secret: "sk-test-secret-4aaa"
            )
            XCTFail("expected quotaExceeded")
        } catch let ApiRelayError.quotaExceededFreeTier(limit) {
            XCTAssertEqual(limit, 3)
        }
        let callsAfterFourth = await entitlements.currentTierCallCount
        XCTAssertEqual(callsAfterFourth, 1)
    }

    func testUnlimitedTierAllowsFourthKeyAfterSingleStoreCheck() async throws {
        let entitlements = StubEntitlements(tier: .unlimitedKeys)
        vault = makeVault(entitlements: entitlements)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Unlimited")
        )

        for i in 1...4 {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "u\(i)"),
                secret: "sk-unlimited-secret-\(i)aaa"
            )
        }

        let keyCount = try await vault.keys(in: accountId).count
        let entitlementCalls = await entitlements.currentTierCallCount
        XCTAssertEqual(keyCount, 4)
        XCTAssertEqual(entitlementCalls, 1)
    }

    func testConcurrentFreeCreatesCannotExceedQuota() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Concurrent")
        )
        let sut = vault!

        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for i in 1...4 {
                group.addTask {
                    do {
                        _ = try await sut.createKey(
                            KeyDraft(accountId: accountId, displayName: "c\(i)"),
                            secret: "sk-concurrent-secret-\(i)aaa"
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var count = 0
            for await succeeded in group where succeeded {
                count += 1
            }
            return count
        }

        let storedKeyCount = try await vault.keys(in: accountId).count
        XCTAssertEqual(successes, 3)
        XCTAssertEqual(storedKeyCount, 3)
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
        patch.revealPolicy = .biometricOrPasscode
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
        patch.revealPolicy = .noVerification
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

    func testCreateKeyInvalidatedImmediatelyAfterKeychainCommitRollsBackBothStores() async throws {
        let fakeKeychain = FakeKeychain()
        let sessionLock = PostCommitInvalidatingSessionLock()
        let quarantine = makeIsolatedIntegrityQuarantine()
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: sessionLock,
            integrityQuarantine: quarantine
        )
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "create-race")
        )

        // createKey commits metadata first, then the Keychain secret.
        sessionLock.invalidateAfterSuccessfulCommit(skipping: 1)
        do {
            _ = try await service.createKey(
                KeyDraft(accountId: accountId, displayName: "must-rollback"),
                secret: "sk-create-race-secret"
            )
            XCTFail("a revoked lease must not commit a key")
        } catch ApiRelayError.sessionLocked {
        }
        let records = try await service.keys(in: accountId)
        let storedAccounts = try await fakeKeychain.listAccounts(service: .keys)
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(storedAccounts.isEmpty)
        XCTAssertNil(quarantine.currentIncident())
    }

    func testCreateKeyInvalidatedImmediatelyAfterKeychainCommitDiagnosesOrphanCleanupFailure() async throws {
        let fakeKeychain = FakeKeychain()
        let sessionLock = PostCommitInvalidatingSessionLock()
        let quarantine = makeIsolatedIntegrityQuarantine()
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyVaultCrossStoreTests-\(UUID().uuidString)", isDirectory: true)
        let journal = DurableCrossStoreTransactionJournal(
            fileURL: journalDirectory.appendingPathComponent("journal.json")
        )
        let mutationGate = StorageMutationGate()
        defer { try? FileManager.default.removeItem(at: journalDirectory) }
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: sessionLock,
            integrityQuarantine: quarantine,
            mutationGate: mutationGate,
            crossStoreJournal: journal
        )
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "create-orphan")
        )

        sessionLock.invalidateAfterSuccessfulCommit(
            skipping: 1,
            beforeInvalidation: {
                fakeKeychain.failNextCall("delete", with: .keychainFailure(errSecAuthFailed))
            }
        )
        do {
            _ = try await service.createKey(
                KeyDraft(accountId: accountId, displayName: "orphan-only"),
                secret: "sk-create-orphan-secret"
            )
            XCTFail("cleanup failure must be surfaced")
        } catch let ApiRelayError.storageRecoveryFailed(operation, detail) {
            XCTAssertEqual(operation, "create_key")
            XCTAssertTrue(detail.contains("durable_rollback=keychain_status_"))
            XCTAssertFalse(detail.contains("sk-create-orphan-secret"))
        }

        XCTAssertTrue(mutationGate.isCrossStoreRecoverySealed())
        let pending = try XCTUnwrap(journal.load())
        XCTAssertEqual(pending.kind, .createKey)
        XCTAssertEqual(pending.phase, .applying)
        do {
            _ = try await service.keys(in: accountId)
            XCTFail("ordinary reads must stay sealed until durable recovery finishes")
        } catch ApiRelayError.storageRecoveryFailed(_, let detail) {
            XCTAssertEqual(detail, "cross_store_recovery_pending")
        }

        try await service.recoverInterruptedCrossStoreTransaction(pending)
        let remainingRecords = try await service.keys(in: accountId)
        let remainingSecrets = try await fakeKeychain.listAccounts(service: .keys)
        XCTAssertTrue(remainingRecords.isEmpty)
        XCTAssertTrue(remainingSecrets.isEmpty)
        XCTAssertFalse(mutationGate.isCrossStoreRecoverySealed())
        XCTAssertNil(try journal.load())
        XCTAssertNil(quarantine.currentIncident(), "recoverable WAL state must not become permanent quarantine")
    }

    func testStartupRecoveryRollsCommittedCreateForwardAndRevokesRollbackTag() async throws {
        let fakeKeychain = FakeKeychain()
        let quarantine = makeIsolatedIntegrityQuarantine()
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyVaultCommittedRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        let journal = DurableCrossStoreTransactionJournal(
            fileURL: journalDirectory.appendingPathComponent("journal.json")
        )
        defer { try? FileManager.default.removeItem(at: journalDirectory) }
        let mutationGate = StorageMutationGate(crossStoreRecoveryPending: true)
        let accountID = UUID()
        let keyID = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 12_345)
        _ = try await UpstreamAccountRepository(modelContainer: container).insert(
            UpstreamAccountDraft(platform: "openai", displayName: "Committed Account"),
            id: accountID
        )
        _ = try await APIKeyRecordRepository(modelContainer: container).insert(
            KeyRecordDraft(
                accountId: accountID,
                displayName: "Committed Key",
                origin: .manualEntry
            ),
            id: keyID,
            createdAt: createdAt
        )
        let transactionID = try journal.begin(.createKey)
        try journal.planInsertedKey(
            CrossStoreKeyRollbackPlan(
                id: keyID,
                accountId: accountID,
                createdAt: createdAt
            ),
            transactionId: transactionID
        )
        let insertedSecret = try await fakeKeychain.insertIfAbsent(
            "sk-committed-recovery",
            service: .keys,
            account: keyID,
            transactionTag: transactionID
        )
        XCTAssertTrue(insertedSecret)
        try journal.decideCommit(transactionId: transactionID)
        let pending = try XCTUnwrap(journal.load())

        let recoveredService = KeyVaultService(
            keychain: fakeKeychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            integrityQuarantine: quarantine,
            mutationGate: mutationGate,
            crossStoreJournal: journal
        )
        try await recoveredService.recoverInterruptedCrossStoreTransaction(pending)

        let records = try await recoveredService.keys(in: accountID)
        XCTAssertEqual(records.map(\.id), [keyID])
        let secret = try await fakeKeychain.read(service: .keys, account: keyID)
        XCTAssertEqual(secret, "sk-committed-recovery")
        let rollbackStillOwnsSecret = try await fakeKeychain.deleteIfTransactionTagMatches(
            service: .keys,
            account: keyID,
            transactionTag: transactionID
        )
        XCTAssertFalse(rollbackStillOwnsSecret)
        XCTAssertNil(try journal.load())
        XCTAssertFalse(mutationGate.isCrossStoreRecoverySealed())
        XCTAssertNil(quarantine.currentIncident())
    }

    func testEditKeyInvalidatedImmediatelyAfterKeychainCommitRestoresSecretAndMetadata() async throws {
        let fakeKeychain = FakeKeychain()
        let sessionLock = PostCommitInvalidatingSessionLock()
        let quarantine = makeIsolatedIntegrityQuarantine()
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: sessionLock,
            integrityQuarantine: quarantine
        )
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Account Old")
        )
        let keyId = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "Key Old", notes: "old-note"),
            secret: "sk-edit-old-secret"
        )

        // The replacement-secret Keychain write is editKey's first commit.
        sessionLock.invalidateAfterSuccessfulCommit(skipping: 0)
        do {
            try await service.editKey(
                keyId,
                draft: KeyEditDraft(
                    displayName: "Key New",
                    secret: "sk-edit-new-secret",
                    notes: "new-note",
                    accountDisplayName: "Account New",
                    platform: "anthropic"
                )
            )
            XCTFail("a revoked lease must roll back the edit")
        } catch ApiRelayError.sessionLocked {
        }
        let restoredSecret = try await fakeKeychain.read(service: .keys, account: keyId)
        let restoredKeys = try await service.keys(in: accountId)
        let restoredAccounts = try await service.accounts()
        let restoredKey = try XCTUnwrap(restoredKeys.first)
        let restoredAccount = try XCTUnwrap(restoredAccounts.first { $0.id == accountId })
        XCTAssertEqual(restoredSecret, "sk-edit-old-secret")
        XCTAssertEqual(restoredKey.displayName, "Key Old")
        XCTAssertEqual(restoredKey.notes, "old-note")
        XCTAssertEqual(restoredAccount.displayName, "Account Old")
        XCTAssertEqual(restoredAccount.platform, "openai")
        XCTAssertNil(quarantine.currentIncident())
    }

    func testEditCompensationFailureImmediatelyAfterKeychainCommitPersistsQuarantineAcrossServiceInstances() async throws {
        let fakeKeychain = FakeKeychain()
        let sessionLock = PostCommitInvalidatingSessionLock()
        let quarantine = makeIsolatedIntegrityQuarantine()
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: sessionLock,
            integrityQuarantine: quarantine
        )
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "quarantine")
        )
        let keyId = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "key"),
            secret: "sk-quarantine-old-secret"
        )

        sessionLock.invalidateAfterSuccessfulCommit(
            skipping: 0,
            beforeInvalidation: {
                // The replacement secret has committed; fail only the
                // subsequent compensation that restores the old secret.
                fakeKeychain.failNextCall("save", with: .keychainFailure(errSecAuthFailed))
            }
        )
        do {
            try await service.editKey(
                keyId,
                draft: KeyEditDraft(
                    displayName: "key-new",
                    secret: "sk-quarantine-new-secret",
                    accountDisplayName: "quarantine-new",
                    platform: "anthropic"
                )
            )
            XCTFail("failed compensation must quarantine the vault")
        } catch let ApiRelayError.storageIntegrityQuarantined(operation, detail) {
            XCTAssertEqual(operation, "edit_key")
            XCTAssertTrue(detail.contains("restore_secret=keychain_status_"))
            XCTAssertFalse(detail.contains("sk-quarantine-old-secret"))
            XCTAssertFalse(detail.contains("sk-quarantine-new-secret"))
        }
        XCTAssertNotNil(quarantine.currentIncident())

        do {
            _ = try await service.accounts()
            XCTFail("the originating service must fail closed")
        } catch ApiRelayError.storageIntegrityQuarantined {
        }

        let replacementService = KeyVaultService(
            keychain: fakeKeychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: SessionLockBox(),
            integrityQuarantine: quarantine
        )
        do {
            _ = try await replacementService.keys(in: accountId)
            XCTFail("a new service instance must honor the persisted quarantine")
        } catch ApiRelayError.storageIntegrityQuarantined {
        }
    }

    func testPermanentDeleteInvalidatedImmediatelyAfterKeychainCommitRestoresKeyAndAssignment() async throws {
        let fakeKeychain = FakeKeychain()
        let sessionLock = PostCommitInvalidatingSessionLock()
        let quarantine = makeIsolatedIntegrityQuarantine()
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: sessionLock,
            integrityQuarantine: quarantine
        )
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "delete-race")
        )
        let keyId = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "delete-me"),
            secret: "sk-delete-race-secret"
        )
        let toolId = UUID()
        try await service.addAssignment(keyId: keyId, consumerToolId: toolId)
        try await service.deleteKey(keyId)

        // Assignment and key metadata deletion are the first two commits;
        // invalidate immediately after the third, concrete Keychain delete.
        sessionLock.invalidateAfterSuccessfulCommit(skipping: 2)
        do {
            try await service.permanentlyDeleteKey(keyId)
            XCTFail("a revoked lease must roll back permanent deletion")
        } catch ApiRelayError.sessionLocked {
        }
        let secret = try await fakeKeychain.read(service: .keys, account: keyId)
        let trash = try await service.recentlyDeletedKeys()
        let assignment = try await service.assignmentKind(keyId: keyId)
        XCTAssertEqual(secret, "sk-delete-race-secret")
        XCTAssertEqual(trash.map(\.id), [keyId])
        if case .exclusive(let restoredToolId) = assignment {
            XCTAssertEqual(restoredToolId, toolId)
        } else {
            XCTFail("assignment must be restored")
        }
        XCTAssertNil(quarantine.currentIncident())
    }

    func testStorageRecoveryErrorsUseLocalizedMessagesWithoutDiagnosticDetail() {
        let marker = "internal-marker-must-not-reach-ui"
        let recovery = ApiRelayError.storageRecoveryFailed(
            operation: "create_key",
            detail: marker
        ).localizedDescription
        let quarantine = ApiRelayError.storageIntegrityQuarantined(
            operation: "edit_key",
            detail: marker
        ).localizedDescription

        for message in [recovery, quarantine] {
            XCTAssertFalse(message.contains(marker))
            XCTAssertFalse(message.contains("error.storage"), "catalog key must resolve")
            XCTAssertFalse(message.isEmpty)
        }
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

    func testSessionLockRejectsCreateAndCopy() async throws {
        let box = SessionLockBox()
        box.setLocked(true)
        vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )
        do {
            _ = try await vault.createAccount(UpstreamAccountDraft(platform: "openai", displayName: "Locked"))
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        box.setLocked(false)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Open")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-lock-gate-secret1"
        )
        box.setLocked(true)
        do {
            try await vault.copySecretToClipboard(keyId: keyId)
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
    }

    func testSessionLockRejectsRestoreAssignmentReorderAndPurge() async throws {
        let box = SessionLockBox()
        vault = makeVault(entitlements: StubEntitlements(tier: .unlimitedKeys), sessionLock: box)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Open")
        )
        let first = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-lock-restore-aaaaaa"
        )
        let second = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k2"),
            secret: "sk-lock-restore-bbbbbb"
        )
        try await vault.deleteKey(first)
        var expired = KeyPatch()
        expired.purgeAfter = Date.distantPast
        try await vault.updateKey(first, patch: expired)

        box.setLocked(true)
        do {
            try await vault.restoreKey(first)
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            try await vault.permanentlyDeleteKey(first)
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            try await vault.addAssignment(keyId: second, consumerToolId: UUID())
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            try await vault.removeAssignment(keyId: second, consumerToolId: UUID())
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            try await vault.reorderKeys(orderedIds: [second])
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            try await vault.reorderAccounts(orderedIds: [accountId])
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }

        try await vault.purgeExpiredDeletedKeys()
        let trashWhileLocked = try await vault.recentlyDeletedKeys()
        XCTAssertEqual(trashWhileLocked.map(\.id), [first])

        box.setLocked(false)
        try await vault.purgeExpiredDeletedKeys()
        let trashAfterUnlock = try await vault.recentlyDeletedKeys()
        XCTAssertTrue(trashAfterUnlock.isEmpty)
    }

    func testAuthorizationLeaseRevokedDuringGatePreventsPlaintextClipboardAndDeleteSideEffects() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let chain = FakeKeychain()
        let clip = FakeClipboard()
        let fake = FakeRevealGate()
        let box = SessionLockBox()
        let service = KeyVaultService(
            keychain: chain,
            gate: fake,
            clipboard: clip,
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )
        var setup = PreferencesPatch()
        setup.revealPolicy = .noVerification
        try await UserPreferencesRepository(modelContainer: local).update(setup)
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Lease")
        )
        let keyId = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "kept"),
            secret: "sk-lease-kept-aaaaaa"
        )
        setup.revealPolicy = .biometricOrPasscode
        setup.revealAuthEnabled = true
        try await UserPreferencesRepository(modelContainer: local).update(setup)
        await fake.setAfterConfirmHook {
            box.invalidateAuthorizationLeases()
        }

        let readsBefore = await chain.journal.callCount("read")
        do {
            _ = try await service.revealSecret(keyId: keyId, purpose: .display)
            XCTFail("revoked reveal lease must fail")
        } catch ApiRelayError.sessionLocked {
        }
        var readsAfter = await chain.journal.callCount("read")
        XCTAssertEqual(readsAfter, readsBefore)

        do {
            try await service.copySecretToClipboard(keyId: keyId)
            XCTFail("revoked copy lease must fail")
        } catch ApiRelayError.sessionLocked {
        }
        readsAfter = await chain.journal.callCount("read")
        let clipboardWrites = await clip.journal.callCount("write")
        XCTAssertEqual(readsAfter, readsBefore)
        XCTAssertEqual(clipboardWrites, 0)

        do {
            try await service.deleteKey(keyId)
            XCTFail("revoked delete lease must fail")
        } catch ApiRelayError.sessionLocked {
        }
        let remaining = try await service.keys(in: accountId).map(\.id)
        let trash = try await service.recentlyDeletedKeys()
        XCTAssertEqual(remaining, [keyId])
        XCTAssertTrue(trash.isEmpty)
    }

    func testCreateAndAvatarPatchSkipIdentityWhileEditUsesCurrentPolicy() async throws {
        let fake = FakeRevealGate()
        vault = makeVault(gate: fake, entitlements: StubEntitlements(tier: .unlimitedKeys))
        try await setPrefs(.biometricOrPasscode, revealAuthEnabled: true)

        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-w4-create-aaaaaa"
        )
        await assertCalls(fake, confirm: 0, mandatory: 0)

        var avatar = KeyPatch()
        avatar.updatesAvatar = true
        avatar.avatarSymbol = "star.fill"
        avatar.avatarColor = "orange"
        try await vault.updateKey(keyId, patch: avatar)
        await assertCalls(fake, confirm: 0)

        try await vault.editKey(
            keyId,
            draft: KeyEditDraft(
                displayName: "k2",
                accountDisplayName: "A",
                platform: "openai"
            )
        )
        await assertCalls(fake, confirm: 1, mandatory: 0)
    }

    func testRevealAuthOffSkipsViewCopyButNotDelete() async throws {
        let fake = FakeRevealGate()
        vault = makeVault(gate: fake, entitlements: StubEntitlements(tier: .unlimitedKeys))
        try await setPrefs(.biometricOrPasscode, revealAuthEnabled: false)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-w4-reveal-off-aa"
        )
        let revealed = try await vault.revealSecretWithEvidence(
            keyId: keyId,
            purpose: .display,
            masterPassword: nil
        )
        XCTAssertEqual(revealed.authentication, .notRequired)
        XCTAssertNil(revealed.reuseToken)
        try await vault.copySecretToClipboard(keyId: keyId)
        await assertCalls(fake, confirm: 0)

        try await vault.deleteKey(keyId)
        await assertCalls(fake, confirm: 1, mandatory: 0)
    }

    func testNoVerificationSkipsIdentityIncludingReveal() async throws {
        let fake = FakeRevealGate()
        vault = makeVault(gate: fake, entitlements: StubEntitlements(tier: .unlimitedKeys))
        try await setPrefs(.noVerification, revealAuthEnabled: true)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-w4-none-aaaaaaa"
        )
        let revealed = try await vault.revealSecretWithEvidence(
            keyId: keyId,
            purpose: .display,
            masterPassword: nil
        )
        XCTAssertEqual(revealed.authentication, .notRequired)
        XCTAssertNil(revealed.reuseToken)
        try await vault.deleteKey(keyId)
        await assertCalls(fake, confirm: 0, mandatory: 0)
    }

    func testRevealReturnsEvidenceFromTheSamePolicySnapshotThatWasAuthenticated() async throws {
        let fake = FakeRevealGate()
        vault = makeVault(gate: fake, entitlements: StubEntitlements(tier: .unlimitedKeys))
        try await setPrefs(.biometricOrPasscode, revealAuthEnabled: true)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-evidence-aaaaaa"
        )

        let result = try await vault.revealSecretWithEvidence(
            keyId: keyId,
            purpose: .display,
            masterPassword: nil
        )

        XCTAssertEqual(result.secret, "sk-evidence-aaaaaa")
        XCTAssertEqual(result.authentication, .verified)
        XCTAssertNotNil(result.reuseToken)
        await assertCalls(fake, confirm: 1, mandatory: 0)
    }

    func testMasterPasswordPromptDoesNotMutate() async throws {
        let fake = FakeRevealGate()
        vault = makeVault(gate: fake, entitlements: StubEntitlements(tier: .unlimitedKeys))
        try await setPrefs(.masterPassword, revealAuthEnabled: true)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-w4-master-aaaaaa"
        )
        do {
            try await vault.deleteKey(keyId)
            XCTFail("expected master password prompt")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "master_password_prompt_required")
        }
        let keys = try await vault.keys(in: accountId)
        XCTAssertEqual(keys.map(\.id), [keyId])
        await assertCalls(fake, mandatory: 0, master: 0)
    }

    func testCancelCurrentPolicyLeavesKeyUntouched() async throws {
        let fake = FakeRevealGate()
        await fake.fail("confirm", with: .authenticationCancelled)
        vault = makeVault(gate: fake, entitlements: StubEntitlements(tier: .unlimitedKeys))
        try await setPrefs(.biometricOrPasscode, revealAuthEnabled: true)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-w4-cancel-aaaaaa"
        )
        do {
            try await vault.deleteKey(keyId)
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        let keys = try await vault.keys(in: accountId)
        XCTAssertEqual(keys.map(\.id), [keyId])
    }

    func testCombinationAndDevicePoliciesCallConfirmNotMandatory() async throws {
        for policy in [RevealPolicy.biometricOrPasscode, .biometryOrAppPassword] {
            let fake = FakeRevealGate()
            vault = makeVault(gate: fake, entitlements: StubEntitlements(tier: .unlimitedKeys))
            try await setPrefs(policy, revealAuthEnabled: true)
            let accountId = try await vault.createAccount(
                UpstreamAccountDraft(platform: "openai", displayName: "A")
            )
            let keyId = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "k"),
                secret: "sk-w4-policy-aaaaaa"
            )
            try await vault.deleteKey(keyId)
            await assertCalls(fake, confirm: 1, mandatory: 0)
        }
    }

    func testSessionLockRejectsGatedDeleteBeforeConfirm() async throws {
        let fake = FakeRevealGate()
        let box = SessionLockBox()
        vault = makeVault(
            gate: fake,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )
        try await setPrefs(.biometricOrPasscode, revealAuthEnabled: true)
        box.setLocked(false)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Open")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-w4-lock-aaaaaaa"
        )
        box.setLocked(true)
        do {
            try await vault.deleteKey(keyId)
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        await assertCalls(fake, confirm: 0, mandatory: 0)
    }

    private func makeVault(
        gate: RevealGateServing,
        entitlements: EntitlementServing,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock()
    ) -> KeyVaultService {
        KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: entitlements,
            sessionLock: sessionLock
        )
    }

    private func assertCalls(
        _ fake: FakeRevealGate,
        confirm: Int? = nil,
        mandatory: Int? = nil,
        master: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let journal = await fake.journal
        if let confirm {
            XCTAssertEqual(journal.callCount("confirm"), confirm, file: file, line: line)
        }
        if let mandatory {
            XCTAssertEqual(journal.callCount("confirmMandatory"), mandatory, file: file, line: line)
        }
        if let master {
            XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), master, file: file, line: line)
        }
    }

    private func setPrefs(_ policy: RevealPolicy, revealAuthEnabled: Bool) async throws {
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = policy
        patch.revealAuthEnabled = revealAuthEnabled
        try await prefs.update(patch)
    }
}

extension KeyVaultServiceTests {
    func testSharedCurrentPolicyRoutingMatrix() async throws {
        struct Row {
            let name: String
            let policy: RevealPolicy
            let password: String?
            let failMethod: String?
            let failError: ApiRelayError?
            let expectDeleted: Bool
            let confirm: Int
            let mandatory: Int
            let master: Int
        }
        let rows: [Row] = [
            .init(name: "none-success", policy: .noVerification, password: nil, failMethod: nil, failError: nil, expectDeleted: true, confirm: 0, mandatory: 0, master: 0),
            .init(name: "device-success", policy: .biometricOrPasscode, password: nil, failMethod: nil, failError: nil, expectDeleted: true, confirm: 1, mandatory: 0, master: 0),
            .init(name: "device-cancel", policy: .biometricOrPasscode, password: nil, failMethod: "confirm", failError: .authenticationCancelled, expectDeleted: false, confirm: 1, mandatory: 0, master: 0),
            .init(name: "device-fail", policy: .biometricOrPasscode, password: nil, failMethod: "confirm", failError: .authenticationFailed, expectDeleted: false, confirm: 1, mandatory: 0, master: 0),
            .init(name: "master-missing", policy: .masterPassword, password: nil, failMethod: nil, failError: nil, expectDeleted: false, confirm: 0, mandatory: 0, master: 0),
            .init(name: "master-success", policy: .masterPassword, password: "abcd", failMethod: nil, failError: nil, expectDeleted: true, confirm: 0, mandatory: 0, master: 1),
            .init(name: "master-cancel", policy: .masterPassword, password: "abcd", failMethod: "confirmWithMasterPassword", failError: .authenticationCancelled, expectDeleted: false, confirm: 0, mandatory: 0, master: 1),
            .init(name: "master-fail", policy: .masterPassword, password: "abcd", failMethod: "confirmWithMasterPassword", failError: .authenticationFailed, expectDeleted: false, confirm: 0, mandatory: 0, master: 1),
            .init(name: "combo-success", policy: .biometryOrAppPassword, password: nil, failMethod: nil, failError: nil, expectDeleted: true, confirm: 1, mandatory: 0, master: 0),
            .init(name: "combo-cancel", policy: .biometryOrAppPassword, password: nil, failMethod: "confirm", failError: .authenticationCancelled, expectDeleted: false, confirm: 1, mandatory: 0, master: 0),
            .init(name: "combo-fail", policy: .biometryOrAppPassword, password: nil, failMethod: "confirm", failError: .authenticationFailed, expectDeleted: false, confirm: 1, mandatory: 0, master: 0),
        ]
        for row in rows {
            let local = try AppSchema.makeInMemoryContainer()
            let chain = KeychainStore.makeForTests()
            let fake = FakeRevealGate()
            if let method = row.failMethod, let error = row.failError {
                await fake.fail(method, with: error)
            }
            let service = KeyVaultService(
                keychain: chain,
                gate: fake,
                clipboard: SecureClipboard(),
                modelContainer: local,
                entitlements: StubEntitlements(tier: .unlimitedKeys)
            )
            var patch = PreferencesPatch()
            patch.revealPolicy = row.policy
            patch.revealAuthEnabled = true
            try await UserPreferencesRepository(modelContainer: local).update(patch)
            let accountId = try await service.createAccount(
                UpstreamAccountDraft(platform: "openai", displayName: row.name)
            )
            let keyId = try await service.createKey(
                KeyDraft(accountId: accountId, displayName: "k"),
                secret: "sk-w4-matrix-\(row.name)-aa"
            )
            do {
                try await service.deleteKey(keyId, appPassword: row.password)
                if !row.expectDeleted { XCTFail("\(row.name) should not delete") }
            } catch {
                if row.expectDeleted { XCTFail("\(row.name) \(error)") }
            }
            let remaining = try await service.keys(in: accountId)
            if row.expectDeleted {
                XCTAssertTrue(remaining.isEmpty, row.name)
            } else {
                XCTAssertEqual(remaining.map(\.id), [keyId], row.name)
            }
            await assertCalls(
                fake,
                confirm: row.confirm,
                mandatory: row.mandatory,
                master: row.master
            )
        }
    }
    func testSensitiveOperationWiringMatrix() async throws {
        let ops: [W4WiringOp] = [.reveal, .copy, .editKey, .editAccount, .trash, .restore, .permanent]
        for op in ops {
            for mode in [W4WiringMode.cancel, .masterPrompt, .sessionLock] {
                try await runWiring(op: op, mode: mode)
            }
        }
    }

    func testPermanentDeleteRetryRefreshesKeyAccountAndTool() async throws {
        try await assertPermanentRetryRefreshes(.key)
        try await assertPermanentRetryRefreshes(.account)
        try await assertPermanentRetryRefreshes(.tool)
    }

    private func runWiring(op: W4WiringOp, mode: W4WiringMode) async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let chain = KeychainStore.makeForTests()
        let setupService = KeyVaultService(
            keychain: chain,
            gate: FakeRevealGate(),
            clipboard: SecureClipboard(),
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        var setup = PreferencesPatch()
        setup.revealPolicy = .noVerification
        setup.revealAuthEnabled = true
        try await UserPreferencesRepository(modelContainer: local).update(setup)
        let accountId = try await setupService.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "W")
        )
        let keyId = try await setupService.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-w4-wire-\(op.rawValue)-\(mode.rawValue)-aa"
        )
        if op == .restore || op == .permanent {
            try await setupService.deleteKey(keyId)
        }
        var live = PreferencesPatch()
        live.revealPolicy = mode == .masterPrompt ? .masterPassword : .biometricOrPasscode
        live.revealAuthEnabled = true
        try await UserPreferencesRepository(modelContainer: local).update(live)
        let fake = FakeRevealGate()
        if mode == .cancel {
            await fake.fail("confirm", with: .authenticationCancelled)
        }
        let box = SessionLockBox()
        if mode == .sessionLock {
            box.setLocked(true)
        }
        let service = KeyVaultService(
            keychain: chain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )

        do {
            try await perform(op, service: service, accountId: accountId, keyId: keyId)
            XCTFail("\(op.rawValue) \(mode.rawValue) should fail")
        } catch let error as ApiRelayError {
            switch (mode, error) {
            case (.cancel, .authenticationCancelled):
                break
            case (.masterPrompt, .validationFailed(_, let reason))
                where reason == "master_password_prompt_required":
                break
            case (.sessionLock, .sessionLocked):
                break
            default:
                XCTFail("\(op.rawValue) \(mode.rawValue) \(error)")
            }
        }

        switch op {
        case .reveal, .copy, .editKey, .trash:
            let ids = try await service.keys(in: accountId).map(\.id)
            XCTAssertEqual(ids, [keyId], "\(op.rawValue) \(mode.rawValue)")
        case .editAccount:
            let name = try await service.accounts().first?.displayName
            XCTAssertEqual(name, "W", "\(op.rawValue)")
        case .restore, .permanent:
            let ids = try await service.recentlyDeletedKeys().map(\.id)
            XCTAssertEqual(ids, [keyId], "\(op.rawValue)")
        }
        if mode == .sessionLock {
            await assertCalls(fake, confirm: 0, mandatory: 0, master: 0)
        }
    }

    private func perform(
        _ op: W4WiringOp,
        service: KeyVaultService,
        accountId: UUID,
        keyId: UUID
    ) async throws {
        switch op {
        case .reveal:
            _ = try await service.revealSecret(keyId: keyId, purpose: .display, masterPassword: nil)
        case .copy:
            try await service.copySecretToClipboard(keyId: keyId, masterPassword: nil)
        case .editKey:
            try await service.editKey(
                keyId,
                draft: KeyEditDraft(
                    displayName: "k2",
                    accountDisplayName: "W",
                    platform: "openai"
                )
            )
        case .editAccount:
            var patch = UpstreamAccountPatch()
            patch.displayName = "Renamed"
            try await service.updateAccount(accountId, patch: patch)
        case .trash:
            try await service.deleteKey(keyId)
        case .restore:
            try await service.restoreKey(keyId)
        case .permanent:
            try await service.permanentlyDeleteKey(keyId)
        }
    }

    private func assertPermanentRetryRefreshes(_ kind: W4PermanentKind) async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let vault = FakeKeyVault()
        let tools = FakeConsumerTools()
        await vault.setAppPasswordGate(enabled: true, expected: "correct-password")
        await tools.setAppPasswordGate(enabled: true, expected: "correct-password")
        let gate = FakeRevealGate()
        let prefs = FakePreferences()
        let master = FakeMasterPassword()
        let privacy = AppPrivacyController(
            gate: gate,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: false
        )
        let env = AppEnvironment(
            modelContainer: container,
            keychain: FakeKeychain(),
            masterPassword: master,
            gate: gate,
            clipboard: FakeClipboard(),
            vault: vault,
            consumerTools: tools,
            trashBatch: FakeRecentlyDeletedBatch(),
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            preferences: prefs,
            backups: FakeSecureBackup(),
            backupPassphrase: FakeBackupPassphrase(),
            dataLifecycle: FakeDataLifecycle(),
            cloudSync: FakeCloudSync(),
            appPrivacy: privacy
        )
        let vm = VaultHomeViewModel(environment: env)
        let box = TrashChangeBox()
        let token = NotificationCenter.default.addObserver(
            forName: .trashBundleDidChange,
            object: nil,
            queue: nil
        ) { _ in
            box.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let targetId: UUID
        switch kind {
        case .key:
            let accountId = try await vault.createAccount(
                UpstreamAccountDraft(platform: "openai", displayName: "A")
            )
            targetId = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "k"),
                secret: "sk-preview-not-used"
            )
            try await vault.deleteKey(targetId)
        case .account:
            targetId = try await vault.createAccount(
                UpstreamAccountDraft(platform: "openai", displayName: "A")
            )
            try await vault.deleteAccount(targetId)
        case .tool:
            targetId = try await tools.createTool(ConsumerToolDraft(name: "T"))
            try await tools.deleteTool(id: targetId)
        }

        func stillPresent() async throws -> Bool {
            let bundle = try await vm.loadRecentlyDeletedBundle()
            switch kind {
            case .key: return bundle.keys.contains { $0.id == targetId }
            case .account: return bundle.accounts.contains { $0.id == targetId }
            case .tool: return bundle.tools.contains { $0.id == targetId }
            }
        }

        switch kind {
        case .key: await vm.permanentlyDeleteKey(targetId)
        case .account: await vm.permanentlyDeleteAccount(targetId)
        case .tool: await vm.permanentlyDeleteTool(targetId)
        }
        XCTAssertTrue(vm.hasPendingSensitiveRetry, kind.rawValue)
        var present = try await stillPresent()
        XCTAssertTrue(present, kind.rawValue)
        XCTAssertEqual(box.count, 0, kind.rawValue)

        vm.cancelMasterPasswordPrompt()
        XCTAssertFalse(vm.hasPendingSensitiveRetry, kind.rawValue)
        present = try await stillPresent()
        XCTAssertTrue(present, "\(kind.rawValue) cancel")

        switch kind {
        case .key: await vm.permanentlyDeleteKey(targetId)
        case .account: await vm.permanentlyDeleteAccount(targetId)
        case .tool: await vm.permanentlyDeleteTool(targetId)
        }
        await vm.submitMasterPassword("wrong-password")
        XCTAssertFalse(vm.hasPendingSensitiveRetry, kind.rawValue)
        present = try await stillPresent()
        XCTAssertTrue(present, "\(kind.rawValue) wrong")
        XCTAssertEqual(box.count, 0, kind.rawValue)

        switch kind {
        case .key: await vm.permanentlyDeleteKey(targetId)
        case .account: await vm.permanentlyDeleteAccount(targetId)
        case .tool: await vm.permanentlyDeleteTool(targetId)
        }
        await vm.submitMasterPassword("correct-password")
        XCTAssertFalse(vm.hasPendingSensitiveRetry, kind.rawValue)
        present = try await stillPresent()
        XCTAssertFalse(present, "\(kind.rawValue) success")
        XCTAssertEqual(box.count, 1, kind.rawValue)

        await vm.submitMasterPassword("correct-password")
        XCTAssertEqual(box.count, 1, "\(kind.rawValue) no leak")
    }

    func testCopyRevealedSecretTokenSkipsSecondIdentityAndHonorsSessionLock() async throws {
        let fake = FakeRevealGate()
        let box = SessionLockBox()
        let fakeClipboard = FakeClipboard()
        let service = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: fakeClipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        patch.revealAuthEnabled = true
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "reuse")
        )
        let keyId = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-already-viewed-secret"
        )
        let firstReveal = try await service.revealSecretWithEvidence(
            keyId: keyId,
            purpose: .display,
            masterPassword: nil
        )
        let firstToken = try XCTUnwrap(firstReveal.reuseToken)
        try await service.copyRevealedSecretToClipboard(keyId: keyId, token: firstToken)
        var journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirm"), 1, "reuse copy must not authenticate twice")
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 0)

        let secondReveal = try await service.revealSecretWithEvidence(
            keyId: keyId,
            purpose: .display,
            masterPassword: nil
        )
        let secondToken = try XCTUnwrap(secondReveal.reuseToken)
        box.setLocked(true)
        do {
            try await service.copyRevealedSecretToClipboard(keyId: keyId, token: secondToken)
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirm"), 2)
    }

    func testCopyRevealedSecretPropagatesAutoClearAndLocalOnlyPreferences() async throws {
        let fakeKeychain = FakeKeychain()
        let fakeGate = FakeRevealGate()
        let fakeClipboard = FakeClipboard()
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: fakeGate,
            clipboard: fakeClipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        let repository = UserPreferencesRepository(modelContainer: container)
        try await repository.update(PreferencesPatch(
            clipboardClearEnabled: true,
            clipboardClearSeconds: 37,
            clipboardLocalOnly: true
        ))
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "prefs")
        )
        let firstKey = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "first"),
            secret: "first-secret"
        )
        let secondKey = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "second"),
            secret: "second-secret"
        )
        try await repository.update(PreferencesPatch(
            revealPolicy: .biometricOrPasscode,
            revealAuthEnabled: true
        ))
        let firstResult = try await service.revealSecretWithEvidence(
            keyId: firstKey,
            purpose: .display,
            masterPassword: nil
        )
        try await service.copyRevealedSecretToClipboard(
            keyId: firstKey,
            token: try XCTUnwrap(firstResult.reuseToken)
        )

        let firstWritten = await fakeClipboard.lastWritten
        let firstExpiry = await fakeClipboard.lastExpiresAfter
        let firstLocalOnly = await fakeClipboard.lastLocalOnly
        XCTAssertEqual(firstWritten, "first-secret")
        XCTAssertEqual(firstExpiry, 37)
        XCTAssertEqual(firstLocalOnly, true)

        try await repository.update(PreferencesPatch(
            clipboardClearEnabled: false,
            clipboardLocalOnly: false
        ))
        let secondResult = try await service.revealSecretWithEvidence(
            keyId: secondKey,
            purpose: .display,
            masterPassword: nil
        )
        try await service.copyRevealedSecretToClipboard(
            keyId: secondKey,
            token: try XCTUnwrap(secondResult.reuseToken)
        )

        let secondWritten = await fakeClipboard.lastWritten
        let secondExpiry = await fakeClipboard.lastExpiresAfter
        let secondLocalOnly = await fakeClipboard.lastLocalOnly
        XCTAssertEqual(secondWritten, "second-secret")
        XCTAssertNil(secondExpiry)
        XCTAssertEqual(secondLocalOnly, false)
    }

    func testRevealReuseTokenRejectsForgeryCrossKeyGenerationChangeAndReplay() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let fakeKeychain = FakeKeychain()
        let fakeClipboard = FakeClipboard()
        let fakeGate = FakeRevealGate()
        let box = SessionLockBox()
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: fakeGate,
            clipboard: fakeClipboard,
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )
        let repository = UserPreferencesRepository(modelContainer: local)
        try await repository.update(PreferencesPatch(revealPolicy: .noVerification))
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "tokens")
        )
        let firstKey = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "first"),
            secret: "sk-token-first-secret"
        )
        let secondKey = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "second"),
            secret: "sk-token-second-secret"
        )
        try await repository.update(PreferencesPatch(
            revealPolicy: .biometricOrPasscode,
            revealAuthEnabled: true
        ))

        var reads = await fakeKeychain.journal.callCount("read")
        var writes = await fakeClipboard.journal.callCount("write")
        do {
            try await service.copyRevealedSecretToClipboard(
                keyId: firstKey,
                token: .unissuedForTesting()
            )
            XCTFail("unissued token must fail")
        } catch ApiRelayError.authenticationFailed {
        }
        var readsAfterAttempt = await fakeKeychain.journal.callCount("read")
        var writesAfterAttempt = await fakeClipboard.journal.callCount("write")
        XCTAssertEqual(readsAfterAttempt, reads)
        XCTAssertEqual(writesAfterAttempt, writes)

        let crossResult = try await service.revealSecretWithEvidence(
            keyId: firstKey,
            purpose: .display,
            masterPassword: nil
        )
        let crossToken = try XCTUnwrap(crossResult.reuseToken)
        reads = await fakeKeychain.journal.callCount("read")
        do {
            try await service.copyRevealedSecretToClipboard(keyId: secondKey, token: crossToken)
            XCTFail("cross-key token must fail")
        } catch ApiRelayError.authenticationFailed {
        }
        readsAfterAttempt = await fakeKeychain.journal.callCount("read")
        writesAfterAttempt = await fakeClipboard.journal.callCount("write")
        XCTAssertEqual(readsAfterAttempt, reads)
        XCTAssertEqual(writesAfterAttempt, writes)
        do {
            try await service.copyRevealedSecretToClipboard(keyId: firstKey, token: crossToken)
            XCTFail("cross-key attempt must consume token")
        } catch ApiRelayError.authenticationFailed {
        }
        readsAfterAttempt = await fakeKeychain.journal.callCount("read")
        XCTAssertEqual(readsAfterAttempt, reads)

        let staleResult = try await service.revealSecretWithEvidence(
            keyId: firstKey,
            purpose: .display,
            masterPassword: nil
        )
        let staleToken = try XCTUnwrap(staleResult.reuseToken)
        reads = await fakeKeychain.journal.callCount("read")
        box.invalidateAuthorizationLeases()
        do {
            try await service.copyRevealedSecretToClipboard(keyId: firstKey, token: staleToken)
            XCTFail("generation change must revoke token")
        } catch ApiRelayError.sessionLocked {
        }
        readsAfterAttempt = await fakeKeychain.journal.callCount("read")
        writesAfterAttempt = await fakeClipboard.journal.callCount("write")
        XCTAssertEqual(readsAfterAttempt, reads)
        XCTAssertEqual(writesAfterAttempt, writes)

        let validResult = try await service.revealSecretWithEvidence(
            keyId: firstKey,
            purpose: .display,
            masterPassword: nil
        )
        let validToken = try XCTUnwrap(validResult.reuseToken)
        reads = await fakeKeychain.journal.callCount("read")
        writes = await fakeClipboard.journal.callCount("write")
        try await service.copyRevealedSecretToClipboard(keyId: firstKey, token: validToken)
        let readsAfterValidCopy = await fakeKeychain.journal.callCount("read")
        let writesAfterValidCopy = await fakeClipboard.journal.callCount("write")
        XCTAssertEqual(readsAfterValidCopy, reads + 1)
        XCTAssertEqual(writesAfterValidCopy, writes + 1)
        let lastWritten = await fakeClipboard.lastWritten
        XCTAssertEqual(lastWritten, "sk-token-first-secret")

        do {
            try await service.copyRevealedSecretToClipboard(keyId: firstKey, token: validToken)
            XCTFail("token replay must fail")
        } catch ApiRelayError.authenticationFailed {
        }
        readsAfterAttempt = await fakeKeychain.journal.callCount("read")
        writesAfterAttempt = await fakeClipboard.journal.callCount("write")
        XCTAssertEqual(readsAfterAttempt, readsAfterValidCopy)
        XCTAssertEqual(writesAfterAttempt, writesAfterValidCopy)
    }

    func testRevealReuseGrantStorePrunesInvalidAndEvictsOldestAtHardLimit() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let fakeKeychain = FakeKeychain()
        let fakeClipboard = FakeClipboard()
        let fakeGate = FakeRevealGate()
        let box = SessionLockBox()
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: fakeGate,
            clipboard: fakeClipboard,
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )
        let repository = UserPreferencesRepository(modelContainer: local)
        try await repository.update(PreferencesPatch(revealPolicy: .noVerification))
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "bounded-tokens")
        )
        let keyId = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "bounded"),
            secret: "sk-bounded-token-secret"
        )
        try await repository.update(PreferencesPatch(
            revealPolicy: .biometricOrPasscode,
            revealAuthEnabled: true
        ))

        let staleResult = try await service.revealSecretWithEvidence(
            keyId: keyId,
            purpose: .display,
            masterPassword: nil
        )
        let staleToken = try XCTUnwrap(staleResult.reuseToken)
        var grantCount = await service.revealReuseGrantCountForTesting()
        XCTAssertEqual(grantCount, 1)

        box.invalidateAuthorizationLeases()
        let firstCurrentResult = try await service.revealSecretWithEvidence(
            keyId: keyId,
            purpose: .display,
            masterPassword: nil
        )
        let firstCurrentToken = try XCTUnwrap(firstCurrentResult.reuseToken)
        grantCount = await service.revealReuseGrantCountForTesting()
        XCTAssertEqual(grantCount, 1, "issuing a new token must prune invalid generations")

        var reads = await fakeKeychain.journal.callCount("read")
        var writes = await fakeClipboard.journal.callCount("write")
        do {
            try await service.copyRevealedSecretToClipboard(keyId: keyId, token: staleToken)
            XCTFail("pruned generation token must fail")
        } catch ApiRelayError.authenticationFailed {
        }
        var readsAfterAttempt = await fakeKeychain.journal.callCount("read")
        var writesAfterAttempt = await fakeClipboard.journal.callCount("write")
        XCTAssertEqual(readsAfterAttempt, reads)
        XCTAssertEqual(writesAfterAttempt, writes)

        var newestToken = firstCurrentToken
        for _ in 0..<64 {
            let result = try await service.revealSecretWithEvidence(
                keyId: keyId,
                purpose: .display,
                masterPassword: nil
            )
            newestToken = try XCTUnwrap(result.reuseToken)
        }
        grantCount = await service.revealReuseGrantCountForTesting()
        XCTAssertEqual(grantCount, 64, "unconsumed token storage must remain bounded")

        reads = await fakeKeychain.journal.callCount("read")
        writes = await fakeClipboard.journal.callCount("write")
        do {
            try await service.copyRevealedSecretToClipboard(keyId: keyId, token: firstCurrentToken)
            XCTFail("oldest token beyond the hard limit must be evicted")
        } catch ApiRelayError.authenticationFailed {
        }
        readsAfterAttempt = await fakeKeychain.journal.callCount("read")
        writesAfterAttempt = await fakeClipboard.journal.callCount("write")
        XCTAssertEqual(readsAfterAttempt, reads)
        XCTAssertEqual(writesAfterAttempt, writes)

        try await service.copyRevealedSecretToClipboard(keyId: keyId, token: newestToken)
        let readsAfterValidCopy = await fakeKeychain.journal.callCount("read")
        let writesAfterValidCopy = await fakeClipboard.journal.callCount("write")
        let countAfterValidCopy = await service.revealReuseGrantCountForTesting()
        let lastWritten = await fakeClipboard.lastWritten
        XCTAssertEqual(readsAfterValidCopy, reads + 1)
        XCTAssertEqual(writesAfterValidCopy, writes + 1)
        XCTAssertEqual(countAfterValidCopy, 63)
        XCTAssertEqual(lastWritten, "sk-bounded-token-secret")
    }

    func testCombinationPasswordRevealAndDeleteUseExplicitEntry() async throws {
        let fake = FakeRevealGate()
        let service = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometryOrAppPassword
        patch.revealAuthEnabled = true
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "combo")
        )
        let keyId = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-combo-explicit-aaaa"
        )
        _ = try await service.revealSecret(keyId: keyId, purpose: .display, masterPassword: "combo-pass-word")
        try await service.deleteKey(keyId, appPassword: "combo-pass-word")
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 2)
        XCTAssertEqual(journal.callCount("confirm"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }

    func testKeychainInventoryFailureIsNotReportedAsEverySecretMissing() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let fakeKeychain = FakeKeychain()
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: FakeRevealGate(),
            clipboard: FakeClipboard(),
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        try await UserPreferencesRepository(modelContainer: local).update(
            PreferencesPatch(revealPolicy: .noVerification)
        )
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "inventory-failure")
        )
        _ = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "key"),
            secret: "sk-inventory-failure-secret"
        )
        await fakeKeychain.fail("listAccounts", with: .keychainFailure(errSecAuthFailed))

        do {
            _ = try await service.keys(in: accountId)
            XCTFail("an unavailable Keychain must not be presented as missing credentials")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, errSecAuthFailed)
        }
    }

    func testDuplicateCheckPropagatesUnexpectedKeychainReadFailure() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let fakeKeychain = FakeKeychain()
        let service = KeyVaultService(
            keychain: fakeKeychain,
            gate: FakeRevealGate(),
            clipboard: FakeClipboard(),
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        try await UserPreferencesRepository(modelContainer: local).update(
            PreferencesPatch(revealPolicy: .noVerification)
        )
        let accountId = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "duplicate-failure")
        )
        _ = try await service.createKey(
            KeyDraft(accountId: accountId, displayName: "first"),
            secret: "sk-duplicate-failure-secret"
        )
        await fakeKeychain.fail("read", with: .keychainFailure(errSecAuthFailed))

        do {
            _ = try await service.createKey(
                KeyDraft(accountId: accountId, displayName: "second"),
                secret: "sk-other-secret-value"
            )
            XCTFail("duplicate inspection must fail closed when Keychain cannot be read")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, errSecAuthFailed)
        }
        await fakeKeychain.clearFailure("read")
        let records = try await service.keys(in: accountId)
        XCTAssertEqual(records.count, 1)
    }
}

private enum W4WiringOp: String {
    case reveal, copy, editKey, editAccount, trash, restore, permanent
}

private enum W4WiringMode: String {
    case cancel
    case masterPrompt
    case sessionLock
}

private enum W4PermanentKind: String {
    case key, account, tool
}

private final class TrashChangeBox: @unchecked Sendable {
    var count = 0
}

private actor BlockingClipboardCommit: ClipboardServing {
    private var isBlocked = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var writeCount = 0
    private(set) var lastWritten: String?

    func write(
        _ secret: String,
        expiresAfter: TimeInterval?,
        localOnly: Bool,
        committing: @escaping ClipboardCommit
    ) async throws {
        _ = expiresAfter
        _ = localOnly
        isBlocked = true
        let waiters = entryWaiters
        entryWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        isBlocked = false
        try committing {
            writeCount += 1
            lastWritten = secret
        }
    }

    func waitUntilCommitIsBlocked() async {
        if isBlocked { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func releaseCommit() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func clearIfStillOurs() async {
        lastWritten = nil
    }
}

extension KeyVaultServiceTests {
    func testClipboardCommitInvalidatedWhileBlockedPerformsZeroWrites() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let chain = FakeKeychain()
        let fakeGate = FakeRevealGate()
        let blockingClipboard = BlockingClipboardCommit()
        let sessionLock = SessionLockBox()
        let service = KeyVaultService(
            keychain: chain,
            gate: fakeGate,
            clipboard: blockingClipboard,
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: sessionLock
        )
        try await UserPreferencesRepository(modelContainer: local).update(
            PreferencesPatch(revealPolicy: .noVerification, revealAuthEnabled: true)
        )
        let accountID = try await service.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "clipboard-lease")
        )
        let keyID = try await service.createKey(
            KeyDraft(accountId: accountID, displayName: "key"),
            secret: "sk-clipboard-final-commit"
        )

        let copy = Task {
            try await service.copySecretToClipboard(keyId: keyID, masterPassword: nil)
        }
        await blockingClipboard.waitUntilCommitIsBlocked()
        sessionLock.invalidateAuthorizationLeases()
        await blockingClipboard.releaseCommit()

        do {
            try await copy.value
            XCTFail("a stale lease must not reach the pasteboard commit")
        } catch ApiRelayError.sessionLocked {
            // expected
        }
        let writeCount = await blockingClipboard.writeCount
        let lastWritten = await blockingClipboard.lastWritten
        XCTAssertEqual(writeCount, 0)
        XCTAssertNil(lastWritten)
    }
}
