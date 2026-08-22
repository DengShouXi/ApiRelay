import Foundation
import SwiftData

@ModelActor
actor EntitlementSnapshotRepository {
    func loadOrCreate() throws -> EntitlementSnapshotDTO {
        let model = try ensureSingleton()
        return EntitlementSnapshotDTO(
            id: model.id,
            tier: EntitlementTier(rawValue: model.tier) ?? .free,
            source: model.source,
            updatedAt: model.updatedAt
        )
    }

    func update(tier: EntitlementTier, source: String) throws {
        let model = try ensureSingleton()
        model.tier = tier.rawValue
        model.source = source
        model.updatedAt = Date()
        try modelContext.save()
    }

    private func ensureSingleton() throws -> EntitlementSnapshot {
        let id = EntitlementSnapshot.singletonID
        var descriptor = FetchDescriptor<EntitlementSnapshot>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let created = EntitlementSnapshot()
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    /// FR-061：清本地权益快照；StoreKit 交易保留，可经「恢复购买」写回。
    func deleteAllRecords() throws {
        try modelContext.deleteAllRecords(EntitlementSnapshot.self)
    }
}
