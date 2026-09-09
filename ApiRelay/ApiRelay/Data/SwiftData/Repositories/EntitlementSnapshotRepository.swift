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
        let now = Date()
        var models = try fetchSingletons()
        if models.isEmpty {
            let created = EntitlementSnapshot()
            modelContext.insert(created)
            models = [created]
        }
        for model in models {
            model.tier = tier.rawValue
            model.source = source
            model.updatedAt = now
        }
        try modelContext.save()
    }

    func pruneDuplicateIdentities() throws {
        try modelContext.pruneSyncedDuplicates(of: EntitlementSnapshot.self, id: \.id, rank: Self.rank)
    }

    private func ensureSingleton() throws -> EntitlementSnapshot {
        let models = try fetchSingletons()
        if let winner = SyncedIdentity.winner(in: models, rank: Self.rank) {
            return winner
        }
        let created = EntitlementSnapshot()
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    private func fetchSingletons() throws -> [EntitlementSnapshot] {
        let id = EntitlementSnapshot.singletonID
        return try modelContext.fetch(FetchDescriptor<EntitlementSnapshot>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    private static func rank(_ model: EntitlementSnapshot) -> SyncedIdentity.ReplicaRank {
        SyncedIdentity.ReplicaRank(
            updatedAt: model.updatedAt,
            isDeleted: false,
            fingerprint: [
                model.tier,
                model.source,
                SyncedIdentity.dateStamp(model.updatedAt),
            ].joined(separator: "\u{1e}")
        )
    }

    /// FR-061：清本地权益快照；StoreKit 交易保留，可经「恢复购买」写回。
    func deleteAllRecords() throws {
        try modelContext.deleteAllRecords(EntitlementSnapshot.self)
    }
}
