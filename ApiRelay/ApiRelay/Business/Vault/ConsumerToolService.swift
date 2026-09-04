import Foundation
import SwiftData

protocol ConsumerToolServing: Actor {
    func tools(includeHidden: Bool) async throws -> [ConsumerToolDTO]
    /// 启动维护：不再自动写入预置使用端；并清除历史种子的预置项（用户自建保留）。
    func ensurePresetsSeeded() async throws
    func createTool(_ draft: ConsumerToolDraft) async throws -> UUID
    func updateTool(id: UUID, patch: ConsumerToolPatch) async throws
    func deleteTool(id: UUID) async throws
    /// 按用户拖拽结果重写使用方分区顺序（`orderedIds` 为从上到下）。不改 `updatedAt`。
    func reorderTools(orderedIds: [UUID]) async throws

    func recentlyDeletedTools() async throws -> [ConsumerToolDTO]
    func restoreTool(id: UUID) async throws
    func permanentlyDeleteTool(id: UUID) async throws
    func purgeExpiredDeletedTools() async throws

    /// 调用方 MUST 已完成 `confirmMandatory`。
    func restoreToolsAfterAuthentication(ids: [UUID]) async -> TrashBatchOutcome
    /// 调用方 MUST 已完成 `confirmMandatory`。
    func permanentlyDeleteToolsAfterAuthentication(ids: [UUID]) async -> TrashBatchOutcome
    /// FR-061：物理删除本服务上下文中的使用方与指派（含回收站）。
    func purgeAllRecordsForErase() async throws
}

actor ConsumerToolService: ConsumerToolServing {
    private let repo: ConsumerToolRepository
    private let assignments: KeyAssignmentRepository
    private let gate: RevealGateServing

    init(modelContainer: ModelContainer, gate: RevealGateServing) {
        self.repo = ConsumerToolRepository(modelContainer: modelContainer)
        self.assignments = KeyAssignmentRepository(modelContainer: modelContainer)
        self.gate = gate
    }

    func tools(includeHidden: Bool) async throws -> [ConsumerToolDTO] {
        try await repo.fetchAll(includeHidden: includeHidden, includeDeleted: false)
    }

    /// 使用端改为「用户自建」：不自动 seed；`PresetCatalog.consumerTools` 仅作添加表单的名称建议。
    /// 顺带清除历史上 `isPreset == true` 的种子（否则主列表占满且无法删除），
    /// 为缺少 `iconSymbol` 的存量按名称回填，并把 VS Code 族上的废止三截符号换成现行徽章。
    func ensurePresetsSeeded() async throws {
        let existing = try await repo.fetchAll(includeHidden: true, includeDeleted: true)
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
            try await repo.update(id: tool.id, patch: patch)
        }
        try await purgeExpiredDeletedTools()
    }

    func createTool(_ draft: ConsumerToolDraft) async throws -> UUID {
        var draft = draft
        draft.isPreset = false
        let stored = draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stored.isEmpty {
            draft.iconSymbol = PresetCatalog.toolSymbol(name: draft.name)
        }
        return try await repo.insert(draft)
    }

    func updateTool(id: UUID, patch: ConsumerToolPatch) async throws {
        try await repo.update(id: id, patch: patch)
    }

    func reorderTools(orderedIds: [UUID]) async throws {
        try await repo.reorder(orderedIds: orderedIds)
    }

    /// 删除使用方：移入回收站；回收站期间保留 KeyAssignment，不级联删密钥。
    func deleteTool(id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.deleteTool"))
        try await repo.softDelete(id: id, retainDays: 30, allowPreset: false)
    }

    func recentlyDeletedTools() async throws -> [ConsumerToolDTO] {
        try await repo.fetchSoftDeleted()
    }

    func restoreTool(id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.restoreTool"))
        _ = try await restoreToolAfterAuth(id, requirePresent: true)
    }

    func permanentlyDeleteTool(id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.permanentDelete"))
        _ = try await permanentlyDeleteToolAfterAuth(id)
    }

    /// 调用方 MUST 已完成 `confirmMandatory`。
    func restoreToolsAfterAuthentication(ids: [UUID]) async -> TrashBatchOutcome {
        var successCount = 0
        var failures: [TrashBatchItemFailure] = []
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            let name = (try? await repo.fetch(id: id))?.name ?? id.uuidString
            do {
                if try await restoreToolAfterAuth(id, requirePresent: false) {
                    successCount += 1
                }
            } catch {
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        return TrashBatchOutcome(successCount: successCount, failures: failures)
    }

    /// 调用方 MUST 已完成 `confirmMandatory`。
    func permanentlyDeleteToolsAfterAuthentication(ids: [UUID]) async -> TrashBatchOutcome {
        var successCount = 0
        var failures: [TrashBatchItemFailure] = []
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            let name = (try? await repo.fetch(id: id))?.name ?? id.uuidString
            do {
                if try await permanentlyDeleteToolAfterAuth(id) {
                    successCount += 1
                }
            } catch {
                failures.append(TrashBatchItemFailure(name: name, detail: error.localizedDescription))
            }
        }
        return TrashBatchOutcome(successCount: successCount, failures: failures)
    }

    @discardableResult
    private func restoreToolAfterAuth(_ id: UUID, requirePresent: Bool) async throws -> Bool {
        guard let tool = try await repo.fetch(id: id) else {
            if requirePresent {
                throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
            }
            return true
        }
        guard tool.deletedAt != nil else { return true }
        try await repo.clearDeletionMarks(id: id)
        return true
    }

    @discardableResult
    private func permanentlyDeleteToolAfterAuth(_ id: UUID) async throws -> Bool {
        guard try await repo.fetch(id: id) != nil else { return true }
        try await destroyToolAndAssignments(id: id, allowPreset: false)
        return true
    }

    func purgeExpiredDeletedTools() async throws {
        let deleted = try await repo.fetchSoftDeleted()
        let now = Date()
        for tool in deleted where (tool.purgeAfter ?? .distantFuture) < now {
            try await destroyToolAndAssignments(id: tool.id, allowPreset: true)
        }
    }

    /// FR-061：物理删除本服务上下文中的使用方与指派（含回收站）。
    func purgeAllRecordsForErase() async throws {
        try await assignments.deleteAllRecords()
        try await repo.deleteAllRecords()
    }

    private func destroyToolAndAssignments(id: UUID, allowPreset: Bool) async throws {
        guard let tool = try await repo.fetch(id: id) else { return }
        if tool.isPreset && !allowPreset {
            throw ApiRelayError.validationFailed(field: "isPreset", reason: "preset_not_deletable")
        }
        let keyIds = try await assignments.fetchKeyIDs(consumerToolId: id)
        for keyId in keyIds {
            try await assignments.remove(keyId: keyId, consumerToolId: id)
        }
        try await repo.delete(id: id, allowPreset: allowPreset)
    }
}
