import Foundation
import SwiftData

protocol ConsumerToolServing: Actor {
    func tools(includeHidden: Bool) async throws -> [ConsumerToolDTO]
    /// 启动维护：不再自动写入预置使用端；并清除历史种子的预置项（用户自建保留）。
    func ensurePresetsSeeded() async throws
    func createTool(_ draft: ConsumerToolDraft) async throws -> UUID
    func updateTool(id: UUID, patch: ConsumerToolPatch) async throws
    func deleteTool(id: UUID) async throws

    func recentlyDeletedTools() async throws -> [ConsumerToolDTO]
    func restoreTool(id: UUID) async throws
    func permanentlyDeleteTool(id: UUID) async throws
    func purgeExpiredDeletedTools() async throws
}

actor ConsumerToolService: ConsumerToolServing {
    private let repo: ConsumerToolRepository
    private let assignments: KeyAssignmentRepository
    private let gate: RevealGate

    init(modelContainer: ModelContainer, gate: RevealGate) {
        self.repo = ConsumerToolRepository(modelContainer: modelContainer)
        self.assignments = KeyAssignmentRepository(modelContainer: modelContainer)
        self.gate = gate
    }

    func tools(includeHidden: Bool) async throws -> [ConsumerToolDTO] {
        try await repo.fetchAll(includeHidden: includeHidden, includeDeleted: false)
    }

    /// 使用端改为「用户自建」：不自动 seed；`PresetCatalog.consumerTools` 仅作添加表单的名称建议。
    /// 顺带清除历史上 `isPreset == true` 的种子（否则主列表占满且无法删除）。
    func ensurePresetsSeeded() async throws {
        let existing = try await repo.fetchAll(includeHidden: true, includeDeleted: true)
        for tool in existing where tool.isPreset {
            try await destroyToolAndAssignments(id: tool.id, allowPreset: true)
        }
        try await purgeExpiredDeletedTools()
    }

    func createTool(_ draft: ConsumerToolDraft) async throws -> UUID {
        var draft = draft
        draft.isPreset = false
        return try await repo.insert(draft)
    }

    func updateTool(id: UUID, patch: ConsumerToolPatch) async throws {
        try await repo.update(id: id, patch: patch)
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
        try await repo.clearDeletionMarks(id: id)
    }

    func permanentlyDeleteTool(id: UUID) async throws {
        try await gate.confirmMandatory(reason: String(localized: "gate.permanentDelete"))
        try await destroyToolAndAssignments(id: id, allowPreset: false)
    }

    func purgeExpiredDeletedTools() async throws {
        let deleted = try await repo.fetchSoftDeleted()
        let now = Date()
        for tool in deleted where (tool.purgeAfter ?? .distantFuture) < now {
            try await destroyToolAndAssignments(id: tool.id, allowPreset: true)
        }
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
