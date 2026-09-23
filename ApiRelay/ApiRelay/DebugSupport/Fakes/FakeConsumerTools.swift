#if DEBUG
import Foundation

/// 假使用方库：内存 CRUD + 软删。不碰 SwiftData。
actor FakeConsumerTools: ConsumerToolServing {
    var journal = FakeJournal()
    private var toolsById: [UUID: ConsumerToolDTO] = [:]
    private var appPasswordGateEnabled = false
    private var expectedAppPassword: String?

    /// Preview 用：预置一个使用方。
    init(seedPreviewSample: Bool = false) {
        guard seedPreviewSample else { return }
        let id = UUID()
        toolsById[id] = .fake(id: id, name: "Preview Cursor")
    }

    func tools(includeHidden: Bool) async throws -> [ConsumerToolDTO] {
        try journal.record("tools")
        return toolsById.values
            .filter { $0.deletedAt == nil }
            .filter { includeHidden || !$0.isHidden }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func ensurePresetsSeeded() async throws {
        try journal.record("ensurePresetsSeeded")
    }

    func pruneDuplicateIdentities() async throws {
        try journal.record("pruneDuplicateIdentities")
    }

    func createTool(_ draft: ConsumerToolDraft) async throws -> UUID {
        try journal.record("createTool")
        let id = UUID()
        let now = Date()
        toolsById[id] = ConsumerToolDTO(
            id: id,
            name: draft.name,
            iconSymbol: draft.iconSymbol,
            isPreset: draft.isPreset,
            isHidden: false,
            notes: draft.notes,
            createdAt: now,
            updatedAt: now,
            sortOrder: draft.sortOrder,
            deletedAt: nil,
            purgeAfter: nil,
            avatarSymbol: draft.avatarSymbol,
            avatarColor: draft.avatarColor
        )
        return id
    }

    func updateTool(id: UUID, patch: ConsumerToolPatch, appPassword: String?) async throws {
        _ = appPassword
        try journal.record("updateTool")
        guard let tool = toolsById[id], tool.deletedAt == nil else {
            throw ApiRelayError.validationFailed(field: "tool", reason: "not_found")
        }
        toolsById[id] = ConsumerToolDTO(
            id: tool.id,
            name: patch.name ?? tool.name,
            iconSymbol: patch.iconSymbol ?? tool.iconSymbol,
            isPreset: tool.isPreset,
            isHidden: patch.isHidden ?? tool.isHidden,
            notes: patch.notes ?? tool.notes,
            createdAt: tool.createdAt,
            updatedAt: Date(),
            sortOrder: patch.sortOrder ?? tool.sortOrder,
            deletedAt: tool.deletedAt,
            purgeAfter: tool.purgeAfter,
            avatarSymbol: patch.updatesAvatar ? patch.avatarSymbol : tool.avatarSymbol,
            avatarColor: patch.updatesAvatar ? patch.avatarColor : tool.avatarColor
        )
    }

    func deleteTool(id: UUID, appPassword: String?) async throws {
        _ = appPassword
        try journal.record("deleteTool")
        guard let tool = toolsById[id], tool.deletedAt == nil else {
            throw ApiRelayError.validationFailed(field: "tool", reason: "not_found")
        }
        let now = Date()
        toolsById[id] = ConsumerToolDTO(
            id: tool.id,
            name: tool.name,
            iconSymbol: tool.iconSymbol,
            isPreset: tool.isPreset,
            isHidden: tool.isHidden,
            notes: tool.notes,
            createdAt: tool.createdAt,
            updatedAt: now,
            sortOrder: tool.sortOrder,
            deletedAt: now,
            purgeAfter: now.addingTimeInterval(30 * 24 * 3600),
            avatarSymbol: tool.avatarSymbol,
            avatarColor: tool.avatarColor
        )
    }

    func reorderTools(orderedIds: [UUID]) async throws {
        try journal.record("reorderTools")
        for (index, id) in orderedIds.enumerated() {
            guard let tool = toolsById[id] else { continue }
            toolsById[id] = ConsumerToolDTO(
                id: tool.id,
                name: tool.name,
                iconSymbol: tool.iconSymbol,
                isPreset: tool.isPreset,
                isHidden: tool.isHidden,
                notes: tool.notes,
                createdAt: tool.createdAt,
                updatedAt: tool.updatedAt,
                sortOrder: index,
                deletedAt: tool.deletedAt,
                purgeAfter: tool.purgeAfter,
                avatarSymbol: tool.avatarSymbol,
                avatarColor: tool.avatarColor
            )
        }
    }

    func recentlyDeletedTools() async throws -> [ConsumerToolDTO] {
        try journal.record("recentlyDeletedTools")
        return toolsById.values
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    func restoreTool(id: UUID, appPassword: String?) async throws {
        _ = appPassword
        try journal.record("restoreTool")
        guard restoreOne(id) else {
            throw ApiRelayError.validationFailed(field: "tool", reason: "not_found")
        }
    }

    func permanentlyDeleteTool(id: UUID, appPassword: String?) async throws {
        try rejectIfAppPasswordMissing(appPassword)
        try journal.record("permanentlyDeleteTool")
        toolsById[id] = nil
    }

    func purgeExpiredDeletedTools() async throws {
        try journal.record("purgeExpiredDeletedTools")
        let now = Date()
        for (id, tool) in toolsById {
            if let purge = tool.purgeAfter, purge <= now {
                toolsById[id] = nil
            }
        }
    }

    func restoreToolsAfterAuthentication(
        ids: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome {
        _ = authorization
        journal.recordNonThrowing("restoreToolsAfterAuthentication")
        var success = 0
        var failures: [TrashBatchItemFailure] = []
        for id in ids {
            if restoreOne(id) {
                success += 1
            } else {
                failures.append(TrashBatchItemFailure(name: id.uuidString, detail: "restore_failed"))
            }
        }
        return TrashBatchOutcome(successCount: success, failures: failures)
    }

    func permanentlyDeleteToolsAfterAuthentication(
        ids: [UUID],
        authorization: SessionAuthorizationLease
    ) async throws -> TrashBatchOutcome {
        _ = authorization
        journal.recordNonThrowing("permanentlyDeleteToolsAfterAuthentication")
        var success = 0
        for id in ids where toolsById[id] != nil {
            toolsById[id] = nil
            success += 1
        }
        return TrashBatchOutcome(successCount: success, failures: [])
    }

    func purgeAllRecordsForErase(authorization: SessionAuthorizationLease) async throws {
        _ = authorization
        try journal.record("purgeAllRecordsForErase")
        toolsById.removeAll()
    }

    func purgeAllRecordsForCommittedErase(
        authorization: CommittedEraseToken
    ) async throws {
        try authorization.validate(operation: "fake_consumer_tools_committed_erase")
        try journal.record("purgeAllRecordsForCommittedErase")
        toolsById.removeAll()
    }

    func setAppPasswordGate(enabled: Bool, expected: String? = "correct-password") {
        appPasswordGateEnabled = enabled
        expectedAppPassword = expected
    }

    private func rejectIfAppPasswordMissing(_ appPassword: String?) throws {
        guard appPasswordGateEnabled else { return }
        let trimmed = appPassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw ApiRelayError.validationFailed(
                field: "revealPolicy",
                reason: "master_password_prompt_required"
            )
        }
        if let expectedAppPassword, trimmed != expectedAppPassword {
            throw ApiRelayError.authenticationFailed
        }
    }

    @discardableResult
    private func restoreOne(_ id: UUID) -> Bool {
        guard let tool = toolsById[id], tool.deletedAt != nil else { return false }
        toolsById[id] = ConsumerToolDTO(
            id: tool.id,
            name: tool.name,
            iconSymbol: tool.iconSymbol,
            isPreset: tool.isPreset,
            isHidden: tool.isHidden,
            notes: tool.notes,
            createdAt: tool.createdAt,
            updatedAt: Date(),
            sortOrder: tool.sortOrder,
            deletedAt: nil,
            purgeAfter: nil,
            avatarSymbol: tool.avatarSymbol,
            avatarColor: tool.avatarColor
        )
        return true
    }
}
#endif
