import Foundation
import SwiftData

@Model
final class ConsumerTool {
    var id: UUID = UUID()
    var name: String = ""
    var iconSymbol: String?
    /// 用户在编辑里选的头像；nil = 预置工具跟目录，自建工具跟产品写死的默认（设置不再改默认）。
    var avatarSymbol: String?
    var avatarColor: String?
    var isPreset: Bool = false
    var isHidden: Bool = false
    /// 可选备注（非密文）。
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    /// 移入回收站时间；非 nil 表示软删除。
    var deletedAt: Date?
    /// 永久清除截止（默认 deletedAt + 30 天）。
    var purgeAfter: Date?

    init(
        id: UUID = UUID(),
        name: String,
        iconSymbol: String? = nil,
        avatarSymbol: String? = nil,
        avatarColor: String? = nil,
        isPreset: Bool = false,
        isHidden: Bool = false,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0,
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.avatarSymbol = avatarSymbol
        self.avatarColor = avatarColor
        self.isPreset = isPreset
        self.isHidden = isHidden
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.deletedAt = deletedAt
        self.purgeAfter = purgeAfter
    }
}
