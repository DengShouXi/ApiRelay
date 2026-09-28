import Foundation
import SwiftData

/// 本机 StoreKit 权益观测记录（local，不同步）；不得作为业务授权依据。
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
