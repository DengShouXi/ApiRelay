import Foundation
import SwiftData

/// V2 计价规则；V1 仅建实体。
@Model
final class PricingRule {
    var id: UUID = UUID()
    var platform: String = ""
    var modelPattern: String = "*"
    var inputPricePer1M: Decimal = 0
    var outputPricePer1M: Decimal = 0
    var effectiveFrom: Date = Date()
    var source: String = "bundled"

    init(
        id: UUID = UUID(),
        platform: String,
        modelPattern: String = "*",
        inputPricePer1M: Decimal,
        outputPricePer1M: Decimal,
        effectiveFrom: Date = Date(),
        source: String = "bundled"
    ) {
        self.id = id
        self.platform = platform
        self.modelPattern = modelPattern
        self.inputPricePer1M = inputPricePer1M
        self.outputPricePer1M = outputPricePer1M
        self.effectiveFrom = effectiveFrom
        self.source = source
    }
}
