import Foundation
import SwiftData

/// V2 余额快照；V1 仅建实体。
@Model
final class BalanceSnapshot {
    var id: UUID = UUID()
    var accountId: UUID = UUID()
    var currency: String = "USD"
    var totalBalance: Decimal?
    var grantedBalance: Decimal?
    var toppedUpBalance: Decimal?
    var isSufficient: Bool?
    var fetchedAt: Date = Date()

    init(
        id: UUID = UUID(),
        accountId: UUID,
        currency: String = "USD",
        totalBalance: Decimal? = nil,
        grantedBalance: Decimal? = nil,
        toppedUpBalance: Decimal? = nil,
        isSufficient: Bool? = nil,
        fetchedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.currency = currency
        self.totalBalance = totalBalance
        self.grantedBalance = grantedBalance
        self.toppedUpBalance = toppedUpBalance
        self.isSufficient = isSufficient
        self.fetchedAt = fetchedAt
    }
}
