import Foundation

/// 密钥库整库搜索：密钥、上游账号、使用方三类并列，不限当前分组视角。
enum VaultSearch: Sendable {
    struct Results: Sendable {
        var keys: [KeyRecordDTO]
        var accounts: [UpstreamAccountDTO]
        var tools: [ConsumerToolDTO]

        var isEmpty: Bool {
            keys.isEmpty && accounts.isEmpty && tools.isEmpty
        }
    }

    /// 去掉首尾空白与掩码圆点，便于用列表里看到的 `••••ab12` 去搜末几位。
    static func normalizedQuery(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutBullets = trimmed.replacingOccurrences(of: "•", with: "")
        return withoutBullets.isEmpty ? trimmed : withoutBullets
    }

    static func results(
        query raw: String,
        keys: [KeyRecordDTO],
        accounts: [UpstreamAccountDTO],
        tools: [ConsumerToolDTO]
    ) -> Results {
        let query = normalizedQuery(raw)
        guard !query.isEmpty else {
            return Results(keys: [], accounts: [], tools: [])
        }
        // CloudKit 无唯一约束；仓库漏去重时 `uniqueKeysWithValues` 会直接崩。
        let accounts = SyncedIdentity.uniquedByID(accounts, id: \.id, updatedAt: \.updatedAt)
        let tools = SyncedIdentity.uniquedByID(tools, id: \.id, updatedAt: \.updatedAt)
        let accountById = Dictionary(
            accounts.map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )
        let toolById = Dictionary(
            tools.map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )
        return Results(
            keys: uniquedKeys(
                keys.filter { keyMatches($0, query: query, accountById: accountById, toolById: toolById) }
            ),
            accounts: accounts.filter { accountMatches($0, query: query) },
            tools: tools.filter { toolMatches($0, query: query) }
        )
    }

    static func platformDisplayName(for account: UpstreamAccountDTO) -> String {
        if let custom = account.customPlatformName, !custom.isEmpty {
            return custom
        }
        if let preset = PresetCatalog.platform(id: account.platform) {
            return preset.displayName
        }
        return account.platform
    }

    // MARK: - Matching

    private static func keyMatches(
        _ key: KeyRecordDTO,
        query: String,
        accountById: [UUID: UpstreamAccountDTO],
        toolById: [UUID: ConsumerToolDTO]
    ) -> Bool {
        if contains(key.displayName, query) { return true }
        if contains(key.maskedHint, query) { return true }
        if contains(key.notes, query) { return true }
        if let account = accountById[key.accountId], accountIdentityMatches(account, query: query) {
            return true
        }
        for toolId in key.consumerToolIds {
            if let tool = toolById[toolId], contains(tool.name, query) {
                return true
            }
        }
        return false
    }

    private static func accountMatches(_ account: UpstreamAccountDTO, query: String) -> Bool {
        if accountIdentityMatches(account, query: query) { return true }
        return contains(account.notes, query)
    }

    /// 账号名 / 平台显示名（不含备注）。密钥「归属」匹配走这条，避免备注把无关密钥带出来。
    private static func accountIdentityMatches(_ account: UpstreamAccountDTO, query: String) -> Bool {
        if contains(account.displayName, query) { return true }
        if contains(account.platform, query) { return true }
        if contains(account.customPlatformName, query) { return true }
        return contains(platformDisplayName(for: account), query)
    }

    private static func uniquedKeys(_ keys: [KeyRecordDTO]) -> [KeyRecordDTO] {
        var seen = Set<UUID>()
        return keys.filter { seen.insert($0.id).inserted }
    }

    private static func toolMatches(_ tool: ConsumerToolDTO, query: String) -> Bool {
        if contains(tool.name, query) { return true }
        return contains(tool.notes, query)
    }

    private static func contains(_ value: String?, _ query: String) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.localizedCaseInsensitiveContains(query)
    }
}
