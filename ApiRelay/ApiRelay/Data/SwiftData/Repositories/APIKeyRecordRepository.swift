import Foundation
import SwiftData

@ModelActor
actor APIKeyRecordRepository {
    func fetch(
        accountId: UUID? = nil,
        lifecycles: [KeyLifecycle]? = nil
    ) throws -> [KeyRecordDTO] {
        let models = try modelContext.fetch(FetchDescriptor<APIKeyRecord>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
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
    func insert(_ draft: KeyRecordDraft, id: UUID? = nil) throws -> UUID {
        let trimmed = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else {
            throw ApiRelayError.validationFailed(field: "displayName", reason: "required_1_to_64")
        }
        let id = id ?? UUID()
        let now = Date()
        let sortOrder = draft.sortOrder > 0 ? draft.sortOrder : (try nextSortOrder(in: draft.accountId))
        let model = APIKeyRecord(
            id: id,
            accountId: draft.accountId,
            displayName: trimmed,
            maskedHint: nil,
            origin: draft.origin,
            providerKeyRef: draft.providerKeyRef,
            spendLimit: draft.spendLimit,
            notes: draft.notes,
            createdAt: now,
            updatedAt: now,
            secretLength: nil,
            sortOrder: sortOrder,
            avatarSymbol: AvatarChoice.stored(symbol: draft.avatarSymbol, color: draft.avatarColor).0,
            avatarColor: AvatarChoice.stored(symbol: draft.avatarSymbol, color: draft.avatarColor).1
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
        if let value = patch.lifecycle { model.lifecycle = value.rawValue }
        if let value = patch.spendLimit { model.spendLimit = value }
        if let value = patch.notes { model.notes = value.isEmpty ? nil : value }
        if let value = patch.deletedAt { model.deletedAt = value }
        if let value = patch.purgeAfter { model.purgeAfter = value }
        if let value = patch.healthState { model.healthState = value.rawValue }
        if let value = patch.lastCheckedAt { model.lastCheckedAt = value }
        if let value = patch.lastCheckNote { model.lastCheckNote = value }
        if let value = patch.sortOrder { model.sortOrder = value }
        if patch.updatesAvatar {
            let stored = AvatarChoice.stored(symbol: patch.avatarSymbol, color: patch.avatarColor)
            model.avatarSymbol = stored.0
            model.avatarColor = stored.1
        }
        model.updatedAt = Date()
        try modelContext.save()
    }

    /// 按给定顺序重写 `sortOrder`（0…n-1）。用于分区内拖拽排序。
    func reorder(orderedIds: [UUID]) throws {
        let now = Date()
        for (index, id) in orderedIds.enumerated() {
            guard let model = try fetchModel(id: id) else { continue }
            model.sortOrder = index
            model.updatedAt = now
        }
        try modelContext.save()
    }

    private func nextSortOrder(in accountId: UUID) throws -> Int {
        let models = try modelContext.fetch(FetchDescriptor<APIKeyRecord>())
        let maxOrder = models
            .filter { $0.accountId == accountId && $0.lifecycle != KeyLifecycle.softDeleted.rawValue }
            .map(\.sortOrder)
            .max()
        return (maxOrder ?? -1) + 1
    }

    /// 移入回收站：显式写 lifecycle / deletedAt / purgeAfter（默认 30 天）。
    func softDelete(id: UUID, deletedAt: Date = Date(), retainDays: Int = 30) throws {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        model.lifecycle = KeyLifecycle.softDeleted.rawValue
        model.deletedAt = deletedAt
        model.purgeAfter = deletedAt.addingTimeInterval(TimeInterval(retainDays * 24 * 3600))
        model.updatedAt = Date()
        try modelContext.save()
    }

    /// 回收站列表（按删除时间新→旧）。
    func fetchSoftDeleted() throws -> [KeyRecordDTO] {
        let soft = KeyLifecycle.softDeleted.rawValue
        let models = try modelContext.fetch(FetchDescriptor<APIKeyRecord>(
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        ))
        return try models.compactMap { model in
            guard model.lifecycle == soft else { return nil }
            return try map(model)
        }
    }

    func delete(id: UUID) throws {
        guard let model = try fetchModel(id: id) else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    /// FR-061：清空本仓库上下文中的全部密钥（含回收站），避免另开 ModelContext 删库后本 actor 仍读到旧对象。
    func deleteAllRecords() throws {
        try modelContext.deleteAllRecords(APIKeyRecord.self)
    }

    /// 清空升级前写入的末四位 / 长度。CloudKit 字段保留（不可删），值 MUST 为 nil。
    func clearStoredSecretFragments() throws {
        let models = try modelContext.fetch(FetchDescriptor<APIKeyRecord>())
        var changed = false
        for model in models {
            guard model.maskedHint != nil || model.secretLength != nil else { continue }
            model.maskedHint = nil
            model.secretLength = nil
            model.updatedAt = Date()
            changed = true
        }
        if changed {
            try modelContext.save()
        }
    }

    /// 仅测试：读取是否仍残留末四位 / 长度。
    func storedSecretFragments(id: UUID) throws -> (hint: String?, length: Int?) {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        return (model.maskedHint, model.secretLength)
    }

    /// 仅测试：写入升级前残留的末四位，供 `clearStoredSecretFragments` 验收。
    func plantLegacySecretFragments(id: UUID, hint: String, length: Int) throws {
        guard let model = try fetchModel(id: id) else {
            throw ApiRelayError.validationFailed(field: "id", reason: "not_found")
        }
        model.maskedHint = hint
        model.secretLength = length
        model.updatedAt = Date()
        try modelContext.save()
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
            maskedHint: nil,
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
            notes: model.notes,
            secretAvailable: false,
            secretLength: nil,
            sortOrder: model.sortOrder,
            avatarSymbol: model.avatarSymbol,
            avatarColor: model.avatarColor
        )
    }
}
