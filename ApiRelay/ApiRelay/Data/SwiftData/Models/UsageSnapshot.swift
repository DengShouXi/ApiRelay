import Foundation
import SwiftData

/// V2 用量快照；V1 仅建实体以一次性部署 CloudKit schema。
@Model
final class UsageSnapshot {
    var id: UUID = UUID()
    var keyId: UUID = UUID()
    var granularity: String = UsageGranularity.day.rawValue
    var periodStart: Date = Date()
    var periodTimeZone: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var reportedCostUSD: Decimal?
    var estimatedCostUSD: Decimal?
    var pricingRuleId: UUID?
    var modelName: String?
    var dataSource: String = UsageDataSource.platformAPI.rawValue
    var fetchedAt: Date = Date()
    var capabilityNote: String?

    init(
        id: UUID = UUID(),
        keyId: UUID,
        granularity: UsageGranularity = .day,
        periodStart: Date,
        periodTimeZone: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        reportedCostUSD: Decimal? = nil,
        estimatedCostUSD: Decimal? = nil,
        pricingRuleId: UUID? = nil,
        modelName: String? = nil,
        dataSource: UsageDataSource = .platformAPI,
        fetchedAt: Date = Date(),
        capabilityNote: String? = nil
    ) {
        self.id = id
        self.keyId = keyId
        self.granularity = granularity.rawValue
        self.periodStart = periodStart
        self.periodTimeZone = periodTimeZone
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.reportedCostUSD = reportedCostUSD
        self.estimatedCostUSD = estimatedCostUSD
        self.pricingRuleId = pricingRuleId
        self.modelName = modelName
        self.dataSource = dataSource.rawValue
        self.fetchedAt = fetchedAt
        self.capabilityNote = capabilityNote
    }
}
