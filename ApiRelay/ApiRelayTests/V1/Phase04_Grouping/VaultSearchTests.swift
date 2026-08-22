@preconcurrency import XCTest
@testable import ApiRelay

@MainActor
final class VaultSearchTests: XCTestCase {
    func testEmptyQueryReturnsNoHits() {
        let account = makeAccount(name: "OpenAI 账号 1")
        let key = makeKey(name: "密钥 1", accountId: account.id)
        let results = VaultSearch.results(
            query: "   ",
            keys: [key],
            accounts: [account],
            tools: []
        )
        XCTAssertTrue(results.isEmpty)
    }

    func testFindsEmptyAccountAndEmptyTool() {
        let account = makeAccount(name: "OpenAI 账号 2")
        let tool = makeTool(name: "Cursor")
        let results = VaultSearch.results(
            query: "账号 2",
            keys: [],
            accounts: [account],
            tools: [tool]
        )
        XCTAssertEqual(results.accounts.map(\.id), [account.id])
        XCTAssertTrue(results.keys.isEmpty)
        XCTAssertTrue(results.tools.isEmpty)

        let toolHits = VaultSearch.results(
            query: "curs",
            keys: [],
            accounts: [account],
            tools: [tool]
        )
        XCTAssertEqual(toolHits.tools.map(\.id), [tool.id])
        XCTAssertTrue(toolHits.accounts.isEmpty)
    }

    func testKeyHintAndNotesAndRelatedNames() {
        let account = makeAccount(name: "工作号", platform: "anthropic")
        let tool = makeTool(name: "Zed")
        let key = makeKey(
            name: "备用",
            accountId: account.id,
            tools: [tool.id],
            hint: "cgvh",
            notes: "发给同事前先轮换"
        )

        XCTAssertEqual(
            VaultSearch.results(query: "••••cgvh", keys: [key], accounts: [account], tools: [tool]).keys.map(\.id),
            [key.id]
        )
        XCTAssertEqual(
            VaultSearch.results(query: "轮换", keys: [key], accounts: [account], tools: [tool]).keys.map(\.id),
            [key.id]
        )
        let byPlatform = VaultSearch.results(
            query: "Anthropic",
            keys: [key],
            accounts: [account],
            tools: [tool]
        )
        XCTAssertEqual(byPlatform.keys.map(\.id), [key.id])
        XCTAssertEqual(byPlatform.accounts.map(\.id), [account.id])

        let byTool = VaultSearch.results(
            query: "Zed",
            keys: [key],
            accounts: [account],
            tools: [tool]
        )
        XCTAssertEqual(byTool.keys.map(\.id), [key.id])
        XCTAssertEqual(byTool.tools.map(\.id), [tool.id])
    }

    func testAccountNotesDoNotPullUnrelatedKeys() {
        let account = makeAccount(name: "空账号", notes: "实验室备用")
        let other = makeAccount(name: "别的号")
        let key = makeKey(name: "密钥 1", accountId: other.id)
        let results = VaultSearch.results(
            query: "实验室",
            keys: [key],
            accounts: [account, other],
            tools: []
        )
        XCTAssertEqual(results.accounts.map(\.id), [account.id])
        XCTAssertTrue(results.keys.isEmpty)
    }

    func testUnassignedKeyStillMatchesItsAccount() {
        let account = makeAccount(name: "OpenAI 账号 1")
        let key = makeKey(name: "未指派钥", accountId: account.id, tools: [])
        let results = VaultSearch.results(
            query: "OpenAI",
            keys: [key],
            accounts: [account],
            tools: []
        )
        XCTAssertEqual(results.keys.map(\.id), [key.id])
        XCTAssertEqual(results.accounts.map(\.id), [account.id])
    }

    private func makeAccount(
        name: String,
        platform: String = "openai",
        notes: String? = nil
    ) -> UpstreamAccountDTO {
        UpstreamAccountDTO(
            id: UUID(),
            platform: platform,
            customPlatformName: nil,
            displayName: name,
            customBaseURL: nil,
            hasManagementCredential: false,
            notes: notes,
            createdAt: Date(),
            updatedAt: Date(),
            sortOrder: 0,
            deletedAt: nil,
            purgeAfter: nil
        )
    }

    private func makeTool(name: String) -> ConsumerToolDTO {
        ConsumerToolDTO(
            id: UUID(),
            name: name,
            iconSymbol: nil,
            isPreset: false,
            isHidden: false,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            sortOrder: 0,
            deletedAt: nil,
            purgeAfter: nil
        )
    }

    private func makeKey(
        name: String,
        accountId: UUID,
        tools: [UUID] = [],
        hint: String? = nil,
        notes: String? = nil
    ) -> KeyRecordDTO {
        KeyRecordDTO(
            id: UUID(),
            accountId: accountId,
            consumerToolIds: tools,
            displayName: name,
            maskedHint: hint,
            origin: .manualEntry,
            providerKeyRef: nil,
            lifecycle: .active,
            health: KeyHealthDTO(state: .unknown, lastCheckedAt: nil, lastCheckNote: nil),
            deletedAt: nil,
            purgeAfter: nil,
            spendLimit: nil,
            notes: notes,
            secretAvailable: true,
            sortOrder: 0
        )
    }
}
