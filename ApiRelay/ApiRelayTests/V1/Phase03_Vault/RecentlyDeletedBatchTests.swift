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
    private var gateCounter: GateCallCounter!

    override func setUp() async throws {
        container = try AppSchema.makeInMemoryContainer()
        keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let counter = GateCallCounter()
        gateCounter = counter
        let gate = RevealGate(masterPassword: master) { _, _ in
            counter.increment()
        }
        let clipboard = SecureClipboard()
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
        patch.revealPolicy = RevealPolicy.noVerification
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
