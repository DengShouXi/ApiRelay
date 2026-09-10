import Foundation

/// 一条系统信号。缺的标 `unknown`，实现不得把它当成「已经离屏」。
enum PresenceSignal<Value: Equatable & Sendable>: Equatable, Sendable {
    case known(Value)
    case unknown

    var knownValue: Value? {
        if case let .known(value) = self { return value }
        return nil
    }
}

/// 判定一扇窗在场所需的公开信号。无 UIKit，便于把真值表写进测试夹具。
///
/// `appearsActive`：本 target（iOS 18 / Mac Catalyst 15）没有公开 API，生产路径恒为 `.unknown`。
struct ScenePresenceSignals: Equatable, Sendable {
    var sceneIsForegroundActive: PresenceSignal<Bool>
    var sceneIsForegroundInactive: PresenceSignal<Bool>
    var applicationIsActive: PresenceSignal<Bool>
    var isKeyWindow: PresenceSignal<Bool>
    var activeAppearanceIsActive: PresenceSignal<Bool>
    var appearsActive: PresenceSignal<Bool>
    var authenticationInProgress: Bool

    static func known(
        sceneIsForegroundActive: Bool,
        sceneIsForegroundInactive: Bool,
        applicationIsActive: Bool,
        isKeyWindow: Bool,
        activeAppearanceIsActive: Bool?,
        appearsActive: Bool? = nil,
        authenticationInProgress: Bool = false
    ) -> ScenePresenceSignals {
        ScenePresenceSignals(
            sceneIsForegroundActive: .known(sceneIsForegroundActive),
            sceneIsForegroundInactive: .known(sceneIsForegroundInactive),
            applicationIsActive: .known(applicationIsActive),
            isKeyWindow: .known(isKeyWindow),
            activeAppearanceIsActive: activeAppearanceIsActive.map { .known($0) } ?? .unknown,
            appearsActive: appearsActive.map { .known($0) } ?? .unknown,
            authenticationInProgress: authenticationInProgress
        )
    }
}

extension AppLockScenePresence {
    /// 把系统信号收成三态。调用方负责读 UIKit；本函数无 UIKit，便于单测。
    ///
    /// `applicationIsActive == false`（Face ID / 控制中心）不要看 Key Window：
    /// 系统框会把 Key 抢走，不得当成「点到了别的软件」去取消正在进行的验证。
    /// App 仍是 `.active` 时（iPadOS 26 台前同组）才看 Key / 外观 / `appearsActive`。
    /// 验证进行中视为状态 C：未确定离屏时 MUST 当作正在操作。
    /// 未知信号 MUST NOT 当成离屏。
    static func resolve(_ signals: ScenePresenceSignals) -> AppLockScenePresence {
        if isDefinitelyOffScreen(signals) {
            return .offScreen
        }
        if signals.authenticationInProgress {
            return .userFacing
        }
        if signals.applicationIsActive.knownValue == true {
            return hostIsUserFacing(signals) ? .userFacing : .onScreenIdle
        }
        if signals.sceneIsForegroundActive.knownValue == true {
            return .userFacing
        }
        return .onScreenIdle
    }

    /// 旧入口：全部信号已知、未在验证。夹具请走 `resolve(_:)`。
    static func resolve(
        hasForegroundActive: Bool,
        hasForegroundInactive: Bool,
        applicationIsActive: Bool,
        hostHasKeyOrActiveWindow: Bool
    ) -> AppLockScenePresence {
        resolve(
            ScenePresenceSignals(
                sceneIsForegroundActive: .known(hasForegroundActive),
                sceneIsForegroundInactive: .known(hasForegroundInactive),
                applicationIsActive: .known(applicationIsActive),
                isKeyWindow: .known(hostHasKeyOrActiveWindow),
                activeAppearanceIsActive: hostHasKeyOrActiveWindow ? .known(true) : .unknown,
                appearsActive: .unknown,
                authenticationInProgress: false
            )
        )
    }

    /// 只有 scene 明确既不是 Active 也不是 Inactive 才算离屏。未知 ≠ 离屏。
    static func isDefinitelyOffScreen(_ signals: ScenePresenceSignals) -> Bool {
        signals.sceneIsForegroundActive.knownValue == false
            && signals.sceneIsForegroundInactive.knownValue == false
    }

    /// iPadOS 26 台前：外观 inactive 即使还占 Key 也当闲置；外观 active 即使丢了 Key 也当在用。
    static func hostIsUserFacing(_ signals: ScenePresenceSignals) -> Bool {
        if signals.activeAppearanceIsActive.knownValue == false {
            return false
        }
        if signals.activeAppearanceIsActive.knownValue == true {
            return true
        }
        if signals.appearsActive.knownValue == true {
            return true
        }
        if signals.appearsActive.knownValue == false {
            return signals.isKeyWindow.knownValue == true
        }
        if let isKey = signals.isKeyWindow.knownValue {
            return isKey
        }
        return true
    }
}
