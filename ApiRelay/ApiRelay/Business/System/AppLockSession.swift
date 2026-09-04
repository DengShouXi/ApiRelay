import Foundation

/// App 锁 / 自动锁定 / 切换器遮罩的三项偏好。不含明文。
struct AppLockPreferences: Equatable, Sendable {
    var appLockEnabled: Bool
    var autoLockSeconds: Int
    var hideInAppSwitcher: Bool
    /// App 锁跟「取出明文」同一套验证方式；`.noVerification` 时仍走设备主人验证，避免开关空转。
    var revealPolicy: RevealPolicy = .noVerification

    /// 与 `UserPreferences` 模型默认值一致。
    static let defaults = AppLockPreferences(
        appLockEnabled: false,
        autoLockSeconds: 60,
        hideInAppSwitcher: true,
        revealPolicy: .noVerification
    )

    init(
        appLockEnabled: Bool,
        autoLockSeconds: Int,
        hideInAppSwitcher: Bool,
        revealPolicy: RevealPolicy = .noVerification
    ) {
        self.appLockEnabled = appLockEnabled
        self.autoLockSeconds = autoLockSeconds
        self.hideInAppSwitcher = hideInAppSwitcher
        self.revealPolicy = revealPolicy
    }

    init(_ dto: PreferencesDTO) {
        self.init(
            appLockEnabled: dto.appLockEnabled,
            autoLockSeconds: dto.autoLockSeconds,
            hideInAppSwitcher: dto.hideInAppSwitcher,
            revealPolicy: dto.revealPolicy
        )
    }
}

/// 会话锁与切换器遮罩决策。无 SwiftUI、无 LocalAuthentication。
///
/// 首帧不得露出密钥列表：偏好尚未读出时 `blocksContent == true`。
/// 自动锁定只在「打开 App 需要身份确认」开启时生效。
///
/// 自动锁计时：以**第一次**离开前台为准。系统在后台/切换器里偶尔会短暂拉起
/// active 再 inactive（通知中心、刷新等）；若每次都重置离开时刻，会出现
/// 「设了 30 秒、离开一分钟却不锁」。短于 `briefActiveThreshold` 的 active 不重置计时。
struct AppLockSession: Equatable, Sendable {
    /// 短于此时长的 active→inactive 视为闪断，不刷新 `lastLeftActiveAt`。
    static let briefActiveThreshold: TimeInterval = 1.0

    private(set) var preferences: AppLockPreferences
    private(set) var isPreferencesReady: Bool
    private(set) var isSessionLocked: Bool
    private(set) var isInactive: Bool
    private(set) var lastLeftActiveAt: Date?
    private(set) var lastBecameActiveAt: Date?

    static func unready() -> AppLockSession {
        AppLockSession(
            preferences: .defaults,
            isPreferencesReady: false,
            isSessionLocked: false,
            isInactive: false,
            lastLeftActiveAt: nil,
            lastBecameActiveAt: nil
        )
    }

    /// 列表与详情必须不可见（含偏好未就绪、会话锁、切换器遮罩）。
    var blocksContent: Bool {
        if !isPreferencesReady { return true }
        return isSessionLocked || showsSnapshotCover
    }

    /// 应用切换器应拍到的遮罩：仅在离开前台且开关打开时。
    /// 会话已锁定时离开前台也会遮挡——锁态不得在多任务里露出列表。
    var showsSnapshotCover: Bool {
        guard isInactive else { return false }
        return preferences.hideInAppSwitcher || isSessionLocked
    }

    /// 回到前台后需要弹出身份确认。
    var needsUnlockPrompt: Bool {
        isPreferencesReady && isSessionLocked && !isInactive
    }

    /// 冷启动：App 锁开着则先锁，避免首帧闪出列表。
    mutating func completeColdStart(with prefs: AppLockPreferences) {
        preferences = normalized(prefs)
        isPreferencesReady = true
        isSessionLocked = preferences.appLockEnabled
    }

    /// 设置页改开关：关 App 锁立即解锁；打开不立刻锁，等下次离开/冷启动。
    mutating func applyLivePreferences(_ prefs: AppLockPreferences) {
        preferences = normalized(prefs)
        isPreferencesReady = true
        if !preferences.appLockEnabled {
            isSessionLocked = false
        }
    }

    mutating func noteWillResignActive(now: Date) {
        if !isInactive {
            let wasBriefActive = lastBecameActiveAt
                .map { now.timeIntervalSince($0) < Self.briefActiveThreshold } ?? false
            if lastLeftActiveAt == nil || !wasBriefActive {
                lastLeftActiveAt = now
            }
        } else if lastLeftActiveAt == nil {
            lastLeftActiveAt = now
        }
        isInactive = true
        if preferences.appLockEnabled && preferences.autoLockSeconds <= 0 {
            isSessionLocked = true
        }
    }

    /// 必须在 `noteDidBecomeActive` 之前调用，避免先揭开列表再上锁。
    mutating func noteWillEnterForeground(now: Date) {
        guard isPreferencesReady else { return }
        guard preferences.appLockEnabled else {
            isSessionLocked = false
            return
        }
        if isSessionLocked { return }
        let grace = TimeInterval(max(0, preferences.autoLockSeconds))
        if grace == 0 {
            isSessionLocked = true
            return
        }
        if let left = lastLeftActiveAt, now.timeIntervalSince(left) >= grace {
            isSessionLocked = true
        }
    }

    mutating func noteDidBecomeActive(now: Date) {
        isInactive = false
        lastBecameActiveAt = now
        // 故意不在这里清 `lastLeftActiveAt`：系统闪断 active 时若清掉，
        // 紧接着的 resign 会把离开时刻改成「刚才」，自动锁永远凑不满超时。
        // 真正用完一次离开周期：由下次「非闪断」的 resign 覆写，或 `unlockSucceeded` 清空。
    }

    mutating func unlockSucceeded() {
        isSessionLocked = false
        lastLeftActiveAt = nil
        // 解锁即视为已回到可交互前台。若仍标 inactive，hide 开关会继续
        // `showsSnapshotCover` → 整页挡死且没有解锁按钮（needsUnlockPrompt 为 false）。
        isInactive = false
    }

    private func normalized(_ prefs: AppLockPreferences) -> AppLockPreferences {
        var next = prefs
        next.autoLockSeconds = max(0, next.autoLockSeconds)
        return next
    }
}
