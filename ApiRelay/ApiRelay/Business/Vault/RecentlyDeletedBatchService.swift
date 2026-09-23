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

/// 回收站批量恢复 / 永久删除（FR-006a）。整批一次当前验证方式。
protocol RecentlyDeletedBatchServing: Actor {
    func restore(_ selection: TrashBatchSelection, appPassword: String?) async throws -> TrashBatchOutcome
    func permanentlyDelete(_ selection: TrashBatchSelection, appPassword: String?) async throws -> TrashBatchOutcome
}

extension RecentlyDeletedBatchServing {
    func restore(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome {
        try await restore(selection, appPassword: nil)
    }

    func permanentlyDelete(_ selection: TrashBatchSelection) async throws -> TrashBatchOutcome {
        try await permanentlyDelete(selection, appPassword: nil)
    }
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

    func restore(_ selection: TrashBatchSelection, appPassword: String?) async throws -> TrashBatchOutcome {
        guard !selection.isEmpty else { return .empty }
        let authorization = try sessionLock.captureAuthorizationLease()
        try await vault.preflightRestoreQuota(
            keyIds: selection.keyIds,
            accountIds: selection.accountIds
        )
        try await confirmCurrent(
            reason: String(localized: "gate.restoreTrashBatch"),
            purpose: .destructive,
            appPassword: appPassword
        )
        try sessionLock.validateAuthorizationLease(authorization)
        let keysAndAccounts = try await vault.restoreDeletedAfterAuthentication(
            keyIds: selection.keyIds,
            accountIds: selection.accountIds,
            authorization: authorization
        )
        try sessionLock.validateAuthorizationLease(authorization)
        let tools = try await consumerTools.restoreToolsAfterAuthentication(
            ids: selection.toolIds,
            authorization: authorization
        )
        return keysAndAccounts.merging(tools)
    }

    func permanentlyDelete(_ selection: TrashBatchSelection, appPassword: String?) async throws -> TrashBatchOutcome {
        guard !selection.isEmpty else { return .empty }
        let authorization = try sessionLock.captureAuthorizationLease()
        try await confirmCurrent(
            reason: String(localized: "gate.permanentDeleteTrashBatch"),
            purpose: .destructive,
            appPassword: appPassword
        )
        try sessionLock.validateAuthorizationLease(authorization)
        let keysAndAccounts = try await vault.permanentlyDeleteDeletedAfterAuthentication(
            keyIds: selection.keyIds,
            accountIds: selection.accountIds,
            authorization: authorization
        )
        try sessionLock.validateAuthorizationLease(authorization)
        let tools = try await consumerTools.permanentlyDeleteToolsAfterAuthentication(
            ids: selection.toolIds,
            authorization: authorization
        )
        return keysAndAccounts.merging(tools)
    }

    private func confirmCurrent(
        reason: String,
        purpose: AuthPurpose,
        appPassword: String?
    ) async throws {
        let policy = try await vault.currentRevealPolicy()
        try await CurrentRevealPolicyAuth.confirm(
            policy,
            gate: gate,
            reason: reason,
            purpose: purpose,
            appPassword: appPassword
        )
    }
}
