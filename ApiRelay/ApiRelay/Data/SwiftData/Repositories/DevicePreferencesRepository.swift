import Foundation
import SwiftData

@ModelActor
actor DevicePreferencesRepository {
    func loadOrCreate() throws -> (
        appearance: AppearancePreference,
        defaultGrouping: GroupingMode,
        assignPickerFilter: AssignPickerFilter,
        lastWindowWidth: Double?,
        lastWindowHeight: Double?,
        platformSectionSort: SectionSortPreference,
        consumerSectionSort: SectionSortPreference,
        defaultKeyAvatarSymbol: String,
        defaultKeyAvatarColor: String,
        defaultCustomAccountAvatarSymbol: String,
        defaultCustomAccountAvatarColor: String,
        defaultCustomToolAvatarSymbol: String,
        defaultCustomToolAvatarColor: String
    ) {
        let model = try ensureSingleton()
        return (
            AppearancePreference(rawValue: model.appearance) ?? .system,
            GroupingMode(rawValue: model.defaultGrouping) ?? .byPlatform,
            AssignPickerFilter(rawValue: model.assignPickerFilter) ?? .allowShared,
            model.lastWindowWidth,
            model.lastWindowHeight,
            SectionSortPreference.parse(
                criterionRaw: model.platformSectionSortCriterion,
                ascending: model.platformSectionSortAscending
            ),
            SectionSortPreference.parse(
                criterionRaw: model.consumerSectionSortCriterion,
                ascending: model.consumerSectionSortAscending
            ),
            model.defaultKeyAvatarSymbol,
            model.defaultKeyAvatarColor,
            model.defaultCustomAccountAvatarSymbol,
            model.defaultCustomAccountAvatarColor,
            model.defaultCustomToolAvatarSymbol,
            model.defaultCustomToolAvatarColor
        )
    }

    func update(_ patch: PreferencesPatch) throws {
        let model = try ensureSingleton()
        if let value = patch.appearance { model.appearance = value.rawValue }
        if let value = patch.defaultGrouping { model.defaultGrouping = value.rawValue }
        if let value = patch.assignPickerFilter { model.assignPickerFilter = value.rawValue }
        if let value = patch.lastWindowWidth { model.lastWindowWidth = value }
        if let value = patch.lastWindowHeight { model.lastWindowHeight = value }
        if let value = patch.platformSectionSort {
            model.platformSectionSortCriterion = value.criterion.rawValue
            model.platformSectionSortAscending = value.ascending
        }
        if let value = patch.consumerSectionSort {
            model.consumerSectionSortCriterion = value.criterion.rawValue
            model.consumerSectionSortAscending = value.ascending
        }
        if let value = patch.defaultKeyAvatarSymbol { model.defaultKeyAvatarSymbol = value }
        if let value = patch.defaultKeyAvatarColor { model.defaultKeyAvatarColor = value }
        if let value = patch.defaultCustomAccountAvatarSymbol { model.defaultCustomAccountAvatarSymbol = value }
        if let value = patch.defaultCustomAccountAvatarColor { model.defaultCustomAccountAvatarColor = value }
        if let value = patch.defaultCustomToolAvatarSymbol { model.defaultCustomToolAvatarSymbol = value }
        if let value = patch.defaultCustomToolAvatarColor { model.defaultCustomToolAvatarColor = value }
        try modelContext.save()
    }

    private func ensureSingleton() throws -> DevicePreferences {
        let id = DevicePreferences.singletonID
        var descriptor = FetchDescriptor<DevicePreferences>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let created = DevicePreferences()
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    /// FR-061：删除本机偏好单例；下次 `loadOrCreate` 会写入默认值。
    func deleteAllRecords() throws {
        try modelContext.deleteAllRecords(DevicePreferences.self)
    }
}
