import Foundation
import SwiftData

@ModelActor
actor KeyAssignmentRepository {
    func fetchConsumerToolIDs(keyId: UUID) throws -> [UUID] {
        try Self.dedupedConsumerToolIDs(keyId: keyId, in: modelContext)
    }

    func fetchKeyIDs(consumerToolId: UUID) throws -> [UUID] {
        let rows = try modelContext.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate { $0.consumerToolId == consumerToolId }
        ))
        var seen = Set<UUID>()
        var result: [UUID] = []
        for row in rows.sorted(by: { $0.createdAt < $1.createdAt }) {
            if seen.insert(row.keyId).inserted {
                result.append(row.keyId)
            }
        }
        return result
    }

    @discardableResult
    func add(
        keyId: UUID,
        consumerToolId: UUID,
        createdAt: Date = Date(),
        committing: RepositoryCommit = { operation in try operation() }
    ) throws -> Bool {
        let existing = try modelContext.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate { $0.keyId == keyId && $0.consumerToolId == consumerToolId }
        ))
        if !existing.isEmpty { return false }
        do {
            try committing {
                modelContext.insert(KeyAssignment(
                    keyId: keyId,
                    consumerToolId: consumerToolId,
                    createdAt: createdAt
                ))
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
        return true
    }

    /// Removes only the assignment row created by one uncommitted import.
    @discardableResult
    func removeIfCreatedAtMatches(
        keyId: UUID,
        consumerToolId: UUID,
        createdAt: Date,
        committing: RepositoryCommit = { operation in try operation() }
    ) throws -> Bool {
        let rows = try modelContext.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate {
                $0.keyId == keyId
                    && $0.consumerToolId == consumerToolId
                    && $0.createdAt == createdAt
            }
        ))
        guard !rows.isEmpty else { return false }
        do {
            try committing {
                for row in rows { modelContext.delete(row) }
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
        return true
    }

    func remove(
        keyId: UUID,
        consumerToolId: UUID,
        committing: RepositoryCommit = { operation in try operation() }
    ) throws {
        let rows = try modelContext.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate { $0.keyId == keyId && $0.consumerToolId == consumerToolId }
        ))
        do {
            try committing {
                for row in rows {
                    modelContext.delete(row)
                }
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func deleteAll(
        forKeyId keyId: UUID,
        committing: RepositoryCommit = { operation in try operation() }
    ) throws {
        let rows = try modelContext.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate { $0.keyId == keyId }
        ))
        do {
            try committing {
                for row in rows {
                    modelContext.delete(row)
                }
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 补偿专用：一次 save 把某把密钥的指派精确恢复为给定集合。
    func replaceConsumerToolIDs(
        keyId: UUID,
        consumerToolIds: [UUID],
        committing: RepositoryCommit = { operation in try operation() }
    ) throws {
        let rows = try modelContext.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate { $0.keyId == keyId }
        ))
        do {
            try committing {
                for row in rows {
                    modelContext.delete(row)
                }
                var seen = Set<UUID>()
                for consumerToolId in consumerToolIds where seen.insert(consumerToolId).inserted {
                    modelContext.insert(KeyAssignment(keyId: keyId, consumerToolId: consumerToolId))
                }
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// FR-061：清空本仓库上下文中的全部指派。
    func deleteAllRecords(
        committing: RepositoryCommit = { operation in try operation() }
    ) throws {
        do {
            try committing {
                try modelContext.deleteAllRecords(KeyAssignment.self)
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func assignmentKind(keyId: UUID) throws -> AssignmentKind {
        let tools = try fetchConsumerToolIDs(keyId: keyId)
        switch tools.count {
        case 0: return .unassigned
        case 1: return .exclusive(tools[0])
        default: return .shared(tools)
        }
    }

    /// 供同容器内其他 Repository 复用；按 (keyId, consumerToolId) 去重。
    static func dedupedConsumerToolIDs(keyId: UUID, in context: ModelContext) throws -> [UUID] {
        let rows = try context.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate { $0.keyId == keyId }
        ))
        var seen = Set<UUID>()
        var result: [UUID] = []
        for row in rows.sorted(by: { $0.createdAt < $1.createdAt }) {
            if seen.insert(row.consumerToolId).inserted {
                result.append(row.consumerToolId)
            }
        }
        return result
    }
}
