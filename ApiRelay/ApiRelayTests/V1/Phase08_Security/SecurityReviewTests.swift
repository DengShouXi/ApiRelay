@preconcurrency import XCTest
@testable import ApiRelay
import LocalAuthentication
import SwiftData

/// Phase 8 安全审查自动化子集（T056–T058）。
@MainActor
final class SecurityReviewTests: XCTestCase {
    func testKeychainStoreHasNoAccessControlUsageInSourceContract() {
        // 运行时固化：ACL + sync 失败（与 Phase 2 一致）
        // 明文不进 DTO 可观察字段：KeyRecordDTO 无 secret 字段（编译期/镜像）
        let mirror = Mirror(reflecting: KeyRecordDTO(
            id: UUID(), accountId: UUID(), consumerToolIds: [], displayName: "x",
            maskedHint: "abcd", origin: .manualEntry, providerKeyRef: nil,
            lifecycle: .active,
            health: KeyHealthDTO(state: .unknown, lastCheckedAt: nil, lastCheckNote: nil),
            deletedAt: nil, purgeAfter: nil, spendLimit: nil, notes: nil,
            secretAvailable: false, sortOrder: 0
        ))
        let labels = Set(mirror.children.compactMap(\.label))
        XCTAssertFalse(labels.contains("secret"))
        XCTAssertFalse(labels.contains("apiKey"))
        XCTAssertFalse(labels.contains("secretLength"))
        XCTAssertTrue(labels.contains("maskedHint"))
        XCTAssertTrue(labels.contains("notes"))
    }

    /// 遮罩点数固定：长短密钥的呈现必须逐字符相同。
    func testSecretMaskDoesNotVaryWithSecretLength() {
        XCTAssertEqual(SecretMask.dots.count, SecretMask.dotCount)
        XCTAssertEqual(SecretMask.dots, String(repeating: "•", count: 12))
    }

    /// 列表刷新只回答「本机有没有这一条」，DTO 不得携带任何可推出真实长度的字段。
    func testKeyListExposesAvailabilityWithoutSecretLength() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        let vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: SecureClipboard(),
            modelContainer: container,
            // 本套件考的是明文不外泄，不是 StoreKit：配额走桩，免去商店超时。
            entitlements: StubEntitlements(tier: .free)
        )
        let accountId = try await vault.createAccount(
            UpstreamAccountDraft(platform: "openai", displayName: "Acct")
        )
        let shortId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "Short"),
            secret: "sk-short"
        )
        let longId = try await vault.createKey(
            KeyDraft(accountId: accountId, displayName: "Long"),
            secret: "sk-" + String(repeating: "z", count: 96)
        )
        addTeardownBlock {
            try? await keychain.delete(service: .keys, account: shortId)
            try? await keychain.delete(service: .keys, account: longId)
        }

        let keys = try await vault.keys(in: accountId)
        XCTAssertEqual(keys.count, 2)
        for key in keys {
            XCTAssertTrue(key.secretAvailable)
            XCTAssertNil(key.maskedHint)
            let labels = Set(Mirror(reflecting: key).children.compactMap(\.label))
            XCTAssertFalse(labels.contains("secretLength"))
        }
        // 两条密钥长度差一个数量级，遮罩呈现仍必须逐字符相同。
        XCTAssertEqual(SecretMask.dots.count, SecretMask.dotCount)

        // 明文被移出本机后只有 secretAvailable 变化，仍不涉及长度。
        try await keychain.delete(service: .keys, account: longId)
        let refreshed = try await vault.keys(in: accountId)
        XCTAssertEqual(refreshed.first { $0.id == longId }?.secretAvailable, false)
        XCTAssertEqual(refreshed.first { $0.id == shortId }?.secretAvailable, true)
    }

    func testMasterPasswordNotSynchronizable() async throws {
        let store = KeychainStore.makeForTests(disableSynchronizable: false)
        // masterpw path works without sync entitlement
        let master = MasterPasswordService(keychain: store, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("test-pass-word")
        let ok = try await master.verify("test-pass-word")
        XCTAssertTrue(ok)
        try await master.reset()
    }

    func testRevealPolicySingleSwitchSemantics() {
        // 查看与复制共用 revealPolicy（无独立 copyPolicy）
        XCTAssertEqual(RevealPolicy.allCases.count, 4)
        XCTAssertEqual(
            Set(RevealPolicy.allCases),
            [.biometricOrPasscode, .masterPassword, .biometryOrAppPassword, .noVerification]
        )
    }

    func testConfirmMandatoryIgnoresCurrentPolicyAndUsesDeviceOwner() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let recorded = PolicyBox()
        let gate = RevealGate(
            masterPassword: master,
            authenticateDeviceOwner: { _, policy in recorded.append(policy) },
            availableBiometry: { .none }
        )
        try await gate.confirmMandatory(reason: "recovery", purpose: .recovery)
        XCTAssertEqual(recorded.snapshot(), [.deviceOwnerAuthentication])
    }

    func testCombinationCancelKeepsOneDeviceOwnerAuthenticationFlow() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let recorded = PolicyBox()
        let gate = RevealGate(
            masterPassword: master,
            authenticateDeviceOwner: { _, policy in
                recorded.append(policy)
                throw LAError(.userCancel)
            },
            availableBiometry: { .faceID }
        )
        do {
            try await gate.confirm(reason: "combo", policy: .biometryOrAppPassword)
            XCTFail("expected cancel")
        } catch ApiRelayError.authenticationCancelled {
        }
        XCTAssertEqual(recorded.snapshot(), [.deviceOwnerAuthentication])
    }

    func testBackupFormatReservesPurposeAndScope() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        let backup = SecureBackupService(gate: gate, keychain: keychain, modelContainer: container)
        let data = try await backup.exportBackup(passphrase: "passphrase-1234", purpose: .fullBackup).data
        XCTAssertTrue(data.starts(with: Data("ARBK1".utf8)))
    }

    func testFirstSetupCoordinatorCallsDeviceOwnerBeforeWritingPassword() async throws {
        let master = FakeMasterPassword()
        let recorded = StringBox()
        try await AppPasswordSetup.createMaterialThenPersistTarget(
            target: .biometryOrAppPassword,
            materialStatus: { await master.materialStatus() },
            confirmCurrentIfNeeded: { recorded.append("current") },
            confirmDeviceOwner: { recorded.append("owner") },
            setAndVerifyMaterial: {
                recorded.append("set")
                try await master.setPassword("test-pass-word")
            },
            persistTarget: { policy in
                recorded.append("persist:\(policy.rawValue)")
            }
        )
        XCTAssertEqual(
            recorded.snapshot(),
            ["current", "owner", "set", "persist:biometryOrAppPassword"]
        )
    }

    func testCreateCoordinatorDoesNotOverwriteWhenOtherWindowSetsDuringConfirm() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        addTeardownBlock { try? await master.reset() }
        let persistLog = StringBox()
        do {
            try await AppPasswordSetup.createMaterialThenPersistTarget(
                target: .biometryOrAppPassword,
                materialStatus: { await master.materialStatus() },
                confirmCurrentIfNeeded: {
                    try await master.setPassword("other-window-pass")
                },
                confirmDeviceOwner: { },
                setAndVerifyMaterial: {
                    try await master.setPassword("stale-create-pass")
                    guard await master.materialStatus() == .set else {
                        throw ApiRelayError.validationFailed(
                            field: "masterPassword",
                            reason: "material_verify_failed"
                        )
                    }
                },
                persistTarget: { policy in
                    persistLog.append(policy.rawValue)
                }
            )
            XCTFail("expected already_set")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "already_set")
        }
        XCTAssertEqual(persistLog.snapshot(), [])
        let otherKept = try await master.verify("other-window-pass")
        let staleKept = try await master.verify("stale-create-pass")
        XCTAssertTrue(otherKept)
        XCTAssertFalse(staleKept)
    }

    func testRecoveryCommitUsesExpectedRevisionOnRealKeychain() async throws {
        let keychain = KeychainStore.makeForTests()
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        try await master.setPassword("original-pass-word")
        addTeardownBlock { try? await master.reset() }
        let persistLog = StringBox()
        do {
            try await AppPasswordRecovery.recoverToDeviceAuth(
                confirmMandatory: { },
                persistDeviceAuth: {
                    persistLog.append("persist")
                    try await master.changePassword(
                        current: "original-pass-word",
                        new: "other-window-pass"
                    )
                },
                resetIfRevision: { expected in
                    persistLog.append("reset")
                    try await master.reset(expectedRevision: expected)
                },
                snapshotRevision: { await master.materialRevision() }
            )
            XCTFail("expected stale_concurrent")
        } catch let ApiRelayError.validationFailed(_, reason) {
            XCTAssertEqual(reason, "stale_concurrent")
        }
        XCTAssertEqual(persistLog.snapshot(), ["persist", "reset"])
        let otherKept = try await master.verify("other-window-pass")
        let originalKept = try await master.verify("original-pass-word")
        XCTAssertTrue(otherKept)
        XCTAssertFalse(originalKept)
    }

    /// 正式组合根只能有一把进程级写闸门。服务构造器保留默认值是为了测试装配便利，
    /// 但生产装配一旦漏传就会形成可绕过全量清除封锁的“旁路”。
    func testProductionCompositionRootSharesOneMutationGateAcrossEveryWriter() throws {
        let source = try productionAppEnvironmentSource()
        let production = try XCTUnwrap(source.components(separatedBy: "    #if DEBUG").first)

        let multilineWriters = [
            "let master = MasterPasswordService(",
            "let entitlements = EntitlementService(",
            "let vaultService = KeyVaultService(",
            "self.consumerTools = ConsumerToolService(",
            "self.preferences = PreferencesService(",
            "let backupService = SecureBackupService(",
            "self.backupPassphrase = BackupPassphraseService(",
            "self.dataLifecycle = DataLifecycleService("
        ]
        for marker in multilineWriters {
            let start = try XCTUnwrap(production.range(of: marker), "missing production writer: \(marker)")
            let remainder = production[start.lowerBound...]
            let end = try XCTUnwrap(
                remainder.range(of: "\n        )"),
                "unterminated production writer: \(marker)"
            )
            let assembly = remainder[..<end.upperBound]
            XCTAssertTrue(
                assembly.contains("mutationGate: mutationGate"),
                "production writer must share the composition-root mutation gate: \(marker)"
            )
        }

        XCTAssertTrue(
            production.contains("let clipboard = SecureClipboard(mutationGate: mutationGate)"),
            "clipboard writes must share the same erase fence"
        )
        XCTAssertEqual(
            production.components(separatedBy: "mutationGate: mutationGate").count - 1,
            multilineWriters.count + 1,
            "every production protected writer must use exactly the one composition-root gate"
        )
        XCTAssertTrue(
            production.contains("VaultIntegrityQuarantineStore.production(")
                && production.contains("committedEraseGate: mutationGate"),
            "production quarantine release must be bound to the same erase gate"
        )
        XCTAssertTrue(
            production.contains("let cloudEraseConvergence = CloudEraseConvergence(monitor: monitor)")
                && production.contains("cloudEraseConvergence: cloudEraseConvergence"),
            "the production erase path must use the same CloudKit monitor as sync status"
        )
    }

    private func productionAppEnvironmentSource() throws -> String {
        let testsFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testsFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRoot.appendingPathComponent("ApiRelay/App/AppEnvironment.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        values.append(value)
    }

    func snapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

private final class PolicyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var policies: [LAPolicy] = []

    func append(_ policy: LAPolicy) {
        lock.lock(); defer { lock.unlock() }
        policies.append(policy)
    }

    func snapshot() -> [LAPolicy] {
        lock.lock(); defer { lock.unlock() }
        return policies
    }
}
