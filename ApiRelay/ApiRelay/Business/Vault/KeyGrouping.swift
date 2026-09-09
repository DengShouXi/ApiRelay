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
    /// `sectionSort` 只排分区（账号 / 使用方），不排分区内密钥（FR-064）。
    static func group(
        keys: [KeyRecordDTO],
        accounts: [UpstreamAccountDTO],
        tools: [ConsumerToolDTO],
        mode: GroupingMode,
        sectionSort: SectionSortPreference = .nameAscending
    ) -> [KeyGroupSection] {
        switch mode {
        case .byPlatform:
            return groupByPlatform(keys: keys, accounts: accounts, sectionSort: sectionSort)
        case .byConsumer:
            return groupByConsumer(keys: keys, tools: tools, sectionSort: sectionSort)
        }
    }

    /// 去重后的密钥总数（共享只计一次）。
    static func uniqueKeyCount(in sections: [KeyGroupSection]) -> Int {
        Set(sections.flatMap { $0.keys.map(\.id) }).count
    }

    private static func groupByPlatform(
        keys: [KeyRecordDTO],
        accounts: [UpstreamAccountDTO],
        sectionSort: SectionSortPreference
    ) -> [KeyGroupSection] {
        // CloudKit 无唯一约束，同步竞态会给出相同 `id` 的两行。
        // `Dictionary(uniqueKeysWithValues:)` 会直接崩（首页一打开就退）。
        let accounts = SyncedIdentity.uniquedByID(accounts, id: \.id, updatedAt: \.updatedAt)
        let titleByAccount = Dictionary(
            accounts.map { ($0.id, $0.displayName) },
            uniquingKeysWith: { _, last in last }
        )
        // Seed every account so 「添加账号」后主列表仍可见（0 密钥也出分区），否则无法点「添加密钥」。
        var buckets: [UUID: [KeyRecordDTO]] = [:]
        for account in accounts {
            buckets[account.id] = []
        }
        for key in keys {
            buckets[key.accountId, default: []].append(key)
        }
        return sortedAccounts(accounts, sort: sectionSort).map { account in
            KeyGroupSection(
                kind: .platform(accountId: account.id, title: titleByAccount[account.id] ?? account.id.uuidString),
                keys: sortedKeys(buckets[account.id] ?? [])
            )
        }
    }

    private static func groupByConsumer(
        keys: [KeyRecordDTO],
        tools: [ConsumerToolDTO],
        sectionSort: SectionSortPreference
    ) -> [KeyGroupSection] {
        let tools = SyncedIdentity.uniquedByID(tools, id: \.id, updatedAt: \.updatedAt)
        let toolName = Dictionary(
            tools.map { ($0.id, $0.name) },
            uniquingKeysWith: { _, last in last }
        )
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
        for tool in sortedTools(tools, sort: sectionSort) {
            sections.append(KeyGroupSection(
                kind: .consumer(toolId: tool.id, title: toolName[tool.id] ?? tool.id.uuidString),
                keys: sortedKeys(exclusive[tool.id] ?? [])
            ))
        }
        if !shared.isEmpty {
            sections.append(KeyGroupSection(kind: .shared, keys: sortedKeys(shared)))
        }
        // 未分配密钥不单独成区：改在「添加已有密钥」候选旁标注「未分配 / 已分配 N 次」。
        _ = unassigned
        return sections
    }

    private static func sortedAccounts(
        _ accounts: [UpstreamAccountDTO],
        sort: SectionSortPreference
    ) -> [UpstreamAccountDTO] {
        accounts.sorted { lhs, rhs in
            compareSections(
                name: (lhs.displayName, rhs.displayName),
                createdAt: (lhs.createdAt, rhs.createdAt),
                updatedAt: (lhs.updatedAt, rhs.updatedAt),
                sortOrder: (lhs.sortOrder, rhs.sortOrder),
                id: (lhs.id, rhs.id),
                sort: sort
            )
        }
    }

    private static func sortedTools(
        _ tools: [ConsumerToolDTO],
        sort: SectionSortPreference
    ) -> [ConsumerToolDTO] {
        tools.sorted { lhs, rhs in
            compareSections(
                name: (lhs.name, rhs.name),
                createdAt: (lhs.createdAt, rhs.createdAt),
                updatedAt: (lhs.updatedAt, rhs.updatedAt),
                sortOrder: (lhs.sortOrder, rhs.sortOrder),
                id: (lhs.id, rhs.id),
                sort: sort
            )
        }
    }

    private static func compareSections(
        name: (String, String),
        createdAt: (Date, Date),
        updatedAt: (Date, Date),
        sortOrder: (Int, Int),
        id: (UUID, UUID),
        sort: SectionSortPreference
    ) -> Bool {
        switch sort.criterion {
        case .name:
            if let ordered = compareName(name.0, name.1, ascending: sort.ascending) { return ordered }
            if createdAt.0 != createdAt.1 { return createdAt.0 < createdAt.1 }
            return id.0.uuidString < id.1.uuidString
        case .createdAt:
            if createdAt.0 != createdAt.1 {
                return sort.ascending ? createdAt.0 < createdAt.1 : createdAt.0 > createdAt.1
            }
            if let ordered = compareName(name.0, name.1, ascending: true) { return ordered }
            return id.0.uuidString < id.1.uuidString
        case .updatedAt:
            if updatedAt.0 != updatedAt.1 {
                return sort.ascending ? updatedAt.0 < updatedAt.1 : updatedAt.0 > updatedAt.1
            }
            if createdAt.0 != createdAt.1 { return createdAt.0 < createdAt.1 }
            if let ordered = compareName(name.0, name.1, ascending: true) { return ordered }
            return id.0.uuidString < id.1.uuidString
        case .custom:
            if sortOrder.0 != sortOrder.1 { return sortOrder.0 < sortOrder.1 }
            if createdAt.0 != createdAt.1 { return createdAt.0 < createdAt.1 }
            return id.0.uuidString < id.1.uuidString
        }
    }

    private static func compareName(_ a: String, _ b: String, ascending: Bool) -> Bool? {
        let order = a.localizedStandardCompare(b)
        guard order != .orderedSame else { return nil }
        if ascending { return order == .orderedAscending }
        return order == .orderedDescending
    }

    private static func sortedKeys(_ keys: [KeyRecordDTO]) -> [KeyRecordDTO] {
        // 同 sortOrder 时保持传入顺序（仓库已按 createdAt 新→旧）。
        keys.enumerated()
            .sorted { a, b in
                if a.element.sortOrder != b.element.sortOrder {
                    return a.element.sortOrder < b.element.sortOrder
                }
                return a.offset < b.offset
            }
            .map(\.element)
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
