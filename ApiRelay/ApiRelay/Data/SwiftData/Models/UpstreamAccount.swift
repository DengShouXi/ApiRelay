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
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        platform: String,
        customPlatformName: String? = nil,
        displayName: String,
        customBaseURL: String? = nil,
        hasManagementCredential: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.platform = platform
        self.customPlatformName = customPlatformName
        self.displayName = displayName
        self.customBaseURL = customBaseURL
        self.hasManagementCredential = hasManagementCredential
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }
}
