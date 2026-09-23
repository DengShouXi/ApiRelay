@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

private actor DataLifecycleCloudConvergenceProbe: CloudEraseConverging {
    private let terminalError: ApiRelayError?
    private var finishCallCount = 0

    init(terminalError: ApiRelayError? = nil) {
        self.terminalError = terminalError
    }

    func finishAfterInitialPurge(
        repurge: @Sendable () async throws -> Void
    ) async throws {
        finishCallCount += 1
        try await repurge()
        if let terminalError { throw terminalError }
    }

    func calls() -> Int { finishCallCount }
}

private actor DataLifecycleReappearingKeychain: KeychainStoring {
    enum ArrivalMode {
        case once
        case everyConvergencePass
    }

    private let initialAccount = UUID()
    private let arrivingAccount = UUID()
    private let arrivalMode: ArrivalMode
    private var storage: [KeychainService: Set<UUID>]
    private var keysListCalls = 0
    private var didInjectArrival = false
    private var deleted: [UUID] = []

    init(arrivalMode: ArrivalMode) {
        self.arrivalMode = arrivalMode
        self.storage = [.keys: [initialAccount]]
    }

    func save(_ secret: String, service: KeychainService, account: UUID) throws {
        _ = secret
        storage[service, default: []].insert(account)
    }

    func read(service: KeychainService, account: UUID) throws -> String {
        guard storage[service]?.contains(account) == true else {
            throw ApiRelayError.keychainFailure(errSecItemNotFound)
        }
        return "test-secret"
    }

    func delete(service: KeychainService, account: UUID) throws {
        if storage[service]?.remove(account) != nil {
            deleted.append(account)
        }
    }

    func listAccounts(service: KeychainService) throws -> [UUID] {
        switch service {
        case .keys:
            keysListCalls += 1
            // Call 1 is the initial erase sweep. Inject only after it deleted
            // the first item, modelling a synchronizable arrival between that
            // sweep and the final Keychain convergence fence.
            if keysListCalls >= 2, storage[.keys, default: []].isEmpty {
                switch arrivalMode {
                case .once where !didInjectArrival:
                    storage[.keys, default: []].insert(arrivingAccount)
                    didInjectArrival = true
                case .everyConvergencePass:
                    storage[.keys, default: []].insert(UUID())
                default:
                    break
                }
            }
        default:
            break
        }
        return Array(storage[service, default: []])
    }

    func snapshot() -> (remaining: Int, deleted: [UUID], listCalls: Int) {
        (
            storage.values.reduce(0) { $0 + $1.count },
            deleted,
            keysListCalls
        )
    }

    func expectedArrivalAccount() -> UUID { arrivingAccount }
}

@MainActor
final class DataLifecycleTests: XCTestCase {
    func testEraseClearsActiveKeysTrashAndConsumerTools() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        let mutationGate = StorageMutationGate()
        // 清除流程要真服务（`purgeLocalSnapshotForErase` 不在协议上，且不碰 StoreKit）；
        // 建密钥时的配额检查走桩，免去每次 60 秒的商店超时。
        let entitlements = EntitlementService(
            modelContainer: container,
            mutationGate: mutationGate
        )
        let vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: SecureClipboard(mutationGate: mutationGate),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .free),
            mutationGate: mutationGate
        )
        let consumerTools = ConsumerToolService(
            modelContainer: container,
            gate: gate,
            mutationGate: mutationGate
        )
        let preferences = PreferencesService(
            modelContainer: container,
            mutationGate: mutationGate
        )
        var patch = PreferencesPatch()
        patch.revealPolicy = .noVerification
        patch.defaultKeyAvatarSymbol = "globe"
        patch.defaultKeyAvatarColor = "teal"
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        try await preferences.update(patch)

        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let activeId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "active"),
            secret: "sk-erase-active-1111"
        )
        let trashId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "trashed"),
            secret: "sk-erase-trash-2222"
        )
        try await vault.deleteKey(trashId)
        let toolId = try await consumerTools.createTool(ConsumerToolDraft(name: "Cursor"))
        try await vault.addAssignment(keyId: activeId, consumerToolId: toolId)

        let accountsBefore = try await vault.accounts()
        let activeKeysBefore = try await vault.keys(in: accountId)
        let trashBefore = try await vault.recentlyDeletedKeys()
        let toolsBefore = try await consumerTools.tools(includeHidden: true)
        XCTAssertFalse(accountsBefore.isEmpty)
        XCTAssertEqual(activeKeysBefore.count, 1)
        XCTAssertEqual(trashBefore.count, 1)
        XCTAssertEqual(toolsBefore.count, 1)

        let backup = BackupPassphraseService(keychain: keychain)
        try? await backup.clear()
        try await backup.set("erase-backup-pass")

        let lifecycle = DataLifecycleService(
            gate: gate,
            keychain: keychain,
            modelContainer: container,
            vault: vault,
            consumerTools: consumerTools,
            backups: FakeSecureBackup(),
            preferences: preferences,
            entitlements: entitlements,
            eraseJournal: InMemoryDataEraseJournal(),
            mutationGate: mutationGate
        )
        try await lifecycle.eraseAllUserData()

        let accountsAfter = try await vault.accounts()
        let keysAfter = try await vault.keys(in: nil)
        let deletedKeys = try await vault.recentlyDeletedKeys()
        let deletedAccounts = try await vault.recentlyDeletedAccounts()
        let toolsAfter = try await consumerTools.tools(includeHidden: true)
        let deletedTools = try await consumerTools.recentlyDeletedTools()
        XCTAssertTrue(accountsAfter.isEmpty)
        XCTAssertTrue(keysAfter.isEmpty)
        XCTAssertTrue(deletedKeys.isEmpty)
        XCTAssertTrue(deletedAccounts.isEmpty)
        XCTAssertTrue(toolsAfter.isEmpty)
        XCTAssertTrue(deletedTools.isEmpty)

        do {
            _ = try await keychain.read(service: .keys, account: activeId)
            XCTFail("expected missing active key")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, errSecItemNotFound)
        }
        do {
            _ = try await keychain.read(service: .keys, account: trashId)
            XCTFail("expected missing trashed key")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, errSecItemNotFound)
        }
        let backupStillSet = try await backup.isSet()
        XCTAssertFalse(backupStillSet)

        let prefsAfter = try await preferences.load()
        XCTAssertNil(prefsAfter.defaultKeyAvatarSymbol)
        XCTAssertNil(prefsAfter.defaultKeyAvatarColor)
    }

    func testEraseUsesCurrentPolicyAndCancelLeavesData() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let fake = FakeRevealGate()
        await fake.fail("confirm", with: .authenticationCancelled)
        let vault = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .free)
        )
        let consumerTools = ConsumerToolService(modelContainer: container, gate: fake)
        let preferences = PreferencesService(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Keep")
        )
        _ = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "keep"),
            secret: "sk-erase-keep-1111"
        )
        let lifecycle = DataLifecycleService(
            gate: fake,
            keychain: keychain,
            modelContainer: container,
            vault: vault,
            consumerTools: consumerTools,
            backups: FakeSecureBackup(),
            preferences: preferences,
            entitlements: EntitlementService(modelContainer: container),
            eraseJournal: InMemoryDataEraseJournal()
        )
        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        let accounts = try await vault.accounts()
        XCTAssertEqual(accounts.count, 1)
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirm"), 1)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }

    func testEraseSessionLockDoesNotConfirm() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let fake = FakeRevealGate()
        let box = SessionLockBox()
        box.setLocked(true)
        let vault = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .free),
            sessionLock: box
        )
        let lifecycle = DataLifecycleService(
            gate: fake,
            keychain: keychain,
            modelContainer: container,
            vault: vault,
            consumerTools: ConsumerToolService(modelContainer: container, gate: fake, sessionLock: box),
            backups: FakeSecureBackup(),
            preferences: PreferencesService(modelContainer: container),
            entitlements: EntitlementService(modelContainer: container),
            sessionLock: box,
            eraseJournal: InMemoryDataEraseJournal()
        )
        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirm"), 0)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }

    func testEraseAuthorizationLeaseRevokedDuringConfirmHasZeroSideEffects() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let gate = FakeRevealGate()
        let box = SessionLockBox()
        let vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: FakeClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )
        let tools = ConsumerToolService(modelContainer: container, gate: gate, sessionLock: box)
        let preferences = PreferencesService(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .noVerification
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Keep")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "keep"),
            secret: "sk-erase-lease-keep"
        )
        patch.revealPolicy = .biometricOrPasscode
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        await gate.setAfterConfirmHook {
            box.invalidateAuthorizationLeases()
        }
        let deletesBefore = await keychain.journal.callCount("delete")
        let lifecycle = DataLifecycleService(
            gate: gate,
            keychain: keychain,
            modelContainer: container,
            vault: vault,
            consumerTools: tools,
            backups: FakeSecureBackup(),
            preferences: preferences,
            entitlements: EntitlementService(modelContainer: container),
            sessionLock: box,
            eraseJournal: InMemoryDataEraseJournal()
        )

        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("revoked erase lease must fail")
        } catch ApiRelayError.sessionLocked {
        }

        let deletesAfter = await keychain.journal.callCount("delete")
        let remainingAccounts = try await vault.accounts().map(\.id)
        let keptSecret = try await keychain.read(service: .keys, account: keyId)
        XCTAssertEqual(deletesAfter, deletesBefore)
        XCTAssertEqual(remainingAccounts, [accountId])
        XCTAssertEqual(keptSecret, "sk-erase-lease-keep")
    }
}

extension DataLifecycleTests {
    func testEraseInvalidatedAtFinalStartCommitHasNoJournalAndNoDeletes() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let secretID = UUID()
        try await keychain.save("keep", service: .keys, account: secretID)
        let barrier = CommitBarrierSessionLock()
        let eraseJournal = InMemoryDataEraseJournal()
        let vault = FakeKeyVault()
        let tools = FakeConsumerTools()
        let lifecycle = DataLifecycleService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: local,
            vault: vault,
            consumerTools: tools,
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            sessionLock: barrier,
            eraseJournal: eraseJournal
        )
        barrier.blockNextCommit()

        let revoke = Task.detached {
            await barrier.waitUntilCommitIsBlocked()
            barrier.invalidateAuthorizationLeases()
            barrier.releaseCommit()
        }
        let erasing = Task { try await lifecycle.eraseAllUserData() }
        await revoke.value

        do {
            try await erasing.value
            XCTFail("stale lease must not start an erase transaction")
        } catch ApiRelayError.sessionLocked {
            // expected
        }
        let deleteCount = await keychain.journal.callCount("delete")
        let vaultPurgeCount = await vault.journal.callCount("purgeAllRecordsForCommittedErase")
        let keptSecret = try await keychain.read(service: .keys, account: secretID)
        XCTAssertFalse(eraseJournal.hasPendingErase())
        XCTAssertEqual(deleteCount, 0)
        XCTAssertEqual(vaultPurgeCount, 0)
        XCTAssertEqual(keptSecret, "keep")
    }

    func testEraseContinuesAfterSessionInvalidationOnceJournaled() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let firstID = UUID()
        let secondID = UUID()
        try await keychain.save("first", service: .keys, account: firstID)
        try await keychain.save("second", service: .keys, account: secondID)
        keychain.blockNextCall("delete")
        let box = SessionLockBox()
        let eraseJournal = InMemoryDataEraseJournal()
        let vault = FakeKeyVault()
        let tools = FakeConsumerTools()
        let lifecycle = DataLifecycleService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: local,
            vault: vault,
            consumerTools: tools,
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            sessionLock: box,
            eraseJournal: eraseJournal
        )

        let erasing = Task { try await lifecycle.eraseAllUserData() }
        await keychain.waitUntilCallIsBlocked("delete")
        box.invalidateAuthorizationLeases()
        keychain.releaseBlockedCall("delete")
        try await erasing.value

        let deleteCount = await keychain.journal.callCount("delete")
        let remainingAccounts = try await keychain.listAccounts(service: .keys)
        let vaultPurgeCount = await vault.journal.callCount("purgeAllRecordsForCommittedErase")
        let toolPurgeCount = await tools.journal.callCount("purgeAllRecordsForCommittedErase")
        XCTAssertFalse(eraseJournal.hasPendingErase())
        XCTAssertEqual(deleteCount, 2)
        XCTAssertTrue(remainingAccounts.isEmpty)
        XCTAssertEqual(vaultPurgeCount, 1)
        XCTAssertEqual(toolPurgeCount, 1)
    }

    func testInterruptedEraseRetryUsesDeviceOwnerRecoveryWhenAppPasswordMaterialIsGone() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let gate = FakeRevealGate()
        let preferences = FakePreferences()
        try await preferences.update(PreferencesPatch(revealPolicy: .masterPassword))
        let eraseJournal = InMemoryDataEraseJournal()
        eraseJournal.seedPending(.vault)
        let lifecycle = DataLifecycleService(
            gate: gate,
            keychain: FakeKeychain(),
            modelContainer: local,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: preferences,
            entitlements: FakeEntitlements(),
            eraseJournal: eraseJournal
        )

        try await lifecycle.eraseAllUserData(appPassword: nil)

        let calls = await gate.journal
        XCTAssertEqual(calls.callCount("confirmMandatory"), 1)
        XCTAssertEqual(calls.callCount("confirmWithMasterPassword"), 0)
        XCTAssertEqual(calls.callCount("confirm"), 0)
        XCTAssertFalse(eraseJournal.hasPendingErase())
    }

    func testEraseJournalWriteFailureStartsNoDeletion() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let secretID = UUID()
        try await keychain.save("keep", service: .keys, account: secretID)
        let eraseJournal = InMemoryDataEraseJournal()
        let mutationGate = StorageMutationGate()
        eraseJournal.failMarks(with: .storageRecoveryFailed(
            operation: "test_journal",
            detail: "forced"
        ))
        let vault = FakeKeyVault()
        let lifecycle = DataLifecycleService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: local,
            vault: vault,
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            eraseJournal: eraseJournal,
            mutationGate: mutationGate
        )

        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("erase must not start without a verified journal marker")
        } catch ApiRelayError.storageRecoveryFailed {
            // expected
        }
        let deleteCount = await keychain.journal.callCount("delete")
        let vaultPurgeCount = await vault.journal.callCount("purgeAllRecordsForCommittedErase")
        let keptSecret = try await keychain.read(service: .keys, account: secretID)
        XCTAssertEqual(deleteCount, 0)
        XCTAssertEqual(vaultPurgeCount, 0)
        XCTAssertEqual(keptSecret, "keep")
        XCTAssertFalse(mutationGate.isEraseSealed())
        let laterWrite = try mutationGate.beginNormal(operation: "journal_failure_recovery")
        laterWrite.finish()
    }

    func testEraseFlowSharedRoutingDoesNotCallServiceUntilAllowed() async throws {
        struct Row {
            let policy: RevealPolicy
            let expected: SettingsEraseAllFlow.Command
            let steps: [String]
        }
        let rows: [Row] = [
            .init(policy: .noVerification, expected: .erase(appPassword: nil), steps: ["destructiveConfirmed", "identityStarted"]),
            .init(policy: .biometricOrPasscode, expected: .erase(appPassword: nil), steps: ["destructiveConfirmed", "identityStarted"]),
            .init(policy: .biometryOrAppPassword, expected: .erase(appPassword: nil), steps: ["destructiveConfirmed", "identityStarted"]),
            .init(policy: .masterPassword, expected: .promptAppPassword, steps: ["destructiveConfirmed", "identityPrompt"]),
        ]
        for row in rows {
            var trace = SettingsEraseAllFlow.Trace()
            XCTAssertEqual(
                SettingsEraseAllFlow.afterDestructiveConfirm(policy: row.policy, trace: &trace),
                row.expected,
                "policy \(row.policy.rawValue)"
            )
            XCTAssertEqual(trace.steps, row.steps, "policy \(row.policy.rawValue)")
        }

        var cancelTrace = SettingsEraseAllFlow.Trace()
        _ = SettingsEraseAllFlow.afterDestructiveConfirm(policy: .masterPassword, trace: &cancelTrace)
        XCTAssertEqual(SettingsEraseAllFlow.afterAppPasswordCancel(trace: &cancelTrace), .none)
        XCTAssertEqual(
            cancelTrace.steps,
            ["destructiveConfirmed", "identityPrompt", "identityCancelled"]
        )

        var emptyTrace = SettingsEraseAllFlow.Trace()
        _ = SettingsEraseAllFlow.afterDestructiveConfirm(policy: .masterPassword, trace: &emptyTrace)
        XCTAssertEqual(SettingsEraseAllFlow.afterAppPasswordEntry("   ", trace: &emptyTrace), .none)
        XCTAssertTrue(emptyTrace.steps.contains("identityRejected.empty"))

        var okTrace = SettingsEraseAllFlow.Trace()
        _ = SettingsEraseAllFlow.afterDestructiveConfirm(policy: .masterPassword, trace: &okTrace)
        let command = SettingsEraseAllFlow.afterAppPasswordEntry("abcd", trace: &okTrace)
        guard case .erase(let password) = command else {
            return XCTFail("expected erase after password")
        }
        SettingsEraseAllFlow.noteEraseStarted(trace: &okTrace)
        let fake = FakeDataLifecycle()
        try await fake.eraseAllUserData(appPassword: password)
        XCTAssertEqual(
            okTrace.steps,
            ["destructiveConfirmed", "identityPrompt", "identityStarted", "eraseStarted"]
        )
        let storedPassword = await fake.lastAppPassword
        XCTAssertEqual(storedPassword, "abcd")
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("eraseAllUserData"), 1)
    }

    func testEraseCombinationPasswordUsesExplicitEntryWithoutRepeatingDestructiveConfirm() async throws {
        var trace = SettingsEraseAllFlow.Trace()
        XCTAssertEqual(
            SettingsEraseAllFlow.afterDestructiveConfirm(policy: .biometryOrAppPassword, trace: &trace),
            .erase(appPassword: nil)
        )
        XCTAssertEqual(
            SettingsEraseAllFlow.afterCombinationBiometricEnded(trace: &trace),
            .promptAppPassword
        )
        XCTAssertEqual(trace.steps.filter { $0 == "destructiveConfirmed" }.count, 1)
        XCTAssertTrue(trace.steps.contains("combinationOffer"))
        let retry = SettingsEraseAllFlow.afterAppPasswordEntry("combo-pass-word", trace: &trace)
        guard case .erase(let password) = retry else {
            return XCTFail("combination offer must retry the same erase")
        }
        XCTAssertEqual(password, "combo-pass-word")

        let fake = FakeRevealGate()
        let harness = try await makeEraseHarness(
            policy: .biometryOrAppPassword,
            gate: fake,
            useRealGate: false
        )
        let accountId = try await harness.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Keep")
        )
        _ = try await harness.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "keep"),
            secret: "sk-erase-combo-111"
        )
        try await harness.lifecycle.eraseAllUserData(appPassword: "combo-pass-word")
        let remainingAccounts = try await harness.vault.accounts()
        XCTAssertTrue(remainingAccounts.isEmpty)
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 1)
        XCTAssertEqual(journal.callCount("confirm"), 0)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
    }

    func testEraseMasterPasswordWrongEmptyAndRateLimitLeaveData() async throws {
        let harness = try await makeEraseHarness(policy: .masterPassword, useRealGate: true)
        try await harness.master.setPassword("abcd")
        let accountId = try await harness.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Keep")
        )
        _ = try await harness.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "keep"),
            secret: "sk-erase-master-111"
        )

        do {
            try await harness.lifecycle.eraseAllUserData(appPassword: nil)
            XCTFail("expected prompt")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "master_password_prompt_required")
        }
        do {
            try await harness.lifecycle.eraseAllUserData(appPassword: "")
            XCTFail("expected prompt")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "master_password_prompt_required")
        }
        do {
            try await harness.lifecycle.eraseAllUserData(appPassword: "nope")
            XCTFail("expected auth failure")
        } catch ApiRelayError.authenticationFailed {
        }
        do {
            try await harness.lifecycle.eraseAllUserData(appPassword: "nope")
            XCTFail("expected auth failure")
        } catch ApiRelayError.authenticationFailed {
        }
        do {
            try await harness.lifecycle.eraseAllUserData(appPassword: "nope")
            XCTFail("expected delay or failure")
        } catch let error as ApiRelayError {
            switch error {
            case .authenticationFailed, .masterPasswordRetryDelayed:
                break
            default:
                XCTFail("unexpected \(error)")
            }
        }
        do {
            try await harness.lifecycle.eraseAllUserData(appPassword: "nope")
            XCTFail("expected delay")
        } catch let error as ApiRelayError {
            switch error {
            case .masterPasswordRetryDelayed(let secondsRemaining):
                XCTAssertGreaterThan(secondsRemaining, 0)
            case .authenticationFailed:
                break
            default:
                XCTFail("unexpected \(error)")
            }
        }
        let remaining = try await harness.vault.accounts().count
        XCTAssertEqual(remaining, 1)
    }

    func testEraseMasterPasswordSuccessClearsData() async throws {
        let harness = try await makeEraseHarness(policy: .masterPassword, useRealGate: true)
        try await harness.master.setPassword("abcd")
        let accountId = try await harness.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Gone")
        )
        _ = try await harness.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "gone"),
            secret: "sk-erase-master-ok-1"
        )
        try await harness.lifecycle.eraseAllUserData(appPassword: "abcd")
        let after = try await harness.vault.accounts()
        XCTAssertTrue(after.isEmpty)
    }

    func testEraseCombinationUsesConfirmNotAppPasswordPrompt() async throws {
        let fake = FakeRevealGate()
        let harness = try await makeEraseHarness(
            policy: .biometryOrAppPassword,
            gate: fake,
            useRealGate: false
        )
        let accountId = try await harness.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Combo")
        )
        _ = try await harness.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-erase-combo-1111"
        )
        try await harness.lifecycle.eraseAllUserData()
        let remaining = try await harness.vault.accounts()
        XCTAssertTrue(remaining.isEmpty)
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirm"), 1)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 0)
    }

    func testDurableEraseJournalPersistsStageAcrossInstancesAndClears() throws {
        let fixture = try makeDurableJournalFixture()
        defer { fixture.cleanup() }
        let first = DurableDataEraseJournal(
            defaults: fixture.defaults,
            fileURL: fixture.fileURL
        )

        try first.mark(.vault)

        let reopened = DurableDataEraseJournal(
            defaults: fixture.defaults,
            fileURL: fixture.fileURL
        )
        XCTAssertTrue(reopened.hasPendingErase())
        XCTAssertEqual(reopened.currentStage(), .vault)

        try reopened.clear()
        XCTAssertFalse(reopened.hasPendingErase())
        XCTAssertNil(reopened.currentStage())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testDurableEraseJournalCorruptionStillFailsClosedAsPending() throws {
        let fixture = try makeDurableJournalFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fixture.fileURL)
        let sut = DurableDataEraseJournal(
            defaults: fixture.defaults,
            fileURL: fixture.fileURL
        )

        XCTAssertTrue(sut.hasPendingErase())
        XCTAssertNil(sut.currentStage())

        try sut.clear()
        XCTAssertFalse(sut.hasPendingErase())
    }

    func testDurableEraseJournalReadsAndClearsLegacyMarker() throws {
        let fixture = try makeDurableJournalFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set(
            DataEraseStage.consumerTools.rawValue,
            forKey: "com.apirelay.dataErase.stage.v1"
        )
        fixture.defaults.set(
            Date().timeIntervalSince1970,
            forKey: "com.apirelay.dataErase.startedAt.v1"
        )
        let sut = DurableDataEraseJournal(
            defaults: fixture.defaults,
            fileURL: fixture.fileURL
        )

        XCTAssertTrue(sut.hasPendingErase())
        XCTAssertEqual(sut.currentStage(), .consumerTools)

        try sut.clear()
        XCTAssertFalse(sut.hasPendingErase())
    }

    func testSharedEraseGateWaitsForEarlierMutationAndRejectsLaterServiceWrites() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let authGate = FakeRevealGate()
        let mutationGate = StorageMutationGate()
        let suiteName = "ApiRelay.EraseFenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let quarantine = VaultIntegrityQuarantineStore(defaults: defaults)
        let preferences = PreferencesService(
            modelContainer: container,
            mutationGate: mutationGate
        )
        try await preferences.update(PreferencesPatch(revealPolicy: .noVerification))
        let vault = KeyVaultService(
            keychain: keychain,
            gate: authGate,
            clipboard: FakeClipboard(),
            modelContainer: container,
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            integrityQuarantine: quarantine,
            mutationGate: mutationGate
        )
        let tools = ConsumerToolService(
            modelContainer: container,
            gate: authGate,
            integrityQuarantine: quarantine,
            mutationGate: mutationGate
        )
        // Represent a real storage transaction that won the shared fence before
        // erase sealing. Do not suspend an actor on a blocking semaphore here:
        // that can starve Swift's cooperative executor and turn the test itself
        // into a deadlock while trying to exercise an unrelated service actor.
        let earlierMutation = try mutationGate.beginNormal(
            operation: "test_earlier_mutation"
        )
        defer { earlierMutation.finish() }

        let eraseJournal = InMemoryDataEraseJournal()
        let clipboard = FakeClipboard()
        let lifecycle = DataLifecycleService(
            gate: authGate,
            keychain: keychain,
            modelContainer: container,
            vault: vault,
            consumerTools: tools,
            backups: FakeSecureBackup(),
            preferences: preferences,
            entitlements: FakeEntitlements(),
            clipboard: clipboard,
            eraseJournal: eraseJournal,
            mutationGate: mutationGate
        )
        let erasing = Task { try await lifecycle.eraseAllUserData() }
        try await waitUntilEraseSealed(mutationGate)
        for _ in 0..<500 where !eraseJournal.hasPendingErase() {
            await Task.yield()
        }

        XCTAssertTrue(eraseJournal.hasPendingErase())
        XCTAssertEqual(eraseJournal.currentStage(), .authorized)
        let keychainJournal = await keychain.journal
        XCTAssertEqual(keychainJournal.callCount("delete"), 0)
        do {
            _ = try await tools.createTool(ConsumerToolDraft(name: "must-not-write"))
            XCTFail("a write that starts after erase sealing must be rejected")
        } catch ApiRelayError.storageRecoveryFailed {
            // expected
        }
        do {
            _ = try await vault.createAccount(
                UpstreamAccountDraft(platform: "openai", displayName: "must-not-write")
            )
            XCTFail("vault writes that start after erase sealing must be rejected")
        } catch ApiRelayError.storageRecoveryFailed {
            // expected
        }
        let toolsWhileSealed = try await tools.tools(includeHidden: true)
        XCTAssertTrue(toolsWhileSealed.isEmpty)

        earlierMutation.finish()
        try await erasing.value

        XCTAssertFalse(mutationGate.isEraseSealed())
        XCTAssertFalse(eraseJournal.hasPendingErase())
        let remainingAccounts = try await vault.accounts()
        let remainingKeys = try await vault.keys(in: nil)
        let clipboardJournal = await clipboard.journal
        XCTAssertTrue(remainingAccounts.isEmpty)
        XCTAssertTrue(remainingKeys.isEmpty)
        XCTAssertEqual(clipboardJournal.callCount("clearIfStillOurs"), 1)
    }

    func testFailedEraseKeepsGateSealedUntilAuthenticatedRecoveryCompletes() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let secretID = UUID()
        try await keychain.save("erase-me", service: .keys, account: secretID)
        keychain.failNextCall("delete", with: .keychainFailure(errSecAuthFailed))
        let mutationGate = StorageMutationGate()
        let eraseJournal = InMemoryDataEraseJournal()
        let authGate = FakeRevealGate()
        let suiteName = "ApiRelay.EraseFailureQuarantineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let quarantine = VaultIntegrityQuarantineStore(defaults: defaults)
        quarantine.quarantine(operation: "preexisting_incident", detail: "must_survive_partial_erase")
        let lifecycle = DataLifecycleService(
            gate: authGate,
            keychain: keychain,
            modelContainer: container,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            clipboard: FakeClipboard(),
            eraseJournal: eraseJournal,
            mutationGate: mutationGate,
            integrityQuarantine: quarantine
        )

        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("forced storage failure must keep recovery armed")
        } catch ApiRelayError.storageRecoveryFailed {
            // expected
        }
        XCTAssertTrue(eraseJournal.hasPendingErase())
        XCTAssertTrue(mutationGate.isEraseSealed())
        XCTAssertNotNil(quarantine.currentIncident())
        do {
            _ = try mutationGate.beginNormal(operation: "must-remain-blocked")
            XCTFail("normal writes must remain blocked after partial erase")
        } catch ApiRelayError.storageRecoveryFailed {
            // expected
        }

        try await lifecycle.eraseAllUserData()

        XCTAssertFalse(eraseJournal.hasPendingErase())
        XCTAssertFalse(mutationGate.isEraseSealed())
        XCTAssertNil(quarantine.currentIncident())
        let resumedWrite = try mutationGate.beginNormal(operation: "after_recovery")
        resumedWrite.finish()
        let authJournal = await authGate.journal
        XCTAssertEqual(authJournal.callCount("confirmMandatory"), 1)
    }

    func testCommittedFullEraseRecoversFromIntegrityQuarantineAndClearsItLast() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let authGate = FakeRevealGate()
        let mutationGate = StorageMutationGate()
        let suiteName = "ApiRelay.EraseQuarantineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let quarantine = VaultIntegrityQuarantineStore(defaults: defaults)
        let preferences = PreferencesService(
            modelContainer: container,
            mutationGate: mutationGate
        )
        try await preferences.update(PreferencesPatch(revealPolicy: .noVerification))
        let vault = KeyVaultService(
            keychain: keychain,
            gate: authGate,
            clipboard: FakeClipboard(),
            modelContainer: container,
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            integrityQuarantine: quarantine,
            mutationGate: mutationGate
        )
        let tools = ConsumerToolService(
            modelContainer: container,
            gate: authGate,
            integrityQuarantine: quarantine,
            mutationGate: mutationGate
        )
        let accountID = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "quarantined")
        )
        _ = try await vault.createKey(
            KeyDraft(accountId: accountID, displayName: "erase-me"),
            secret: "sk-quarantined-erase"
        )
        _ = try await tools.createTool(ConsumerToolDraft(name: "erase-me"))
        quarantine.quarantine(operation: "forced_test_incident", detail: "compensation_failed")

        do {
            _ = try await vault.accounts()
            XCTFail("ordinary vault access must remain quarantined before reset")
        } catch ApiRelayError.storageIntegrityQuarantined {
            // expected
        }

        let lifecycle = DataLifecycleService(
            gate: authGate,
            keychain: keychain,
            modelContainer: container,
            vault: vault,
            consumerTools: tools,
            backups: FakeSecureBackup(),
            preferences: preferences,
            entitlements: FakeEntitlements(),
            clipboard: FakeClipboard(),
            eraseJournal: InMemoryDataEraseJournal(),
            mutationGate: mutationGate,
            integrityQuarantine: quarantine
        )
        try await lifecycle.eraseAllUserData()

        XCTAssertNil(quarantine.currentIncident())
        let remainingAccounts = try await vault.accounts()
        let remainingKeys = try await vault.keys(in: nil)
        let remainingTools = try await tools.tools(includeHidden: true)
        XCTAssertTrue(remainingAccounts.isEmpty)
        XCTAssertTrue(remainingKeys.isEmpty)
        XCTAssertTrue(remainingTools.isEmpty)
    }

    func testLockedColdLaunchCanAuthenticateAndResumePendingErase() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sessionLock = SessionLockBox()
        sessionLock.setLocked(true)
        sessionLock.setAuthorizationSuspended(false)
        let journal = InMemoryDataEraseJournal()
        journal.seedPending(.vault)
        let mutationGate = StorageMutationGate(erasePending: true)
        let gate = FakeRevealGate()
        let keychain = FakeKeychain()
        let secretID = UUID()
        try await keychain.save("erase-after-relaunch", service: .keys, account: secretID)
        let lifecycle = DataLifecycleService(
            gate: gate,
            keychain: keychain,
            modelContainer: container,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            sessionLock: sessionLock,
            eraseJournal: journal,
            mutationGate: mutationGate
        )

        try await lifecycle.eraseAllUserData()

        XCTAssertFalse(lifecycle.hasPendingErase())
        let remainingAccounts = try await keychain.listAccounts(service: .keys)
        XCTAssertTrue(remainingAccounts.isEmpty)
        let authCalls = await gate.journal
        XCTAssertEqual(authCalls.callCount("confirmMandatory"), 1)
        XCTAssertEqual(authCalls.callCount("confirm"), 0)
    }

    func testDeviceOwnerCanEraseAllDataWhenCrossStoreRecoveryCannotComplete() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sessionLock = SessionLockBox()
        sessionLock.setLocked(true)
        sessionLock.setAuthorizationSuspended(false)
        let eraseJournal = InMemoryDataEraseJournal()
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataLifecycleCrossStoreTests-\(UUID().uuidString)", isDirectory: true)
        let crossStoreJournal = DurableCrossStoreTransactionJournal(
            fileURL: journalDirectory.appendingPathComponent("journal.json")
        )
        defer { try? FileManager.default.removeItem(at: journalDirectory) }
        _ = try crossStoreJournal.begin(.backupImport)

        let mutationGate = StorageMutationGate(crossStoreRecoveryPending: true)
        let gate = FakeRevealGate()
        let keychain = FakeKeychain()
        let secretID = UUID()
        try await keychain.save("must-be-erased", service: .keys, account: secretID)
        let lifecycle = DataLifecycleService(
            gate: gate,
            keychain: keychain,
            modelContainer: container,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            sessionLock: sessionLock,
            eraseJournal: eraseJournal,
            crossStoreJournal: crossStoreJournal,
            mutationGate: mutationGate
        )

        try await lifecycle.eraseAllUserDataForStorageRecovery()

        XCTAssertFalse(eraseJournal.hasPendingErase())
        XCTAssertNil(try crossStoreJournal.load())
        XCTAssertFalse(mutationGate.isEraseSealed())
        XCTAssertFalse(mutationGate.isCrossStoreRecoverySealed())
        let remainingSecrets = try await keychain.listAccounts(service: .keys)
        XCTAssertTrue(remainingSecrets.isEmpty)
        let authCalls = await gate.journal
        XCTAssertEqual(authCalls.callCount("confirmMandatory"), 1)
        XCTAssertEqual(authCalls.callCount("confirm"), 0)
    }

    func testPendingEraseCannotResumeWhileAppIsNotUserFacing() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let sessionLock = SessionLockBox()
        sessionLock.setLocked(true)
        sessionLock.setAuthorizationSuspended(true)
        let journal = InMemoryDataEraseJournal()
        journal.seedPending(.keychain)
        let mutationGate = StorageMutationGate(erasePending: true)
        let gate = FakeRevealGate()
        let keychain = FakeKeychain()
        let secretID = UUID()
        try await keychain.save("must-remain", service: .keys, account: secretID)
        let lifecycle = DataLifecycleService(
            gate: gate,
            keychain: keychain,
            modelContainer: container,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            sessionLock: sessionLock,
            eraseJournal: journal,
            mutationGate: mutationGate
        )

        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("background recovery must not mint device-owner authority")
        } catch ApiRelayError.sessionLocked {
            // expected
        }

        XCTAssertTrue(lifecycle.hasPendingErase())
        let remainingAccounts = try await keychain.listAccounts(service: .keys)
        XCTAssertEqual(remainingAccounts, [secretID])
        let authCalls = await gate.journal
        XCTAssertEqual(authCalls.callCount("confirmMandatory"), 0)
    }

    func testConcurrentEraseRequestIsRejectedWhileFirstTransactionIsInFlight() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let secretID = UUID()
        try await keychain.save("single-flight", service: .keys, account: secretID)
        keychain.blockNextCall("delete")
        let lifecycle = DataLifecycleService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            eraseJournal: InMemoryDataEraseJournal(),
            mutationGate: StorageMutationGate()
        )

        let first = Task { try await lifecycle.eraseAllUserData() }
        await keychain.waitUntilCallIsBlocked("delete")
        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("a second erase must not interleave with the first")
        } catch let ApiRelayError.storageRecoveryFailed(operation, detail) {
            XCTAssertEqual(operation, "erase_all_user_data")
            XCTAssertEqual(detail, "erase_already_running")
        }
        keychain.releaseBlockedCall("delete")
        try await first.value

        let deletes = await keychain.journal.callCount("delete")
        XCTAssertEqual(deletes, 1)
        XCTAssertFalse(lifecycle.hasPendingErase())
    }

    func testJournalMarkThatPersistsThenThrowsKeepsGateSealedForRecovery() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let secretID = UUID()
        try await keychain.save("do-not-delete-yet", service: .keys, account: secretID)
        let journal = InMemoryDataEraseJournal()
        journal.failMarks(
            with: .storageRecoveryFailed(operation: "test_mark", detail: "uncertain_fsync"),
            afterPersisting: true
        )
        let mutationGate = StorageMutationGate()
        let gate = FakeRevealGate()
        let lifecycle = DataLifecycleService(
            gate: gate,
            keychain: keychain,
            modelContainer: container,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            eraseJournal: journal,
            mutationGate: mutationGate
        )

        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("uncertain durable mark must stop before deletion")
        } catch ApiRelayError.storageRecoveryFailed {
            // expected
        }
        XCTAssertTrue(journal.hasPendingErase())
        XCTAssertTrue(mutationGate.isEraseSealed())
        let deletesBeforeRecovery = await keychain.journal.callCount("delete")
        XCTAssertEqual(deletesBeforeRecovery, 0)

        journal.allowMarks()
        try await lifecycle.eraseAllUserData()

        XCTAssertFalse(journal.hasPendingErase())
        XCTAssertFalse(mutationGate.isEraseSealed())
        let deletesAfterRecovery = await keychain.journal.callCount("delete")
        XCTAssertEqual(deletesAfterRecovery, 1)
        let authCalls = await gate.journal
        XCTAssertEqual(authCalls.callCount("confirmMandatory"), 1)
    }

    func testPendingEraseAtLaunchStartsWithNormalWritesSealed() throws {
        let mutationGate = StorageMutationGate(erasePending: true)
        XCTAssertTrue(mutationGate.isEraseSealed())
        XCTAssertThrowsError(try mutationGate.beginNormal(operation: "cold_launch_write")) {
            guard case ApiRelayError.storageRecoveryFailed = $0 else {
                return XCTFail("unexpected error: \($0)")
            }
        }
    }

    func testProductionCloudConvergenceHookRepurgesEverySyncedLongLivedContext() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let mutationGate = StorageMutationGate()
        let vault = FakeKeyVault()
        let tools = FakeConsumerTools()
        let backups = FakeSecureBackup()
        let preferences = FakePreferences()
        let entitlements = FakeEntitlements()
        let convergence = DataLifecycleCloudConvergenceProbe()
        let suite = "ApiRelay.DataLifecycleCloudConvergence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let quarantine = VaultIntegrityQuarantineStore(
            defaults: defaults,
            committedEraseGate: mutationGate
        )
        let lifecycle = DataLifecycleService(
            gate: FakeRevealGate(),
            keychain: FakeKeychain(),
            modelContainer: container,
            vault: vault,
            consumerTools: tools,
            backups: backups,
            preferences: preferences,
            entitlements: entitlements,
            eraseJournal: InMemoryDataEraseJournal(),
            mutationGate: mutationGate,
            integrityQuarantine: quarantine,
            cloudEraseConvergence: convergence
        )

        try await lifecycle.eraseAllUserData()

        let convergenceCalls = await convergence.calls()
        let vaultJournal = await vault.journal
        let toolsJournal = await tools.journal
        let backupJournal = await backups.journal
        let preferencesJournal = await preferences.journal
        let entitlementJournal = await entitlements.journal
        XCTAssertEqual(convergenceCalls, 1)
        XCTAssertEqual(vaultJournal.callCount("purgeAllRecordsForCommittedErase"), 2)
        XCTAssertEqual(toolsJournal.callCount("purgeAllRecordsForCommittedErase"), 2)
        XCTAssertEqual(backupJournal.callCount("purgeAllRecordsForCommittedErase"), 2)
        XCTAssertEqual(preferencesJournal.callCount("purgeAllRecordsForErase"), 2)
        XCTAssertEqual(entitlementJournal.callCount("purgeLocalSnapshotForErase"), 1)
        XCTAssertFalse(lifecycle.hasPendingErase())
        XCTAssertFalse(mutationGate.isEraseSealed())
    }

    func testCloudConvergenceFailureKeepsJournalSealedAndPublishesOpaqueRecoveryState() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let mutationGate = StorageMutationGate()
        let journal = InMemoryDataEraseJournal()
        let convergence = DataLifecycleCloudConvergenceProbe(
            terminalError: .storageRecoveryFailed(
                operation: "erase_cloud_convergence",
                detail: "cloud_pipeline_failed"
            )
        )
        let suite = "ApiRelay.DataLifecycleCloudFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let quarantine = VaultIntegrityQuarantineStore(
            defaults: defaults,
            committedEraseGate: mutationGate
        )
        let stateChanged = expectation(
            forNotification: .userDataEraseRecoveryStateDidChange,
            object: nil
        )
        let lifecycle = DataLifecycleService(
            gate: FakeRevealGate(),
            keychain: FakeKeychain(),
            modelContainer: container,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            eraseJournal: journal,
            mutationGate: mutationGate,
            integrityQuarantine: quarantine,
            cloudEraseConvergence: convergence
        )

        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("Cloud convergence failure must keep erase recovery armed")
        } catch let ApiRelayError.storageRecoveryFailed(operation, detail) {
            XCTAssertEqual(operation, "erase_all_user_data")
            XCTAssertTrue(detail.contains("stage=cloudConvergence"))
        }

        await fulfillment(of: [stateChanged], timeout: 1)
        XCTAssertTrue(lifecycle.hasPendingErase())
        XCTAssertTrue(journal.hasPendingErase())
        XCTAssertEqual(journal.currentStage(), .cloudConvergence)
        XCTAssertTrue(mutationGate.isEraseSealed())
        XCTAssertThrowsError(try mutationGate.beginNormal(operation: "must_stay_opaque"))
    }

    func testFinalKeychainConvergenceDeletesEntryArrivingAfterInitialSweep() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = DataLifecycleReappearingKeychain(arrivalMode: .once)
        let mutationGate = StorageMutationGate()
        let journal = InMemoryDataEraseJournal()
        let lifecycle = DataLifecycleService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            eraseJournal: journal,
            mutationGate: mutationGate,
            keychainConvergenceGrace: .zero,
            maxKeychainConvergencePasses: 6
        )

        try await lifecycle.eraseAllUserData()

        let state = await keychain.snapshot()
        let arrival = await keychain.expectedArrivalAccount()
        XCTAssertEqual(state.remaining, 0)
        XCTAssertTrue(state.deleted.contains(arrival))
        XCTAssertGreaterThanOrEqual(state.listCalls, 4)
        XCTAssertFalse(journal.hasPendingErase())
        XCTAssertFalse(mutationGate.isEraseSealed())
    }

    func testSustainedKeychainArrivalsKeepEraseJournalAndGateSealed() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = DataLifecycleReappearingKeychain(arrivalMode: .everyConvergencePass)
        let mutationGate = StorageMutationGate()
        let journal = InMemoryDataEraseJournal()
        let lifecycle = DataLifecycleService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            backups: FakeSecureBackup(),
            preferences: FakePreferences(),
            entitlements: FakeEntitlements(),
            eraseJournal: journal,
            mutationGate: mutationGate,
            keychainConvergenceGrace: .zero,
            maxKeychainConvergencePasses: 3
        )

        do {
            try await lifecycle.eraseAllUserData()
            XCTFail("sustained Keychain arrivals must not reopen normal access")
        } catch let ApiRelayError.storageRecoveryFailed(operation, detail) {
            XCTAssertEqual(operation, "erase_all_user_data")
            XCTAssertTrue(detail.contains("stage=keychainConvergence"))
        }

        XCTAssertTrue(journal.hasPendingErase())
        XCTAssertEqual(journal.currentStage(), .keychainConvergence)
        XCTAssertTrue(mutationGate.isEraseSealed())
        XCTAssertThrowsError(try mutationGate.beginNormal(operation: "must_stay_opaque"))
    }

    private struct DurableJournalFixture {
        let suiteName: String
        let defaults: UserDefaults
        let root: URL
        let fileURL: URL

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeDurableJournalFixture() throws -> DurableJournalFixture {
        let id = UUID().uuidString
        let suiteName = "ApiRelay.DataEraseJournalTests.\(id)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApiRelay-DataEraseJournalFixture-\(id)", isDirectory: true)
        return DurableJournalFixture(
            suiteName: suiteName,
            defaults: defaults,
            root: root,
            fileURL: root.appendingPathComponent("journal.json", isDirectory: false)
        )
    }

    private func waitUntilEraseSealed(_ gate: StorageMutationGate) async throws {
        for _ in 0..<1_000 {
            if gate.isEraseSealed() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("erase gate did not seal")
    }

    private struct EraseHarness {
        let vault: KeyVaultService
        let lifecycle: DataLifecycleService
        let master: MasterPasswordService
    }

    private func makeEraseHarness(
        policy: RevealPolicy,
        gate: RevealGateServing? = nil,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock(),
        useRealGate: Bool
    ) async throws -> EraseHarness {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let mutationGate = StorageMutationGate()
        let master = MasterPasswordService(
            keychain: keychain,
            calibratedIterations: 10_000,
            mutationGate: mutationGate
        )
        try? await master.reset()
        let resolvedGate: RevealGateServing
        if let gate {
            resolvedGate = gate
        } else if useRealGate {
            resolvedGate = RevealGate(masterPassword: master) { _, _ in }
        } else {
            resolvedGate = FakeRevealGate()
        }
        let vault = KeyVaultService(
            keychain: keychain,
            gate: resolvedGate,
            clipboard: SecureClipboard(mutationGate: mutationGate),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .free),
            sessionLock: sessionLock,
            mutationGate: mutationGate
        )
        var patch = PreferencesPatch()
        patch.revealPolicy = policy
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let lifecycle = DataLifecycleService(
            gate: resolvedGate,
            keychain: keychain,
            modelContainer: container,
            vault: vault,
            consumerTools: ConsumerToolService(
                modelContainer: container,
                gate: resolvedGate,
                sessionLock: sessionLock,
                mutationGate: mutationGate
            ),
            backups: FakeSecureBackup(),
            preferences: PreferencesService(
                modelContainer: container,
                mutationGate: mutationGate
            ),
            entitlements: EntitlementService(
                modelContainer: container,
                mutationGate: mutationGate
            ),
            sessionLock: sessionLock,
            eraseJournal: InMemoryDataEraseJournal(),
            mutationGate: mutationGate
        )
        return EraseHarness(vault: vault, lifecycle: lifecycle, master: master)
    }
}
