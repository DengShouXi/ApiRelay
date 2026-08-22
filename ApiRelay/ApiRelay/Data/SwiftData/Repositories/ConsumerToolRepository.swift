import Foundation
import SwiftData

@ModelActor
actor ConsumerToolRepository {
    func fetchAll(includeHidden: Bool = false, includeDeleted: Bool = false) throws -> [ConsumerToolDTO] {
        let models = try modelContext.fetch(FetchDescriptor<ConsumerTool>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        return models
            .filter { includeDeleted || $0.deletedAt == nil }
            .filter { includeHidden || !$0.isHidden }
            .map(Self.map)
    }

    func fetchSoftDeleted() throws -> [ConsumerToolDTO] {
        let models = try modelContext.fetch(FetchDescriptor<ConsumerTool>(
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        ))
        return models.filter { $0.deletedAt != nil }.map(Self.map)
    }

    func fetch(id: UUID) throws -> ConsumerToolDTO? {
        guard let model = try fetchModel(id: id) else { return nil }
        return Self.map(model)
    }

    @discardableResult
    func insert(_ draft: ConsumerToolDraft, id: UUID? = nil) throws -> UUID {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 48 else {
            throw ApiRelayError.validationFailed(field: "name", reason: "required_1_to_48")
        }
        let id = id ?? UUID()
        let trimmedNotes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let sortOrder = draft.sortOrder > 0 ? draft.sortOrder : (try nextSortOrder())
        let model = ConsumerTool(
            id: id,
            name: trimmed,
            iconSymbol: draft.iconSymbol,
            avatarSymbol: AvatarChoice.stored(symbol: draft.avatarSymbol, color: draft.avatarColor).0,
            avatarColor: AvatarChoice.stored(symbol: draft.avatarSymbol, color: draft.avatarColor).1,
            isPreset: draft.isPreset,
            notes: (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil,
            createdAt: now,
            updatedAt: now,
            sortOrder: sortOrder
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
        if let value = patch.notes { model.notes = value.isEmpty ? nil : value }
        if let value = patch.sortOrder { model.sortOrder = value }
        if patch.updatesAvatar {
            let stored = AvatarChoice.stored(symbol: patch.avatarSymbol, color: patch.avatarColor)
            model.avatarSymbol = stored.0
            model.avatarColor = stored.1
        }
        let touchesContent = patch.name != nil
            || patch.iconSymbol != nil
            || patch.isHidden != nil
            || patch.notes != nil
            || patch.updatesAvatar
        if touchesContent {
            model.updatedAt = Date()
        }
        try modelContext.save()
    }

    /// 按给定顺序重写 `sortOrder`（0…n-1）。不碰 `updatedAt`。
    func reorder(orderedIds: [UUID]) throws {
        for (index, id) in orderedIds.enumerated() {
            guard let model = try fetchModel(id: id) else { continue }
            model.sortOrder = index
        }
        try modelContext.save()
    }

    private func nextSortOrder() throws -> Int {
        let models = try modelContext.fetch(FetchDescriptor<ConsumerTool>())
        return (models.map(\.sortOrder).max() ?? -1) + 1
    }

    /// 移入回收站（默认保留 30 天）。回收站期间保留 KeyAssignment。
    func softDelete(id: UUID, deletedAt: Date = Date(), retainDays: Int = 30, allowPreset: Bool = false) throws {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        if model.isPreset && !allowPreset {
            throw ApiRelayError.validationFailed(field: "isPreset", reason: "preset_not_deletable")
        }
        model.deletedAt = deletedAt
        model.purgeAfter = deletedAt.addingTimeInterval(TimeInterval(retainDays * 24 * 3600))
        try modelContext.save()
    }

    func clearDeletionMarks(id: UUID) throws {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        model.deletedAt = nil
        model.purgeAfter = nil
        try modelContext.save()
    }

    /// 预置项默认不可物理删除（FR-007a）；`allowPreset` 仅用于清除历史自动种子。
    func delete(id: UUID, allowPreset: Bool = false) throws {
        guard let model = try fetchModel(id: id) else { return }
        if model.isPreset && !allowPreset {
            throw ApiRelayError.validationFailed(field: "isPreset", reason: "preset_not_deletable")
        }
        modelContext.delete(model)
        try modelContext.save()
    }

    /// FR-061：全量清除时预置项一并物理删除（用户销毁全部数据，不是单条删除）。
    func deleteAllRecords() throws {
        try modelContext.deleteAllRecords(ConsumerTool.self)
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
            notes: model.notes,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            sortOrder: model.sortOrder,
            deletedAt: model.deletedAt,
            purgeAfter: model.purgeAfter,
            avatarSymbol: model.avatarSymbol,
            avatarColor: model.avatarColor
        )
    }
}
