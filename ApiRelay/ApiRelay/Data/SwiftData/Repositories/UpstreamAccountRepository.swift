import Foundation
import SwiftData

/// UpstreamAccount 持久化。不向上层泄露 ModelContext。
@ModelActor
actor UpstreamAccountRepository {
    func fetchAll(includeDeleted: Bool = false) throws -> [UpstreamAccountDTO] {
        let descriptor = FetchDescriptor<UpstreamAccount>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
            .filter { includeDeleted || $0.deletedAt == nil }
            .map(Self.map)
    }

    func fetchSoftDeleted() throws -> [UpstreamAccountDTO] {
        let models = try modelContext.fetch(FetchDescriptor<UpstreamAccount>(
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        ))
        return models.filter { $0.deletedAt != nil }.map(Self.map)
    }

    func fetch(id: UUID) throws -> UpstreamAccountDTO? {
        var descriptor = FetchDescriptor<UpstreamAccount>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(Self.map)
    }

    @discardableResult
    func insert(_ draft: UpstreamAccountDraft) throws -> UUID {
        let trimmed = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else {
            throw ApiRelayError.validationFailed(field: "displayName", reason: "required_1_to_64")
        }
        let id = UUID()
        let now = Date()
        let trimmedNotes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = UpstreamAccount(
            id: id,
            platform: draft.platform,
            customPlatformName: draft.customPlatformName,
            displayName: trimmed,
            customBaseURL: draft.customBaseURL,
            notes: (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil,
            createdAt: now,
            updatedAt: now,
            sortOrder: draft.sortOrder
        )
        modelContext.insert(model)
        try modelContext.save()
        return id
    }

    func update(id: UUID, patch: UpstreamAccountPatch) throws {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        if let platform = patch.platform {
            let trimmed = platform.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ApiRelayError.validationFailed(field: "platform", reason: "required")
            }
            model.platform = trimmed
        }
        if let name = patch.displayName {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 64 else {
                throw ApiRelayError.validationFailed(field: "displayName", reason: "required_1_to_64")
            }
            model.displayName = trimmed
        }
        if let value = patch.customPlatformName {
            model.customPlatformName = value.isEmpty ? nil : value
        }
        if let value = patch.customBaseURL {
            model.customBaseURL = value.isEmpty ? nil : value
        }
        if let value = patch.hasManagementCredential { model.hasManagementCredential = value }
        if let value = patch.notes { model.notes = value.isEmpty ? nil : value }
        if let value = patch.sortOrder { model.sortOrder = value }
        model.updatedAt = Date()
        try modelContext.save()
    }

    /// 移入回收站（默认保留 30 天）。
    func softDelete(id: UUID, deletedAt: Date = Date(), retainDays: Int = 30) throws {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        model.deletedAt = deletedAt
        model.purgeAfter = deletedAt.addingTimeInterval(TimeInterval(retainDays * 24 * 3600))
        model.updatedAt = Date()
        try modelContext.save()
    }

    func clearDeletionMarks(id: UUID) throws {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        model.deletedAt = nil
        model.purgeAfter = nil
        model.updatedAt = Date()
        try modelContext.save()
    }

    func delete(id: UUID) throws {
        guard let model = try fetchModel(id: id) else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    private func fetchModel(id: UUID) throws -> UpstreamAccount? {
        var descriptor = FetchDescriptor<UpstreamAccount>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func map(_ model: UpstreamAccount) -> UpstreamAccountDTO {
        UpstreamAccountDTO(
            id: model.id,
            platform: model.platform,
            customPlatformName: model.customPlatformName,
            displayName: model.displayName,
            customBaseURL: model.customBaseURL,
            hasManagementCredential: model.hasManagementCredential,
            notes: model.notes,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            sortOrder: model.sortOrder,
            deletedAt: model.deletedAt,
            purgeAfter: model.purgeAfter
        )
    }
}
