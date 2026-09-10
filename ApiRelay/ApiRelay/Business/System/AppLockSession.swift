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
/// 推荐规则：
/// - 没开 App 锁：冷启动直接进列表。手机锁屏是系统的事。不得画软件锁。
/// - 开了 App 锁：冷启动（含划掉再点开）与离开再进都走软件锁，否则划掉即可绕过。
/// - 多任务遮罩不是锁：只挡截屏，不得画锁图标。
/// iOS 冷启动会先 inactive；进前台后 1 秒内的 inactive 也不是「去了切换器」。
/// 本机缓存只回答「上次是不是开着 App 锁」，且不得伪造验证方式。
///
/// 自动锁定只在设置里打开「自动锁定」时生效（`appLockEnabled`）。
///
/// 遮罩、上锁、系统验证是三件事，不要焊在同一次 inactive 上：
/// - `noteWillResignActive` 只盖多任务遮罩（系统此时拍缩略图）。
/// - `noteDidEnterBackground` 才开始自动锁计时；「立即」也在这里静默上锁。
///   调用方 MUST 先确认窗口已离开当前空间。台前同一组里的其它软件仍能看到本窗时，
///   Catalyst 误发的 background 不得传进来。
/// - 回到前台后由调用方决定是否弹出系统验证。Mac 默认不自动弹，避免盖到别的软件上。
///
/// 自动锁计时以**第一次真正进后台**为准。控制中心 / 触控 ID 框只有 resign、
/// 没有 background，不得开始计时。系统在后台里偶尔会短暂拉起 active 再
/// background；短于 `briefActiveThreshold` 的 active 不重置离开时刻。
struct AppLockSession: Equatable, Sendable {
    /// 短于此时长的 active→inactive 视为闪断，不刷新 `lastLeftActiveAt`。
    static let briefActiveThreshold: TimeInterval = 1.0

    private(set) var preferences: AppLockPreferences
    private(set) var isPreferencesReady: Bool
    private(set) var isSessionLocked: Bool
    private(set) var isInactive: Bool
    /// 冷启动会先 inactive 再 active；在真正进过前台之前，resign 不是「去了切换器」。
    private(set) var hasBecomeActiveOnce: Bool
    private(set) var lastLeftActiveAt: Date?
    /// 自动锁计时用单调时钟，避免用户改系统时间提前/推迟解锁。
    private(set) var lastLeftMonotonic: TimeInterval?
    private(set) var lastBecameActiveAt: Date?

    static func unready() -> AppLockSession {
        AppLockSession(
            preferences: .defaults,
            isPreferencesReady: false,
            isSessionLocked: false,
            isInactive: false,
            hasBecomeActiveOnce: false,
            lastLeftActiveAt: nil,
            lastLeftMonotonic: nil,
            lastBecameActiveAt: nil
        )
    }

    /// 软件锁挡住列表。多任务遮罩不走这里——那会把冷启动画成一张白屏。
    var blocksContent: Bool {
        isSessionLocked || showsSnapshotCover
    }

    /// 软件锁界面（白底锁 / 解锁）。没开 App 锁时必须为 false。
    var showsAppLockUI: Bool {
        isSessionLocked
    }

    /// 应用切换器应拍到的遮罩：仅在离开前台且开关打开时。
    /// 会话已锁定时离开前台也会遮挡——锁态不得在多任务里露出列表。
    var showsSnapshotCover: Bool {
        guard isInactive else { return false }
        guard hasBecomeActiveOnce else { return false }
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

    /// 本机记得上次开着 App 锁：立刻挡列表，但验证方式仍等 `start()`。
    mutating func applyCachedLockEnabled() {
        isSessionLocked = true
    }

    /// 设置页改开关：关 App 锁立即解锁；打开不立刻锁，等下次离开/冷启动。
    mutating func applyLivePreferences(_ prefs: AppLockPreferences) {
        preferences = normalized(prefs)
        isPreferencesReady = true
        if !preferences.appLockEnabled {
            isSessionLocked = false
        }
    }

    /// 应用即将失去前台：只盖遮罩。MUST NOT 在这里上锁——控制中心、触控 ID、
    /// 本 App 的 sheet 都会走 resign，上锁会变成白底锁或系统框盖到别的软件上。
    /// 调用方 MUST 只在整个应用 resign 时调用，不得把某一扇窗的 deactivate 传进来。
    mutating func noteWillResignActive(now: Date) {
        guard hasBecomeActiveOnce else { return }
        let wasBriefActive = lastBecameActiveAt
            .map { now.timeIntervalSince($0) < Self.briefActiveThreshold } ?? false
        // 刚进前台不到 1 秒又 inactive：冷启动 / 模拟器调试常见闪断。
        // 没开 App 锁时不得盖层，否则用户会一直看着白屏直到系统真正 active。
        if wasBriefActive && !preferences.appLockEnabled {
            return
        }
        isInactive = true
    }

    /// 应用已进后台：开始自动锁计时；「立即」在这里静默锁会话。
    /// 调用方 MUST 只在窗口已离开当前空间时调用。台前同一组点别的软件不是后台。
    mutating func noteDidEnterBackground(now: Date, uptime: TimeInterval? = nil) {
        guard hasBecomeActiveOnce else { return }
        isInactive = true
        let wasBriefActive = lastBecameActiveAt
            .map { now.timeIntervalSince($0) < Self.briefActiveThreshold } ?? false
        let mark = uptime ?? now.timeIntervalSinceReferenceDate
        if lastLeftMonotonic == nil || !wasBriefActive {
            lastLeftActiveAt = now
            lastLeftMonotonic = mark
        }
        if preferences.appLockEnabled && preferences.autoLockSeconds <= 0 {
            isSessionLocked = true
        }
    }

    /// 必须在 `noteDidBecomeActive` 之前调用，避免先揭开列表再上锁。
    mutating func noteWillEnterForeground(now: Date, uptime: TimeInterval? = nil) {
        guard isPreferencesReady else { return }
        guard preferences.appLockEnabled else {
            isSessionLocked = false
            return
        }
        if isSessionLocked { return }
        // 没有真正进过后台（控制中心、触控 ID 框）不得在回来时补锁。
        guard lastLeftMonotonic != nil else { return }
        let grace = TimeInterval(max(0, preferences.autoLockSeconds))
        if grace == 0 {
            isSessionLocked = true
            return
        }
        let current = uptime ?? now.timeIntervalSinceReferenceDate
        if let left = lastLeftMonotonic, current - left >= grace {
            isSessionLocked = true
        }
    }

    mutating func noteDidBecomeActive(now: Date) {
        hasBecomeActiveOnce = true
        isInactive = false
        lastBecameActiveAt = now
        // 故意不在这里清 `lastLeftActiveAt`：系统闪断 active 时若清掉，
        // 紧接着的 resign 会把离开时刻改成「刚才」，自动锁永远凑不满超时。
        // 真正用完一次离开周期：由下次「非闪断」的 resign 覆写，或 `unlockSucceeded` 清空。
    }

    /// 台前同组闲置：允许先盖切换器快照再立刻摘掉。MUST NOT 写入离开时刻，也 MUST NOT 上锁。
    mutating func releaseOnScreenIdle() {
        guard hasBecomeActiveOnce else { return }
        isInactive = false
    }

    mutating func unlockSucceeded() {
        isSessionLocked = false
        lastLeftActiveAt = nil
        lastLeftMonotonic = nil
        hasBecomeActiveOnce = true
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

/// 本 App 的窗口相对于当前空间的关系。台前调度同一组里点别的软件时，
/// 窗仍在屏上（`.onScreenIdle`），那不是离开，也不得弹系统验证。
///
/// iPadOS 26 起同组里的窗可以一直保持 `foregroundActive`。这时「人没在用我们」
/// 要靠本窗不是 Key、外观是闲置来认，不能再只看 scene 是否 Active。
enum AppLockScenePresence: Equatable, Sendable {
    /// 所有窗口都不在当前空间（切到另一组 / 进后台）。
    case offScreen
    /// 窗还在当前空间，但人没在用我们（同一组里的别的软件；本窗失去 Key / 闲置外观）。
    case onScreenIdle
    /// 人正在用我们（本窗是 Key，或系统验证框还盖在我们头上）。
    case userFacing
}

/// 本机上次的 App 锁开关。冷启动等不及 CloudKit / SwiftData 时用它决定要不要挡首帧。
/// 测试走 `AppRuntime.userDefaultsForCurrentRuntime()`，不得碰 `.standard`。
enum AppLockLaunchCache: Sendable {
    nonisolated static let defaultsKey = "ApiRelay.appLock.enabled"

    /// `nil` = 从未写过（升级前的安装）。此时不得当成已开锁，也不要先画锁图标。
    nonisolated static func read() -> Bool? {
        let defaults = AppRuntime.userDefaultsForCurrentRuntime()
        guard defaults.object(forKey: defaultsKey) != nil else { return nil }
        return defaults.bool(forKey: defaultsKey)
    }

    nonisolated static func write(_ enabled: Bool) {
        AppRuntime.userDefaultsForCurrentRuntime().set(enabled, forKey: defaultsKey)
    }

    nonisolated static func resetForTests() {
        AppRuntime.userDefaultsForCurrentRuntime().removeObject(forKey: defaultsKey)
    }
}
