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
            lastWindowWidth: device.lastWindowWidth,
            lastWindowHeight: device.lastWindowHeight
        )
    }

    func update(_ patch: PreferencesPatch) async throws {
        // FR-060：外观/默认视角/窗口 → DevicePreferences；其余 → UserPreferences
        try await userRepo.update(patch)
        try await deviceRepo.update(patch)
    }
}
