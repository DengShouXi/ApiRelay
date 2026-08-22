import Foundation
import SwiftData

protocol PreferencesServing: Actor {
    func load() async throws -> PreferencesDTO
    func update(_ patch: PreferencesPatch) async throws
}

actor PreferencesService: PreferencesServing {
    private let userRepo: UserPreferencesRepository
    private let deviceRepo: DevicePreferencesRepository

    init(modelContainer: ModelContainer) {
        self.userRepo = UserPreferencesRepository(modelContainer: modelContainer)
        self.deviceRepo = DevicePreferencesRepository(modelContainer: modelContainer)
    }

    func load() async throws -> PreferencesDTO {
        let user = try await userRepo.loadOrCreate()
        let device = try await deviceRepo.loadOrCreate()
        return PreferencesDTO(
            appLockEnabled: user.appLockEnabled,
            autoLockSeconds: user.autoLockSeconds,
            revealPolicy: user.revealPolicy,
            clipboardClearSeconds: user.clipboardClearSeconds,
            clipboardLocalOnly: user.clipboardLocalOnly,
            hideInAppSwitcher: user.hideInAppSwitcher,
            refreshIntervalMinutes: user.refreshIntervalMinutes,
            displayCurrency: user.displayCurrency,
            usdToDisplayRate: user.usdToDisplayRate,
            notifyLowBalance: user.notifyLowBalance,
            notifyKeyRevoked: user.notifyKeyRevoked,
            notifyWeeklyDigest: user.notifyWeeklyDigest,
            lowBalanceThreshold: user.lowBalanceThreshold,
            appearance: device.appearance,
            defaultGrouping: device.defaultGrouping,
            assignPickerFilter: device.assignPickerFilter,
            lastWindowWidth: device.lastWindowWidth,
            lastWindowHeight: device.lastWindowHeight,
            platformSectionSort: device.platformSectionSort,
            consumerSectionSort: device.consumerSectionSort,
            defaultKeyAvatarSymbol: nonempty(device.defaultKeyAvatarSymbol),
            defaultKeyAvatarColor: nonempty(device.defaultKeyAvatarColor),
            defaultCustomAccountAvatarSymbol: nonempty(device.defaultCustomAccountAvatarSymbol),
            defaultCustomAccountAvatarColor: nonempty(device.defaultCustomAccountAvatarColor),
            defaultCustomToolAvatarSymbol: nonempty(device.defaultCustomToolAvatarSymbol),
            defaultCustomToolAvatarColor: nonempty(device.defaultCustomToolAvatarColor)
        )
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func update(_ patch: PreferencesPatch) async throws {
        // FR-060：外观/默认视角/窗口 → DevicePreferences；其余 → UserPreferences
        if patch.writesUserPreferences {
            try await userRepo.update(patch)
        }
        if patch.writesDevicePreferences {
            try await deviceRepo.update(patch)
        }
    }

    /// 界面写入 CloudKit 同步的 UserPreferences 时，MUST NOT 在 MainActor 上 `await update`。
    /// SwiftUI `.modelContainer` 的 mainContext 与 `@ModelActor` save 互相等待，会卡住整窗转圈。
    /// `Task.detached`：工程开了 NonisolatedNonsendingByDefault，普通 `Task {}` 仍会继承 MainActor。
    nonisolated func persist(_ patch: PreferencesPatch) {
        Task.detached {
            try? await self.update(patch)
        }
    }

    /// FR-061：清空同步偏好与本机偏好；下次 `load` 会重建默认值。
    func purgeAllRecordsForErase() async throws {
        try await userRepo.deleteAllRecords()
        try await deviceRepo.deleteAllRecords()
    }
}
