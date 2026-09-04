#if DEBUG
import Foundation

/// 假回收站批量：内存里直接委托给注入的假 vault / tools，或自记 journal。
/// 默认自己记 journal 并返回按勾选数量计的成功结果（不依赖真门闩）。
actor FakeRecentlyDeletedBatch: RecentlyDeletedBatchServing {
    var journal = FakeJournal()

    func restore(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome {
        try journal.record("restore")
        guard !selection.isEmpty else { return .empty }
        return TrashBatchOutcome(successCount: selection.itemCount, failures: [])
    }

    func permanentlyDelete(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome {
        try journal.record("permanentlyDelete")
        guard !selection.isEmpty else { return .empty }
        return TrashBatchOutcome(successCount: selection.itemCount, failures: [])
    }
}
#endif
