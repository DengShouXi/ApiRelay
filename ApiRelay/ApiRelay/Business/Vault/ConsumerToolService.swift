import Foundation
import SwiftData

protocol ConsumerToolServing: Actor {
    func tools(includeHidden: Bool) async throws -> [ConsumerToolDTO]
    /// 启动维护：不再自动写入预置使用端；并清除历史种子的预置项（用户自建保留）。
    func ensurePresetsSeeded() async throws
    /// CloudKit 导入成功后的身份清扫。
    func pruneDuplicateIdentities() async throws
    func createTool(_ draft: ConsumerToolDraft) async throws -> UUID
    func updateTool(id: UUID, patch: ConsumerToolPatch, appPassword: String?) async throws
    func deleteTool(id: UUID, appPassword: String?) async throws
    /// 按用户拖拽结果重写使用方分区顺序（`orderedIds` 为从上到下）。不改 `updatedAt`。
    func reorderTools(orderedIds: [UUID]) async throws

    func recentlyDeletedTools() async throws -> [ConsumerToolDTO]
    func restoreTool(id: UUID, appPassword: String?) async throws
    func permanentlyDeleteTool(id: UUID, appPassword: String?) async throws
    func purgeExpiredDeletedTools() async throws

    /// 调用方 MUST 已按当前验证方式完成确认，并传入认证前捕获的同一会话租约。
    func restoreToolsAfterAuthentication(
        ids: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome
    /// 调用方 MUST 已按当前验证方式完成确认，并传入认证前捕获的同一会话租约。
    func permanentlyDeleteToolsAfterAuthentication(
        ids: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome
    /// FR-061：物理删除本服务上下文中的使用方与指派（含回收站）。
    func purgeAllRecordsForErase(authorization: SessionAuthorizationLease) async throws
    /// `DataLifecycleService` 已在线性化的清除起点完成身份授权后调用。
    /// 一旦清除事务开始，切到后台/锁屏不得把全量清除截成半状态。
    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws
}

extension ConsumerToolServing {
    func updateTool(id: UUID, patch: ConsumerToolPatch) async throws {
        try await updateTool(id: id, patch: patch, appPassword: nil)
    }

    func deleteTool(id: UUID) async throws {
        try await deleteTool(id: id, appPassword: nil)
    }

    func restoreTool(id: UUID) async throws {
        try await restoreTool(id: id, appPassword: nil)
    }

    func permanentlyDeleteTool(id: UUID) async throws {
        try await permanentlyDeleteTool(id: id, appPassword: nil)
    }
}

actor ConsumerToolService: ConsumerToolServing {
    private let repo: ConsumerToolRepository
    private let userPrefs: UserPreferencesRepository
    private let gate: RevealGateServing
    private let sessionLock: any SessionLockQuerying
    private let integrityQuarantine: VaultIntegrityQuarantineStore
    private let mutationGate: StorageMutationGate

    init(
        modelContainer: ModelContainer,
        gate: RevealGateServing,
        sessionLock: any SessionLockQuerying = AlwaysUnlockedSessionLock(),
        integrityQuarantine: VaultIntegrityQuarantineStore = .shared,
        mutationGate: StorageMutationGate = StorageMutationGate()
    ) {
        self.repo = ConsumerToolRepository(modelContainer: modelContainer)
        self.userPrefs = UserPreferencesRepository(modelContainer: modelContainer)
        self.gate = gate
        self.sessionLock = sessionLock
        self.integrityQuarantine = integrityQuarantine
        self.mutationGate = mutationGate
    }

    private func captureSessionAuthorization() throws -> SessionAuthorizationLease {
        try ensureStorageIntegrity()
        return try sessionLock.captureAuthorizationLease()
    }

    private func validateSessionAuthorization(_ authorization: SessionAuthorizationLease) throws {
        try ensureStorageIntegrity()
        try sessionLock.validateAuthorizationLease(authorization)
    }

    private func ensureStorageIntegrity() throws {
        if let incident = integrityQuarantine.currentIncident() {
            throw ApiRelayError.storageIntegrityQuarantined(
                operation: incident.operation,
                detail: incident.detail
            )
        }
    }

    private func commitSessionAuthorization(
        _ authorization: SessionAuthorizationLease
    ) -> RepositoryCommit {
        { [sessionLock, integrityQuarantine] operation in
            if let incident = integrityQuarantine.currentIncident() {
                throw ApiRelayError.storageIntegrityQuarantined(
                    operation: incident.operation,
                    detail: incident.detail
                )
            }
            try sessionLock.commitAuthorizationLease(authorization, operation: operation)
        }
    }

    private func integrityRepositoryCommit() -> RepositoryCommit {
        { [integrityQuarantine] operation in
            if let incident = integrityQuarantine.currentIncident() {
                throw ApiRelayError.storageIntegrityQuarantined(
                    operation: incident.operation,
                    detail: incident.detail
                )
            }
            try operation()
        }
    }

    func tools(includeHidden: Bool) async throws -> [ConsumerToolDTO] {
        try ensureStorageIntegrity()
        let result = try await repo.fetchAll(includeHidden: includeHidden, includeDeleted: false)
        try ensureStorageIntegrity()
        return result
    }

    /// 使用端改为「用户自建」：不自动 seed；`PresetCatalog.consumerTools` 仅作添加表单的名称建议。
    /// 顺带清除历史上 `isPreset == true` 的种子（否则主列表占满且无法删除），
    /// 为缺少 `iconSymbol` 的存量按名称回填，并把 VS Code 族上的废止三截符号换成现行徽章。
    func ensurePresetsSeeded() async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tools_startup")
        defer { storagePermit.finish() }
        try ensureStorageIntegrity()
        await pruneDuplicateIdentities(source: .startup)
        try ensureStorageIntegrity()
        let existing = try await repo.fetchAll(includeHidden: true, includeDeleted: true)
        try ensureStorageIntegrity()
        for tool in existing where tool.isPreset {
            try await destroyToolAndAssignments(id: tool.id, allowPreset: true)
        }
        for tool in existing where !tool.isPreset {
            let stored = tool.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let needsFill = stored.isEmpty
                || PresetCatalog.isRetiredVSCodeSymbol(stored, toolName: tool.name)
            guard needsFill else { continue }
            var patch = ConsumerToolPatch()
            patch.iconSymbol = PresetCatalog.toolSymbol(name: tool.name)
            try await repo.update(
                id: tool.id,
                patch: patch,
                committing: integrityRepositoryCommit()
            )
        }
        do {
            try await purgeExpiredDeletedTools()
        } catch {
            IdentityHygieneLog.failed(source: .startup, kind: .expiredTools, error: error)
        }
        try ensureStorageIntegrity()
    }

    func pruneDuplicateIdentities() async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tools_prune")
        defer { storagePermit.finish() }
        try ensureStorageIntegrity()
        await pruneDuplicateIdentities(source: .cloudImport)
        try ensureStorageIntegrity()
    }

    private func pruneDuplicateIdentities(source: IdentityHygieneLog.Source) async {
        await IdentityHygieneLog.runIsolated(source: source, steps: [
            (.tool, { try await self.pruneToolDuplicatesForMaintenance() }),
        ])
    }

    private func pruneToolDuplicatesForMaintenance() async throws {
        try ensureStorageIntegrity()
        try await repo.pruneDuplicateIdentities(
            committing: integrityRepositoryCommit()
        )
        try ensureStorageIntegrity()
    }

    func createTool(_ draft: ConsumerToolDraft) async throws -> UUID {
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tool_create")
        defer { storagePermit.finish() }
        let authorization = try captureSessionAuthorization()
        var draft = draft
        draft.isPreset = false
        let stored = draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stored.isEmpty {
            draft.iconSymbol = PresetCatalog.toolSymbol(name: draft.name)
        }
        return try await repo.insert(
            draft,
            committing: commitSessionAuthorization(authorization)
        )
    }

    func updateTool(id: UUID, patch: ConsumerToolPatch, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        if Self.toolPatchRequiresIdentity(patch) {
            try await confirmCurrent(
                reason: String(localized: "vault.consumer.edit"),
                purpose: .settings,
                appPassword: appPassword
            )
        }
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tool_update")
        defer { storagePermit.finish() }
        try validateSessionAuthorization(authorization)
        try await repo.update(
            id: id,
            patch: patch,
            committing: commitSessionAuthorization(authorization)
        )
    }

    func reorderTools(orderedIds: [UUID]) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tools_reorder")
        defer { storagePermit.finish() }
        let authorization = try captureSessionAuthorization()
        try await repo.reorder(
            orderedIds: orderedIds,
            committing: commitSessionAuthorization(authorization)
        )
    }

    /// 删除使用方：移入回收站；回收站期间保留 KeyAssignment，不级联删密钥。
    func deleteTool(id: UUID, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "gate.deleteTool"),
            purpose: .destructive,
            appPassword: appPassword
        )
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tool_delete")
        defer { storagePermit.finish() }
        try validateSessionAuthorization(authorization)
        try await repo.softDelete(
            id: id,
            retainDays: 30,
            allowPreset: false,
            committing: commitSessionAuthorization(authorization)
        )
    }

    func recentlyDeletedTools() async throws -> [ConsumerToolDTO] {
        try ensureStorageIntegrity()
        let result = try await repo.fetchSoftDeleted()
        try ensureStorageIntegrity()
        return result
    }

    func restoreTool(id: UUID, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "gate.restoreTool"),
            purpose: .destructive,
            appPassword: appPassword
        )
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tool_restore")
        defer { storagePermit.finish() }
        try validateSessionAuthorization(authorization)
        _ = try await restoreToolAfterAuth(
            id,
            requirePresent: true,
            authorization: authorization
        )
    }

    func permanentlyDeleteTool(id: UUID, appPassword: String?) async throws {
        let authorization = try captureSessionAuthorization()
        try await confirmCurrent(
            reason: String(localized: "gate.permanentDelete"),
            purpose: .destructive,
            appPassword: appPassword
        )
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tool_permanent_delete")
        defer { storagePermit.finish() }
        try validateSessionAuthorization(authorization)
        _ = try await permanentlyDeleteToolAfterAuth(id, authorization: authorization)
    }

    /// 调用方 MUST 已按当前验证方式完成确认。
    func restoreToolsAfterAuthentication(
        ids: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome {
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tools_batch_restore")
        defer { storagePermit.finish() }
        try validateSessionAuthorization(authorization)
        var successCount = 0
        var failures: [TrashBatchItemFailure] = []
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            try validateSessionAuthorization(authorization)
            let name = (try? await repo.fetch(id: id))?.name ?? id.uuidString
            do {
                if try await restoreToolAfterAuth(
                    id,
                    requirePresent: false,
                    authorization: authorization
                ) {
                    successCount += 1
                }
            } catch ApiRelayError.sessionLocked {
                throw ApiRelayError.sessionLocked
            } catch {
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        return TrashBatchOutcome(successCount: successCount, failures: failures)
    }

    /// 调用方 MUST 已按当前验证方式完成确认。
    func permanentlyDeleteToolsAfterAuthentication(
        ids: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome {
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tools_batch_delete")
        defer { storagePermit.finish() }
        try validateSessionAuthorization(authorization)
        var successCount = 0
        var failures: [TrashBatchItemFailure] = []
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            try validateSessionAuthorization(authorization)
            let name = (try? await repo.fetch(id: id))?.name ?? id.uuidString
            do {
                if try await permanentlyDeleteToolAfterAuth(id, authorization: authorization) {
                    successCount += 1
                }
            } catch ApiRelayError.sessionLocked {
                throw ApiRelayError.sessionLocked
            } catch {
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        return TrashBatchOutcome(successCount: successCount, failures: failures)
    }

    @discardableResult
    private func restoreToolAfterAuth(
        _ id: UUID,
        requirePresent: Bool,
        authorization: SessionAuthorizationLease
    ) async throws -> Bool {
        try validateSessionAuthorization(authorization)
        guard let tool = try await repo.fetch(id: id) else {
            if requirePresent {
                throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
            }
            return true
        }
        guard tool.deletedAt != nil else { return true }
        try await repo.clearDeletionMarks(
            id: id,
            committing: commitSessionAuthorization(authorization)
        )
        return true
    }

    @discardableResult
    private func permanentlyDeleteToolAfterAuth(
        _ id: UUID,
        authorization: SessionAuthorizationLease
    ) async throws -> Bool {
        try validateSessionAuthorization(authorization)
        guard try await repo.fetch(id: id) != nil else { return true }
        try await destroyToolAndAssignments(
            id: id,
            allowPreset: false,
            authorization: authorization
        )
        return true
    }

    func purgeExpiredDeletedTools() async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tools_expiry_purge")
        defer { storagePermit.finish() }
        let authorization: SessionAuthorizationLease
        do {
            authorization = try captureSessionAuthorization()
        } catch ApiRelayError.sessionLocked {
            return
        }
        let deleted = try await repo.fetchSoftDeleted()
        try validateSessionAuthorization(authorization)
        let now = Date()
        for tool in deleted where (tool.purgeAfter ?? .distantFuture) < now {
            try await destroyToolAndAssignments(
                id: tool.id,
                allowPreset: true,
                authorization: authorization
            )
        }
    }

    /// FR-061：物理删除本服务上下文中的使用方与指派（含回收站）。
    func purgeAllRecordsForErase(authorization: SessionAuthorizationLease) async throws {
        let storagePermit = try mutationGate.beginNormal(operation: "consumer_tools_legacy_erase")
        defer { storagePermit.finish() }
        try validateSessionAuthorization(authorization)
        try await repo.deleteAllRecordsIncludingAssignments(
            committing: commitSessionAuthorization(authorization)
        )
        try validateSessionAuthorization(authorization)
    }

    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws {
        try mutationGate.validateCommittedEraseToken(
            authorization,
            operation: "consumer_tools_committed_erase"
        )
        // Quarantine can be the reason the user chose a full reset. Once the
        // coordinator has durably committed that destructive transaction,
        // this idempotent purge must remain available.
        try await repo.deleteAllRecordsIncludingAssignments()
    }

    private func destroyToolAndAssignments(
        id: UUID,
        allowPreset: Bool,
        authorization: SessionAuthorizationLease? = nil
    ) async throws {
        if let authorization {
            try validateSessionAuthorization(authorization)
        } else {
            try ensureStorageIntegrity()
        }
        guard let tool = try await repo.fetch(id: id) else { return }
        if tool.isPreset && !allowPreset {
            throw ApiRelayError.validationFailed(field: "isPreset", reason: "preset_not_deletable")
        }
        let committing: RepositoryCommit
        if let authorization {
            committing = commitSessionAuthorization(authorization)
        } else {
            committing = integrityRepositoryCommit()
        }
        try await repo.deleteWithAssignments(
            id: id,
            allowPreset: allowPreset,
            committing: committing
        )
    }

    private func confirmCurrent(
        reason: String,
        purpose: AuthPurpose,
        appPassword: String?
    ) async throws {
        let policy: RevealPolicy
        do {
            let storagePermit = try mutationGate.beginNormal(
                operation: "consumer_tools_auth_policy_read"
            )
            defer { storagePermit.finish() }
            policy = try await userPrefs.loadOrCreate().revealPolicy
        }
        try await CurrentRevealPolicyAuth.confirm(
            policy,
            gate: gate,
            reason: reason,
            purpose: purpose,
            appPassword: appPassword
        )
    }

    private static func toolPatchRequiresIdentity(_ patch: ConsumerToolPatch) -> Bool {
        patch.name != nil || patch.notes != nil || patch.isHidden != nil
    }
}
