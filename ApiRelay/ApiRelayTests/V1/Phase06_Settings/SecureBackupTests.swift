@preconcurrency import XCTest
@testable import ApiRelay
import Security
import SwiftData

nonisolated private struct BackupImportPrimaryFault: Error, Sendable {}
nonisolated private struct BackupImportCompensationFault: Error, Sendable {}

private func makeUnprotectedBackupPayload(
    accounts: [[String: Any]],
    keys: [[String: Any]] = [],
    tools: [[String: Any]] = [],
    assignments: [[String: Any]] = []
) throws -> Data {
    let root: [String: Any] = [
        "version": 1,
        "purpose": BackupPurpose.fullBackup.rawValue,
        "accounts": accounts,
        "keys": keys,
        "tools": tools,
        "assignments": assignments,
    ]
    var payload = Data()
    payload.append(SecureBackupFile.unprotectedMagic)
    payload.append(try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))
    return payload
}

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
        let offset = SecureBackupFile.passphraseMagic.count + 16
        var encodedIterations: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &encodedIterations) { buffer in
            exported.data.copyBytes(to: buffer, from: offset..<(offset + 4))
        }
        XCTAssertEqual(UInt32(bigEndian: encodedIterations), 600_000)
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

    func testImportWithEmptySecretCannotExposePreexistingOrphanKeychainItem() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let accountID = UUID()
        let keyID = UUID()
        try await keychain.save("local-orphan-secret", service: .keys, account: keyID)
        let payload = try makeUnprotectedBackupPayload(
            accounts: [[
                "id": accountID.uuidString,
                "platform": "openai",
                "displayName": "Imported Account",
            ]],
            keys: [[
                "id": keyID.uuidString,
                "accountId": accountID.uuidString,
                "displayName": "Must Not Bind",
                "secret": "",
            ]]
        )
        let backups = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container
        )

        let summary = try await backups.importBackup(data: payload, passphrase: nil)

        XCTAssertEqual(summary.keyCount, 0)
        XCTAssertEqual(summary.skippedKeyCount, 1)
        let importedKey = try await APIKeyRecordRepository(modelContainer: container)
            .fetch(id: keyID)
        XCTAssertNil(importedKey)
        let preservedSecret = try await keychain.read(service: .keys, account: keyID)
        XCTAssertEqual(preservedSecret, "local-orphan-secret")
    }

    func testImportRestoresMetadataOnlyWhenExistingOrphanSecretMatchesBackup() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let accountID = UUID()
        let matchingKeyID = UUID()
        let conflictingKeyID = UUID()
        try await keychain.save("same-secret", service: .keys, account: matchingKeyID)
        try await keychain.save("local-wins", service: .keys, account: conflictingKeyID)
        let payload = try makeUnprotectedBackupPayload(
            accounts: [[
                "id": accountID.uuidString,
                "platform": "openai",
                "displayName": "Imported Account",
            ]],
            keys: [
                [
                    "id": matchingKeyID.uuidString,
                    "accountId": accountID.uuidString,
                    "displayName": "Matching Key",
                    "secret": "same-secret",
                ],
                [
                    "id": conflictingKeyID.uuidString,
                    "accountId": accountID.uuidString,
                    "displayName": "Conflicting Key",
                    "secret": "backup-loses",
                ],
            ]
        )
        let backups = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container
        )

        let summary = try await backups.importBackup(data: payload, passphrase: nil)

        XCTAssertEqual(summary.keyCount, 1)
        XCTAssertEqual(summary.skippedKeyCount, 1)
        let repository = APIKeyRecordRepository(modelContainer: container)
        let matching = try await repository.fetch(id: matchingKeyID)
        let conflicting = try await repository.fetch(id: conflictingKeyID)
        XCTAssertEqual(matching?.displayName, "Matching Key")
        XCTAssertNil(conflicting)
        let conflictingSecret = try await keychain.read(
            service: .keys,
            account: conflictingKeyID
        )
        XCTAssertEqual(conflictingSecret, "local-wins")
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

    func testCommittedErasePurgesPrewarmedBackupContextsAndAllowsSameIDsToReimport() async throws {
        let accountID = UUID()
        let keyID = UUID()
        let toolID = UUID()
        let root: [String: Any] = [
            "version": 1,
            "purpose": BackupPurpose.fullBackup.rawValue,
            "scope": ["keyIds": [keyID.uuidString]],
            "accounts": [[
                "id": accountID.uuidString,
                "platform": "openai",
                "displayName": "Erase Context Account",
            ]],
            "keys": [[
                "id": keyID.uuidString,
                "accountId": accountID.uuidString,
                "displayName": "Erase Context Key",
                "secret": "sk-erase-context-1111",
                "lifecycle": KeyLifecycle.active.rawValue,
                "origin": KeyOrigin.manualEntry.rawValue,
            ]],
            "tools": [[
                "id": toolID.uuidString,
                "name": "Erase Context Tool",
                "isPreset": false,
            ]],
            "assignments": [[
                "keyId": keyID.uuidString,
                "consumerToolId": toolID.uuidString,
            ]],
        ]
        var originalBackup = Data()
        originalBackup.append(SecureBackupFile.unprotectedMagic)
        originalBackup.append(try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))

        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let mutationGate = StorageMutationGate()
        let defaultsName = "SecureBackupTests.committed-erase.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let quarantine = VaultIntegrityQuarantineStore(defaults: defaults)
        let backups = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container,
            integrityQuarantine: quarantine,
            mutationGate: mutationGate
        )

        let firstImport = try await backups.importBackup(data: originalBackup, passphrase: nil)
        XCTAssertEqual(firstImport.accountCount, 1)
        XCTAssertEqual(firstImport.keyCount, 1)
        XCTAssertEqual(firstImport.toolCount, 1)

        // Export through this same service before erase so all of its long-lived
        // repository actors have observed the records that used to survive a
        // fresh-context-only deletion.
        let beforeErase = try await backups.exportBackup(
            passphrase: nil,
            purpose: .fullBackup
        )
        let beforeRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(beforeErase.data.dropFirst(SecureBackupFile.unprotectedMagic.count))
            ) as? [String: Any]
        )
        XCTAssertEqual((beforeRoot["accounts"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((beforeRoot["keys"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((beforeRoot["tools"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((beforeRoot["assignments"] as? [[String: Any]])?.count, 1)

        XCTAssertTrue(try mutationGate.sealForErase(resumingInterruptedErase: false))
        let eraseAuthorization = try mutationGate.mintCommittedEraseToken()
        await mutationGate.waitUntilNormalMutationsDrain()
        try await backups.purgeAllRecordsForCommittedErase(
            authorization: eraseAuthorization
        )
        for account in try await keychain.listAccounts(service: .keys) {
            try await keychain.delete(service: .keys, account: account)
        }
        try mutationGate.completeEraseAndReopen()

        let afterErase = try await backups.exportBackup(
            passphrase: nil,
            purpose: .fullBackup
        )
        let afterRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(afterErase.data.dropFirst(SecureBackupFile.unprotectedMagic.count))
            ) as? [String: Any]
        )
        XCTAssertEqual((afterRoot["accounts"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((afterRoot["keys"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((afterRoot["tools"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((afterRoot["assignments"] as? [[String: Any]])?.count, 0)

        let secondImport = try await backups.importBackup(data: originalBackup, passphrase: nil)
        XCTAssertEqual(secondImport.accountCount, 1)
        XCTAssertEqual(secondImport.keyCount, 1)
        XCTAssertEqual(secondImport.toolCount, 1)
        XCTAssertEqual(secondImport.skippedKeyCount, 0)
        let restoredAccount = try await UpstreamAccountRepository(
            modelContainer: container
        ).fetch(id: accountID)
        let restoredKey = try await APIKeyRecordRepository(
            modelContainer: container
        ).fetch(id: keyID)
        let restoredTool = try await ConsumerToolRepository(
            modelContainer: container
        ).fetch(id: toolID)
        let restoredAssignments = try await KeyAssignmentRepository(
            modelContainer: container
        ).fetchConsumerToolIDs(keyId: keyID)
        let restoredSecret = try await keychain.read(service: .keys, account: keyID)
        XCTAssertEqual(restoredAccount?.id, accountID)
        XCTAssertEqual(restoredKey?.id, keyID)
        XCTAssertEqual(restoredTool?.id, toolID)
        XCTAssertEqual(restoredAssignments, [toolID])
        XCTAssertEqual(restoredSecret, "sk-erase-context-1111")
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

    /// `errSecItemNotFound` is the only Keychain read outcome that may become an
    /// explicit missing-secret entry. Permission/transient failures must abort the
    /// export rather than silently producing a backup with an empty secret.
    func testExportFailsClosedWhenKeychainReadFailsForReasonOtherThanNotFound() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let gate = FakeRevealGate()
        let vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: FakeClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .unlimitedKeys)
        )
        let backups = SecureBackupService(
            gate: gate,
            keychain: keychain,
            modelContainer: container
        )
        var patch = PreferencesPatch()
        patch.revealPolicy = .noVerification
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Fail Closed")
        )
        _ = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "protected"),
            secret: "sk-must-not-be-silently-omitted"
        )

        let readsBeforeExport = await keychain.journal.callCount("read")
        await keychain.fail("read", with: .keychainFailure(errSecAuthFailed))
        do {
            _ = try await backups.exportBackup(passphrase: nil, purpose: .fullBackup)
            XCTFail("Keychain read failure must abort backup export")
        } catch ApiRelayError.keychainFailure(let status) {
            XCTAssertEqual(status, errSecAuthFailed)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        let journal = await keychain.journal
        XCTAssertEqual(
            journal.callCount("read") - readsBeforeExport,
            1,
            "export must stop at the first unexpected Keychain read failure"
        )
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

extension SecureBackupTests {
    func testImportFailureAfterAccountAndToolLeavesNoNewRecords() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let accountID = UUID()
        let toolID = UUID()
        let keyID = UUID()
        let payload = try makeUnprotectedBackupPayload(
            accounts: [[
                "id": accountID.uuidString,
                "platform": "openai",
                "displayName": "Provisional Account",
            ]],
            keys: [[
                "id": keyID.uuidString,
                "accountId": accountID.uuidString,
                "displayName": "Injected Failure Key",
                "secret": "",
            ]],
            tools: [[
                "id": toolID.uuidString,
                "name": "Provisional Tool",
                "isPreset": false,
            ]]
        )
        let backups = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container,
            importMutationObserver: { mutation in
                if mutation == .keyInsert { throw BackupImportPrimaryFault() }
            }
        )

        do {
            _ = try await backups.importBackup(data: payload, passphrase: nil)
            XCTFail("injected key failure must abort the whole import")
        } catch is BackupImportPrimaryFault {
            // expected
        }

        let remainingAccounts = try await UpstreamAccountRepository(modelContainer: container)
            .fetchAll(includeDeleted: true)
        let remainingTools = try await ConsumerToolRepository(modelContainer: container)
            .fetchAll(includeHidden: true, includeDeleted: true)
        let remainingKey = try await APIKeyRecordRepository(modelContainer: container).fetch(id: keyID)
        let remainingKeychainAccounts = try await keychain.listAccounts(service: .keys)
        XCTAssertTrue(remainingAccounts.isEmpty)
        XCTAssertTrue(remainingTools.isEmpty)
        XCTAssertNil(remainingKey)
        XCTAssertTrue(remainingKeychainAccounts.isEmpty)
    }

    func testImportCompensationNeverDeletesPreexistingAccountOrTool() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let existingAccountID = UUID()
        let importedAccountID = UUID()
        let existingToolID = UUID()
        let importedToolID = UUID()
        let keyID = UUID()
        let accountRepository = UpstreamAccountRepository(modelContainer: container)
        let toolRepository = ConsumerToolRepository(modelContainer: container)
        _ = try await accountRepository.insert(
            UpstreamAccountDraft(platform: "anthropic", displayName: "Keep Existing Account"),
            id: existingAccountID
        )
        _ = try await toolRepository.insert(
            ConsumerToolDraft(name: "Keep Existing Tool"),
            id: existingToolID
        )
        let payload = try makeUnprotectedBackupPayload(
            accounts: [
                [
                    "id": existingAccountID.uuidString,
                    "platform": "openai",
                    "displayName": "Backup Must Not Overwrite",
                ],
                [
                    "id": importedAccountID.uuidString,
                    "platform": "openai",
                    "displayName": "Rollback Account",
                ],
            ],
            keys: [[
                "id": keyID.uuidString,
                "accountId": importedAccountID.uuidString,
                "displayName": "Injected Failure Key",
                "secret": "",
            ]],
            tools: [
                [
                    "id": existingToolID.uuidString,
                    "name": "Backup Must Not Overwrite",
                    "isPreset": false,
                ],
                [
                    "id": importedToolID.uuidString,
                    "name": "Rollback Tool",
                    "isPreset": false,
                ],
            ]
        )
        let backups = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: FakeKeychain(),
            modelContainer: container,
            importMutationObserver: { mutation in
                if mutation == .keyInsert { throw BackupImportPrimaryFault() }
            }
        )

        do {
            _ = try await backups.importBackup(data: payload, passphrase: nil)
            XCTFail("injected key failure must abort the whole import")
        } catch is BackupImportPrimaryFault {
            // expected
        }

        let existingAccount = try await accountRepository.fetch(id: existingAccountID)
        let importedAccount = try await accountRepository.fetch(id: importedAccountID)
        let existingTool = try await toolRepository.fetch(id: existingToolID)
        let importedTool = try await toolRepository.fetch(id: importedToolID)
        XCTAssertEqual(existingAccount?.displayName, "Keep Existing Account")
        XCTAssertNil(importedAccount)
        XCTAssertEqual(existingTool?.name, "Keep Existing Tool")
        XCTAssertNil(importedTool)
    }

    func testHiddenToolUpdateFailureRemovesInsertedToolAndAccount() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let accountID = UUID()
        let toolID = UUID()
        let payload = try makeUnprotectedBackupPayload(
            accounts: [[
                "id": accountID.uuidString,
                "platform": "openai",
                "displayName": "Rollback Account",
            ]],
            tools: [[
                "id": toolID.uuidString,
                "name": "Rollback Hidden Tool",
                "isPreset": false,
                "isHidden": true,
            ]]
        )
        let backups = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: FakeKeychain(),
            modelContainer: container,
            importMutationObserver: { mutation in
                if mutation == .toolUpdate { throw BackupImportPrimaryFault() }
            }
        )

        do {
            _ = try await backups.importBackup(data: payload, passphrase: nil)
            XCTFail("hidden-state update failure must abort the whole import")
        } catch is BackupImportPrimaryFault {
            // expected
        }

        let remainingAccount = try await UpstreamAccountRepository(modelContainer: container).fetch(id: accountID)
        let remainingTool = try await ConsumerToolRepository(modelContainer: container).fetch(id: toolID)
        XCTAssertNil(remainingAccount)
        XCTAssertNil(remainingTool)
    }

    func testImportCompensationFailurePersistsJournalAndStartupRecoveryCompletes() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let accountID = UUID()
        let toolID = UUID()
        let payload = try makeUnprotectedBackupPayload(
            accounts: [[
                "id": accountID.uuidString,
                "platform": "openai",
                "displayName": "Compensation Account",
            ]],
            tools: [[
                "id": toolID.uuidString,
                "name": "Compensation Tool",
                "isPreset": false,
                "isHidden": true,
            ]]
        )
        let defaultsName = "SecureBackupTests.compensation-quarantine.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecureBackupCrossStoreTests-\(UUID().uuidString)", isDirectory: true)
        let journal = DurableCrossStoreTransactionJournal(
            fileURL: journalDirectory.appendingPathComponent("journal.json")
        )
        let mutationGate = StorageMutationGate()
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: journalDirectory)
        }
        let quarantine = VaultIntegrityQuarantineStore(defaults: defaults)
        let backups = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container,
            integrityQuarantine: quarantine,
            mutationGate: mutationGate,
            crossStoreJournal: journal,
            importMutationObserver: { mutation in
                switch mutation {
                case .toolUpdate:
                    throw BackupImportPrimaryFault()
                case .toolCompensation:
                    throw BackupImportCompensationFault()
                default:
                    break
                }
            }
        )

        do {
            _ = try await backups.importBackup(data: payload, passphrase: nil)
            XCTFail("failed compensation must leave durable recovery pending")
        } catch ApiRelayError.storageRecoveryFailed(let operation, let detail) {
            XCTAssertEqual(operation, "backup_import")
            XCTAssertTrue(detail.contains("BackupImportPrimaryFault"))
            XCTAssertTrue(detail.contains("BackupImportCompensationFault"))
        }

        XCTAssertTrue(mutationGate.isCrossStoreRecoverySealed())
        let pending = try XCTUnwrap(journal.load())
        XCTAssertEqual(pending.kind, .backupImport)
        XCTAssertEqual(pending.phase, .applying)
        XCTAssertNil(quarantine.currentIncident())

        // Provisional rows may remain physically present, but the shared gate
        // makes them unobservable until a fault-free startup replay removes all
        // rows owned by this transaction.
        let remainingAccount = try await UpstreamAccountRepository(modelContainer: container).fetch(id: accountID)
        let remainingTool = try await ConsumerToolRepository(modelContainer: container).fetch(id: toolID)
        XCTAssertNotNil(remainingAccount)
        XCTAssertNotNil(remainingTool)

        do {
            _ = try await backups.importBackup(data: payload, passphrase: nil)
            XCTFail("ordinary import must remain sealed before startup replay")
        } catch ApiRelayError.storageRecoveryFailed(_, let detail) {
            XCTAssertEqual(detail, "cross_store_recovery_pending")
        }

        let recoveredService = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container,
            integrityQuarantine: quarantine,
            mutationGate: mutationGate,
            crossStoreJournal: journal
        )
        try await recoveredService.recoverInterruptedCrossStoreTransaction(pending)

        let recoveredAccount = try await UpstreamAccountRepository(modelContainer: container)
            .fetch(id: accountID)
        let recoveredTool = try await ConsumerToolRepository(modelContainer: container)
            .fetch(id: toolID)
        XCTAssertNil(recoveredAccount)
        XCTAssertNil(recoveredTool)
        XCTAssertNil(try journal.load())
        XCTAssertFalse(mutationGate.isCrossStoreRecoverySealed())
        XCTAssertNil(quarantine.currentIncident())
    }

    func testStartupRecoveryRollsCommittedImportForwardAndRevokesRollbackTag() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = FakeKeychain()
        let accountID = UUID()
        let keyID = UUID()
        let accountCreatedAt = Date(timeIntervalSinceReferenceDate: 20_000)
        let keyCreatedAt = Date(timeIntervalSinceReferenceDate: 20_001)
        _ = try await UpstreamAccountRepository(modelContainer: container).insert(
            UpstreamAccountDraft(platform: "openai", displayName: "Committed Import"),
            id: accountID,
            createdAt: accountCreatedAt
        )
        _ = try await APIKeyRecordRepository(modelContainer: container).insert(
            KeyRecordDraft(
                accountId: accountID,
                displayName: "Committed Imported Key",
                origin: .manualEntry
            ),
            id: keyID,
            createdAt: keyCreatedAt
        )
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecureBackupCommittedRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        let journal = DurableCrossStoreTransactionJournal(
            fileURL: journalDirectory.appendingPathComponent("journal.json")
        )
        defer { try? FileManager.default.removeItem(at: journalDirectory) }
        let transactionID = try journal.begin(.backupImport)
        try journal.planInsertedAccount(
            CrossStoreInsertedRecordPlan(id: accountID, createdAt: accountCreatedAt),
            transactionId: transactionID
        )
        try journal.planInsertedKey(
            CrossStoreKeyRollbackPlan(
                id: keyID,
                accountId: accountID,
                createdAt: keyCreatedAt
            ),
            transactionId: transactionID
        )
        let insertedSecret = try await keychain.insertIfAbsent(
            "sk-committed-import",
            service: .keys,
            account: keyID,
            transactionTag: transactionID
        )
        XCTAssertTrue(insertedSecret)
        try journal.decideCommit(transactionId: transactionID)
        let pending = try XCTUnwrap(journal.load())
        let mutationGate = StorageMutationGate(crossStoreRecoveryPending: true)
        let backups = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: keychain,
            modelContainer: container,
            mutationGate: mutationGate,
            crossStoreJournal: journal
        )

        try await backups.recoverInterruptedCrossStoreTransaction(pending)

        let storedKey = try await APIKeyRecordRepository(modelContainer: container)
            .fetch(id: keyID)
        XCTAssertEqual(storedKey?.displayName, "Committed Imported Key")
        let storedSecret = try await keychain.read(service: .keys, account: keyID)
        XCTAssertEqual(storedSecret, "sk-committed-import")
        let rollbackStillOwnsSecret = try await keychain.deleteIfTransactionTagMatches(
            service: .keys,
            account: keyID,
            transactionTag: transactionID
        )
        XCTAssertFalse(rollbackStillOwnsSecret)
        XCTAssertNil(try journal.load())
        XCTAssertFalse(mutationGate.isCrossStoreRecoverySealed())
    }
}

extension SecureBackupTests {
    func testExportImportUseCurrentPolicyNotMandatory() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let fake = FakeRevealGate()
        let vault = KeyVaultService(
            keychain: keychain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: StubEntitlements(tier: .free)
        )
        let backups = SecureBackupService(gate: fake, keychain: keychain, modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Backup")
        )
        _ = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-w4-backup-1111"
        )
        _ = try await backups.exportBackup(passphrase: "passphrase-1234", purpose: .fullBackup)
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirm"), 1)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }

    func testExportCancelDoesNotProduceFile() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let fake = FakeRevealGate()
        await fake.fail("confirm", with: .authenticationCancelled)
        let backups = SecureBackupService(gate: fake, keychain: keychain, modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        do {
            _ = try await backups.exportBackup(passphrase: "passphrase-1234", purpose: .fullBackup)
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirm"), 1)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }

    func testBackupAuthorizationLeaseRevokedDuringConfirmPreventsExportReadAndImportWrite() async throws {
        let sourceContainer = try AppSchema.makeInMemoryContainer()
        let sourceKeychain = FakeKeychain()
        let sourceGate = FakeRevealGate()
        let sourceBox = SessionLockBox()
        let sourceVault = KeyVaultService(
            keychain: sourceKeychain,
            gate: sourceGate,
            clipboard: FakeClipboard(),
            modelContainer: sourceContainer,
            entitlements: StubEntitlements(tier: .unlimitedKeys),
            sessionLock: sourceBox
        )
        var patch = PreferencesPatch()
        patch.revealPolicy = .noVerification
        try await UserPreferencesRepository(modelContainer: sourceContainer).update(patch)
        let accountId = try await sourceVault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Lease")
        )
        _ = try await sourceVault.createKey(
            KeyDraft(accountId: accountId, displayName: "kept"),
            secret: "sk-backup-lease-kept"
        )
        patch.revealPolicy = .biometricOrPasscode
        try await UserPreferencesRepository(modelContainer: sourceContainer).update(patch)
        let sourceBackups = SecureBackupService(
            gate: sourceGate,
            keychain: sourceKeychain,
            modelContainer: sourceContainer,
            sessionLock: sourceBox
        )
        await sourceGate.setAfterConfirmHook {
            sourceBox.invalidateAuthorizationLeases()
        }
        let readsBefore = await sourceKeychain.journal.callCount("read")
        do {
            _ = try await sourceBackups.exportBackup(passphrase: nil, purpose: .fullBackup)
            XCTFail("revoked export lease must fail")
        } catch ApiRelayError.sessionLocked {
        }
        let readsAfter = await sourceKeychain.journal.callCount("read")
        XCTAssertEqual(readsAfter, readsBefore)

        let destinationContainer = try AppSchema.makeInMemoryContainer()
        let destinationKeychain = FakeKeychain()
        let destinationGate = FakeRevealGate()
        let destinationBox = SessionLockBox()
        var destinationPatch = PreferencesPatch()
        destinationPatch.revealPolicy = .biometricOrPasscode
        try await UserPreferencesRepository(modelContainer: destinationContainer).update(destinationPatch)
        let destinationBackups = SecureBackupService(
            gate: destinationGate,
            keychain: destinationKeychain,
            modelContainer: destinationContainer,
            sessionLock: destinationBox
        )
        await destinationGate.setAfterConfirmHook {
            destinationBox.invalidateAuthorizationLeases()
        }
        var payload = Data()
        payload.append(SecureBackupFile.unprotectedMagic)
        payload.append(Data("{}".utf8))
        do {
            _ = try await destinationBackups.importBackup(data: payload, passphrase: nil)
            XCTFail("revoked import lease must fail")
        } catch ApiRelayError.sessionLocked {
        }
        let destinationSaves = await destinationKeychain.journal.callCount("save")
        XCTAssertEqual(destinationSaves, 0)
    }

    func testImportInvalidatedAtActualRepositoryCommitWritesNoPayloadItem() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let chain = FakeKeychain()
        let barrier = CommitBarrierSessionLock()
        let backups = SecureBackupService(
            gate: FakeRevealGate(),
            keychain: chain,
            modelContainer: local,
            sessionLock: barrier
        )
        let accountID = UUID()
        let root: [String: Any] = [
            "version": 1,
            "purpose": BackupPurpose.fullBackup.rawValue,
            "accounts": [[
                "id": accountID.uuidString,
                "platform": "openai",
                "displayName": "Must Not Import",
            ]],
            "keys": [],
            "tools": [],
            "assignments": [],
        ]
        var payload = Data()
        payload.append(SecureBackupFile.unprotectedMagic)
        payload.append(try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))

        barrier.blockNextCommit()
        let revoke = Task.detached {
            await barrier.waitUntilCommitIsBlocked()
            barrier.invalidateAuthorizationLeases()
            barrier.releaseCommit()
        }
        let importing = Task {
            try await backups.importBackup(data: payload, passphrase: nil)
        }
        await revoke.value

        do {
            _ = try await importing.value
            XCTFail("stale lease must not enter the account repository commit")
        } catch ApiRelayError.sessionLocked {
            // expected
        }
        let accounts = try await UpstreamAccountRepository(modelContainer: local).fetchAll()
        XCTAssertTrue(accounts.isEmpty)
        let keychainWrites = await chain.journal.callCount("save")
        XCTAssertEqual(keychainWrites, 0)
    }
}

extension SecureBackupTests {
    func testExportImportCurrentPolicyMatrix() async throws {
        struct Row {
            let name: String
            let policy: RevealPolicy
            let password: String?
            let fail: Bool
            let expectOk: Bool
            let confirm: Int
            let master: Int
        }
        let rows: [Row] = [
            .init(name: "none", policy: .noVerification, password: nil, fail: false, expectOk: true, confirm: 0, master: 0),
            .init(name: "device", policy: .biometricOrPasscode, password: nil, fail: false, expectOk: true, confirm: 1, master: 0),
            .init(name: "device-cancel", policy: .biometricOrPasscode, password: nil, fail: true, expectOk: false, confirm: 1, master: 0),
            .init(name: "combo", policy: .biometryOrAppPassword, password: nil, fail: false, expectOk: true, confirm: 1, master: 0),
            .init(name: "master-missing", policy: .masterPassword, password: nil, fail: false, expectOk: false, confirm: 0, master: 0),
            .init(name: "master-ok", policy: .masterPassword, password: "abcd", fail: false, expectOk: true, confirm: 0, master: 1),
        ]
        for row in rows {
            let local = try AppSchema.makeInMemoryContainer()
            let chain = KeychainStore.makeForTests()
            let fake = FakeRevealGate()
            if row.fail {
                await fake.fail("confirm", with: .authenticationCancelled)
            }
            let vault = KeyVaultService(
                keychain: chain,
                gate: fake,
                clipboard: SecureClipboard(),
                modelContainer: local,
                entitlements: StubEntitlements(tier: .free)
            )
            let backups = SecureBackupService(gate: fake, keychain: chain, modelContainer: local)
            var setup = PreferencesPatch()
            setup.revealPolicy = .noVerification
            try await UserPreferencesRepository(modelContainer: local).update(setup)
            let accountId = try await vault.createAccount(
                UpstreamAccountDraft(platform: "openai", displayName: row.name)
            )
            _ = try await vault.createKey(
                KeyDraft(accountId: accountId, displayName: "k1"),
                secret: "sk-w4-bex-\(row.name)-aa"
            )
            var live = PreferencesPatch()
            live.revealPolicy = row.policy
            try await UserPreferencesRepository(modelContainer: local).update(live)
            do {
                let exported = try await backups.exportBackup(
                    passphrase: "passphrase-1234",
                    purpose: .fullBackup,
                    appPassword: row.password
                )
                if !row.expectOk { XCTFail("\(row.name) export should fail") }
                if row.expectOk {
                    let destination = try AppSchema.makeInMemoryContainer()
                    let destKeychain = KeychainStore.makeForTests()
                    let destFake = FakeRevealGate()
                    var destPatch = PreferencesPatch()
                    destPatch.revealPolicy = row.policy
                    try await UserPreferencesRepository(modelContainer: destination).update(destPatch)
                    let dest = SecureBackupService(
                        gate: destFake,
                        keychain: destKeychain,
                        modelContainer: destination
                    )
                    _ = try await dest.importBackup(
                        data: exported.data,
                        passphrase: "passphrase-1234",
                        appPassword: row.password
                    )
                }
            } catch {
                if row.expectOk { XCTFail("\(row.name) \(error)") }
            }
            let journal = await fake.journal
            XCTAssertEqual(journal.callCount("confirm"), row.confirm, "\(row.name) confirm")
            XCTAssertEqual(journal.callCount("confirmMandatory"), 0, row.name)
            XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), row.master, row.name)
            XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 0, row.name)
        }
    }

    func testExportCombinationPasswordUsesExplicitEntry() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let chain = KeychainStore.makeForTests()
        let fake = FakeRevealGate()
        let vault = KeyVaultService(
            keychain: chain,
            gate: fake,
            clipboard: SecureClipboard(),
            modelContainer: local,
            entitlements: StubEntitlements(tier: .free)
        )
        let backups = SecureBackupService(gate: fake, keychain: chain, modelContainer: local)
        var setup = PreferencesPatch()
        setup.revealPolicy = .noVerification
        try await UserPreferencesRepository(modelContainer: local).update(setup)
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "combo-pw")
        )
        _ = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "k1"),
            secret: "sk-w5-bex-combo-pw-aa"
        )
        var live = PreferencesPatch()
        live.revealPolicy = .biometryOrAppPassword
        try await UserPreferencesRepository(modelContainer: local).update(live)
        _ = try await backups.exportBackup(
            passphrase: "passphrase-1234",
            purpose: .fullBackup,
            appPassword: "combo-pass-word"
        )
        let journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 1)
        XCTAssertEqual(journal.callCount("confirm"), 0)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
    }

    func testBackupPassphraseManagementUsesCurrentPolicy() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let fake = FakeRevealGate()
        let prefs = FakePreferences()
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        try await prefs.update(patch)
        let master = FakeMasterPassword()
        let env = AppEnvironment(
            modelContainer: container,
            keychain: FakeKeychain(),
            masterPassword: master,
            gate: fake,
            clipboard: FakeClipboard(),
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            trashBatch: FakeRecentlyDeletedBatch(),
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            preferences: prefs,
            backups: FakeSecureBackup(),
            backupPassphrase: FakeBackupPassphrase(),
            dataLifecycle: FakeDataLifecycle(),
            cloudSync: FakeCloudSync(),
            appPrivacy: AppPrivacyController(
                gate: fake,
                preferences: prefs,
                masterPassword: master,
                installsSnapshotCover: false,
                enablesUnlockPrompt: false,
                launchAppLockEnabled: false
            )
        )
        try await BackupCurrentPolicyAuth.confirm(
            environment: env,
            reason: "gate.backupPassphraseSet",
            appPassword: nil
        )
        var journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirm"), 1)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)

        patch.revealPolicy = .masterPassword
        try await prefs.update(patch)
        // 本用例验证“已有应用密码”的当前方式确认；缺材料应由独立恢复用例验证。
        await fake.setAppPasswordMaterialSet(true)
        do {
            try await BackupCurrentPolicyAuth.confirm(
                environment: env,
                reason: "gate.backupPassphraseCopy",
                appPassword: nil
            )
            XCTFail("expected prompt")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "master_password_prompt_required")
        }
        try await BackupCurrentPolicyAuth.confirm(
            environment: env,
            reason: "gate.backupPassphraseClear",
            appPassword: "abcd"
        )
        journal = await fake.journal
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 1)
    }

    func testBackupPassphraseSaveCopyClearSessionLockHasZeroSideEffects() async throws {
        struct Row {
            let name: String
            let action: BackupPassphraseSensitiveOps.Action
            let seed: Bool
        }
        let rows: [Row] = [
            .init(name: "save", action: .save("new-backup-pass"), seed: false),
            .init(name: "copy", action: .copy, seed: true),
            .init(name: "clear", action: .clear, seed: true),
        ]
        for row in rows {
            AppLockLaunchCache.resetForTests()
            let harness = try await makePassphraseHarness(sessionLocked: true)
            if row.seed {
                await harness.passphrase.seedForTests("kept-backup-pass")
            }
            let gateBefore = await harness.gate.journal
            let passBefore = await harness.passphrase.journal
            let clipBefore = await harness.clipboard.journal
            do {
                try await BackupPassphraseSensitiveOps.perform(
                    row.action,
                    environment: harness.env,
                    appPassword: nil
                )
                XCTFail("\(row.name) expected sessionLocked")
            } catch ApiRelayError.sessionLocked {
            } catch {
                XCTFail("\(row.name) \(error)")
            }
            let gateAfter = await harness.gate.journal
            let passAfter = await harness.passphrase.journal
            let clipAfter = await harness.clipboard.journal
            XCTAssertEqual(gateAfter.callCount("confirm"), gateBefore.callCount("confirm"), row.name)
            XCTAssertEqual(gateAfter.callCount("confirmMandatory"), 0, row.name)
            XCTAssertEqual(
                gateAfter.callCount("confirmWithMasterPassword"),
                gateBefore.callCount("confirmWithMasterPassword"),
                row.name
            )
            XCTAssertEqual(passAfter.callCount("set"), passBefore.callCount("set"), row.name)
            XCTAssertEqual(passAfter.callCount("plaintext"), passBefore.callCount("plaintext"), row.name)
            XCTAssertEqual(passAfter.callCount("clear"), passBefore.callCount("clear"), row.name)
            XCTAssertEqual(clipAfter.callCount("write"), clipBefore.callCount("write"), row.name)
            if row.seed {
                let secret = await harness.passphrase.plaintextForTests()
                XCTAssertEqual(secret, "kept-backup-pass", row.name)
            } else {
                let stillSet = try await harness.passphrase.isSet()
                XCTAssertFalse(stillSet, row.name)
            }
            let lastWritten = await harness.clipboard.lastWritten
            XCTAssertNil(lastWritten, row.name)
            AppLockLaunchCache.resetForTests()
        }
    }

    func testBackupPassphraseCopyCancelLeavesPassphraseAndClipboardUntouched() async throws {
        AppLockLaunchCache.resetForTests()
        let harness = try await makePassphraseHarness(sessionLocked: false)
        await harness.passphrase.seedForTests("kept-backup-pass")
        await harness.gate.fail("confirm", with: .authenticationCancelled)
        let passBefore = await harness.passphrase.journal
        let clipBefore = await harness.clipboard.journal
        do {
            try await BackupPassphraseSensitiveOps.perform(
                .copy,
                environment: harness.env,
                appPassword: nil
            )
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        let gateJournal = await harness.gate.journal
        XCTAssertEqual(gateJournal.callCount("confirm"), 1)
        XCTAssertEqual(gateJournal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(gateJournal.callCount("confirmWithMasterPassword"), 0)
        let passAfter = await harness.passphrase.journal
        let clipAfter = await harness.clipboard.journal
        XCTAssertEqual(passAfter.callCount("plaintext"), passBefore.callCount("plaintext"))
        XCTAssertEqual(passAfter.callCount("clear"), passBefore.callCount("clear"))
        XCTAssertEqual(clipAfter.callCount("write"), clipBefore.callCount("write"))
        let secret = try await harness.passphrase.plaintext()
        XCTAssertEqual(secret, "kept-backup-pass")
        let lastWritten = await harness.clipboard.lastWritten
        XCTAssertNil(lastWritten)
        AppLockLaunchCache.resetForTests()
    }

    func testBackupPassphraseLeaseInvalidatedAfterConfirmHasZeroSensitiveSideEffects() async throws {
        struct Row {
            let name: String
            let action: BackupPassphraseSensitiveOps.Action
            let seed: Bool
        }
        let rows: [Row] = [
            .init(name: "save", action: .save("new-backup-pass"), seed: false),
            .init(name: "copy", action: .copy, seed: true),
            .init(name: "clear", action: .clear, seed: true),
        ]

        for row in rows {
            AppLockLaunchCache.resetForTests()
            let harness = try await makePassphraseHarness(sessionLocked: false)
            if row.seed {
                await harness.passphrase.seedForTests("kept-backup-pass")
            }
            let passBefore = await harness.passphrase.journal
            let clipBefore = await harness.clipboard.journal
            await harness.gate.setAfterConfirmHook {
                harness.sessionLock.invalidateAuthorizationLeases()
            }

            do {
                try await BackupPassphraseSensitiveOps.perform(
                    row.action,
                    environment: harness.env,
                    appPassword: nil
                )
                XCTFail("\(row.name) expected stale authorization")
            } catch ApiRelayError.sessionLocked {
                // Expected: invalidation after authentication wins before any
                // Keychain read/write/delete or pasteboard write starts.
            } catch {
                XCTFail("\(row.name) unexpected error: \(error)")
            }

            let passAfter = await harness.passphrase.journal
            let clipAfter = await harness.clipboard.journal
            XCTAssertEqual(passAfter.callCount("set"), passBefore.callCount("set"), row.name)
            XCTAssertEqual(passAfter.callCount("plaintext"), passBefore.callCount("plaintext"), row.name)
            XCTAssertEqual(passAfter.callCount("clear"), passBefore.callCount("clear"), row.name)
            XCTAssertEqual(clipAfter.callCount("write"), clipBefore.callCount("write"), row.name)
            if row.seed {
                // Seed inspection uses a new test-only lease after the stale
                // operation; it verifies that clear/copy did not alter storage.
                let secret = try await harness.passphrase.plaintext()
                XCTAssertEqual(secret, "kept-backup-pass", row.name)
            } else {
                let isSet = try await harness.passphrase.isSet()
                XCTAssertFalse(isSet, row.name)
            }
            let lastWritten = await harness.clipboard.lastWritten
            XCTAssertNil(lastWritten, row.name)
            AppLockLaunchCache.resetForTests()
        }
    }

    func testBackupPassphraseCopyPreferenceLoadFailurePerformsZeroClipboardWrites() async throws {
        AppLockLaunchCache.resetForTests()
        defer { AppLockLaunchCache.resetForTests() }
        let harness = try await makePassphraseHarness(sessionLocked: false)
        await harness.passphrase.seedForTests("kept-backup-pass")
        let clipboardBefore = await harness.clipboard.journal
        await harness.gate.setAfterConfirmHook {
            await harness.preferences.setLoadError(
                ApiRelayError.validationFailed(
                    field: "preferences",
                    reason: "injected_load_failure"
                )
            )
        }

        do {
            try await BackupPassphraseSensitiveOps.perform(
                .copy,
                environment: harness.env,
                appPassword: nil
            )
            XCTFail("a security-preference read failure must fail closed")
        } catch let ApiRelayError.validationFailed(field, reason) {
            XCTAssertEqual(field, "preferences")
            XCTAssertEqual(reason, "injected_load_failure")
        }

        let clipboardAfter = await harness.clipboard.journal
        XCTAssertEqual(
            clipboardAfter.callCount("write"),
            clipboardBefore.callCount("write")
        )
        let lastWritten = await harness.clipboard.lastWritten
        XCTAssertNil(lastWritten)
    }

    func testExportUsingStoredPassphraseSessionLockDoesNotReadSecret() async throws {
        // 生产入口：BackupExportView.exportWithStored → BackupStoredPassphraseAccess.exportUsingStored
        AppLockLaunchCache.resetForTests()
        let harness = try await makePassphraseHarness(sessionLocked: true)
        await harness.passphrase.seedForTests("kept-backup-pass")
        let passBefore = await harness.passphrase.journal
        let gateBefore = await harness.gate.journal
        let backupBefore = await harness.backups.journal
        do {
            _ = try await BackupStoredPassphraseAccess.exportUsingStored(harness.env)
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        let passAfter = await harness.passphrase.journal
        let gateAfter = await harness.gate.journal
        let backupAfter = await harness.backups.journal
        XCTAssertEqual(passAfter.callCount("plaintext"), passBefore.callCount("plaintext"))
        XCTAssertEqual(gateAfter.callCount("confirm"), gateBefore.callCount("confirm"))
        XCTAssertEqual(gateAfter.callCount("confirmMandatory"), 0)
        XCTAssertEqual(gateAfter.callCount("confirmWithMasterPassword"), 0)
        XCTAssertEqual(backupAfter.callCount("exportBackup"), backupBefore.callCount("exportBackup"))
        XCTAssertEqual(backupAfter.callCount("inspectProtection"), backupBefore.callCount("inspectProtection"))
        let secret = await harness.passphrase.plaintextForTests()
        XCTAssertEqual(secret, "kept-backup-pass")
        AppLockLaunchCache.resetForTests()
    }

    func testImportUsingStoredPassphraseSessionLockDoesNotReadSecret() async throws {
        // 生产入口：BackupImportView.importBytes(.defaultStored) → importWithStored → importUsingStored
        AppLockLaunchCache.resetForTests()
        let harness = try await makePassphraseHarness(sessionLocked: true)
        await harness.passphrase.seedForTests("kept-backup-pass")
        var protected = Data()
        protected.append(SecureBackupFile.passphraseMagic)
        protected.append(Data("{}".utf8))
        let passBefore = await harness.passphrase.journal
        let gateBefore = await harness.gate.journal
        let backupBefore = await harness.backups.journal
        do {
            _ = try await BackupStoredPassphraseAccess.importUsingStored(harness.env, data: protected)
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        let passAfter = await harness.passphrase.journal
        let gateAfter = await harness.gate.journal
        let backupAfter = await harness.backups.journal
        XCTAssertEqual(passAfter.callCount("plaintext"), passBefore.callCount("plaintext"))
        XCTAssertEqual(gateAfter.callCount("confirm"), gateBefore.callCount("confirm"))
        XCTAssertEqual(gateAfter.callCount("confirmMandatory"), 0)
        XCTAssertEqual(gateAfter.callCount("confirmWithMasterPassword"), 0)
        XCTAssertEqual(backupAfter.callCount("importBackup"), backupBefore.callCount("importBackup"))
        XCTAssertEqual(backupAfter.callCount("inspectProtection"), backupBefore.callCount("inspectProtection"))
        let secret = await harness.passphrase.plaintextForTests()
        XCTAssertEqual(secret, "kept-backup-pass")
        AppLockLaunchCache.resetForTests()
    }

    private func makePassphraseHarness(sessionLocked: Bool) async throws -> (
        env: AppEnvironment,
        gate: FakeRevealGate,
        passphrase: FakeBackupPassphrase,
        clipboard: FakeClipboard,
        backups: FakeSecureBackup,
        preferences: FakePreferences,
        sessionLock: SessionLockBox
    ) {
        let container = try AppSchema.makeInMemoryContainer()
        let gate = FakeRevealGate()
        let prefs = FakePreferences()
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        try await prefs.update(patch)
        let master = FakeMasterPassword()
        let sessionLock = SessionLockBox()
        let passphrase = FakeBackupPassphrase(sessionLock: sessionLock)
        let clipboard = FakeClipboard()
        let backups = FakeSecureBackup()
        let privacy = AppPrivacyController(
            gate: gate,
            preferences: prefs,
            masterPassword: master,
            installsSnapshotCover: false,
            enablesUnlockPrompt: false,
            launchAppLockEnabled: sessionLocked,
            scenePresence: { .userFacing },
            sessionLockBox: sessionLock
        )
        let env = AppEnvironment(
            modelContainer: container,
            keychain: FakeKeychain(),
            masterPassword: master,
            gate: gate,
            clipboard: clipboard,
            vault: FakeKeyVault(),
            consumerTools: FakeConsumerTools(),
            trashBatch: FakeRecentlyDeletedBatch(),
            entitlements: FakeEntitlements(tier: .unlimitedKeys),
            preferences: prefs,
            backups: backups,
            backupPassphrase: passphrase,
            dataLifecycle: FakeDataLifecycle(),
            cloudSync: FakeCloudSync(),
            appPrivacy: privacy
        )
        if !sessionLocked {
            // Production calls start before unlocking the UI. The neutral cold-
            // launch barrier is intentionally locked until that authoritative
            // preference load completes, so unlocked fixtures must do the same.
            await privacy.start()
        }
        return (env, gate, passphrase, clipboard, backups, prefs, sessionLock)
    }
}
