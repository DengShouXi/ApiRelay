import Foundation
import SwiftData

/// 本机界面偏好（local，不同步）。外观 / 默认视角 / 指派筛选 / 分区排序只允许出现在此实体。
@Model
final class DevicePreferences {
    static let singletonID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!

    var id: UUID = DevicePreferences.singletonID
    var appearance: String = AppearancePreference.system.rawValue
    var defaultGrouping: String = GroupingMode.byPlatform.rawValue
    /// 默认一钥多用，与 DC-011 多对多指派一致；用户可改为只看未指派。
    var assignPickerFilter: String = AssignPickerFilter.allowShared.rawValue
    var lastWindowWidth: Double?
    var lastWindowHeight: Double?
    /// 按平台中间栏分区排序（FR-064）。
    var platformSectionSortCriterion: String = SectionSortCriterion.name.rawValue
    var platformSectionSortAscending: Bool = true
    /// 按使用方中间栏分区排序（FR-064）。
    var consumerSectionSortCriterion: String = SectionSortCriterion.name.rawValue
    var consumerSectionSortAscending: Bool = true
    /// 遗留：界面 MUST NOT 读；设置 MUST NOT 提供改默认。未单独覆盖的条目走产品写死的默认。
    var defaultKeyAvatarSymbol: String = ""
    var defaultKeyAvatarColor: String = ""
    var defaultCustomAccountAvatarSymbol: String = ""
    var defaultCustomAccountAvatarColor: String = ""
    var defaultCustomToolAvatarSymbol: String = ""
    var defaultCustomToolAvatarColor: String = ""

    init(
        id: UUID = DevicePreferences.singletonID,
        appearance: AppearancePreference = .system,
        defaultGrouping: GroupingMode = .byPlatform,
        assignPickerFilter: AssignPickerFilter = .allowShared,
        lastWindowWidth: Double? = nil,
        lastWindowHeight: Double? = nil
    ) {
        self.id = id
        self.appearance = appearance.rawValue
        self.defaultGrouping = defaultGrouping.rawValue
        self.assignPickerFilter = assignPickerFilter.rawValue
        self.lastWindowWidth = lastWindowWidth
        self.lastWindowHeight = lastWindowHeight
    }
}
