@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class CrossStoreTransactionJournalTests: XCTestCase {
    func testJournalPersistsPlansAndCommitDecisionAcrossInstancesThenClears() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL)
        let transactionID = try first.begin(.backupImport)
        let account = CrossStoreInsertedRecordPlan(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        let tool = CrossStoreInsertedRecordPlan(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        let key = CrossStoreKeyRollbackPlan(
            id: UUID(),
            accountId: account.id,
            createdAt: Date(timeIntervalSinceReferenceDate: 3_000)
        )
        let assignment = CrossStoreAssignmentRollbackPlan(
            keyId: key.id,
            consumerToolId: tool.id,
            createdAt: Date(timeIntervalSinceReferenceDate: 4_000)
        )
        try first.planInsertedAccount(account, transactionId: transactionID)
        try first.planInsertedTool(tool, transactionId: transactionID)
        try first.planInsertedKey(key, transactionId: transactionID)
        try first.planInsertedAssignment(assignment, transactionId: transactionID)

        let reopened = DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL)
        let applying = try XCTUnwrap(reopened.load())
        XCTAssertEqual(applying.transactionId, transactionID)
        XCTAssertEqual(applying.phase, .applying)
        XCTAssertEqual(applying.insertedAccounts, [account])
        XCTAssertEqual(applying.insertedTools, [tool])
        XCTAssertEqual(applying.insertedKeys, [key])
        XCTAssertEqual(applying.insertedAssignments, [assignment])

        try reopened.decideCommit(transactionId: transactionID)
        let committed = try XCTUnwrap(
            DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL).load()
        )
        XCTAssertEqual(committed.phase, .commitDecided)

        try DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL)
            .clear(transactionId: transactionID)
        let cleared = DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL)
        XCTAssertFalse(cleared.hasPendingTransaction())
        XCTAssertNil(try cleared.load())
    }

    func testVersionTwoMarkerWithoutPhaseLoadsAsApplying() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = CrossStoreTransactionRecord(
            kind: .createKey,
            insertedKeys: [CrossStoreKeyRollbackPlan(
                id: UUID(),
                accountId: UUID(),
                createdAt: Date(timeIntervalSinceReferenceDate: 10)
            )]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
                as? [String: Any]
        )
        object["version"] = 2
        object.removeValue(forKey: "phase")
        try FileManager.default.createDirectory(
            at: fixture.directory,
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: fixture.fileURL)

        let decoded = try XCTUnwrap(
            DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL).load()
        )
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.phase, .applying)
        XCTAssertEqual(decoded.insertedKeys, original.insertedKeys)
    }

    func testDuplicateAssignmentPairIsRejectedEvenWithDifferentTimestamps() {
        let keyID = UUID()
        let toolID = UUID()
        let record = CrossStoreTransactionRecord(
            kind: .backupImport,
            insertedAssignments: [
                CrossStoreAssignmentRollbackPlan(
                    keyId: keyID,
                    consumerToolId: toolID,
                    createdAt: Date(timeIntervalSinceReferenceDate: 1)
                ),
                CrossStoreAssignmentRollbackPlan(
                    keyId: keyID,
                    consumerToolId: toolID,
                    createdAt: Date(timeIntervalSinceReferenceDate: 2)
                ),
            ]
        )

        XCTAssertThrowsError(try record.validateForRecovery()) { error in
            guard case ApiRelayError.storageRecoveryFailed(_, let detail) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(detail, "duplicate_assignment_plan")
        }
    }

    func testWrongTransactionIdentifierCannotMutateOrClearMarker() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let journal = DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL)
        let transactionID = try journal.begin(.createKey)
        let wrongID = UUID()

        XCTAssertThrowsError(try journal.planInsertedKey(
            CrossStoreKeyRollbackPlan(
                id: UUID(),
                accountId: UUID(),
                createdAt: Date()
            ),
            transactionId: wrongID
        ))
        XCTAssertThrowsError(try journal.clear(transactionId: wrongID))
        XCTAssertEqual(try journal.load()?.transactionId, transactionID)
    }

    func testTwoInstancesCannotBothBeginForTheSamePath() async throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL)
        let second = DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL)

        let firstAttempt = Task.detached { () -> UUID? in
            try? first.begin(.createKey)
        }
        let secondAttempt = Task.detached { () -> UUID? in
            try? second.begin(.backupImport)
        }
        let identifiers = await [firstAttempt.value, secondAttempt.value].compactMap { $0 }

        XCTAssertEqual(identifiers.count, 1)
        let durable = try XCTUnwrap(first.load())
        XCTAssertEqual(durable.transactionId, identifiers[0])
        try first.clear(transactionId: durable.transactionId)
    }

    func testCommittedEraseCanDiscardCorruptMarker() throws {
        let fixture = makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.createDirectory(
            at: fixture.directory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fixture.fileURL)
        let journal = DurableCrossStoreTransactionJournal(fileURL: fixture.fileURL)
        XCTAssertTrue(journal.hasPendingTransaction())
        XCTAssertThrowsError(try journal.load())

        let gate = StorageMutationGate()
        XCTAssertTrue(try gate.sealForErase(resumingInterruptedErase: false))
        let authorization = try gate.mintCommittedEraseToken()
        try journal.discardForCommittedErase(authorization: authorization)
        XCTAssertFalse(journal.hasPendingTransaction())
        XCTAssertNil(try journal.load())
        try gate.completeEraseAndReopen()
    }

    private func makeFixture() -> (directory: URL, fileURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrossStoreJournalTests-\(UUID().uuidString)", isDirectory: true)
        return (
            directory,
            directory.appendingPathComponent("journal.json", isDirectory: false)
        )
    }
}

@MainActor
final class StorageMutationGateTests: XCTestCase {
    func testExclusiveWaitsForEarlierNormalMutationAndBlocksLaterNormalWork() async throws {
        let gate = StorageMutationGate()
        let earlier = try gate.beginNormal(operation: "earlier")
        let exclusiveTask = Task {
            try await gate.beginExclusive(operation: "exclusive")
        }
        try await waitUntil { gate.isCrossStoreExclusivePendingOrActive() }

        XCTAssertThrowsError(try gate.beginNormal(operation: "later"))
        earlier.finish()
        let exclusive = try await exclusiveTask.value
        XCTAssertThrowsError(try gate.beginNormal(operation: "during_exclusive"))
        exclusive.finish()

        let reopened = try gate.beginNormal(operation: "after")
        reopened.finish()
    }

    func testCancellingQueuedExclusiveDoesNotLeaveGhostFence() async throws {
        let gate = StorageMutationGate()
        let earlier = try gate.beginNormal(operation: "earlier")
        let cancelledTask = Task {
            try await gate.beginExclusive(operation: "cancelled")
        }
        try await waitUntil { gate.isCrossStoreExclusivePendingOrActive() }
        cancelledTask.cancel()
        do {
            _ = try await cancelledTask.value
            XCTFail("cancelled exclusive request must not receive a permit")
        } catch is CancellationError {
            // expected
        }
        XCTAssertFalse(gate.isCrossStoreExclusivePendingOrActive())
        earlier.finish()

        let normal = try gate.beginNormal(operation: "after_cancel")
        normal.finish()
    }

    func testCrossStoreRecoveryPermitMustFinishBeforeGateReopens() async throws {
        let gate = StorageMutationGate(crossStoreRecoveryPending: true)
        XCTAssertThrowsError(try gate.beginNormal(operation: "normal"))
        do {
            _ = try await gate.beginExclusive(operation: "ordinary_exclusive")
            XCTFail("ordinary exclusive work must not bypass startup recovery")
        } catch ApiRelayError.storageRecoveryFailed(_, let detail) {
            XCTAssertEqual(detail, "cross_store_recovery_pending")
        }

        let recovery = try await gate.beginCrossStoreRecoveryExclusive(
            operation: "startup_recovery"
        )
        XCTAssertThrowsError(try gate.completeCrossStoreRecoveryAndReopen())
        recovery.finish()
        try gate.completeCrossStoreRecoveryAndReopen()

        let normal = try gate.beginNormal(operation: "reopened")
        normal.finish()
    }

    func testRecoveryAuthorizedEraseClearsBothSealsOnlyAtCompletion() throws {
        let gate = StorageMutationGate(crossStoreRecoveryPending: true)
        XCTAssertTrue(try gate.sealForErase(resumingInterruptedErase: true))
        XCTAssertTrue(gate.isEraseSealed())
        XCTAssertTrue(gate.isCrossStoreRecoverySealed())
        _ = try gate.mintCommittedEraseToken()

        try gate.completeEraseAndReopen()
        XCTAssertFalse(gate.isEraseSealed())
        XCTAssertFalse(gate.isCrossStoreRecoverySealed())
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () -> Bool
    ) async throws {
        for _ in 0..<1_000 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("condition did not become true")
    }
}
