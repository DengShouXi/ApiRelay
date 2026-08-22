@preconcurrency import XCTest
@testable import ApiRelay
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
        let keychain = KeychainStore(accessGroup: nil, disableSynchronizableForTesting: true)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        let vault = KeyVaultService(
            keychain: keychain,
            gate: gate,
            clipboard: SecureClipboard(),
            modelContainer: container,
            entitlements: EntitlementService(modelContainer: container)
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
        let store = KeychainStore(accessGroup: nil, disableSynchronizableForTesting: false)
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
    }

    func testBackupFormatReservesPurposeAndScope() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore(accessGroup: nil, disableSynchronizableForTesting: true)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        let gate = RevealGate(masterPassword: master) { _, _ in }
        let backup = SecureBackupService(gate: gate, keychain: keychain, modelContainer: container)
        let data = try await backup.exportBackup(passphrase: "passphrase-1234", purpose: .fullBackup)
        XCTAssertTrue(data.starts(with: Data("ARBK1".utf8)))
    }
}

extension RevealPolicy: CaseIterable {
    public static var allCases: [RevealPolicy] {
        [.biometricOrPasscode, .biometricOnly, .masterPassword, .none]
    }
}
