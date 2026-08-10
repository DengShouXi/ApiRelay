@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class ConsumerToolIconBackfillTests: XCTestCase {
    private var container: ModelContainer!
    private var tools: ConsumerToolService!

    override func setUp() async throws {
        container = try AppSchema.makeInMemoryContainer()
        let keychain = KeychainStore(accessGroup: nil, disableSynchronizableForTesting: true)
        let master = MasterPasswordService(keychain: keychain, calibratedIterations: 10_000)
        try? await master.reset()
        let gate = RevealGate(masterPassword: master) { _, _ in }
        tools = ConsumerToolService(modelContainer: container, gate: gate)
    }

    func testCreateToolFillsMissingIconSymbol() async throws {
        let id = try await tools.createTool(ConsumerToolDraft(name: "Cursor · 电脑 1", iconSymbol: nil))
        let list = try await tools.tools(includeHidden: true)
        let created = try XCTUnwrap(list.first { $0.id == id })
        XCTAssertEqual(created.iconSymbol, "cursorarrow")
    }

    func testEnsurePresetsSeededBackfillsHistoricalNilIcon() async throws {
        let repo = ConsumerToolRepository(modelContainer: container)
        let id = try await repo.insert(
            ConsumerToolDraft(name: "VS Code · 电脑 1", iconSymbol: nil, isPreset: false)
        )
        try await tools.ensurePresetsSeeded()
        let list = try await tools.tools(includeHidden: true)
        let tool = try XCTUnwrap(list.first { $0.id == id })
        XCTAssertEqual(tool.iconSymbol, "chevron.left.forwardslash.chevron.right")
    }

    func testEnsurePresetsSeededDoesNotOverwriteExistingIcon() async throws {
        let id = try await tools.createTool(
            ConsumerToolDraft(name: "Cursor", iconSymbol: "hammer")
        )
        try await tools.ensurePresetsSeeded()
        let list = try await tools.tools(includeHidden: true)
        let tool = try XCTUnwrap(list.first { $0.id == id })
        XCTAssertEqual(tool.iconSymbol, "hammer")
    }
}
