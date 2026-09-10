import Foundation

/// 回收站勾选结果。UI 只传当前可见 ∩ 已勾选的 id。
nonisolated struct TrashBatchSelection: Sendable, Equatable {
    var keyIds: [UUID]
    var accountIds: [UUID]
    var toolIds: [UUID]

    var isEmpty: Bool {
        keyIds.isEmpty && accountIds.isEmpty && toolIds.isEmpty
    }

    var itemCount: Int {
        keyIds.count + accountIds.count + toolIds.count
    }
}

nonisolated struct TrashBatchItemFailure: Sendable, Equatable {
    let name: String
    let detail: String
}

nonisolated struct TrashBatchOutcome: Sendable, Equatable {
    var successCount: Int
    var failures: [TrashBatchItemFailure]

    static let empty = TrashBatchOutcome(successCount: 0, failures: [])

    var hasFailures: Bool { !failures.isEmpty }

    func merging(_ other: TrashBatchOutcome) -> TrashBatchOutcome {
        TrashBatchOutcome(
            successCount: successCount + other.successCount,
            failures: failures + other.failures
        )
    }
}

/// 回收站批量恢复 / 永久删除（FR-006a）。整批一次 `confirmMandatory`。
protocol RecentlyDeletedBatchServing: Actor {
    func restore(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome
    func permanentlyDelete(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome
}

actor RecentlyDeletedBatchService: RecentlyDeletedBatchServing {
    private let vault: KeyVaultServing
    private let consumerTools: ConsumerToolServing
    private let gate: RevealGateServing
    private let sessionLock: any SessionLockQuerying

    init(
        vault: KeyVaultServing,
        consumerTools: ConsumerToolServing,
        gate: RevealGateServing,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock()
    ) {
        self.vault = vault
        self.consumerTools = consumerTools
        self.gate = gate
        self.sessionLock = sessionLock
    }

    private func rejectIfSessionLocked() throws {
        if sessionLock.isSessionLocked() {
            throw ApiRelayError.sessionLocked
        }
    }

    func restore(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome {
        guard !selection.isEmpty else { return .empty }
        try rejectIfSessionLocked()
        try await vault.preflightRestoreQuota(
            keyIds: selection.keyIds,
            accountIds: selection.accountIds
        )
        try await gate.confirmMandatory(reason: String(localized: "gate.restoreTrashBatch"))
        let keysAndAccounts = await vault.restoreDeletedAfterAuthentication(
            keyIds: selection.keyIds,
            accountIds: selection.accountIds
        )
        let tools = await consumerTools.restoreToolsAfterAuthentication(ids: selection.toolIds)
        return keysAndAccounts.merging(tools)
    }

    func permanentlyDelete(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome {
        guard !selection.isEmpty else { return .empty }
        try rejectIfSessionLocked()
        try await gate.confirmMandatory(reason: String(localized: "gate.permanentDeleteTrashBatch"))
        let keysAndAccounts = await vault.permanentlyDeleteDeletedAfterAuthentication(
            keyIds: selection.keyIds,
            accountIds: selection.accountIds
        )
        let tools = await consumerTools.permanentlyDeleteToolsAfterAuthentication(ids: selection.toolIds)
        return keysAndAccounts.merging(tools)
    }
}
