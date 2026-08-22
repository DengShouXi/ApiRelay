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

    func add(keyId: UUID, consumerToolId: UUID) throws {
        let existing = try modelContext.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate { $0.keyId == keyId && $0.consumerToolId == consumerToolId }
        ))
        if !existing.isEmpty { return }
        modelContext.insert(KeyAssignment(keyId: keyId, consumerToolId: consumerToolId))
        try modelContext.save()
    }

    func remove(keyId: UUID, consumerToolId: UUID) throws {
        let rows = try modelContext.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate { $0.keyId == keyId && $0.consumerToolId == consumerToolId }
        ))
        for row in rows {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    func deleteAll(forKeyId keyId: UUID) throws {
        let rows = try modelContext.fetch(FetchDescriptor<KeyAssignment>(
            predicate: #Predicate { $0.keyId == keyId }
        ))
        for row in rows {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    /// FR-061：清空本仓库上下文中的全部指派。
    func deleteAllRecords() throws {
        try modelContext.deleteAllRecords(KeyAssignment.self)
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
