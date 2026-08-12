@preconcurrency import XCTest
@testable import ApiRelay
import SwiftData

@MainActor
final class GroupingTests: XCTestCase {
    func testPlatformModeIncludesAccountWithoutKeys() {
        let accountId = UUID()
        let accounts = [UpstreamAccountDTO(
            id: accountId, platform: "openai", customPlatformName: nil,
            displayName: "Empty Acc", customBaseURL: nil, hasManagementCredential: false,
            notes: nil, createdAt: Date(), updatedAt: Date(), sortOrder: 0,
            deletedAt: nil, purgeAfter: nil
        )]
        let sections = KeyGrouping.group(keys: [], accounts: accounts, tools: [], mode: .byPlatform)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.kind, .platform(accountId: accountId, title: "Empty Acc"))
        XCTAssertTrue(sections.first?.keys.isEmpty == true)
    }

    func testConsumerModeIncludesToolWithoutKeys() {
        let toolId = UUID()
        let tools = [ConsumerToolDTO(
            id: toolId, name: "Empty Tool", iconSymbol: nil,
            isPreset: false, isHidden: false, notes: nil, createdAt: Date(), sortOrder: 0,
            deletedAt: nil, purgeAfter: nil
        )]
        let sections = KeyGrouping.group(keys: [], accounts: [], tools: tools, mode: .byConsumer)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.kind, .consumer(toolId: toolId, title: "Empty Tool"))
        XCTAssertTrue(sections.first?.keys.isEmpty == true)
    }

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
            notes: nil, createdAt: Date(), updatedAt: Date(), sortOrder: 0,
            deletedAt: nil, purgeAfter: nil
        )]
        let tools = [
            ConsumerToolDTO(id: toolA, name: "VS Code", iconSymbol: nil, isPreset: true, isHidden: false, notes: nil, createdAt: Date(), sortOrder: 0, deletedAt: nil, purgeAfter: nil),
            ConsumerToolDTO(id: toolB, name: "Cursor", iconSymbol: nil, isPreset: true, isHidden: false, notes: nil, createdAt: Date(), sortOrder: 1, deletedAt: nil, purgeAfter: nil),
        ]

        let byPlatform = KeyGrouping.group(keys: keys, accounts: accounts, tools: tools, mode: .byPlatform)
        let byConsumer = KeyGrouping.group(keys: keys, accounts: accounts, tools: tools, mode: .byConsumer)

        XCTAssertEqual(KeyGrouping.uniqueKeyCount(in: byPlatform), 3)
        // 按使用方不再单独列出「未分配」；未指派密钥只出现在「添加已有密钥」候选里。
        XCTAssertEqual(KeyGrouping.uniqueKeyCount(in: byConsumer), 2)
        XCTAssertTrue(byConsumer.contains { $0.kind == .shared })
        XCTAssertFalse(byConsumer.contains { $0.kind == .unassigned })
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
            notes: nil,
            secretAvailable: true,
            sortOrder: 0
        )
    }
}
