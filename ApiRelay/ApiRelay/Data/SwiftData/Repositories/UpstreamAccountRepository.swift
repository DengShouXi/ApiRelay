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
    func insert(_ draft: UpstreamAccountDraft, id: UUID? = nil) throws -> UUID {
        let trimmed = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else {
            throw ApiRelayError.validationFailed(field: "displayName", reason: "required_1_to_64")
        }
        let id = id ?? UUID()
        let now = Date()
        let trimmedNotes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortOrder = draft.sortOrder > 0 ? draft.sortOrder : (try nextSortOrder())
        let model = UpstreamAccount(
            id: id,
            platform: draft.platform,
            customPlatformName: draft.customPlatformName,
            displayName: trimmed,
            customBaseURL: draft.customBaseURL,
            notes: (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil,
            createdAt: now,
            updatedAt: now,
            sortOrder: sortOrder
        )
        if draft.avatarSymbol != nil || draft.avatarColor != nil {
            let stored = AvatarChoice.stored(symbol: draft.avatarSymbol, color: draft.avatarColor)
            model.avatarSymbol = stored.0
            model.avatarColor = stored.1
        }
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
        if patch.updatesAvatar {
            let stored = AvatarChoice.stored(symbol: patch.avatarSymbol, color: patch.avatarColor)
            model.avatarSymbol = stored.0
            model.avatarColor = stored.1
        }
        let touchesContent = patch.platform != nil
            || patch.displayName != nil
            || patch.customPlatformName != nil
            || patch.customBaseURL != nil
            || patch.hasManagementCredential != nil
            || patch.notes != nil
            || patch.updatesAvatar
        if touchesContent {
            model.updatedAt = Date()
        }
        try modelContext.save()
    }

    /// 按给定顺序重写 `sortOrder`（0…n-1）。不碰 `updatedAt`（自定义拖拽不是「上次修改」）。
    func reorder(orderedIds: [UUID]) throws {
        for (index, id) in orderedIds.enumerated() {
            guard let model = try fetchModel(id: id) else { continue }
            model.sortOrder = index
        }
        try modelContext.save()
    }

    private func nextSortOrder() throws -> Int {
        let models = try modelContext.fetch(FetchDescriptor<UpstreamAccount>())
        return (models.map(\.sortOrder).max() ?? -1) + 1
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

    /// FR-061：清空本仓库上下文中的全部上游账号（含回收站）。
    func deleteAllRecords() throws {
        try modelContext.deleteAllRecords(UpstreamAccount.self)
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
            purgeAfter: model.purgeAfter,
            avatarSymbol: model.avatarSymbol,
            avatarColor: model.avatarColor
        )
    }
}
