import Foundation
import SwiftData

/// 本机界面偏好（local，不同步）。appearance / defaultGrouping 只允许出现在此实体。
@Model
final class DevicePreferences {
    static let singletonID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!

    var id: UUID = DevicePreferences.singletonID
    var appearance: String = AppearancePreference.system.rawValue
    var defaultGrouping: String = GroupingMode.byPlatform.rawValue
    var lastWindowWidth: Double?
    var lastWindowHeight: Double?

    init(
        id: UUID = DevicePreferences.singletonID,
        appearance: AppearancePreference = .system,
        defaultGrouping: GroupingMode = .byPlatform,
        lastWindowWidth: Double? = nil,
        lastWindowHeight: Double? = nil
    ) {
        self.id = id
        self.appearance = appearance.rawValue
        self.defaultGrouping = defaultGrouping.rawValue
        self.lastWindowWidth = lastWindowWidth
        self.lastWindowHeight = lastWindowHeight
    }
}
