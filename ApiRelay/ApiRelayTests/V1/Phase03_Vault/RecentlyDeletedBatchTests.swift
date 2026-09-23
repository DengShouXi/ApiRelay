@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

private final class GateCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

@MainActor
final class RecentlyDeletedBatchTests: XCTestCase {
    private var container: ModelContainer!
    private var keychain: KeychainStore!
    private var vault: KeyVaultService!
    private var tools: ConsumerToolService!
    private var batch: RecentlyDeletedBatchService!
    private var gate: RevealGate!
    private var clipboard: SecureClipboard!
    private var gateCounter: GateCallCounter!

    override func setUp() async throws {
        container = try AppSchema.makeInMemoryContainer()
        keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let counter = GateCallCounter()
        gateCounter = counter
        gate = RevealGate(masterPassword: master) { _, _ in
            counter.increment()
        }
        clipboard = SecureClipboard()
        // 本套件考的是回收站批量操作与门闩次数，不是 StoreKit：配额走桩，免去商店超时。
        vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .free)
        )
        tools = ConsumerToolService(modelContainer: container, gate: gate)
        batch = RecentlyDeletedBatchService(vault: vault, consumerTools: tools, gate: gate)
        let entitlement = EntitlementSnapshotRepository(modelContainer: container)
        try await entitlement.update(tier: .free, source: "test")
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = RevealPolicy.biometricOrPasscode
        try await prefs.update(patch)
    }

    func testBatchRestoreKeysUsesOneGate() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "A")
        )
        let first = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-batch-one-aaaaaa"
        )
        let second = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k2"),
            secret: "sk-batch-two-bbbbbb"
        )
        try await vault.deleteKey(first)
        try await vault.deleteKey(second)
        let deleteGates = gateCounter.count

        let outcome = try await batch.restore(
            TrashBatchSelection(keyIds: [first, second], accountIds: [], toolIds: [])
        )
        XCTAssertEqual(outcome.successCount, 2)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(gateCounter.count, deleteGates + 1)

        let trash = try await vault.recentlyDeletedKeys()
        XCTAssertTrue(trash.isEmpty)
        let revealed = try await vault.revealSecret(keyId: first, purpose: .display, masterPassword: nil)
        XCTAssertEqual(revealed, "sk-batch-one-aaaaaa")
    }

    func testBatchRestoreRefusesWhenQuotaWouldExceed() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Cap")
        )
        let trashed1 = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "t1"),
            secret: "sk-trash-one-aaaa"
        )
        let trashed2 = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "t2"),
            secret: "sk-trash-two-bbbb"
        )
        try await vault.deleteKey(trashed1)
        try await vault.deleteKey(trashed2)
        _ = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "a1"),
            secret: "sk-active-one-cccc"
        )
        _ = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "a2"),
            secret: "sk-active-two-dddd"
        )
        let gatesBefore = gateCounter.count

        do {
            _ = try await batch.restore(
                TrashBatchSelection(keyIds: [trashed1, trashed2], accountIds: [], toolIds: [])
            )
            XCTFail("expected quotaExceeded")
        } catch let ApiRelayError.quotaExceededFreeTier(limit) {
            XCTAssertEqual(limit, 3)
        }
        XCTAssertEqual(gateCounter.count, gatesBefore)

        let trash = try await vault.recentlyDeletedKeys()
        XCTAssertEqual(Set(trash.map(\.id)), [trashed1, trashed2])
    }

    func testBatchRestoreAccountCoversSelectedKeys() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Cascade")
        )
        let first = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "c1"),
            secret: "sk-cascade-one-aa"
        )
        let second = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "c2"),
            secret: "sk-cascade-two-bb"
        )
        try await vault.deleteAccount(accountId)
        let gatesBefore = gateCounter.count

        let outcome = try await batch.restore(
            TrashBatchSelection(keyIds: [first], accountIds: [accountId], toolIds: [])
        )
        XCTAssertEqual(outcome.successCount, 2)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(gateCounter.count, gatesBefore + 1)

        let remainingKeys = try await vault.recentlyDeletedKeys()
        let remainingAccounts = try await vault.recentlyDeletedAccounts()
        XCTAssertTrue(remainingKeys.isEmpty)
        XCTAssertTrue(remainingAccounts.isEmpty)
        let keys = try await vault.keys(in: accountId)
        XCTAssertEqual(Set(keys.map(\.id)), [first, second])
    }

    func testBatchPermanentDeleteAccountCoversKeys() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Gone")
        )
        let first = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "g1"),
            secret: "sk-gone-one-aaaaaa"
        )
        let second = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "g2"),
            secret: "sk-gone-two-bbbbbb"
        )
        try await vault.deleteAccount(accountId)
        let gatesBefore = gateCounter.count

        let outcome = try await batch.permanentlyDelete(
            TrashBatchSelection(keyIds: [first], accountIds: [accountId], toolIds: [])
        )
        XCTAssertEqual(outcome.successCount, 2)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(gateCounter.count, gatesBefore + 1)

        let remainingKeys = try await vault.recentlyDeletedKeys()
        let remainingAccounts = try await vault.recentlyDeletedAccounts()
        XCTAssertTrue(remainingKeys.isEmpty)
        XCTAssertTrue(remainingAccounts.isEmpty)
        await assertKeychainMissing(first)
        await assertKeychainMissing(second)
    }

    func testBatchPermanentDeleteKeysUsesOneGate() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Drop")
        )
        let first = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "d1"),
            secret: "sk-drop-one-aaaaaaa"
        )
        let second = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "d2"),
            secret: "sk-drop-two-bbbbbbb"
        )
        try await vault.deleteKey(first)
        try await vault.deleteKey(second)
        let gatesBefore = gateCounter.count

        let outcome = try await batch.permanentlyDelete(
            TrashBatchSelection(keyIds: [first, second], accountIds: [], toolIds: [])
        )
        XCTAssertEqual(outcome.successCount, 2)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(gateCounter.count, gatesBefore + 1)
        let remaining = try await vault.recentlyDeletedKeys()
        XCTAssertTrue(remaining.isEmpty)
        await assertKeychainMissing(first)
        await assertKeychainMissing(second)
    }

    func testBatchRestoreMixedKeysAndToolsUsesOneGate() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Mix")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "mix-key"),
            secret: "sk-mix-key-aaaaaaaa"
        )
        let toolId = try await tools.createTool(ConsumerToolDraft(name: "Mix Tool"))
        try await vault.deleteKey(keyId)
        try await tools.deleteTool(id: toolId)
        let gatesBefore = gateCounter.count

        let outcome = try await batch.restore(
            TrashBatchSelection(keyIds: [keyId], accountIds: [], toolIds: [toolId])
        )
        XCTAssertEqual(outcome.successCount, 2)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(gateCounter.count, gatesBefore + 1)
        let remainingKeys = try await vault.recentlyDeletedKeys()
        let remainingTools = try await tools.recentlyDeletedTools()
        XCTAssertTrue(remainingKeys.isEmpty)
        XCTAssertTrue(remainingTools.isEmpty)
    }

    func testQuotaFailureLeavesToolsInTrash() async throws {
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "CapTool")
        )
        let trashed = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "full"),
            secret: "sk-full-one-aaaaaaa"
        )
        try await vault.deleteKey(trashed)
        for i in 1...3 {
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "live\(i)"),
                secret: "sk-live-\(i)-bbbbbbbb"
            )
        }
        let toolId = try await tools.createTool(ConsumerToolDraft(name: "Stay Deleted"))
        try await tools.deleteTool(id: toolId)
        let gatesBefore = gateCounter.count

        do {
            _ = try await batch.restore(
                TrashBatchSelection(keyIds: [trashed], accountIds: [], toolIds: [toolId])
            )
            XCTFail("expected quotaExceeded")
        } catch let ApiRelayError.quotaExceededFreeTier(limit) {
            XCTAssertEqual(limit, 3)
        }
        XCTAssertEqual(gateCounter.count, gatesBefore)
        let remainingKeys = try await vault.recentlyDeletedKeys()
        let remainingTools = try await tools.recentlyDeletedTools()
        XCTAssertEqual(remainingKeys.map(\.id), [trashed])
        XCTAssertEqual(remainingTools.map(\.id), [toolId])
    }

    func testBatchRestoreToolsUsesSameGatePass() async throws {
        let toolId = try await tools.createTool(ConsumerToolDraft(name: "Batch Tool"))
        try await tools.deleteTool(id: toolId)
        let gatesBefore = gateCounter.count

        let outcome = try await batch.restore(
            TrashBatchSelection(keyIds: [], accountIds: [], toolIds: [toolId])
        )
        XCTAssertEqual(outcome.successCount, 1)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(gateCounter.count, gatesBefore + 1)
        let remaining = try await tools.recentlyDeletedTools()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSessionLockRejectsBatchBeforeGate() async throws {
        let box = SessionLockBox()
        vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )
        tools = ConsumerToolService(modelContainer: container, gate: gate, sessionLock: box)
        batch = RecentlyDeletedBatchService(
            vault: vault,
            consumerTools: tools,
            gate: gate,
            sessionLock: box
        )
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "BatchLock")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-batch-lock-aaaaaa"
        )
        try await vault.deleteKey(keyId)
        let gatesBefore = gateCounter.count
        box.setLocked(true)
        do {
            _ = try await batch.restore(
                TrashBatchSelection(keyIds: [keyId], accountIds: [], toolIds: [])
            )
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            _ = try await batch.permanentlyDelete(
                TrashBatchSelection(keyIds: [keyId], accountIds: [], toolIds: [])
            )
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        XCTAssertEqual(gateCounter.count, gatesBefore, "锁住时不得先弹身份框")
        let trash = try await vault.recentlyDeletedKeys()
        XCTAssertEqual(trash.map(\.id), [keyId])
    }

    func testAuthorizationLeaseRevokedDuringBatchGateLeavesKeysAndToolsUntouched() async throws {
        let fake = FakeRevealGate()
        let box = SessionLockBox()
        vault = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: box
        )
        tools = ConsumerToolService(modelContainer: container, gate: fake, sessionLock: box)
        batch = RecentlyDeletedBatchService(
            vault: vault,
            consumerTools: tools,
            gate: fake,
            sessionLock: box
        )
        var patch = PreferencesPatch()
        patch.revealPolicy = .noVerification
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Lease")
        )
        let keyId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "kept"),
            secret: "sk-batch-lease-kept"
        )
        let toolId = try await tools.createTool(ConsumerToolDraft(name: "Kept Tool"))
        try await vault.deleteKey(keyId)
        try await tools.deleteTool(id: toolId)
        patch.revealPolicy = .biometricOrPasscode
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        await fake.setAfterConfirmHook {
            box.invalidateAuthorizationLeases()
        }

        do {
            _ = try await batch.restore(
                TrashBatchSelection(keyIds: [keyId], accountIds: [], toolIds: [toolId])
            )
            XCTFail("revoked batch lease must fail")
        } catch ApiRelayError.sessionLocked {
        }

        let remainingKeys = try await vault.recentlyDeletedKeys().map(\.id)
        let remainingTools = try await tools.recentlyDeletedTools().map(\.id)
        XCTAssertEqual(remainingKeys, [keyId])
        XCTAssertEqual(remainingTools, [toolId])
    }

    func testBatchRestoreCancelLeavesAllItems() async throws {
        let fake = FakeRevealGate()
        vault = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: clipboard,
            modelContainer: container,
            entitlements: StubEntitlements(tier: .free)
        )
        tools = ConsumerToolService(modelContainer: container, gate: fake)
        batch = RecentlyDeletedBatchService(vault: vault, consumerTools: tools, gate: fake)
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        try await prefs.update(patch)

        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Cancel")
        )
        let first = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "c1"),
            secret: "sk-w4-batch-c1-aaaa"
        )
        let second = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "c2"),
            secret: "sk-w4-batch-c2-bbbb"
        )
        try await vault.deleteKey(first)
        try await vault.deleteKey(second)
        await fake.fail("confirm", with: .authenticationCancelled)
        do {
            _ = try await batch.restore(
                TrashBatchSelection(keyIds: [first, second], accountIds: [], toolIds: [])
            )
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        let trash = try await vault.recentlyDeletedKeys()
        XCTAssertEqual(Set(trash.map(\.id)), [first, second])
        let journal = await fake.journal
        XCTAssertTrue(journal.didCall("confirm"))
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }

    private func assertKeychainMissing(_ id: UUID) async {
        do {
            _ = try await keychain.read(service: .keys, account: id)
            XCTFail("expected missing keychain item")
        } catch let ApiRelayError.keychainFailure(status) {
            XCTAssertEqual(status, errSecItemNotFound)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

extension RecentlyDeletedBatchTests {
    func testBatchRestoreAndPermanentUseCurrentPolicyMatrix() async throws {
        struct Row {
            let name: String
            let policy: RevealPolicy
            let password: String?
            let failConfirm: Bool
            let expectSuccess: Bool
            let confirm: Int
            let master: Int
        }
        let rows: [Row] = [
            .init(name: "none", policy: .noVerification, password: nil, failConfirm: false, expectSuccess: true, confirm: 0, master: 0),
            .init(name: "device", policy: .biometricOrPasscode, password: nil, failConfirm: false, expectSuccess: true, confirm: 1, master: 0),
            .init(name: "device-cancel", policy: .biometricOrPasscode, password: nil, failConfirm: true, expectSuccess: false, confirm: 1, master: 0),
            .init(name: "combo", policy: .biometryOrAppPassword, password: nil, failConfirm: false, expectSuccess: true, confirm: 1, master: 0),
            .init(name: "master-missing", policy: .masterPassword, password: nil, failConfirm: false, expectSuccess: false, confirm: 0, master: 0),
            .init(name: "master-ok", policy: .masterPassword, password: "abcd", failConfirm: false, expectSuccess: true, confirm: 0, master: 1),
        ]
        for row in rows {
            for permanent in [false, true] {
                let local = try AppSchema.makeInMemoryContainer()
                let chain = KeychainStore.makeForTests()
                var setup = PreferencesPatch()
                setup.revealPolicy = .noVerification
                try await UserPreferencesRepository(modelContainer: local).update(setup)
                let setupVault = KeyVaultService(
                    keychain: chain,
                    gate: FakeRevealGate(),
                    clipboard: SecureClipboard(),
                    modelContainer: local,
                    entitlements: StubEntitlements(tier: .unlimitedKeys)
                )
                let accountId = try await setupVault.createAccount(
                    UpstreamAccountDraft(platform: "openai", displayName: row.name)
                )
                let keyId = try await setupVault.createKey(
                    KeyDraft(accountId: accountId, displayName: "k"),
                    secret: "sk-w4-batch-\(row.name)-\(permanent)-aa"
                )
                try await setupVault.deleteKey(keyId)
                var live = PreferencesPatch()
                live.revealPolicy = row.policy
                try await UserPreferencesRepository(modelContainer: local).update(live)
                let fake = FakeRevealGate()
                if row.failConfirm {
                    await fake.fail("confirm", with: .authenticationCancelled)
                }
                let service = KeyVaultService(
                    keychain: chain,
                    gate: fake,
                    clipboard: SecureClipboard(),
                    modelContainer: local,
                    entitlements: StubEntitlements(tier: .unlimitedKeys)
                )
                let toolService = ConsumerToolService(modelContainer: local, gate: fake)
                let batchService = RecentlyDeletedBatchService(
                    vault: service,
                    consumerTools: toolService,
                    gate: fake
                )
                let selection = TrashBatchSelection(keyIds: [keyId], accountIds: [], toolIds: [])
                do {
                    if permanent {
                        _ = try await batchService.permanentlyDelete(selection, appPassword: row.password)
                    } else {
                        _ = try await batchService.restore(selection, appPassword: row.password)
                    }
                    if !row.expectSuccess {
                        XCTFail("\(row.name) permanent=\(permanent) should fail")
                    }
                } catch {
                    if row.expectSuccess {
                        XCTFail("\(row.name) permanent=\(permanent) \(error)")
                    }
                }
                let trash = try await service.recentlyDeletedKeys()
                if row.expectSuccess {
                    XCTAssertTrue(trash.isEmpty, "\(row.name) \(permanent)")
                } else {
                    XCTAssertEqual(trash.map(\.id), [keyId], "\(row.name) \(permanent)")
                }
                let journal = await fake.journal
                XCTAssertEqual(journal.callCount("confirm"), row.confirm, "\(row.name) confirm")
                XCTAssertEqual(journal.callCount("confirmMandatory"), 0, row.name)
                XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), row.master, row.name)
                XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 0, row.name)
            }
        }
    }

    func testBatchCombinationPasswordUsesExplicitEntry() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let chain = KeychainStore.makeForTests()
        var setup = PreferencesPatch()
        setup.revealPolicy = .noVerification
        try await UserPreferencesRepository(modelContainer: local).update(setup)
        let setupVault = KeyVaultService(
            keychain: chain,
            gate: FakeRevealGate(),
            clipboard: SecureClipboard(),
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        let accountId = try await setupVault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "combo-pw")
        )
        let keyId = try await setupVault.createKey(
            KeyDraft(accountId: accountId, displayName: "k"),
            secret: "sk-w5-batch-combo-pw-aa"
        )
        try await setupVault.deleteKey(keyId)
        var live = PreferencesPatch()
        live.revealPolicy = .biometryOrAppPassword
        try await UserPreferencesRepository(modelContainer: local).update(live)
        let fake = FakeRevealGate()
        let service = KeyVaultService(
            keychain: chain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: local,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        let toolService = ConsumerToolService(modelContainer: local, gate: fake)
        let batchService = RecentlyDeletedBatchService(
            vault: service,
            consumerTools: toolService,
            gate: fake
        )
        let selection = TrashBatchSelection(keyIds: [keyId], accountIds: [], toolIds: [])
        _ = try await batchService.restore(selection, appPassword: "combo-pass-word")
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 1)
        XCTAssertEqual(journal.callCount("confirm"), 0)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
    }
}
