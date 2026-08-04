import Foundation
import SwiftData

@ModelActor
actor APIKeyRecordRepository {
    func fetch(
        accountId: UUID? = nil,
        lifecycles: [KeyLifecycle]? = nil
    ) throws -> [KeyRecordDTO] {
        let models = try modelContext.fetch(FetchDescriptor<APIKeyRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        let lifecycleFilter = lifecycles.map { Set($0.map(\.rawValue)) }
        return try models.compactMap { model in
            if let accountId, model.accountId != accountId { return nil }
            if let lifecycleFilter, !lifecycleFilter.contains(model.lifecycle) { return nil }
            return try map(model)
        }
    }

    func fetch(id: UUID) throws -> KeyRecordDTO? {
        guard let model = try fetchModel(id: id) else { return nil }
        return try map(model)
    }

    func countActiveNonDeleted() throws -> Int {
        let active = KeyLifecycle.active.rawValue
        let all = try modelContext.fetch(FetchDescriptor<APIKeyRecord>())
        return all.filter { $0.lifecycle == active && $0.deletedAt == nil }.count
    }

    @discardableResult
    func insert(_ draft: KeyRecordDraft) throws -> UUID {
        let trimmed = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else {
            throw ApiRelayError.validationFailed(field: "displayName", reason: "required_1_to_64")
        }
        let id = UUID()
        let now = Date()
        let model = APIKeyRecord(
            id: id,
            accountId: draft.accountId,
            displayName: trimmed,
            maskedHint: draft.maskedHint,
            origin: draft.origin,
            providerKeyRef: draft.providerKeyRef,
            spendLimit: draft.spendLimit,
            notes: draft.notes,
            createdAt: now,
            updatedAt: now,
            secretLength: draft.secretLength
        )
        modelContext.insert(model)
        try modelContext.save()
        return id
    }

    func update(id: UUID, patch: KeyRecordPatch) throws {
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
        if let value = patch.maskedHint { model.maskedHint = value }
        if let value = patch.lifecycle { model.lifecycle = value.rawValue }
        if let value = patch.spendLimit { model.spendLimit = value }
        if let value = patch.notes { model.notes = value }
        if let value = patch.deletedAt { model.deletedAt = value }
        if let value = patch.purgeAfter { model.purgeAfter = value }
        if let value = patch.healthState { model.healthState = value.rawValue }
        if let value = patch.lastCheckedAt { model.lastCheckedAt = value }
        if let value = patch.lastCheckNote { model.lastCheckNote = value }
        if let value = patch.secretLength { model.secretLength = value }
        model.updatedAt = Date()
        try modelContext.save()
    }

    func delete(id: UUID) throws {
        guard let model = try fetchModel(id: id) else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    /// 弱重复：同账号、相同末 4 位掩码、相同 secretLength（FR-057）。
    func findWeakDuplicate(accountId: UUID, last4: String, length: Int) throws -> UUID? {
        let all = try modelContext.fetch(FetchDescriptor<APIKeyRecord>())
        return all.first {
            $0.accountId == accountId
                && $0.lifecycle != KeyLifecycle.softDeleted.rawValue
                && $0.maskedHint == last4
                && $0.secretLength == length
        }?.id
    }

    func clearDeletionMarks(id: UUID) throws {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        model.lifecycle = KeyLifecycle.active.rawValue
        model.deletedAt = nil
        model.purgeAfter = nil
        model.updatedAt = Date()
        try modelContext.save()
    }

    private func fetchModel(id: UUID) throws -> APIKeyRecord? {
        var descriptor = FetchDescriptor<APIKeyRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func map(_ model: APIKeyRecord) throws -> KeyRecordDTO {
        let toolIDs = try KeyAssignmentRepository.dedupedConsumerToolIDs(
            keyId: model.id,
            in: modelContext
        )
        let origin = KeyOrigin(rawValue: model.origin) ?? .manualEntry
        let lifecycle = KeyLifecycle(rawValue: model.lifecycle) ?? .active
        let healthState = KeyHealthState(rawValue: model.healthState) ?? .unknown
        return KeyRecordDTO(
            id: model.id,
            accountId: model.accountId,
            consumerToolIds: toolIDs,
            displayName: model.displayName,
            maskedHint: model.maskedHint,
            origin: origin,
            providerKeyRef: model.providerKeyRef,
            lifecycle: lifecycle,
            health: KeyHealthDTO(
                state: healthState,
                lastCheckedAt: model.lastCheckedAt,
                lastCheckNote: model.lastCheckNote
            ),
            deletedAt: model.deletedAt,
            purgeAfter: model.purgeAfter,
            spendLimit: model.spendLimit,
            secretAvailable: false
        )
    }
}
