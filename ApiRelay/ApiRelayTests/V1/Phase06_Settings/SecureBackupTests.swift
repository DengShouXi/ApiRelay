@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class SecureBackupTests: XCTestCase {
    func testExportSucceedsWhenOptionalFieldsAreNil() async throws {
        let env = try makeEnvironment()
        let accountId = try await env.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Nil Fields")
        )
        _ = try await env.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-backup-export-1111"
        )

        let exported = try await env.backups.exportBackup(
            passphrase: "passphrase-1234",
            purpose: .fullBackup
        )
        XCTAssertTrue(exported.data.starts(with: SecureBackupFile.passphraseMagic))
        XCTAssertGreaterThan(exported.data.count, 64)
        XCTAssertEqual(exported.keysWithoutSecretCount, 0)
    }

    func testExportImportRoundTripRestoresSecret() async throws {
        let source = try makeEnvironment()
        let accountId = try await source.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "RoundTrip")
        )
        let keyId = try await source.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "prod"),
            secret: "sk-backup-roundtrip-9999"
        )
        let data = try await source.backups.exportBackup(
            passphrase: "passphrase-1234",
            purpose: .fullBackup
        ).data

        let destination = try makeEnvironment()
        let summary = try await destination.backups.importBackup(
            data: data,
            passphrase: "passphrase-1234"
        )
        XCTAssertEqual(summary.accountCount, 1)
        XCTAssertEqual(summary.keyCount, 1)
        XCTAssertEqual(summary.skippedKeyCount, 0)
        XCTAssertEqual(summary.keysWithoutSecretCount, 0)
        XCTAssertEqual(summary.purpose, .fullBackup)

        let restored = try await destination.keychain.read(service: .keys, account: keyId)
        XCTAssertEqual(restored, "sk-backup-roundtrip-9999")
        let accounts = try await destination.vault.accounts()
        XCTAssertEqual(accounts.first?.displayName, "RoundTrip")
        let keys = try await destination.vault.keys(in: accountId)
        XCTAssertEqual(keys.first?.displayName, "prod")
        XCTAssertNil(keys.first?.maskedHint)
    }

    func testExportImportRoundTripRestoresAvatars() async throws {
        let source = try makeEnvironment()
        let accountId = try await source.vault.createAccount(
            UpstreamAccountDraft(
                platform: "openai",
                displayName: "IconAcct",
                avatarSymbol: "globe",
                avatarColor: "teal"
            )
        )
        var keyDraft = KeyDraft(accountId: accountId, displayName: "prod")
        keyDraft.avatarSymbol = "bolt.fill"
        keyDraft.avatarColor = "orange"
        _ = try await source.vault.createKey(
            keyDraft,
            secret: "sk-backup-avatar-4444"
        )
        var toolDraft = ConsumerToolDraft(name: "自建 IDE")
        toolDraft.avatarSymbol = "hammer"
        toolDraft.avatarColor = "plum"
        _ = try await source.tools.createTool(toolDraft)
        let data = try await source.backups.exportBackup(
            passphrase: "passphrase-1234",
            purpose: .fullBackup
        ).data

        let destination = try makeEnvironment()
        let summary = try await destination.backups.importBackup(
            data: data,
            passphrase: "passphrase-1234"
        )
        XCTAssertEqual(summary.accountCount, 1)
        XCTAssertEqual(summary.keyCount, 1)
        XCTAssertEqual(summary.toolCount, 1)

        let accounts = try await destination.vault.accounts()
        XCTAssertEqual(accounts.first?.avatarSymbol, "globe")
        XCTAssertEqual(accounts.first?.avatarColor, "teal")
        let keys = try await destination.vault.keys(in: accountId)
        XCTAssertEqual(keys.first?.avatarSymbol, "bolt.fill")
        XCTAssertEqual(keys.first?.avatarColor, "orange")
        let tools = try await destination.tools.tools(includeHidden: true)
        XCTAssertEqual(tools.first?.avatarSymbol, "hammer")
        XCTAssertEqual(tools.first?.avatarColor, "plum")
    }

    func testWrongPassphraseIsRejected() async throws {
        let env = try makeEnvironment()
        let data = try await env.backups.exportBackup(
            passphrase: "passphrase-1234",
            purpose: .fullBackup
        ).data
        do {
            _ = try await env.backups.importBackup(data: data, passphrase: "wrong-passphrase")
            XCTFail("expected incorrect passphrase")
        } catch ApiRelayError.backupPassphraseIncorrect {
            // expected
        }
    }

    func testSecondImportSkipsExistingKeys() async throws {
        let env = try makeEnvironment()
        let accountId = try await env.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Skip")
        )
        _ = try await env.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-backup-skip-1111"
        )
        let data = try await env.backups.exportBackup(
            passphrase: "passphrase-1234",
            purpose: .fullBackup
        ).data
        let summary = try await env.backups.importBackup(
            data: data,
            passphrase: "passphrase-1234"
        )
        XCTAssertEqual(summary.accountCount, 0)
        XCTAssertEqual(summary.keyCount, 0)
        XCTAssertEqual(summary.skippedKeyCount, 1)
    }

    func testUnprotectedExportImportRoundTrip() async throws {
        let source = try makeEnvironment()
        let accountId = try await source.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Open")
        )
        let keyId = try await source.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "prod"),
            secret: "sk-backup-open-2222"
        )
        let data = try await source.backups.exportBackup(passphrase: nil, purpose: .fullBackup).data
        let protection = try await source.backups.inspectProtection(data)
        XCTAssertEqual(protection, .unprotected)
        XCTAssertTrue(data.starts(with: SecureBackupFile.unprotectedMagic))

        let destination = try makeEnvironment()
        let summary = try await destination.backups.importBackup(data: data, passphrase: nil)
        XCTAssertEqual(summary.keyCount, 1)
        let restored = try await destination.keychain.read(service: .keys, account: keyId)
        XCTAssertEqual(restored, "sk-backup-open-2222")
    }

    func testEmptyPassphraseIsRejectedForEncryptedExport() async throws {
        let env = try makeEnvironment()
        do {
            _ = try await env.backups.exportBackup(passphrase: "   ", purpose: .fullBackup)
            XCTFail("expected empty passphrase rejection")
        } catch ApiRelayError.validationFailed(let field, _) {
            XCTAssertEqual(field, "backupPassphrase")
        }
    }

    func testBackupPassphrasePersistsOnDeviceAndEncryptsExport() async throws {
        let env = try makeEnvironment()
        let store = BackupPassphraseService(keychain: env.keychain)
        try? await store.clear()
        try await store.set("device-pass-9999")
        let isSet = try await store.isSet()
        let stored = try await store.plaintext()
        XCTAssertTrue(isSet)
        XCTAssertEqual(stored, "device-pass-9999")

        let accountId = try await env.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Stored")
        )
        _ = try await env.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-backup-stored-3333"
        )
        let secret = try await store.plaintext()
        let data = try await env.backups.exportBackup(passphrase: secret, purpose: .fullBackup).data
        let protection = try await env.backups.inspectProtection(data)
        XCTAssertEqual(protection, .passphraseProtected)

        let destination = try makeEnvironment()
        _ = try await destination.backups.importBackup(data: data, passphrase: "device-pass-9999")
        try await store.clear()
        let cleared = try await store.isSet()
        XCTAssertFalse(cleared)
    }

    /// 本机 Keychain 没有明文时，导出仍保留元信息，但 MUST 把「无明文」数出来；
    /// 导入后也不能假装「密钥都齐了」。
    func testExportImportSurfacesKeysWithoutSecret() async throws {
        let source = try makeEnvironment()
        let accountId = try await source.vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Missing")
        )
        let keyId = try await source.vault.createKey(
            KeyDraft(accountId: accountId, displayName: "orphan"),
            secret: "sk-will-delete"
        )
        try await source.keychain.delete(service: .keys, account: keyId)

        let exported = try await source.backups.exportBackup(
            passphrase: "passphrase-1234",
            purpose: .fullBackup
        )
        XCTAssertEqual(exported.keysWithoutSecretCount, 1)

        let destination = try makeEnvironment()
        let summary = try await destination.backups.importBackup(
            data: exported.data,
            passphrase: "passphrase-1234"
        )
        XCTAssertEqual(summary.keyCount, 1)
        XCTAssertEqual(summary.keysWithoutSecretCount, 1)
        let keys = try await destination.vault.keys(in: accountId)
        XCTAssertEqual(keys.first?.secretAvailable, false)
    }

    private func makeEnvironment() throws -> (
        vault: KeyVaultService,
        backups: SecureBackupService,
        keychain: KeychainStore,
        tools: ConsumerToolService
    ) {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        // 本套件考的是备份导出导入，不是 StoreKit：配额走桩，免去商店超时。
        let vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .free)
        )
        let backups = SecureBackupService(
            gate: gate,
            keychain: keychain,
            modelContainer: container
        )
        let tools = ConsumerToolService(modelContainer: container, gate: gate)
        return (vault, backups, keychain, tools)
    }
}
