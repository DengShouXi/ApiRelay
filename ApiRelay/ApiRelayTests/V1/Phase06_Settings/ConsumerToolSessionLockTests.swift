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
        let confirmsBefore = await gate.journal.calls.filter { $0 == "confirmMandatory" }.count

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
        let confirmsAfter = await gate.journal.calls.filter { $0 == "confirmMandatory" }.count
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
}
