import Foundation

/// 列表分组结果。`shared` / `unassigned` 独立小计；计数侧共享密钥只计一次。
struct KeyGroupSection: Identifiable, Sendable {
    enum Kind: Sendable, Hashable {
        case platform(accountId: UUID, title: String)
        case consumer(toolId: UUID, title: String)
        case shared
        case unassigned
    }

    var id: Kind { kind }
    let kind: Kind
    /// 该分区展示的密钥（共享密钥可出现在多个工具分区，但 uniqueKeyCount 全局去重）。
    let keys: [KeyRecordDTO]
}

enum KeyGrouping {
    /// `byPlatform` 与 `byConsumer` 共用此函数，仅分组键与归集规则不同（T034 / FR-008a）。
    static func group(
        keys: [KeyRecordDTO],
        accounts: [UpstreamAccountDTO],
        tools: [ConsumerToolDTO],
        mode: GroupingMode
    ) -> [KeyGroupSection] {
        switch mode {
        case .byPlatform:
            return groupByPlatform(keys: keys, accounts: accounts)
        case .byConsumer:
            return groupByConsumer(keys: keys, tools: tools)
        }
    }

    /// 去重后的密钥总数（共享只计一次）。
    static func uniqueKeyCount(in sections: [KeyGroupSection]) -> Int {
        Set(sections.flatMap { $0.keys.map(\.id) }).count
    }

    private static func groupByPlatform(
        keys: [KeyRecordDTO],
        accounts: [UpstreamAccountDTO]
    ) -> [KeyGroupSection] {
        let titleByAccount = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.displayName) })
        // Seed every account so 「添加账号」后主列表仍可见（0 密钥也出分区），否则无法点「添加密钥」。
        var buckets: [UUID: [KeyRecordDTO]] = [:]
        for account in accounts {
            buckets[account.id] = []
        }
        for key in keys {
            buckets[key.accountId, default: []].append(key)
        }
        return buckets.keys.sorted { a, b in
            (titleByAccount[a] ?? "") < (titleByAccount[b] ?? "")
        }.map { accountId in
            KeyGroupSection(
                kind: .platform(accountId: accountId, title: titleByAccount[accountId] ?? accountId.uuidString),
                keys: buckets[accountId] ?? []
            )
        }
    }

    private static func groupByConsumer(
        keys: [KeyRecordDTO],
        tools: [ConsumerToolDTO]
    ) -> [KeyGroupSection] {
        let toolName = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0.name) })
        // 与按平台一致：每个使用端都出分区（含 0 密钥），否则「添加使用端」后主列表看不见。
        var exclusive: [UUID: [KeyRecordDTO]] = [:]
        for tool in tools {
            exclusive[tool.id] = []
        }
        var shared: [KeyRecordDTO] = []
        var unassigned: [KeyRecordDTO] = []

        for key in keys {
            switch AssignmentKind.from(consumerToolIds: key.consumerToolIds) {
            case .unassigned:
                unassigned.append(key)
            case .exclusive(let toolId):
                exclusive[toolId, default: []].append(key)
            case .shared:
                shared.append(key)
                // 列表 MAY 同时出现在各工具下：追加展示副本
                for toolId in key.consumerToolIds {
                    exclusive[toolId, default: []].append(key)
                }
            }
        }

        var sections: [KeyGroupSection] = []
        for toolId in exclusive.keys.sorted(by: { (toolName[$0] ?? "") < (toolName[$1] ?? "") }) {
            sections.append(KeyGroupSection(
                kind: .consumer(toolId: toolId, title: toolName[toolId] ?? toolId.uuidString),
                keys: exclusive[toolId] ?? []
            ))
        }
        if !shared.isEmpty {
            sections.append(KeyGroupSection(kind: .shared, keys: shared))
        }
        // 未分配密钥不单独成区：改在「添加已有密钥」候选旁标注「未分配 / 已分配 N 次」。
        _ = unassigned
        return sections
    }
}

extension AssignmentKind {
    static func from(consumerToolIds: [UUID]) -> AssignmentKind {
        switch consumerToolIds.count {
        case 0: return .unassigned
        case 1: return .exclusive(consumerToolIds[0])
        default: return .shared(consumerToolIds)
        }
    }
}
