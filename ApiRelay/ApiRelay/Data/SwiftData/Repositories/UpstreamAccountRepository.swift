import Foundation
import SwiftData

/// UpstreamAccount 持久化。不向上层泄露 ModelContext。
@ModelActor
actor UpstreamAccountRepository {
    func fetchAll() throws -> [UpstreamAccountDTO] {
        let descriptor = FetchDescriptor<UpstreamAccount>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).map(Self.map)
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
        let model = UpstreamAccount(
            id: id,
            platform: draft.platform,
            customPlatformName: draft.customPlatformName,
            displayName: trimmed,
            customBaseURL: draft.customBaseURL,
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
        if let name = patch.displayName {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 64 else {
                throw ApiRelayError.validationFailed(field: "displayName", reason: "required_1_to_64")
            }
            model.displayName = trimmed
        }
        if let value = patch.customPlatformName { model.customPlatformName = value }
        if let value = patch.customBaseURL { model.customBaseURL = value }
        if let value = patch.hasManagementCredential { model.hasManagementCredential = value }
        if let value = patch.sortOrder { model.sortOrder = value }
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
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            sortOrder: model.sortOrder
        )
    }
}
