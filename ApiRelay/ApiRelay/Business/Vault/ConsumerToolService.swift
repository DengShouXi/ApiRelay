import Foundation
import SwiftData

protocol ConsumerToolServing: Actor {
    func tools(includeHidden: Bool) async throws -> [ConsumerToolDTO]
    func ensurePresetsSeeded() async throws
    func createTool(_ draft: ConsumerToolDraft) async throws -> UUID
    func updateTool(id: UUID, patch: ConsumerToolPatch) async throws
    func deleteTool(id: UUID) async throws
}

actor ConsumerToolService: ConsumerToolServing {
    private let repo: ConsumerToolRepository
    private let assignments: KeyAssignmentRepository

    init(modelContainer: ModelContainer) {
        self.repo = ConsumerToolRepository(modelContainer: modelContainer)
        self.assignments = KeyAssignmentRepository(modelContainer: modelContainer)
    }

    func tools(includeHidden: Bool) async throws -> [ConsumerToolDTO] {
        try await repo.fetchAll(includeHidden: includeHidden)
    }

    func ensurePresetsSeeded() async throws {
        let existing = try await repo.fetchAll(includeHidden: true)
        let existingNames = Set(existing.map(\.name))
        for (index, tool) in PresetCatalog.consumerTools.enumerated() where !existingNames.contains(tool.name) {
            _ = try await repo.insert(ConsumerToolDraft(
                name: tool.name,
                iconSymbol: tool.iconSymbol,
                isPreset: true,
                sortOrder: index
            ))
        }
    }

    func createTool(_ draft: ConsumerToolDraft) async throws -> UUID {
        try await repo.insert(draft)
    }

    func updateTool(id: UUID, patch: ConsumerToolPatch) async throws {
        try await repo.update(id: id, patch: patch)
    }

    /// 删除使用方：MUST NOT 级联删密钥，只删 KeyAssignment。
    func deleteTool(id: UUID) async throws {
        guard let tool = try await repo.fetch(id: id) else { return }
        if tool.isPreset {
            throw ApiRelayError.validationFailed(field: "isPreset", reason: "preset_not_deletable")
        }
        let keyIds = try await assignments.fetchKeyIDs(consumerToolId: id)
        for keyId in keyIds {
            try await assignments.remove(keyId: keyId, consumerToolId: id)
        }
        try await repo.delete(id: id)
    }
}
