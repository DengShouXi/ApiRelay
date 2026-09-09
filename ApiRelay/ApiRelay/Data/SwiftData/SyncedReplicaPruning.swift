import Foundation
import SwiftData

extension ModelContext {
    /// 同业务 `id` 多行且能稳定分出唯一赢家时，删除输家并保存。
    nonisolated func pruneSyncedDuplicates<T: PersistentModel>(
        of type: T.Type,
        id: (T) -> UUID,
        rank: (T) -> SyncedIdentity.ReplicaRank
    ) throws {
        let models = try fetch(FetchDescriptor<T>())
        var groups: [UUID: [T]] = [:]
        for model in models {
            groups[id(model), default: []].append(model)
        }
        var changed = false
        for replicas in groups.values where replicas.count > 1 {
            for loser in SyncedIdentity.losersToPrune(replicas, rank: rank) {
                delete(loser)
                changed = true
            }
        }
        if changed {
            try save()
        }
    }
}
