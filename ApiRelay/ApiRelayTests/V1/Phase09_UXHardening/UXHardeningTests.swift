@preconcurrency import XCTest
@testable import ApiRelay

/// Phase 9（v1.9）可用性加固契约子集：软删除字段 + 无明文。
/// 历史实现主要落在 Vault/Data；本目录补齐与小迭代对应的测试落点。
@MainActor
final class UXHardeningTests: XCTestCase {
    func testKeyRecordDTOExposesSoftDeleteFieldsWithoutSecret() {
        let dto = KeyRecordDTO(
            id: UUID(),
            accountId: UUID(),
            consumerToolIds: [],
            displayName: "phase9",
            maskedHint: "abcd",
            origin: .manualEntry,
            providerKeyRef: nil,
            lifecycle: .softDeleted,
            health: KeyHealthDTO(state: .unknown, lastCheckedAt: nil, lastCheckNote: nil),
            deletedAt: Date(),
            purgeAfter: Date().addingTimeInterval(30 * 24 * 3600),
            spendLimit: nil,
            notes: nil,
            secretAvailable: false,
            sortOrder: 0
        )
        let labels = Set(Mirror(reflecting: dto).children.compactMap(\.label))
        XCTAssertTrue(labels.contains("deletedAt"))
        XCTAssertTrue(labels.contains("purgeAfter"))
        XCTAssertTrue(labels.contains("lifecycle"))
        XCTAssertFalse(labels.contains("secret"))
        XCTAssertFalse(labels.contains("apiKey"))
        XCTAssertEqual(dto.lifecycle, .softDeleted)
        XCTAssertNotNil(dto.deletedAt)
        XCTAssertNotNil(dto.purgeAfter)
    }

    func testSoftDeletedLifecycleIsDistinctFromActive() {
        XCTAssertNotEqual(KeyLifecycle.active, KeyLifecycle.softDeleted)
    }
}
