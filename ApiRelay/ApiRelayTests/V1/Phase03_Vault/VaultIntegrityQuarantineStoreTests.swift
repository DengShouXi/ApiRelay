@preconcurrency import XCTest
@testable import ApiRelay

nonisolated private enum QuarantineStoreInjectedError: Error {
    case directorySync
}

nonisolated private final class QuarantineDirectorySyncSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = false

    func setShouldFail(_ value: Bool) {
        lock.lock()
        shouldFail = value
        lock.unlock()
    }

    func sync(_ url: URL) throws {
        lock.lock()
        let fail = shouldFail
        lock.unlock()
        if fail {
            throw QuarantineStoreInjectedError.directorySync
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

final class VaultIntegrityQuarantineStoreTests: XCTestCase {
    func testDurableQuarantinePersistsAcrossStoreInstances() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let first = makeStore(fixture)

        first.quarantine(operation: "create_key", detail: "rollback_failed")

        let reopened = makeStore(fixture)
        XCTAssertEqual(
            reopened.currentIncident(),
            VaultIntegrityIncident(
                operation: "create_key",
                detail: "rollback_failed"
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testLegacyDefaultsIncidentMigratesToDurableFile() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set([
            "operation": "legacy_operation",
            "detail": "legacy_detail",
            "recordedAt": "2026-09-23T00:00:00Z",
        ], forKey: fixture.key)
        let sut = makeStore(fixture)

        XCTAssertEqual(
            sut.currentIncident(),
            VaultIntegrityIncident(
                operation: "legacy_operation",
                detail: "legacy_detail"
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.fileURL.path))

        fixture.defaults.removeObject(forKey: fixture.key)
        _ = fixture.defaults.synchronize()
        XCTAssertEqual(
            makeStore(fixture).currentIncident(),
            VaultIntegrityIncident(
                operation: "legacy_operation",
                detail: "legacy_detail"
            )
        )
    }

    func testCorruptDurableMarkerFailsClosed() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fixture.fileURL)

        XCTAssertEqual(
            makeStore(fixture).currentIncident(),
            VaultIntegrityIncident(
                operation: "integrity_quarantine_recovery",
                detail: "durable_record_unreadable"
            )
        )
    }

    func testDurableClearRemovesFileAndLegacyMirror() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let sut = makeStore(fixture)
        sut.quarantine(operation: "update_key", detail: "compensation_failed")
        let authorization = try makeCommittedEraseAuthorization()

        try sut.clearAfterCommittedFullEraseDurably(authorization: authorization)

        XCTAssertNil(sut.currentIncident())
        XCTAssertNil(fixture.defaults.object(forKey: fixture.key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        XCTAssertNil(makeStore(fixture).currentIncident())
    }

    func testClearFailureRestoresQuarantineBeforeThrowing() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let syncSwitch = QuarantineDirectorySyncSwitch()
        let sut = VaultIntegrityQuarantineStore(
            defaults: fixture.defaults,
            key: fixture.key,
            fileURL: fixture.fileURL,
            directorySync: { try syncSwitch.sync($0) }
        )
        let expected = VaultIntegrityIncident(
            operation: "delete_key",
            detail: "metadata_restore_failed"
        )
        sut.quarantine(operation: expected.operation, detail: expected.detail)
        syncSwitch.setShouldFail(true)
        let authorization = try makeCommittedEraseAuthorization()

        XCTAssertThrowsError(
            try sut.clearAfterCommittedFullEraseDurably(authorization: authorization)
        ) { error in
            guard case ApiRelayError.storageRecoveryFailed(let operation, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(operation, "integrity_quarantine_clear")
        }

        XCTAssertEqual(sut.currentIncident(), expected)
        XCTAssertNotNil(fixture.defaults.object(forKey: fixture.key))
        XCTAssertEqual(makeStore(fixture).currentIncident(), expected)
    }

    func testCommittedClearRejectsCapabilityAfterIssuingGateReopens() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let sut = makeStore(fixture)
        let expected = VaultIntegrityIncident(
            operation: "create_key",
            detail: "compensation_failed"
        )
        sut.quarantine(operation: expected.operation, detail: expected.detail)
        let gate = StorageMutationGate()
        XCTAssertTrue(try gate.sealForErase(resumingInterruptedErase: false))
        let authorization = try gate.mintCommittedEraseToken()
        try gate.completeEraseAndReopen()

        XCTAssertThrowsError(
            try sut.clearAfterCommittedFullEraseDurably(authorization: authorization)
        ) { error in
            guard case ApiRelayError.storageRecoveryFailed(let operation, let detail) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(operation, "integrity_quarantine_committed_erase")
            XCTAssertEqual(detail, "invalid_committed_erase_capability")
        }
        XCTAssertEqual(sut.currentIncident(), expected)
    }

    func testCommittedEraseCapabilityRequiresSealAndRejectsAnotherGate() throws {
        let issuer = StorageMutationGate()
        XCTAssertThrowsError(try issuer.mintCommittedEraseToken()) { error in
            guard case ApiRelayError.storageRecoveryFailed(let operation, let detail) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(operation, "erase_capability_issue")
            XCTAssertEqual(detail, "erase_not_sealed")
        }

        XCTAssertTrue(try issuer.sealForErase(resumingInterruptedErase: false))
        let authorization = try issuer.mintCommittedEraseToken()
        let otherGate = StorageMutationGate(erasePending: true)

        XCTAssertThrowsError(
            try otherGate.validateCommittedEraseToken(
                authorization,
                operation: "cross_gate_committed_erase"
            )
        ) { error in
            guard case ApiRelayError.storageRecoveryFailed(let operation, let detail) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(operation, "cross_gate_committed_erase")
            XCTAssertEqual(detail, "invalid_committed_erase_capability")
        }
        XCTAssertNoThrow(
            try issuer.validateCommittedEraseToken(
                authorization,
                operation: "issuing_gate_committed_erase"
            )
        )
    }

    func testProductionBoundStoreRejectsTokenFromUnrelatedSealedGate() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let productionGate = StorageMutationGate(erasePending: true)
        let unrelatedGate = StorageMutationGate(erasePending: true)
        let sut = VaultIntegrityQuarantineStore(
            defaults: fixture.defaults,
            key: fixture.key,
            fileURL: fixture.fileURL,
            committedEraseGate: productionGate
        )
        let expected = VaultIntegrityIncident(
            operation: "backup_import",
            detail: "compensation_failed"
        )
        sut.quarantine(operation: expected.operation, detail: expected.detail)
        let wrongAuthorization = try unrelatedGate.mintCommittedEraseToken()

        XCTAssertThrowsError(
            try sut.clearAfterCommittedFullEraseDurably(
                authorization: wrongAuthorization
            )
        ) { error in
            guard case ApiRelayError.storageRecoveryFailed(let operation, let detail) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(operation, "integrity_quarantine_committed_erase")
            XCTAssertEqual(detail, "invalid_committed_erase_capability")
        }
        XCTAssertEqual(sut.currentIncident(), expected)

        let correctAuthorization = try productionGate.mintCommittedEraseToken()
        try sut.clearAfterCommittedFullEraseDurably(
            authorization: correctAuthorization
        )
        XCTAssertNil(sut.currentIncident())
    }

    private func makeStore(
        _ fixture: QuarantineStoreFixture
    ) -> VaultIntegrityQuarantineStore {
        VaultIntegrityQuarantineStore(
            defaults: fixture.defaults,
            key: fixture.key,
            fileURL: fixture.fileURL
        )
    }

    private func makeCommittedEraseAuthorization() throws -> CommittedEraseToken {
        let gate = StorageMutationGate()
        XCTAssertTrue(try gate.sealForErase(resumingInterruptedErase: false))
        return try gate.mintCommittedEraseToken()
    }

    private func makeFixture() throws -> QuarantineStoreFixture {
        let identifier = UUID().uuidString
        let suiteName = "ApiRelay.VaultIntegrityQuarantineStoreTests.\(identifier)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ApiRelay-VaultIntegrityQuarantineStoreFixture-\(identifier)",
                isDirectory: true
            )
        return QuarantineStoreFixture(
            suiteName: suiteName,
            defaults: defaults,
            key: "quarantine-test-\(identifier)",
            directory: directory,
            fileURL: directory.appendingPathComponent(
                "quarantine-v1.json",
                isDirectory: false
            )
        )
    }
}

nonisolated private struct QuarantineStoreFixture {
    let suiteName: String
    let defaults: UserDefaults
    let key: String
    let directory: URL
    let fileURL: URL

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
