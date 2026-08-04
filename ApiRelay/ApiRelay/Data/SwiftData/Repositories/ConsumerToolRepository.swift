import Foundation
import SwiftData

@ModelActor
actor ConsumerToolRepository {
    func fetchAll(includeHidden: Bool = false) throws -> [ConsumerToolDTO] {
        let models = try modelContext.fetch(FetchDescriptor<ConsumerTool>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        return models
            .filter { includeHidden || !$0.isHidden }
            .map(Self.map)
    }

    func fetch(id: UUID) throws -> ConsumerToolDTO? {
        guard let model = try fetchModel(id: id) else { return nil }
        return Self.map(model)
    }

    @discardableResult
    func insert(_ draft: ConsumerToolDraft) throws -> UUID {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 48 else {
            throw ApiRelayError.validationFailed(field: "name", reason: "required_1_to_48")
        }
        let id = UUID()
        let model = ConsumerTool(
            id: id,
            name: trimmed,
            iconSymbol: draft.iconSymbol,
            isPreset: draft.isPreset,
            sortOrder: draft.sortOrder
        )
        modelContext.insert(model)
        try modelContext.save()
        return id
    }

    func update(id: UUID, patch: ConsumerToolPatch) throws {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        if let name = patch.name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 48 else {
                throw ApiRelayError.validationFailed(field: "name", reason: "required_1_to_48")
            }
            model.name = trimmed
        }
        if let value = patch.iconSymbol { model.iconSymbol = value }
        if let value = patch.isHidden { model.isHidden = value }
        if let value = patch.sortOrder { model.sortOrder = value }
        try modelContext.save()
    }

    /// 预置项不可物理删除（FR-007a）。
    func delete(id: UUID) throws {
        guard let model = try fetchModel(id: id) else { return }
        if model.isPreset {
            throw ApiRelayError.validationFailed(field: "isPreset", reason: "preset_not_deletable")
        }
        modelContext.delete(model)
        try modelContext.save()
    }

    private func fetchModel(id: UUID) throws -> ConsumerTool? {
        var descriptor = FetchDescriptor<ConsumerTool>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func map(_ model: ConsumerTool) -> ConsumerToolDTO {
        ConsumerToolDTO(
            id: model.id,
            name: model.name,
            iconSymbol: model.iconSymbol,
            isPreset: model.isPreset,
            isHidden: model.isHidden,
            createdAt: model.createdAt,
            sortOrder: model.sortOrder
        )
    }
}
