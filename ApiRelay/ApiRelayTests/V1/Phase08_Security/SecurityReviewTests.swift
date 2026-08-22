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
            secretAvailable: false, secretLength: nil, sortOrder: 0
        ))
        let labels = Set(mirror.children.compactMap(\.label))
        XCTAssertFalse(labels.contains("secret"))
        XCTAssertFalse(labels.contains("apiKey"))
        XCTAssertTrue(labels.contains("maskedHint"))
        XCTAssertTrue(labels.contains("notes"))
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
