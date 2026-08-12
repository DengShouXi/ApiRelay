import Foundation
import SwiftData

@Model
final class UpstreamAccount {
    var id: UUID = UUID()
    var platform: String = ""
    var customPlatformName: String?
    var displayName: String = ""
    var customBaseURL: String?
    var hasManagementCredential: Bool = false
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
        platform: String,
        customPlatformName: String? = nil,
        displayName: String,
        customBaseURL: String? = nil,
        hasManagementCredential: Bool = false,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0,
        deletedAt: Date? = nil,
        purgeAfter: Date? = nil
    ) {
        self.id = id
        self.platform = platform
        self.customPlatformName = customPlatformName
        self.displayName = displayName
        self.customBaseURL = customBaseURL
        self.hasManagementCredential = hasManagementCredential
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.deletedAt = deletedAt
        self.purgeAfter = purgeAfter
    }
}
