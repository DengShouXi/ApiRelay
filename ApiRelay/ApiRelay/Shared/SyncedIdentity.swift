import Foundation

/// CloudKit 不能给业务字段加唯一约束。同步竞态会留下「业务 `id` 相同、记录名不同」的多行。
/// 读取与卫生清扫共用这一套跨设备可复算的规则；MUST NOT 用 `persistentModelID` 或抓取顺序当赢家依据。
nonisolated enum SyncedIdentity: Sendable {
    /// 仓库选赢家 / 清输家用。`>` 为更应保留。
    nonisolated struct ReplicaRank: Comparable, Equatable, Sendable {
        var updatedAt: Date
        var isDeleted: Bool
        var fingerprint: String

        static func < (lhs: ReplicaRank, rhs: ReplicaRank) -> Bool {
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt < rhs.updatedAt
            }
            if lhs.isDeleted != rhs.isDeleted {
                // 时间戳打平：墓碑优先，避免活着的旧行把较新删除盖掉。
                return !lhs.isDeleted && rhs.isDeleted
            }
            return lhs.fingerprint < rhs.fingerprint
        }
    }

    /// DTO 侧最后保险：同业务 `id` 只留 `updatedAt` 较新者；相等则留后出现的。
    static func uniquedByID<T>(
        _ items: [T],
        id: (T) -> UUID,
        updatedAt: (T) -> Date
    ) -> [T] {
        var best: [UUID: T] = [:]
        var order: [UUID] = []
        for item in items {
            let key = id(item)
            if let existing = best[key] {
                if updatedAt(item) >= updatedAt(existing) {
                    best[key] = item
                }
            } else {
                best[key] = item
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    /// 同业务 `id` 只留排名最高的一条。用于仓库 `fetchAll` / `fetch(id)`。
    static func uniquedReplicas<T>(
        _ items: [T],
        id: (T) -> UUID,
        rank: (T) -> ReplicaRank
    ) -> [T] {
        var groups: [UUID: [T]] = [:]
        var order: [UUID] = []
        for item in items {
            let key = id(item)
            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(item)
        }
        return order.compactMap { key in
            winner(in: groups[key] ?? [], rank: rank)
        }
    }

    static func winner<T>(in replicas: [T], rank: (T) -> ReplicaRank) -> T? {
        replicas.max { rank($0) < rank($1) }
    }

    /// 仅当排名最高者唯一时返回输家。完全打平（同时间戳、同删除态、同指纹）MUST NOT 删，
    /// 否则两台设备可能各删「另一行」，同步后一条不剩。
    static func losersToPrune<T: AnyObject>(
        _ replicas: [T],
        rank: (T) -> ReplicaRank
    ) -> [T] {
        guard replicas.count > 1 else { return [] }
        let ranked = replicas.map { (item: $0, rank: rank($0)) }
        guard let best = ranked.map(\.rank).max() else { return [] }
        let winners = ranked.filter { $0.rank == best }
        guard winners.count == 1, let winner = winners.first?.item else { return [] }
        return replicas.filter { $0 !== winner }
    }

    /// 整数微秒，不含小数点，与当前 Locale 无关。禁止 `String(format:)`。
    static func dateStamp(_ date: Date?) -> String {
        guard let date else { return "" }
        let microseconds = (date.timeIntervalSince1970 * 1_000_000).rounded(.towardZero)
        return String(Int64(microseconds))
    }

    /// POSIX 小数点。禁止 `String(describing:)`（随 Locale 可能变成逗号）。
    static func decimalStamp(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return NSDecimalNumber(decimal: value).description(withLocale: posixLocale)
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
}
