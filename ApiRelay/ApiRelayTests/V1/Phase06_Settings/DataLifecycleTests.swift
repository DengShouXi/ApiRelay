@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class DataLifecycleTests: XCTestCase {
    func testEraseClearsActiveKeysTrashAndConsumerTools() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        // 清除流程要真服务（`purgeLocalSnapshotForErase` 不在协议上，且不碰 StoreKit）；
        // 建密钥时的配额检查走桩，免去每次 60 秒的商店超时。
        let entitlements = EntitlementService(modelContainer: container)
        let vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .free)
        )
        let consumerTools = ConsumerToolService(modelContainer: container, gate: gate)
        let preferences = PreferencesService(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .none
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
            preferences: preferences,
            entitlements: entitlements
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
}
