@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class GroupingTests: XCTestCase {
    func testSharedKeyCountedOnceAcrossModes() {
        let account = UUID()
        let toolA = UUID()
        let toolB = UUID()
        let sharedKey = makeKey(id: UUID(), accountId: account, tools: [toolA, toolB])
        let exclusive = makeKey(id: UUID(), accountId: account, tools: [toolA])
        let unassigned = makeKey(id: UUID(), accountId: account, tools: [])
        let keys = [sharedKey, exclusive, unassigned]

        let accounts = [UpstreamAccountDTO(
            id: account, platform: "openai", customPlatformName: nil,
            displayName: "OpenAI", customBaseURL: nil, hasManagementCredential: false,
            createdAt: Date(), updatedAt: Date(), sortOrder: 0
        )]
        let tools = [
            ConsumerToolDTO(id: toolA, name: "VS Code", iconSymbol: nil, isPreset: true, isHidden: false, createdAt: Date(), sortOrder: 0),
            ConsumerToolDTO(id: toolB, name: "Cursor", iconSymbol: nil, isPreset: true, isHidden: false, createdAt: Date(), sortOrder: 1),
        ]

        let byPlatform = KeyGrouping.group(keys: keys, accounts: accounts, tools: tools, mode: .byPlatform)
        let byConsumer = KeyGrouping.group(keys: keys, accounts: accounts, tools: tools, mode: .byConsumer)

        XCTAssertEqual(KeyGrouping.uniqueKeyCount(in: byPlatform), 3)
        XCTAssertEqual(KeyGrouping.uniqueKeyCount(in: byConsumer), 3)
        XCTAssertEqual(
            KeyGrouping.uniqueKeyCount(in: byConsumer),
            KeyGrouping.uniqueKeyCount(in: byPlatform)
        )
        XCTAssertTrue(byConsumer.contains { $0.kind == .shared })
        XCTAssertTrue(byConsumer.contains { $0.kind == .unassigned })
    }

    func testAssignmentDedupDoesNotInflateKind() async throws {
        let container = try AppSchema.makeInMemoryContainer()
        let repo = KeyAssignmentRepository(modelContainer: container)
        let keyId = UUID()
        let toolId = UUID()
        let ctx = ModelContext(container)
        ctx.insert(KeyAssignment(keyId: keyId, consumerToolId: toolId))
        ctx.insert(KeyAssignment(keyId: keyId, consumerToolId: toolId))
        try ctx.save()
        let kind = try await repo.assignmentKind(keyId: keyId)
        if case .exclusive(let id) = kind {
            XCTAssertEqual(id, toolId)
        } else {
            XCTFail("expected exclusive after dedupe")
        }
    }

    private func makeKey(id: UUID, accountId: UUID, tools: [UUID]) -> KeyRecordDTO {
        KeyRecordDTO(
            id: id,
            accountId: accountId,
            consumerToolIds: tools,
            displayName: "k",
            maskedHint: "abcd",
            origin: .manualEntry,
            providerKeyRef: nil,
            lifecycle: .active,
            health: KeyHealthDTO(state: .unknown, lastCheckedAt: nil, lastCheckNote: nil),
            deletedAt: nil,
            purgeAfter: nil,
            spendLimit: nil,
            secretAvailable: true
        )
    }
}
