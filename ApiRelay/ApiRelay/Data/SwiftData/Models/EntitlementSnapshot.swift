import Foundation
import SwiftData

/// StoreKit 权益本地兜底（local，不同步）。
@Model
final class EntitlementSnapshot {
    static let singletonID = UUID(uuidString: "00000000-0000-4000-8000-000000000012")!

    var id: UUID = EntitlementSnapshot.singletonID
    var tier: String = EntitlementTier.free.rawValue
    var source: String = "storekit"
    var updatedAt: Date = Date()

    init(
        id: UUID = EntitlementSnapshot.singletonID,
        tier: EntitlementTier = .free,
        source: String = "storekit",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.tier = tier.rawValue
        self.source = source
        self.updatedAt = updatedAt
    }
}
