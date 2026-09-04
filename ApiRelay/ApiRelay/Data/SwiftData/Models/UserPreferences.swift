import Foundation
import SwiftData

/// 安全相关偏好（CloudKit 同步）。外观 / 默认视角 MUST NOT 出现在此实体（FR-060）。
@Model
final class UserPreferences {
    static let singletonID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!

    var id: UUID = UserPreferences.singletonID
    var appLockEnabled: Bool = false
    var autoLockSeconds: Int = 60
    var revealPolicy: String = RevealPolicy.noVerification.rawValue
    var clipboardClearSeconds: Int = 120
    var clipboardLocalOnly: Bool = false
    var hideInAppSwitcher: Bool = true
    var refreshIntervalMinutes: Int = 0
    var displayCurrency: String = "USD"
    var usdToDisplayRate: Decimal?
    var notifyLowBalance: Bool = false
    var notifyKeyRevoked: Bool = false
    var notifyWeeklyDigest: Bool = false
    var lowBalanceThreshold: Decimal?

    init(
        id: UUID = UserPreferences.singletonID,
        appLockEnabled: Bool = false,
        autoLockSeconds: Int = 60,
        revealPolicy: RevealPolicy = .noVerification,
        clipboardClearSeconds: Int = 120,
        clipboardLocalOnly: Bool = false,
        hideInAppSwitcher: Bool = true,
        refreshIntervalMinutes: Int = 0,
        displayCurrency: String = "USD",
        usdToDisplayRate: Decimal? = nil,
        notifyLowBalance: Bool = false,
        notifyKeyRevoked: Bool = false,
        notifyWeeklyDigest: Bool = false,
        lowBalanceThreshold: Decimal? = nil
    ) {
        self.id = id
        self.appLockEnabled = appLockEnabled
        self.autoLockSeconds = autoLockSeconds
        self.revealPolicy = revealPolicy.rawValue
        self.clipboardClearSeconds = clipboardClearSeconds
        self.clipboardLocalOnly = clipboardLocalOnly
        self.hideInAppSwitcher = hideInAppSwitcher
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.displayCurrency = displayCurrency
        self.usdToDisplayRate = usdToDisplayRate
        self.notifyLowBalance = notifyLowBalance
        self.notifyKeyRevoked = notifyKeyRevoked
        self.notifyWeeklyDigest = notifyWeeklyDigest
        self.lowBalanceThreshold = lowBalanceThreshold
    }
}
