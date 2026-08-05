import Foundation
import SwiftData

@ModelActor
actor DevicePreferencesRepository {
    func loadOrCreate() throws -> (
        appearance: AppearancePreference,
        defaultGrouping: GroupingMode,
        assignPickerFilter: AssignPickerFilter,
        lastWindowWidth: Double?,
        lastWindowHeight: Double?
    ) {
        let model = try ensureSingleton()
        return (
            AppearancePreference(rawValue: model.appearance) ?? .system,
            GroupingMode(rawValue: model.defaultGrouping) ?? .byPlatform,
            AssignPickerFilter(rawValue: model.assignPickerFilter) ?? .allowShared,
            model.lastWindowWidth,
            model.lastWindowHeight
        )
    }

    func update(_ patch: PreferencesPatch) throws {
        let model = try ensureSingleton()
        if let value = patch.appearance { model.appearance = value.rawValue }
        if let value = patch.defaultGrouping { model.defaultGrouping = value.rawValue }
        if let value = patch.assignPickerFilter { model.assignPickerFilter = value.rawValue }
        if let value = patch.lastWindowWidth { model.lastWindowWidth = value }
        if let value = patch.lastWindowHeight { model.lastWindowHeight = value }
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
}
