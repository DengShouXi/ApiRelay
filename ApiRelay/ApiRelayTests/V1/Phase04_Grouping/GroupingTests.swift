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
            isPreset: false, isHidden: false, notes: nil, createdAt: Date(), updatedAt: Date(), sortOrder: 0,
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
            ConsumerToolDTO(id: toolA, name: "VS Code", iconSymbol: nil, isPreset: true, isHidden: false, notes: nil, createdAt: Date(), updatedAt: Date(), sortOrder: 0, deletedAt: nil, purgeAfter: nil),
            ConsumerToolDTO(id: toolB, name: "Cursor", iconSymbol: nil, isPreset: true, isHidden: false, notes: nil, createdAt: Date(), updatedAt: Date(), sortOrder: 1, deletedAt: nil, purgeAfter: nil),
        ]

        let byPlatform = KeyGrouping.group(keys: keys, accounts: accounts, tools: tools, mode: .byPlatform)
        let byConsumer = KeyGrouping.group(keys: keys, accounts: accounts, tools: tools, mode: .byConsumer)

        XCTAssertEqual(KeyGrouping.uniqueKeyCount(in: byPlatform), 3)
        // 按使用方不再单独列出「未分配」；未指派密钥只出现在「添加已有密钥」候选里。
        XCTAssertEqual(KeyGrouping.uniqueKeyCount(in: byConsumer), 2)
        XCTAssertTrue(byConsumer.contains { $0.kind == .shared })
        XCTAssertFalse(byConsumer.contains { $0.kind == .unassigned })
    }

    func testPlatformSectionsSortByNameDescending() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let beta = makeAccount(name: "Beta", createdAt: older, updatedAt: older, sortOrder: 0)
        let alpha = makeAccount(name: "Alpha", createdAt: newer, updatedAt: newer, sortOrder: 1)
        let sections = KeyGrouping.group(
            keys: [],
            accounts: [beta, alpha],
            tools: [],
            mode: .byPlatform,
            sectionSort: SectionSortPreference(criterion: .name, ascending: false)
        )
        XCTAssertEqual(titles(sections), ["Beta", "Alpha"])
    }

    func testPlatformSectionsSortByCreatedDescending() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let first = makeAccount(name: "Zed", createdAt: older, updatedAt: newer, sortOrder: 5)
        let second = makeAccount(name: "Alpha", createdAt: newer, updatedAt: older, sortOrder: 0)
        let sections = KeyGrouping.group(
            keys: [],
            accounts: [first, second],
            tools: [],
            mode: .byPlatform,
            sectionSort: SectionSortPreference(criterion: .createdAt, ascending: false)
        )
        XCTAssertEqual(titles(sections), ["Alpha", "Zed"])
    }

    func testPlatformSectionsSortByUpdatedAscending() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let stale = makeAccount(name: "New name", createdAt: newer, updatedAt: older, sortOrder: 1)
        let fresh = makeAccount(name: "Old name", createdAt: older, updatedAt: newer, sortOrder: 0)
        let sections = KeyGrouping.group(
            keys: [],
            accounts: [stale, fresh],
            tools: [],
            mode: .byPlatform,
            sectionSort: SectionSortPreference(criterion: .updatedAt, ascending: true)
        )
        XCTAssertEqual(titles(sections), ["New name", "Old name"])
    }

    func testPlatformSectionsSortByCustomOrder() {
        let a = makeAccount(name: "Alpha", sortOrder: 2)
        let b = makeAccount(name: "Beta", sortOrder: 0)
        let c = makeAccount(name: "Gamma", sortOrder: 1)
        let sections = KeyGrouping.group(
            keys: [],
            accounts: [a, b, c],
            tools: [],
            mode: .byPlatform,
            sectionSort: SectionSortPreference(criterion: .custom, ascending: true)
        )
        XCTAssertEqual(titles(sections), ["Beta", "Gamma", "Alpha"])
    }

    func testConsumerCustomSortKeepsSharedLast() {
        let account = UUID()
        let toolA = UUID()
        let toolB = UUID()
        let keys = [
            makeKey(id: UUID(), accountId: account, tools: [toolA, toolB]),
        ]
        let tools = [
            makeTool(id: toolA, name: "Alpha", sortOrder: 1),
            makeTool(id: toolB, name: "Beta", sortOrder: 0),
        ]
        let sections = KeyGrouping.group(
            keys: keys,
            accounts: [],
            tools: tools,
            mode: .byConsumer,
            sectionSort: SectionSortPreference(criterion: .custom, ascending: true)
        )
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(titles(sections.dropLast()), ["Beta", "Alpha"])
        XCTAssertEqual(sections.last?.kind, .shared)
    }

    func testPlatformModeDedupesDuplicateAccountIdsWithoutCrashing() {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let stale = makeAccount(id: id, name: "Old", createdAt: older, updatedAt: older)
        let fresh = makeAccount(id: id, name: "New", createdAt: older, updatedAt: newer)
        let sections = KeyGrouping.group(
            keys: [],
            accounts: [stale, fresh],
            tools: [],
            mode: .byPlatform
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.kind, .platform(accountId: id, title: "New"))
    }

    func testConsumerModeDedupesDuplicateToolIdsWithoutCrashing() {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let stale = makeTool(id: id, name: "Old", createdAt: older, updatedAt: older)
        let fresh = makeTool(id: id, name: "New", createdAt: older, updatedAt: newer)
        let sections = KeyGrouping.group(
            keys: [],
            accounts: [],
            tools: [stale, fresh],
            mode: .byConsumer
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.kind, .consumer(toolId: id, title: "New"))
    }

    func testNeedsCustomSeedWhenOrdersCollide() {
        XCTAssertTrue(SectionSortPreference.needsCustomSeed(sortOrders: [0, 0, 0]))
        XCTAssertFalse(SectionSortPreference.needsCustomSeed(sortOrders: [0, 1, 2]))
        XCTAssertFalse(SectionSortPreference.needsCustomSeed(sortOrders: [0]))
        XCTAssertFalse(SectionSortPreference.needsCustomSeed(sortOrders: []))
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

    private func titles(_ sections: some Sequence<KeyGroupSection>) -> [String] {
        sections.compactMap { section in
            switch section.kind {
            case .platform(_, let title), .consumer(_, let title):
                return title
            case .shared, .unassigned:
                return nil
            }
        }
    }

    private func makeAccount(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) -> UpstreamAccountDTO {
        UpstreamAccountDTO(
            id: id, platform: "openai", customPlatformName: nil,
            displayName: name, customBaseURL: nil, hasManagementCredential: false,
            notes: nil, createdAt: createdAt, updatedAt: updatedAt, sortOrder: sortOrder,
            deletedAt: nil, purgeAfter: nil
        )
    }

    private func makeTool(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) -> ConsumerToolDTO {
        ConsumerToolDTO(
            id: id, name: name, iconSymbol: nil,
            isPreset: false, isHidden: false, notes: nil,
            createdAt: createdAt, updatedAt: updatedAt, sortOrder: sortOrder,
            deletedAt: nil, purgeAfter: nil
        )
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
