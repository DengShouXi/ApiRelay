import Foundation
import SwiftData

@Model
final class ConsumerTool {
    var id: UUID = UUID()
    var name: String = ""
    var iconSymbol: String?
    var isPreset: Bool = false
    var isHidden: Bool = false
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        name: String,
        iconSymbol: String? = nil,
        isPreset: Bool = false,
        isHidden: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.isPreset = isPreset
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
