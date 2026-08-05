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
    /// 移入回收站时间；非 nil 表示软删除。
    var deletedAt: Date?
    /// 永久清除截止（默认 deletedAt + 30 天）。
    var purgeAfter: Date?

    init(
        id: UUID = UUID(),
        name: String,
        iconSymbol: String? = nil,
        isPreset: Bool = false,
        isHidden: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.isPreset = isPreset
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.deletedAt = deletedAt
        self.purgeAfter = purgeAfter
    }
}
