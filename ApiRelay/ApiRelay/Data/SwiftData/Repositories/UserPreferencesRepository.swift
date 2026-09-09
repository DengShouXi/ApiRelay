import Foundation
import SwiftData

@ModelActor
actor UserPreferencesRepository {
    func loadOrCreate() throws -> PreferencesDTO {
        let model = try ensureSingleton()
        var didSeed = false
        let autoLockOptions = seededOptions(
            stored: model.autoLockDurationOptionsJSON,
            current: model.autoLockSeconds,
            factory: DurationOptionList.autoLockFactory,
            didSeed: &didSeed
        ) { model.autoLockDurationOptionsJSON = $0 }
        let clipboardOptions = seededOptions(
            stored: model.clipboardClearDurationOptionsJSON,
            current: model.clipboardClearSeconds,
            factory: DurationOptionList.clipboardFactory,
            didSeed: &didSeed
        ) { model.clipboardClearDurationOptionsJSON = $0 }
        if didSeed {
            try modelContext.save()
        }
        // Device fields filled as defaults here; PreferencesService (Phase 6) merges DevicePreferences.
        return PreferencesDTO(
            appLockEnabled: model.appLockEnabled,
            autoLockSeconds: model.autoLockSeconds,
            autoLockDurationOptions: autoLockOptions,
            revealPolicy: RevealPolicy(rawValue: model.revealPolicy) ?? .noVerification,
            clipboardClearEnabled: model.clipboardClearEnabled,
            clipboardClearSeconds: model.clipboardClearSeconds,
            clipboardClearDurationOptions: clipboardOptions,
            clipboardLocalOnly: model.clipboardLocalOnly,
            hideInAppSwitcher: model.hideInAppSwitcher,
            refreshIntervalMinutes: model.refreshIntervalMinutes,
            displayCurrency: model.displayCurrency,
            usdToDisplayRate: model.usdToDisplayRate,
            notifyLowBalance: model.notifyLowBalance,
            notifyKeyRevoked: model.notifyKeyRevoked,
            notifyWeeklyDigest: model.notifyWeeklyDigest,
            lowBalanceThreshold: model.lowBalanceThreshold,
            appearance: .system,
            defaultGrouping: .byPlatform,
            assignPickerFilter: .allowShared,
            lastWindowWidth: nil,
            lastWindowHeight: nil,
            platformSectionSort: .nameAscending,
            consumerSectionSort: .nameAscending,
            defaultKeyAvatarSymbol: nil,
            defaultKeyAvatarColor: nil,
            defaultCustomAccountAvatarSymbol: nil,
            defaultCustomAccountAvatarColor: nil,
            defaultCustomToolAvatarSymbol: nil,
            defaultCustomToolAvatarColor: nil
        )
    }

    func update(_ patch: PreferencesPatch) throws {
        let model = try ensureSingleton()
        if let value = patch.appLockEnabled { model.appLockEnabled = value }
        if let value = patch.autoLockSeconds { model.autoLockSeconds = value }
        if let value = patch.autoLockDurationOptions {
            model.autoLockDurationOptionsJSON = DurationOptionList.encode(value)
        }
        if let value = patch.revealPolicy { model.revealPolicy = value.rawValue }
        if let value = patch.clipboardClearEnabled { model.clipboardClearEnabled = value }
        if let value = patch.clipboardClearSeconds { model.clipboardClearSeconds = value }
        if let value = patch.clipboardClearDurationOptions {
            model.clipboardClearDurationOptionsJSON = DurationOptionList.encode(value)
        }
        if let value = patch.clipboardLocalOnly { model.clipboardLocalOnly = value }
        if let value = patch.hideInAppSwitcher { model.hideInAppSwitcher = value }
        if let value = patch.refreshIntervalMinutes { model.refreshIntervalMinutes = value }
        if let value = patch.displayCurrency { model.displayCurrency = value }
        if let value = patch.usdToDisplayRate { model.usdToDisplayRate = value }
        if let value = patch.notifyLowBalance { model.notifyLowBalance = value }
        if let value = patch.notifyKeyRevoked { model.notifyKeyRevoked = value }
        if let value = patch.notifyWeeklyDigest { model.notifyWeeklyDigest = value }
        if let value = patch.lowBalanceThreshold { model.lowBalanceThreshold = value }
        // appearance / defaultGrouping / window → DevicePreferences（此处刻意忽略）
        try modelContext.save()
    }

    private func ensureSingleton() throws -> UserPreferences {
        let id = UserPreferences.singletonID
        var descriptor = FetchDescriptor<UserPreferences>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let created = UserPreferences()
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    /// FR-061：删除安全偏好单例；下次 `loadOrCreate` 会写入默认值。
    func deleteAllRecords() throws {
        try modelContext.deleteAllRecords(UserPreferences.self)
    }

    private func seededOptions(
        stored: String?,
        current: Int,
        factory: [Int],
        didSeed: inout Bool,
        assign: (String) -> Void
    ) -> [Int] {
        if let decoded = DurationOptionList.decode(stored) {
            return decoded
        }
        let seeded = DurationOptionList.seedIfNeeded(stored: nil, current: current, factory: factory)
        assign(DurationOptionList.encode(seeded))
        didSeed = true
        return seeded
    }
}
