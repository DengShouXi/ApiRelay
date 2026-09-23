@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class ConsumerToolSessionLockTests: XCTestCase {
    private var container: ModelContainer!
    private var gate: FakeRevealGate!
    private var box: SessionLockBox!
    private var tools: ConsumerToolService!

    override func setUp() async throws {
        container = try AppSchema.makeInMemoryContainer()
        gate = FakeRevealGate()
        box = SessionLockBox()
        tools = ConsumerToolService(modelContainer: container, gate: gate, sessionLock: box)
    }

    func testSessionLockRejectsCreateUpdateDeleteAndRestore() async throws {
        box.setLocked(false)
        let id = try await tools.createTool(ConsumerToolDraft(name: "Open"))
        try await tools.deleteTool(id: id)
        box.setLocked(true)
        let confirmsBefore = await gate.journal.calls.filter { $0 == "confirm" || $0 == "confirmMandatory" }.count

        do {
            _ = try await tools.createTool(ConsumerToolDraft(name: "Locked"))
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            try await tools.updateTool(id: id, patch: ConsumerToolPatch(name: "Nope"))
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            try await tools.restoreTool(id: id)
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            try await tools.permanentlyDeleteTool(id: id)
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        do {
            try await tools.reorderTools(orderedIds: [id])
            XCTFail("expected sessionLocked")
        } catch ApiRelayError.sessionLocked {
        }
        let confirmsAfter = await gate.journal.calls.filter { $0 == "confirm" || $0 == "confirmMandatory" }.count
        XCTAssertEqual(confirmsBefore, confirmsAfter, "锁住时不得先弹门闩")
    }

    func testSessionLockSkipsExpiredToolPurge() async throws {
        box.setLocked(false)
        let id = try await tools.createTool(ConsumerToolDraft(name: "Expired"))
        try await tools.deleteTool(id: id)
        let ctx = ModelContext(container)
        let rows = try ctx.fetch(FetchDescriptor<ConsumerTool>())
        let row = try XCTUnwrap(rows.first { $0.id == id })
        row.purgeAfter = Date.distantPast
        try ctx.save()

        box.setLocked(true)
        try await tools.purgeExpiredDeletedTools()
        let trash = try await tools.recentlyDeletedTools()
        XCTAssertEqual(trash.map(\.id), [id])

        box.setLocked(false)
        try await tools.purgeExpiredDeletedTools()
        let empty = try await tools.recentlyDeletedTools()
        XCTAssertTrue(empty.isEmpty)
    }

    func testRenameConfirmsButAvatarOnlyDoesNot() async throws {
        let prefs = UserPreferencesRepository(modelContainer: container)
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        try await prefs.update(patch)
        box.setLocked(false)
        let id = try await tools.createTool(ConsumerToolDraft(name: "Open"))
        var journal = await gate.journal
        XCTAssertEqual(journal.callCount("confirm"), 0)

        var avatar = ConsumerToolPatch()
        avatar.updatesAvatar = true
        avatar.avatarSymbol = "hammer"
        avatar.avatarColor = "plum"
        try await tools.updateTool(id: id, patch: avatar)
        journal = await gate.journal
        XCTAssertEqual(journal.callCount("confirm"), 0)

        var rename = ConsumerToolPatch()
        rename.name = "Renamed"
        try await tools.updateTool(id: id, patch: rename)
        journal = await gate.journal
        XCTAssertEqual(journal.callCount("confirm"), 1)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
    }
}

extension ConsumerToolSessionLockTests {
    func testCreateInvalidatedAtRepositoryCommitPerformsZeroWrites() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let barrier = CommitBarrierSessionLock()
        let service = ConsumerToolService(
            modelContainer: local,
            gate: FakeRevealGate(),
            sessionLock: barrier
        )
        barrier.blockNextCommit()

        // SwiftData may execute a ModelActor commit on the main executor on
        // iOS. Keep the waiter/release off MainActor so the synchronous test
        // barrier cannot deadlock the continuation that releases it.
        let revoke = Task.detached {
            await barrier.waitUntilCommitIsBlocked()
            barrier.invalidateAuthorizationLeases()
            barrier.releaseCommit()
        }
        let create = Task {
            try await service.createTool(ConsumerToolDraft(name: "Must Not Persist"))
        }
        await revoke.value

        do {
            _ = try await create.value
            XCTFail("stale lease must not enter the SwiftData commit")
        } catch ApiRelayError.sessionLocked {
            // expected
        }
        let stored = try await ConsumerToolRepository(modelContainer: local)
            .fetchAll(includeHidden: true, includeDeleted: true)
        XCTAssertTrue(stored.isEmpty)
    }

    func testPermanentDeleteInvalidatedAtCommitKeepsToolAndAssignmentsTogether() async throws {
        let local = try AppSchema.makeInMemoryContainer()
        let barrier = CommitBarrierSessionLock()
        let service = ConsumerToolService(
            modelContainer: local,
            gate: FakeRevealGate(),
            sessionLock: barrier
        )
        let toolID = try await service.createTool(ConsumerToolDraft(name: "Keep Together"))
        let keyID = UUID()
        try await KeyAssignmentRepository(modelContainer: local).add(
            keyId: keyID,
            consumerToolId: toolID
        )
        try await service.deleteTool(id: toolID)

        barrier.blockNextCommit()
        let revoke = Task.detached {
            await barrier.waitUntilCommitIsBlocked()
            barrier.invalidateAuthorizationLeases()
            barrier.releaseCommit()
        }
        let deletion = Task {
            try await service.permanentlyDeleteTool(id: toolID)
        }
        await revoke.value

        do {
            try await deletion.value
            XCTFail("stale lease must not delete either side of the relation")
        } catch ApiRelayError.sessionLocked {
            // expected
        }
        let storedTool = try await ConsumerToolRepository(modelContainer: local).fetch(id: toolID)
        let storedKeys = try await KeyAssignmentRepository(modelContainer: local)
            .fetchKeyIDs(consumerToolId: toolID)
        XCTAssertNotNil(storedTool)
        XCTAssertEqual(storedKeys, [keyID])
    }

    func testToolDeleteRestorePermanentWiring() async throws {
        let ops = ["delete", "restore", "permanent"]
        for op in ops {
            for mode in ["cancel", "master", "lock"] {
                try await runToolWiring(op: op, mode: mode)
            }
        }
    }

    private func runToolWiring(op: String, mode: String) async throws {
        let local = try AppSchema.makeInMemoryContainer()
        var setup = PreferencesPatch()
        setup.revealPolicy = .noVerification
        try await UserPreferencesRepository(modelContainer: local).update(setup)
        let setupService = ConsumerToolService(modelContainer: local, gate: FakeRevealGate())
        let id = try await setupService.createTool(ConsumerToolDraft(name: "T"))
        if op == "restore" || op == "permanent" {
            try await setupService.deleteTool(id: id)
        }
        var live = PreferencesPatch()
        live.revealPolicy = mode == "master" ? .masterPassword : .biometricOrPasscode
        try await UserPreferencesRepository(modelContainer: local).update(live)
        let fake = FakeRevealGate()
        let box = SessionLockBox()
        if mode == "cancel" {
            await fake.fail("confirm", with: .authenticationCancelled)
        }
        if mode == "lock" {
            box.setLocked(true)
        }
        let service = ConsumerToolService(modelContainer: local, gate: fake, sessionLock: box)
        do {
            switch op {
            case "delete":
                try await service.deleteTool(id: id)
            case "restore":
                try await service.restoreTool(id: id)
            default:
                try await service.permanentlyDeleteTool(id: id)
            }
            XCTFail("\(op) \(mode) should fail")
        } catch let error as ApiRelayError {
            switch (mode, error) {
            case ("cancel", .authenticationCancelled):
                break
            case ("master", .validationFailed(_, let reason))
                where reason == "master_password_prompt_required":
                break
            case ("lock", .sessionLocked):
                break
            default:
                XCTFail("\(op) \(mode) \(error)")
            }
        }
        if op == "delete" {
            let ids = try await service.tools(includeHidden: true).map(\.id)
            XCTAssertEqual(ids, [id])
        } else {
            let ids = try await service.recentlyDeletedTools().map(\.id)
            XCTAssertEqual(ids, [id])
        }
        if mode == "lock" {
            let journal = await fake.journal
            XCTAssertEqual(journal.callCount("confirm"), 0)
            XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        }
    }

    func testCombinationPasswordUsesExplicitEntry() async throws {
        var patch = PreferencesPatch()
        patch.revealPolicy = .biometryOrAppPassword
        try await UserPreferencesRepository(modelContainer: container).update(patch)
        let id = try await tools.createTool(ConsumerToolDraft(name: "Combo"))
        try await tools.deleteTool(id: id, appPassword: "combo-pass-word")
        let journal = await gate.journal
        XCTAssertEqual(journal.callCount("confirmCombinationWithAppPassword"), 1)
        XCTAssertEqual(journal.callCount("confirm"), 0)
        XCTAssertEqual(journal.callCount("confirmMandatory"), 0)
        XCTAssertEqual(journal.callCount("confirmWithMasterPassword"), 0)
    }
}
