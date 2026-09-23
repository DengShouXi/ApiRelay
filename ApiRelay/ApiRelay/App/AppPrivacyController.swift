import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

/// `Notification` predates Swift concurrency and is not Sendable. UIKit
/// lifecycle delivery is consumed synchronously on the posting main thread;
/// this wrapper documents that narrow, non-escaping bridge.
nonisolated private struct MainThreadLifecycleNotification: @unchecked Sendable {
    let value: Notification
}

/// 把 `AppLockSession` 接到生命周期、门闩与切换器快照。
///
/// 没开 App 锁，或验证方式是「不验证」：冷启动直接进内容，软件不画锁。
/// 已武装的 App 锁：冷启动与离开再进都走软件锁。
/// 多任务遮罩盖在每一扇 UIKit / AppKit 内容窗口上、不画锁，避免被当成解锁页。
///
/// iPhone / iPad 的「离开」只认整个 ApiRelay 离开当前空间；同组分屏仍按窗口焦点判定。
/// Mac 的安全边界不同：焦点交给任何其它 App 就算离开，必须开始自动锁并按设置遮挡。
/// 本 App 的 sheet / 系统身份验证不算离开。
/// iPadOS 26 往往不发 resign，要靠本窗 Key / `activeAppearance` 才能取消盖在别人头上的 Face ID。
@MainActor
final class AppPrivacyController: ObservableObject {
    @Published private(set) var session: AppLockSession {
        didSet { sessionLockBox?.setLocked(session.isSessionLocked) }
    }
    @Published private(set) var isUnlocking = false
    @Published private(set) var unlockError: String?
    /// 走「忘记主密码」出口的过程中。
    @Published private(set) var isRecovering = false
    /// 策略要主密码、本机却没有存主密码。此时口令框永远验不过，只能走恢复出口。
    @Published private(set) var masterPasswordMissing = false
    /// 组合档里用户点了「使用应用密码」，但本机还没有校验材料。生物识别仍可用；密码入口改先设。
    @Published private(set) var combinationAppPasswordMissing = false
    /// 兼容旧错误来源：组合档系统路径通常会在同一系统流程回落设备密码；若底层仍明确报告生物不可用，则保留应用密码出口。
    @Published private(set) var biometryUnavailableForUnlock = false
    /// 安全偏好读失败：保持已知锁态，不得落到默认关锁。
    @Published private(set) var securityPreferencesUnavailable = false

    /// 主密码档只出应用口令框，MUST NOT 再弹系统「iPhone 密码」。
    var usesMasterPasswordUnlock: Bool {
        session.preferences.revealPolicy == .masterPassword
    }

    /// 组合档：系统路径由一次设备主人认证承接生物识别→设备密码；界面另提供显式「使用应用密码」。
    var usesCombinationUnlock: Bool {
        session.preferences.revealPolicy == .biometryOrAppPassword
    }

    private let gate: any RevealGateServing
    private let preferences: any PreferencesServing
    private let masterPassword: any MasterPasswordServing
    private let installsSnapshotCover: Bool
    private let enablesUnlockPrompt: Bool
    /// Mac 上不得从生命周期自动弹出触控 ID：回到前台只展示本 App 的显式解锁入口。
    private let autoPromptsSystemAuth: Bool
    /// macOS / Catalyst：应用失焦就是离开；iPhone/iPad 仍等真正 background。
    private let treatsApplicationResignAsBackground: Bool
    private let scenePresence: @MainActor () -> AppLockScenePresence
    /// Keeps the raw scene lifecycle dimension that the three-state presence
    /// reducer intentionally hides. Stage Manager idle stays foreground-active;
    /// a Home transition moves the scene out of foreground-active first.
    private let hasForegroundActiveScene: @MainActor () -> Bool
    /// A rapid Home transition can stop at foreground-inactive without emitting
    /// didEnterBackground. Requiring the window appearance to be inactive keeps
    /// Control Center/system overlays (whose host appearance remains active)
    /// out of the immediate-lock compensation.
    private let hasForegroundInactiveSceneWithoutActiveAppearance: @MainActor () -> Bool
    private let monotonicUptime: @MainActor () -> TimeInterval
    private let windowsSnapshot: @MainActor () -> [WindowPrivacyInput]
    private let sessionLockBox: SessionLockBox?
    private var didStart = false
    /// `didStart` is set before the first await and therefore is not proof that
    /// the authoritative security policy has been read. Startup-time lifecycle
    /// and Cloud import callbacks stay fenced until this attempt has completed.
    private var initialSecurityLoadCompleted = false
    private var cancelledCurrentLock = false
    private var snapshotCoverTask: Task<Void, Never>?
    /// 只有经历过 `willEnterForeground` 且当前人正在用我们，才自动弹系统验证。
    private var shouldAutoPromptOnBecomeActive = false
    /// 桌面端 UIKit scene 可能在切到其它 App 后仍报 foregroundActive；以应用焦点为准覆盖旧信号。
    private var applicationIsInactiveForPrivacy = false
    /// 系统认证也会触发 Mac resign。先记下离开时刻；认证结束后若宿主仍不在前台，
    /// 必须补做真正离开，避免用户在 Touch ID 面板期间 Cmd-Tab 绕过自动锁。
    private var deferredDesktopLeaveAt: Date?
    private var desktopLeaveReconciliationTask: Task<Void, Never>?
    /// iPad Stage Manager can report the window as idle only once, while the
    /// LocalAuthentication sheet is still active. Re-check when that transient
    /// authentication state settles so queued writes cannot retain a lease.
    private var hostFocusReconciliationTask: Task<Void, Never>?
    private var hostFocusCancellables: Set<AnyCancellable> = []
    private var applicationLifecycleObservers: [NSObjectProtocol] = []
    /// UIApplication 与最后一扇 UIScene 都可能报告同一轮后台切换。
    /// 每轮只记录一次，避免重复通知把自动锁计时起点向后推迟。
    private var didRecordBackgroundForCurrentCycle = false
    /// `UIApplication.didEnterBackground` is a lifecycle fact, but during a
    /// very fast Home -> reopen transition the live scene snapshot can still be
    /// (or already be again) foreground-inactive. Preserve the first event so
    /// `willEnterForeground` can close the cycle before any vault UI is shown.
    private struct PendingApplicationBackground {
        let date: Date
        let uptime: TimeInterval
    }
    private var pendingApplicationBackground: PendingApplicationBackground?
    /// UIKit reports Home and Control Center identically on the first resign
    /// frame. Keep a short observation open for immediate-lock sessions; only a
    /// later off-screen/inactive-appearance signal promotes it to a real leave.
    private struct ImmediateResignProbe {
        let observation: PendingApplicationBackground
        let deadlineUptime: TimeInterval
    }
    private var pendingImmediateResignProbe: ImmediateResignProbe?
    private var immediateResignProbeAcceptsRawEvidence = false
    private var immediateResignProbeTask: Task<Void, Never>?
    private var immediateResignProbeRevision: UInt64 = 0
    /// `willResignActive` must install the switcher cover synchronously, before
    /// UIKit has updated the live scene/window snapshot. This visual override is
    /// independent of whether the ambiguous transition is later promoted to a
    /// real leave and lock.
    private var mobileLifecyclePrivacyOverride = false
    /// 最近一次按窗汇总。测试读 `coveredIDs` / `unlockChromeIDs`。
    private(set) var windowPrivacy = WindowPrivacyReduction(
        processPresence: .offScreen,
        startIdleTimer: true,
        surfaces: [:]
    )
    /// 锁屏恢复提交身份。离前台或退出时作废，不能倒转已落盘步骤。
    private var recoverySubmit: AppPasswordSubmitContext?
    var applicationLifecycleObserverCount: Int { applicationLifecycleObservers.count }
    #if canImport(UIKit)
    private var hostTraitRegistrations: [any UITraitChangeRegistration] = []
    #endif

    init(
        gate: any RevealGateServing,
        preferences: any PreferencesServing,
        masterPassword: any MasterPasswordServing,
        installsSnapshotCover: Bool = true,
        enablesUnlockPrompt: Bool = true,
        launchAppLockEnabled: Bool? = nil,
        autoPromptsSystemAuth: Bool = AppPrivacyController.defaultAutoPromptsSystemAuth,
        treatsApplicationResignAsBackground: Bool = AppPrivacyController.isMacDesktopRuntime,
        scenePresence: @escaping @MainActor () -> AppLockScenePresence = AppPrivacyController.liveScenePresence,
        hasForegroundActiveScene: @escaping @MainActor () -> Bool = AppPrivacyController.liveHasForegroundActiveScene,
        hasForegroundInactiveSceneWithoutActiveAppearance: @escaping @MainActor () -> Bool = AppPrivacyController.liveHasForegroundInactiveSceneWithoutActiveAppearance,
        monotonicUptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        windowsSnapshot: (@MainActor () -> [WindowPrivacyInput])? = nil,
        sessionLockBox: SessionLockBox? = nil
    ) {
        self.gate = gate
        self.preferences = preferences
        self.masterPassword = masterPassword
        self.installsSnapshotCover = installsSnapshotCover
        self.enablesUnlockPrompt = enablesUnlockPrompt
        self.autoPromptsSystemAuth = autoPromptsSystemAuth
        self.treatsApplicationResignAsBackground = treatsApplicationResignAsBackground
        self.hasForegroundActiveScene = hasForegroundActiveScene
        self.hasForegroundInactiveSceneWithoutActiveAppearance = hasForegroundInactiveSceneWithoutActiveAppearance
        self.monotonicUptime = monotonicUptime
        let snapshot = windowsSnapshot ?? {
            [WindowPrivacyInput(id: WindowPrivacyInput.syntheticProcessID, presence: scenePresence())]
        }
        self.windowsSnapshot = snapshot
        self.scenePresence = { WindowPrivacyReducer.processPresence(of: snapshot()) }
        self.sessionLockBox = sessionLockBox
        var launch = AppLockSession.unready()
        let cached = launchAppLockEnabled ?? AppLockLaunchCache.read()
        if cached == true {
            launch.applyCachedLockEnabled()
        }
        // cached false/nil must remain a neutral loading barrier. Revealing the
        // vault before authoritative preferences load creates a cold-launch
        // fail-open window when local/Cloud state actually has App Lock armed.
        self.session = launch
        sessionLockBox?.setLocked(launch.isSessionLocked)
        sessionLockBox?.setAuthorizationSuspended(
            !launch.isPreferencesReady || self.scenePresence() != .userFacing
        )
    }

    /// Mac（含 Catalyst）：回到前台不得自动弹系统验证。
    /// 用户点本窗「解锁」仍走 `requestUnlock`。
    nonisolated static var defaultAutoPromptsSystemAuth: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        false
        #else
        !ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    nonisolated static var isMacDesktopRuntime: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    static func liveScenePresence() -> AppLockScenePresence {
        WindowPrivacyReducer.processPresence(of: liveWindowsSnapshot())
    }

    static func liveHasForegroundActiveScene() -> Bool {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes.contains { scene in
            scene.activationState == .foregroundActive
        }
        #elseif canImport(AppKit)
        NSApplication.shared.isActive
        #else
        false
        #endif
    }

    static func liveHasForegroundInactiveSceneWithoutActiveAppearance() -> Bool {
        #if canImport(UIKit)
        let inactiveScenes = UIApplication.shared.connectedScenes.compactMap { scene -> UIWindowScene? in
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundInactive
            else { return nil }
            return windowScene
        }
        guard !inactiveScenes.isEmpty else { return false }
        return inactiveScenes.allSatisfy { scene in
            let visibleWindows = scene.windows.filter { !$0.isHidden }
            if visibleWindows.isEmpty {
                // An empty window list cannot borrow an active appearance from a
                // system overlay. Require the scene itself to be explicitly
                // inactive; `.unspecified` remains unknown, never proof of Home.
                return scene.traitCollection.activeAppearance == .inactive
            }
            // Control Center / LocalAuthentication keep at least one host window
            // actively presented. Home makes every visible host window inactive.
            // Requiring all of them avoids a multi-window false positive.
            return visibleWindows.allSatisfy {
                $0.traitCollection.activeAppearance == .inactive
            }
        }
        #else
        false
        #endif
    }

    static func liveLifecycleSignalSummary() -> String {
        #if canImport(UIKit)
        let appState = String(describing: UIApplication.shared.applicationState)
        let scenes = UIApplication.shared.connectedScenes.compactMap { scene -> String? in
            guard let windowScene = scene as? UIWindowScene else { return nil }
            let visibleWindows = windowScene.windows.filter { !$0.isHidden }
            let key = visibleWindows.contains(where: \.isKeyWindow)
            let sceneAppearance = String(describing: windowScene.traitCollection.activeAppearance)
            let appearances = visibleWindows.map {
                String(describing: $0.traitCollection.activeAppearance)
            }.joined(separator: ",")
            return "scene=\(String(describing: windowScene.activationState)),sceneAppearance=\(sceneAppearance),key=\(key),windowAppearance=[\(appearances)]"
        }.joined(separator: ";")
        return "app=\(appState);\(scenes)"
        #elseif canImport(AppKit)
        return "appActive=\(NSApplication.shared.isActive)"
        #else
        return "unavailable"
        #endif
    }

    static func liveWindowsSnapshot(authenticationInProgress: Bool = false) -> [WindowPrivacyInput] {
        #if canImport(UIKit)
        let appActive = UIApplication.shared.applicationState == .active
        return UIApplication.shared.connectedScenes.compactMap { scene -> WindowPrivacyInput? in
            guard let windowScene = scene as? UIWindowScene else { return nil }
            return WindowPrivacyInput(
                id: windowScene.session.persistentIdentifier,
                presence: AppLockScenePresence.resolve(
                    liveSignals(
                        for: windowScene,
                        applicationIsActive: appActive,
                        authenticationInProgress: authenticationInProgress
                    )
                )
            )
        }
        #elseif canImport(AppKit)
        let appIsActive = NSApplication.shared.isActive
        let windows = NSApplication.shared.windows.filter { $0.isVisible && !$0.isMiniaturized }
        if windows.isEmpty {
            return [WindowPrivacyInput(
                id: WindowPrivacyInput.syntheticProcessID,
                presence: appIsActive ? .userFacing : .offScreen
            )]
        }
        return windows.map { window in
            WindowPrivacyInput(
                id: AppSwitcherSnapshotCover.id(for: window),
                presence: appIsActive
                    ? ((window.isKeyWindow || window.isMainWindow) ? .userFacing : .onScreenIdle)
                    : .offScreen
            )
        }
        #else
        return [WindowPrivacyInput(id: WindowPrivacyInput.syntheticProcessID, presence: .offScreen)]
        #endif
    }

    /// 本窗仍算「人在用」：有 Key，或外观仍是 active（Face ID 可能抢走 Key，但外观不该变成闲置）。
    /// 外观已是 inactive 的窗即使还占着 Key，在 iPadOS 26 台前也当成闲置。
    #if canImport(UIKit)
    static func liveSignals(
        for scene: UIWindowScene,
        applicationIsActive: Bool,
        authenticationInProgress: Bool
    ) -> ScenePresenceSignals {
        let windows = scene.windows.filter { !$0.isHidden }
        let appearance: PresenceSignal<Bool>
        if windows.contains(where: { $0.traitCollection.activeAppearance == .active }) {
            appearance = .known(true)
        } else if windows.contains(where: { $0.traitCollection.activeAppearance == .inactive }) {
            appearance = .known(false)
        } else {
            appearance = .unknown
        }
        return ScenePresenceSignals(
            sceneIsForegroundActive: .known(scene.activationState == .foregroundActive),
            sceneIsForegroundInactive: .known(scene.activationState == .foregroundInactive),
            applicationIsActive: .known(applicationIsActive),
            isKeyWindow: .known(windows.contains(where: \.isKeyWindow)),
            activeAppearanceIsActive: appearance,
            appearsActive: .unknown,
            authenticationInProgress: authenticationInProgress,
            requiresWindowFocus: scene.traitCollection.userInterfaceIdiom != .phone
                || ProcessInfo.processInfo.isiOSAppOnMac,
            applicationInactivityMeansOffScreen: isMacDesktopRuntime
        )
    }

    static func hostHasKeyOrActiveWindow(in scenes: [UIWindowScene]) -> Bool {
        scenes.contains { scene in
            AppLockScenePresence.hostIsUserFacing(
                liveSignals(for: scene, applicationIsActive: true, authenticationInProgress: false)
            )
        }
    }
    #endif

    func start() async {
        guard !didStart else { return }
        didStart = true
        AuthenticationTrace.emit(
            "start build=\(AuthenticationTrace.buildIdentity) bundle=\(Bundle.main.bundleURL.path)"
        )
        armLifecycleObservers()
        await reloadSecurityPreferences(isStart: true)
        initialSecurityLoadCompleted = true
        // A Cloud import can finish while protected storage is still preparing.
        // Its synchronous fence must remain closed until the initial read above,
        // then this controller consumes the newest token and re-reads once.
        if let token = sessionLockBox?.currentSecurityPolicyRefreshToken() {
            let didReload = await reloadSecurityPreferencesAfterExternalImport(token)
            if didReload {
                _ = sessionLockBox?.completeExternalSecurityPolicyRefresh(token)
            }
        }
        await refreshMasterPasswordAvailability()
        await refreshCombinationAppPasswordAvailability()
        refreshBiometryAvailability()
        // SwiftUI `.task` 可能晚于系统 didBecomeActive 通知；补记一次，避免桌面第一次切 App 时
        // 因 `hasBecomeActiveOnce == false` 而既不锁也不遮挡。
        if scenePresence() == .userFacing, !session.hasBecomeActiveOnce {
            var next = session
            next.noteDidBecomeActive(now: Date())
            session = next
        }
        reconcileAuthorizationSuspension()
        syncSnapshotCoverImmediately()
        promptUnlockIfNeeded()
    }

    func retrySecurityPreferences() async {
        await reloadSecurityPreferencesFromPersistence()
        reconcileAuthorizationSuspension()
        syncSnapshotCoverImmediately()
        promptUnlockIfNeeded()
    }

    /// 「策略写着主密码、本机却没有主密码」是死局：口令框怎么输都验不过。
    /// MUST 在锁屏露面之前就查出来，把恢复出口摆到主位，而不是等用户反复试错。
    private func refreshMasterPasswordAvailability() async {
        guard session.preferences.revealPolicy == .masterPassword else {
            masterPasswordMissing = false
            return
        }
        let material = await masterPassword.materialStatus()
        masterPasswordMissing = material == .unset
        updateMaterialReadError(material)
    }

    /// 组合档缺材料不是死局：面容/触控仍可解锁。只给「使用应用密码」这条口标记。
    private func refreshCombinationAppPasswordAvailability() async {
        guard session.preferences.revealPolicy == .biometryOrAppPassword else {
            combinationAppPasswordMissing = false
            return
        }
        let material = await gate.appPasswordMaterialStatus()
        combinationAppPasswordMissing = material == .unset
        updateMaterialReadError(material)
    }

    /// 13.9：仅生物识别已不是运行时档。设备验证可回落本机密码，不再把缺生物识别当死局。
    private func refreshBiometryAvailability() {
        biometryUnavailableForUnlock = false
    }

    func applyLivePreferences(_ prefs: AppLockPreferences) {
        guard session.isPreferencesReady else { return }
        if session.preferences != prefs {
            sessionLockBox?.invalidateAuthorizationLeases()
        }
        var next = session
        next.applyLivePreferences(prefs)
        session = next
        AppLockLaunchCache.write(prefs.isAppLockArmed)
        if !prefs.isAppLockArmed {
            unlockError = nil
            cancelledCurrentLock = false
        }
        if prefs.revealPolicy != .masterPassword {
            masterPasswordMissing = false
        }
        if prefs.revealPolicy != .biometryOrAppPassword {
            combinationAppPasswordMissing = false
        }
        refreshBiometryAvailability()
        syncSnapshotCoverImmediately()
    }

    /// Settings captures both page and session generations before presenting
    /// authentication. Production always uses the controller's real session
    /// box; previews without one retain the same API without manufacturing a
    /// process-global mutable dependency.
    func makeSecurityPreferenceAuthorization(
        currentPolicy: RevealPolicy,
        targetPolicy: RevealPolicy? = nil
    ) throws -> SecurityPreferenceAuthorization {
        let lock: any SessionLockQuerying = sessionLockBox ?? AlwaysUnlockedSessionLock()
        return try SecurityPreferenceAuthorization(
            currentPolicy: currentPolicy,
            targetPolicy: targetPolicy,
            sessionLock: lock
        )
    }

    /// Authentication may temporarily make the app inactive. Once it returns,
    /// however, a settings transaction may proceed only while our window is
    /// user-facing. This is also an explicit reconciliation point for iPad
    /// Stage Manager, where no second focus notification is guaranteed.
    func requireUserFacingForAuthenticatedSettingsCommit() throws {
        try requireForegroundForAuthenticationCommit()
    }

    /// `start()` 读到真实偏好之后：未就绪则按冷启动上锁；已经按「没开锁」进过界面则不得再 `completeColdStart`（会把刚解开的锁重新锁上）。
    private func applyStartPreferences(_ prefs: AppLockPreferences) {
        if session.isPreferencesReady {
            if prefs.appLockEnabled && !session.hasBecomeActiveOnce {
                var next = session
                next.completeColdStart(with: prefs)
                session = next
                AppLockLaunchCache.write(prefs.isAppLockArmed)
            } else {
                applyLivePreferences(prefs)
            }
            return
        }
        var next = session
        next.completeColdStart(with: prefs)
        session = next
        AppLockLaunchCache.write(prefs.isAppLockArmed)
    }

    func reloadAfterErase() async {
        guard initialSecurityLoadCompleted else { return }
        await reloadSecurityPreferences(isStart: !session.isPreferencesReady)
    }

    /// CloudKit 导入和每次回前台都从同一持久源刷新安全偏好，避免生命周期/UI
    /// 长期持有旧 session，而业务服务已经按新策略执行。
    func reloadSecurityPreferencesFromPersistence() async {
        if let token = sessionLockBox?.currentSecurityPolicyRefreshToken() {
            let didReload = await reloadSecurityPreferencesAfterExternalImport(token)
            if didReload {
                _ = sessionLockBox?.completeExternalSecurityPolicyRefresh(token)
            }
            return
        }
        await reloadSecurityPreferences(isStart: !session.isPreferencesReady)
        await refreshMasterPasswordAvailability()
        await refreshCombinationAppPasswordAvailability()
        refreshBiometryAvailability()
    }

    /// Cloud import uses a two-part revision fence: the notification callback
    /// synchronously blocks all ordinary authorization, then this MainActor
    /// phase reads the authoritative store and applies it only if its token is
    /// still newest. An older overlapping reload must never overwrite the UI
    /// session or reopen authorization around a newer imported policy.
    func reloadSecurityPreferencesAfterExternalImport(
        _ token: SecurityPolicyRefreshToken
    ) async -> Bool {
        guard initialSecurityLoadCompleted else { return false }
        guard sessionLockBox?.isCurrentSecurityPolicyRefresh(token) == true else {
            return false
        }
        let didLoad = await reloadSecurityPreferences(
            isStart: !session.isPreferencesReady,
            externalRefreshToken: token
        )
        guard didLoad else { return false }
        await refreshMasterPasswordAvailability()
        await refreshCombinationAppPasswordAvailability()
        refreshBiometryAvailability()
        return sessionLockBox?.isCurrentSecurityPolicyRefresh(token) == true
    }

    func handleWillResignActive(now: Date = Date()) {
        if treatsApplicationResignAsBackground {
            // Touch ID / 系统密码框也会让 Mac App 暂时 inactive；认证仍在本 App 头上时不能自锁。
            // 只能以门闩正在持有系统认证请求为准。`isUnlocking` / `isRecovering`
            // 还会覆盖认证后的持久化阶段；若那时用户切走，必须立即撤销提交租约。
            guard !gate.isAuthenticationInProgress() else {
                deferDesktopLeaveUntilAuthenticationSettles(now: now)
                syncSnapshotCoverImmediately()
                return
            }
            handleDesktopApplicationDidLeave(now: now)
            return
        }
        let presence = scenePresence()
        let foregroundSceneIsActive = hasForegroundActiveScene()
        let inactiveSceneWithoutActiveAppearance = hasForegroundInactiveSceneWithoutActiveAppearance()
        AuthenticationTrace.emit(
            "will resign active; presence=\(presence) foregroundSceneActive=\(foregroundSceneIsActive) inactiveSceneWithoutActiveAppearance=\(inactiveSceneWithoutActiveAppearance) locked=\(session.isSessionLocked) autoLockSeconds=\(session.preferences.autoLockSeconds) signals={\(Self.liveLifecycleSignalSummary())}"
        )
        switch presence {
        case .userFacing:
            beginImmediateResignProbe(now: now, forcePrivacyCover: true)
            // 控制中心 / Face ID 抢前台：本窗仍在操作。不得当离开去 cancel。
            // 其它已离屏的窗仍按汇总盖快照。
            syncSnapshotCoverImmediately()
            return
        case .onScreenIdle:
            beginImmediateResignProbe(now: now, forcePrivacyCover: false)
            if gate.isAuthenticationInProgress() {
                deferHostFocusRevocationUntilAuthenticationSettles()
            } else {
                revokeNonUserFacingAuthorizations()
            }
            cancelAuthenticationIfUserMovedToAnotherApp()
            flashSwitcherCoverThenReleaseIdle(now: now)
            return
        case .offScreen:
            clearImmediateResignProbe()
            // A very fast Home -> icon return can reverse the UIKit transition
            // before either application/scene `didEnterBackground` notification
            // is delivered. At this point the aggregate scene snapshot already
            // proves that every app window is off screen, so waiting for a later
            // notification creates a real fail-open window for "immediately".
            // Control Center / Face ID either remain `.userFacing` or retain an
            // active host appearance; a window beside another app stays idle.
            recordConfirmedBackground(
                now: now,
                uptime: ProcessInfo.processInfo.systemUptime
            )
            return
        }
    }

    /// UIApplication 的通知可能先于最后一扇 UIScene 把 activationState 更新为
    /// background。先尝试汇总；若快照仍是 onScreenIdle，后续 scene 通知会再次
    /// 汇总。这样既不漏 Home 离场，也不把 iPad 台前同组失焦误判为离屏。
    func handleDidEnterBackground(now: Date = Date()) {
        AuthenticationTrace.emit("application background notification; presence=\(scenePresence())")
        if treatsApplicationResignAsBackground {
            // `willResignActive` is ambiguous on desktop because LocalAuthentication
            // temporarily deactivates the host app. `didEnterBackground` is not: once
            // UIKit confirms a real background transition, every pending recovery or
            // unlock transaction must be revoked before it can persist policy/material.
            handleDesktopApplicationDidLeave(now: now)
            return
        }
        rememberApplicationBackground(now: now)
        reconcileConfirmedBackground(
            now: now,
            uptime: ProcessInfo.processInfo.systemUptime,
            presence: scenePresence()
        )
    }

    /// Scene-based 生命周期的最终确认点。多窗时只有最后一扇离屏，进程汇总才是
    /// `.offScreen`；先后台的单窗通知不得锁住仍在操作的另一扇窗。
    func handleSceneDidEnterBackground(
        now: Date = Date(),
        confirmedSceneID: String? = nil
    ) {
        guard !treatsApplicationResignAsBackground else { return }
        let confirmedPresence = processPresence(confirmingOffScreen: confirmedSceneID)
        AuthenticationTrace.emit("scene background notification; presence=\(confirmedPresence)")
        reconcileConfirmedBackground(
            now: now,
            uptime: ProcessInfo.processInfo.systemUptime,
            presence: confirmedPresence
        )
    }

    private func reconcileConfirmedBackground(
        now: Date,
        uptime: TimeInterval,
        presence: AppLockScenePresence
    ) {
        switch presence {
        case .userFacing:
            // One scene may have entered the background while another window of
            // this app is still being used. Keep the process authority available;
            // that active scene is not guaranteed to emit another didBecomeActive
            // notification that could reopen a globally suspended SessionLockBox.
            hostFocusReconciliationTask?.cancel()
            hostFocusReconciliationTask = nil
            cancelImmediateResignCandidateForAuthoritativeUserFacingHost()
            reconcileAuthorizationSuspension()
            shouldAutoPromptOnBecomeActive = false
            syncSnapshotCoverImmediately()
        case .onScreenIdle:
            shouldAutoPromptOnBecomeActive = false
            if gate.isAuthenticationInProgress() {
                deferHostFocusRevocationUntilAuthenticationSettles()
            } else {
                revokeNonUserFacingAuthorizations()
            }
            cancelAuthenticationIfUserMovedToAnotherApp()
            syncSnapshotCoverImmediately()
        case .offScreen:
            recordConfirmedBackground(now: now, uptime: uptime)
        }
    }

    private func rememberApplicationBackground(now: Date) {
        guard !didRecordBackgroundForCurrentCycle else { return }
        guard pendingApplicationBackground == nil else { return }
        pendingApplicationBackground = PendingApplicationBackground(
            date: now,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func beginImmediateResignProbe(now: Date, forcePrivacyCover: Bool) {
        clearImmediateResignProbe()
        guard isImmediateLockArmed,
              session.hasBecomeActiveOnce,
              !session.isSessionLocked,
              !gate.isAuthenticationInProgress()
        else {
            return
        }
        let uptime = monotonicUptime()
        pendingImmediateResignProbe = ImmediateResignProbe(
            observation: PendingApplicationBackground(date: now, uptime: uptime),
            deadlineUptime: uptime + 2
        )
        immediateResignProbeAcceptsRawEvidence = true
        // The first frame cannot tell Home from Control Center, so it is not
        // enough to revoke a generation permanently. A reversible fence closes
        // the commit window until either a real leave is confirmed or the exact
        // same active session returns.
        sessionLockBox?.setAuthorizationProvisionallyFenced(true)
        if forcePrivacyCover,
           session.preferences.hideInAppSwitcher || session.isSessionLocked {
            mobileLifecyclePrivacyOverride = true
        }
        let probeRevision = immediateResignProbeRevision
        AuthenticationTrace.emit(
            "immediate resign probe started; revision=\(probeRevision) signals={\(Self.liveLifecycleSignalSummary())}"
        )
        if finalizeImmediateResignProbeIfQualified() { return }
        immediateResignProbeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while true {
                do {
                    try await Task.sleep(for: .milliseconds(25))
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      self.immediateResignProbeRevision == probeRevision,
                      self.pendingImmediateResignProbe != nil
                else { return }
                if !self.isImmediateLockArmed || self.gate.isAuthenticationInProgress() {
                    self.stopImmediateResignRawObservation(keepForForegroundProof: false)
                    return
                }
                if self.finalizeImmediateResignProbeIfQualified() { return }
            }
        }
    }

    private var isImmediateLockArmed: Bool {
        session.isPreferencesReady
            && session.preferences.isAppLockArmed
            && session.preferences.autoLockSeconds <= 0
    }

    @discardableResult
    private func finalizeImmediateResignProbeIfQualified() -> Bool {
        guard immediateResignProbeAcceptsRawEvidence,
              let probe = pendingImmediateResignProbe else { return false }
        guard monotonicUptime() <= probe.deadlineUptime else {
            expireImmediateResignRawObservation()
            return false
        }
        guard isImmediateLockArmed, !gate.isAuthenticationInProgress() else {
            stopImmediateResignRawObservation(keepForForegroundProof: false)
            return false
        }
        let presence = scenePresence()
        let hasRawHomeTransition = !hasForegroundActiveScene()
            && hasForegroundInactiveSceneWithoutActiveAppearance()
        guard presence == .offScreen || hasRawHomeTransition else { return false }
        AuthenticationTrace.emit(
            "immediate resign probe confirmed; presence=\(presence) rawHomeTransition=\(hasRawHomeTransition) signals={\(Self.liveLifecycleSignalSummary())}"
        )
        recordConfirmedBackground(
            now: probe.observation.date,
            uptime: probe.observation.uptime
        )
        return true
    }

    @discardableResult
    private func clearImmediateResignProbe() -> Bool {
        let hadCandidate = pendingImmediateResignProbe != nil
        immediateResignProbeRevision &+= 1
        pendingImmediateResignProbe = nil
        immediateResignProbeAcceptsRawEvidence = false
        immediateResignProbeTask?.cancel()
        immediateResignProbeTask = nil
        return hadCandidate
    }

    private func cancelImmediateResignCandidateForAuthoritativeUserFacingHost() {
        clearImmediateResignProbe()
        sessionLockBox?.setAuthorizationProvisionallyFenced(false)
        mobileLifecyclePrivacyOverride = false
    }

    private func stopImmediateResignRawObservation(keepForForegroundProof: Bool) {
        immediateResignProbeRevision &+= 1
        if !keepForForegroundProof {
            pendingImmediateResignProbe = nil
        }
        immediateResignProbeAcceptsRawEvidence = false
        immediateResignProbeTask?.cancel()
        immediateResignProbeTask = nil
    }

    private func expireImmediateResignRawObservation() {
        guard immediateResignProbeAcceptsRawEvidence else { return }
        let revision = immediateResignProbeRevision
        AuthenticationTrace.emit(
            "immediate resign probe expired; revision=\(revision) signals={\(Self.liveLifecycleSignalSummary())}"
        )
        // Raw traits are no longer accepted after the absolute monotonic
        // deadline. Keep only the original timestamp so a later, authoritative
        // willEnterForeground can still close a background cycle.
        stopImmediateResignRawObservation(keepForForegroundProof: true)
    }

    private func processPresence(confirmingOffScreen sceneID: String?) -> AppLockScenePresence {
        guard let sceneID else { return scenePresence() }
        let confirmed = windowsSnapshot().map { input in
            input.id == sceneID
                ? WindowPrivacyInput(id: input.id, presence: .offScreen)
                : input
        }
        return WindowPrivacyReducer.processPresence(of: confirmed)
    }

    private func recordConfirmedBackground(now: Date, uptime: TimeInterval) {
        // Promote the reversible candidate fence before clearing its state. The
        // order leaves no cross-thread interval in which an old lease can commit.
        sessionLockBox?.setAuthorizationSuspended(true)
        sessionLockBox?.setAuthorizationProvisionallyFenced(false)
        clearImmediateResignProbe()
        guard !didRecordBackgroundForCurrentCycle else {
            pendingApplicationBackground = nil
            syncSnapshotCoverImmediately()
            return
        }
        let observation = pendingApplicationBackground
            ?? PendingApplicationBackground(date: now, uptime: uptime)
        pendingApplicationBackground = nil
        didRecordBackgroundForCurrentCycle = true
        var next = session
        next.noteDidEnterBackground(now: observation.date, uptime: observation.uptime)
        session = next
        if session.preferences.hideInAppSwitcher || session.isSessionLocked {
            mobileLifecyclePrivacyOverride = true
        }
        shouldAutoPromptOnBecomeActive = false
        invalidateActiveSubmitRequests()
        gate.cancelAllAuthentication()
        syncSnapshotCoverImmediately()
    }

    func handleWillEnterForeground(now: Date = Date()) {
        AuthenticationTrace.emit(
            "will enter foreground; recordedBackground=\(didRecordBackgroundForCurrentCycle) pendingBackground=\(pendingApplicationBackground != nil) pendingImmediateProbe=\(pendingImmediateResignProbe != nil) locked=\(session.isSessionLocked)"
        )
        // This notification is posted only when the application is leaving the
        // background. If a rapid return prevented the scene snapshot from ever
        // settling on `.offScreen`, consume the preserved background event now,
        // before the foreground path can reveal the vault.
        if let pending = pendingApplicationBackground,
           !didRecordBackgroundForCurrentCycle {
            recordConfirmedBackground(now: pending.date, uptime: pending.uptime)
        } else if let pending = pendingImmediateResignProbe,
                  !didRecordBackgroundForCurrentCycle {
            // Unlike a plain resign, willEnterForeground is itself proof that
            // UIKit is returning from background, even when didEnter was omitted.
            recordConfirmedBackground(
                now: pending.observation.date,
                uptime: pending.observation.uptime
            )
        }
        clearImmediateResignProbe()
        var next = session
        next.noteWillEnterForeground(now: now, uptime: ProcessInfo.processInfo.systemUptime)
        session = next
        // 台前组被点亮但焦点在组里别的软件：不得预约触控 ID。
        if scenePresence() == .userFacing {
            shouldAutoPromptOnBecomeActive = true
        }
        syncSnapshotCoverImmediately()
    }

    /// iPadOS 26 台前同组切焦点常常不走 `willResignActive`。Key / 闲置外观变了就要收掉系统验证，仍不得上锁。
    func handleHostFocusDidChange() {
        if finalizeImmediateResignProbeIfQualified() { return }
        switch scenePresence() {
        case .userFacing:
            hostFocusReconciliationTask?.cancel()
            hostFocusReconciliationTask = nil
            reconcileAuthorizationSuspension()
            return
        case .onScreenIdle:
            shouldAutoPromptOnBecomeActive = false
            if gate.isAuthenticationInProgress() {
                deferHostFocusRevocationUntilAuthenticationSettles()
            } else {
                revokeNonUserFacingAuthorizations()
            }
            cancelAuthenticationIfUserMovedToAnotherApp()
            syncSnapshotCoverImmediately()
        case .offScreen:
            shouldAutoPromptOnBecomeActive = false
            if gate.isAuthenticationInProgress() {
                deferHostFocusRevocationUntilAuthenticationSettles()
            } else {
                revokeNonUserFacingAuthorizations()
            }
            cancelAuthenticationIfUserMovedToAnotherApp()
            syncSnapshotCoverImmediately()
        }
    }

    func handleDidBecomeActive(now: Date = Date()) {
        // The active edge wins before logging or any other work. It revokes the
        // old generation of asynchronous probes and removes only the reversible
        // candidate fence; a confirmed background's formal suspension remains
        // until normal foreground reconciliation below.
        let hadUnconfirmedResignCandidate = clearImmediateResignProbe()
        sessionLockBox?.setAuthorizationProvisionallyFenced(false)
        mobileLifecyclePrivacyOverride = false
        AuthenticationTrace.emit(
            "did become active; recordedBackground=\(didRecordBackgroundForCurrentCycle) pendingBackground=\(pendingApplicationBackground != nil) cancelledImmediateProbe=\(hadUnconfirmedResignCandidate) locked=\(session.isSessionLocked)"
        )
        // Lifecycle observers are armed before protected-storage preparation.
        // A didBecomeActive delivered during that startup barrier must not start
        // a non-start preference reload and accidentally bypass cold-start rules.
        let mayRefreshSecurityPreferences = session.isPreferencesReady
        // A plain pending application notification without a return edge remains
        // ambiguous in the multi-window model and must not outlive activation.
        pendingApplicationBackground = nil
        deferredDesktopLeaveAt = nil
        desktopLeaveReconciliationTask?.cancel()
        desktopLeaveReconciliationTask = nil
        if scenePresence() == .userFacing {
            hostFocusReconciliationTask?.cancel()
            hostFocusReconciliationTask = nil
            reconcileAuthorizationSuspension()
        } else if gate.isAuthenticationInProgress() {
            deferHostFocusRevocationUntilAuthenticationSettles()
        } else {
            revokeNonUserFacingAuthorizations()
        }
        applicationIsInactiveForPrivacy = false
        var next = session
        // Only the dedicated will-enter-foreground notification may evaluate a
        // background timeout. `didBecomeActive` also follows Control Center,
        // Face ID and other transient interruptions; reusing an older departure
        // timestamp here can lock a session while the user never left again.
        next.noteDidBecomeActive(now: now)
        session = next
        didRecordBackgroundForCurrentCycle = false
        if session.isSessionLocked {
            // 路径 2：已锁 — 只揭当前操作窗的截屏遮罩，把点击交给 SwiftUI 解锁层。
            // MUST NOT 一次摘掉其它显示器上的罩。
            snapshotCoverTask?.cancel()
            snapshotCoverTask = nil
            syncSnapshotCoverImmediately()
        } else if hadUnconfirmedResignCandidate {
            // Control Center and other unconfirmed overlays must not leave the
            // provisional privacy cover visibly hanging over the active app.
            syncSnapshotCoverImmediately()
        } else {
            // 路径 1：未锁 — 直接进内容；截屏遮罩只为多任务预览，可略延迟摘且不可抢点击。
            scheduleSnapshotCoverSyncAfterActivation()
        }
        // 台前调度闪一下 active 不会先走 willEnterForeground，不得在这里自动弹触控 ID。
        let shouldPrompt = shouldAutoPromptOnBecomeActive
        shouldAutoPromptOnBecomeActive = false
        if shouldPrompt, shouldAutomaticallyPromptUnlock() {
            promptUnlockIfNeeded()
        }
        // 主密码可能在别处（设置页、另一台设备）被清掉；生物识别也可能被系统关掉。
        if initialSecurityLoadCompleted, mayRefreshSecurityPreferences {
            Task {
                await reloadSecurityPreferencesFromPersistence()
            }
        }
    }

    func requestUnlock() {
        cancelledCurrentLock = false
        if usesMasterPasswordUnlock { return }
        promptUnlockIfNeeded(force: true)
    }

    /// 主密码只在这次调用里用，不写入可观察状态。
    func unlockWithMasterPassword(_ password: String) async {
        guard session.needsUnlockPrompt else { return }
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            unlockError = String(localized: "appLock.masterPassword.empty")
            return
        }
        guard !isUnlocking else { return }
        isUnlocking = true
        unlockError = nil
        defer { isUnlocking = false }
        do {
            try await gate.confirmWithMasterPassword(
                reason: String(localized: "gate.unlockApp"),
                password: trimmed,
                purpose: .unlockApp
            )
            try requireForegroundForAuthenticationCommit()
            finishUnlockSucceeded()
        } catch {
            cancelledCurrentLock = true
            if isMasterPasswordNotSet(error) {
                masterPasswordMissing = true
                unlockError = String(localized: "appLock.masterPassword.notSet")
            } else {
                unlockError = appPasswordUnlockMessage(for: error)
            }
        }
    }

    /// 用户显式点「使用应用密码」：取消进行中的系统设备认证并进入独立应用密码路径。
    func beginCombinationAppPasswordEntry() async {
        guard usesCombinationUnlock else { return }
        cancelledCurrentLock = true
        gate.cancelAuthentication(owner: .appUnlock)
        unlockError = nil
        await refreshCombinationAppPasswordAvailability()
    }

    /// 组合档已设应用密码：只走 `confirmCombinationWithAppPassword`，MUST NOT 改走设备主人或自动从生物取消进来。
    func unlockWithCombinationAppPassword(_ password: String) async {
        guard session.needsUnlockPrompt, usesCombinationUnlock else { return }
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            unlockError = String(localized: "appLock.masterPassword.empty")
            return
        }
        guard !isUnlocking else { return }
        isUnlocking = true
        unlockError = nil
        defer { isUnlocking = false }
        do {
            let material = await gate.appPasswordMaterialStatus()
            guard AppPasswordPolicyGate.canUseAppPasswordEntry(material: material) else {
                combinationAppPasswordMissing = material == .unset
                unlockError = AppPasswordPolicyGate.ordinaryEntryUnavailableMessage(material: material)
                return
            }
            try await gate.confirmCombinationWithAppPassword(
                reason: String(localized: "gate.unlockApp"),
                password: trimmed,
                purpose: .unlockApp
            )
            try requireForegroundForAuthenticationCommit()
            combinationAppPasswordMissing = false
            finishUnlockSucceeded()
        } catch {
            cancelledCurrentLock = true
            if isMasterPasswordNotSet(error) {
                combinationAppPasswordMissing = true
                unlockError = String(localized: "appLock.combination.notSet")
            } else {
                unlockError = appPasswordUnlockMessage(for: error)
            }
        }
    }

    /// 锁屏普通入口不得设密。组合档缺材料：生物识别仍可解锁；应用密码路径拒绝，走独立恢复。
    func setupCombinationAppPasswordFromLock(_ password: String) async {
        _ = password
        guard session.needsUnlockPrompt, usesCombinationUnlock else { return }
        combinationAppPasswordMissing = true
        cancelledCurrentLock = true
        unlockError = String(localized: "appLock.combination.notSet")
    }

    /// 忘记应用密码的唯一出口。门槛是设备主人验证（Face ID / 本机密码），与设置页
    /// 「重置应用密码」同一道门，MUST NOT 更低——否则 App 锁形同虚设。
    ///
    /// 应用密码只是门闩、不是加密密钥，清掉它不会让任何已存明文变得读不出来。
    /// 顺序：设备主人 → 策略落到设备验证 → 再按预期版本删 `.masterpw`。
    /// MUST NOT 落到 `.noVerification`。persist 失败则保留材料与锁态。
    func recoverFromLostMasterPassword() async {
        guard !isRecovering, !isUnlocking else { return }
        isRecovering = true
        unlockError = nil
        defer { isRecovering = false }

        let gate = self.gate
        let preferences = self.preferences
        let master = self.masterPassword
        let currentPolicy = await snapshotOpenedRevealPolicy()
        let lease = AppPasswordPageLease(
            target: .biometricOrPasscode,
            currentPolicy: currentPolicy
        )
        guard let token = lease.begin() else { return }
        let request = AppPasswordSubmitContext(lease: lease, token: token)
        recoverySubmit = request
        defer {
            lease.end(token)
            if recoverySubmit?.token == token {
                recoverySubmit = nil
            }
        }
        gate.cancelAuthentication(owner: .appUnlock)
        cancelledCurrentLock = true
        do {
            try await AppPasswordRecovery.recoverToDeviceAuth(
                confirmMandatory: {
                    try await gate.confirmMandatory(
                        reason: String(localized: "gate.resetMasterPassword"),
                        purpose: .recovery
                    )
                    try await self.requireForegroundForAuthenticationCommit()
                },
                persistDeviceAuth: {
                    try await AppPasswordRecovery.awaitPersist(
                        preferences,
                        AppPasswordRecovery.deviceAuthPatch,
                        authorizing: {
                            try await self.authorizeRecoveryCommit(
                                request,
                                step: .policyPersist
                            )
                        },
                        committing: { operation in
                            try request.commit(.policyPersist, operation: operation)
                        },
                        expectedCurrentPolicy: currentPolicy
                    )
                },
                resetIfRevision: { expected in
                    try await self.authorizeRecoveryCommit(
                        request,
                        step: .recoveryDelete
                    )
                    try await master.reset(expectedRevision: expected, committing: { operation in
                        try request.commit(.recoveryDelete, operation: operation)
                    })
                    try await self.authorizeRecoveryCommit(
                        request,
                        step: .recoveryDelete
                    )
                },
                snapshotRevision: {
                    await master.materialRevision()
                },
                authorize: { try request.authorize(.proceed) }
            )
            unlockError = nil
        } catch ApiRelayError.authenticationCancelled {
            unlockError = nil
            return
        } catch {
            unlockError = error.localizedDescription
        }
        await applyRecoveryOutcomeKeepingLock()
    }

    /// 恢复只同步已经落盘的策略/材料，丢弃原解锁待办，MUST NOT 自动解锁。
    private func applyRecoveryOutcomeKeepingLock() async {
        if let stored = try? await preferences.load() {
            applyLivePreferences(AppLockPreferences(stored))
        }
        await refreshMasterPasswordAvailability()
        await refreshCombinationAppPasswordAvailability()
    }

    /// 组合档生物识别不可用/锁定时的出口。门槛与忘记主密码相同：设备主人验证。
    /// 验证方式落到 `.biometricOrPasscode`（可用本机密码），MUST NOT 落到 `.noVerification`。
    func recoverFromUnavailableBiometry() async {
        guard !isRecovering, !isUnlocking else { return }
        isRecovering = true
        unlockError = nil
        defer { isRecovering = false }

        do {
            let currentPolicy = await snapshotOpenedRevealPolicy()
            let lease = AppPasswordPageLease(
                target: .biometricOrPasscode,
                currentPolicy: currentPolicy
            )
            guard let token = lease.begin() else { return }
            let request = AppPasswordSubmitContext(lease: lease, token: token)
            recoverySubmit = request
            defer {
                lease.end(token)
                if recoverySubmit?.token == token {
                    recoverySubmit = nil
                }
            }
            try await gate.confirmMandatory(
                reason: String(localized: "gate.resetMasterPassword"),
                purpose: .recovery
            )
            try requireForegroundForAuthenticationCommit()
            try request.authorize(.proceed)
            try await AppPasswordRecovery.awaitPersist(
                preferences,
                AppPasswordRecovery.deviceAuthPatch,
                authorizing: {
                    try await self.authorizeRecoveryCommit(
                        request,
                        step: .policyPersist
                    )
                },
                committing: { operation in
                    try request.commit(.policyPersist, operation: operation)
                },
                expectedCurrentPolicy: currentPolicy
            )
            try authorizeRecoveryCommit(request, step: .policyPersist)
        } catch ApiRelayError.authenticationCancelled {
            unlockError = nil
            return
        } catch {
            unlockError = error.localizedDescription
            return
        }

        var next = session.preferences
        next.revealPolicy = .biometricOrPasscode
        applyLivePreferences(next)
        finishUnlockSucceeded()
    }

    /// 「本机没有主密码」是死局、要走恢复；「密码输错」重试即可。
    /// 两者 MUST NOT 共用一句提示——用户无从判断该重试还是该找出口。
    private func isMasterPasswordNotSet(_ error: Error) -> Bool {
        guard case let ApiRelayError.validationFailed(_, reason) = error else { return false }
        return reason == "master_password_not_set"
    }

    /// 锁屏不能把取消、限流或 Keychain 故障都说成“密码错误”。
    /// 错误密码允许重试；其余错误必须保留真实类别，避免用户无效地反复输入。
    private func appPasswordUnlockMessage(for error: Error) -> String {
        switch error as? ApiRelayError {
        case .authenticationFailed:
            return String(localized: "appLock.masterPassword.incorrect")
        case .authenticationCancelled:
            return String(localized: "appLock.unlockInterrupted")
        case .validationFailed(_, let reason) where reason == "material_unreadable":
            return String(localized: "settings.appPassword.status.unreadable")
        case .masterPasswordRetryDelayed, .masterPasswordLocked, .keychainFailure:
            return error.localizedDescription
        default:
            return error.localizedDescription
        }
    }

    private func updateMaterialReadError(_ material: AppPasswordMaterialStatus) {
        let unreadable = String(localized: "settings.appPassword.status.unreadable")
        if material == .unreadable {
            unlockError = unreadable
        } else if unlockError == unreadable {
            unlockError = nil
        }
    }

    @discardableResult
    private func reloadSecurityPreferences(
        isStart: Bool,
        externalRefreshToken: SecurityPolicyRefreshToken? = nil
    ) async -> Bool {
        do {
            let prefs = AppLockPreferences(try await preferences.load())
            if let externalRefreshToken,
               sessionLockBox?.isCurrentSecurityPolicyRefresh(externalRefreshToken) != true {
                return false
            }
            securityPreferencesUnavailable = false
            if isStart {
                applyStartPreferences(prefs)
            } else {
                applyLivePreferences(prefs)
            }
            return true
        } catch {
            if let externalRefreshToken,
               sessionLockBox?.isCurrentSecurityPolicyRefresh(externalRefreshToken) != true {
                return false
            }
            securityPreferencesUnavailable = true
            if AppLockLaunchCache.read() == true {
                var next = session
                next.applyCachedLockEnabled()
                session = next
            }
            return false
        }
    }

    /// 生命周期要不要自己弹系统验证。测试可直接问，避免在测试进程里真的 `evaluatePolicy`。
    func shouldAutomaticallyPromptUnlock() -> Bool {
        guard enablesUnlockPrompt else { return false }
        guard session.needsUnlockPrompt else { return false }
        guard !usesMasterPasswordUnlock else { return false }
        guard !cancelledCurrentLock else { return false }
        guard !isUnlocking else { return false }
        guard autoPromptsSystemAuth else { return false }
        guard scenePresence() == .userFacing else { return false }
        guard isHostApplicationFrontmost() else { return false }
        return true
    }

    /// 人已经点到别的软件：进行中的触控 ID 必须立刻收掉，否则系统框会盖在 Xcode 上。
    /// 系统验证框正在前（状态 C）不得当成同组闲置去取消。
    private func cancelAuthenticationIfUserMovedToAnotherApp() {
        guard !isHostApplicationFrontmost() else { return }
        if isUnlocking || isRecovering || gate.isAuthenticationInProgress() {
            return
        }
        cancelledCurrentLock = true
        gate.cancelAllAuthentication()
    }

    private func invalidateActiveSubmitRequests() {
        recoverySubmit?.lease.invalidate()
    }

    /// Leaving the user-facing window revokes both kinds of authority used by
    /// security changes. Keeping this separate from lock timing is important on
    /// iPad: an on-screen-but-idle Stage Manager window need not lock yet, but it
    /// must not finish a privileged write in the background.
    private func revokeNonUserFacingAuthorizations() {
        sessionLockBox?.setAuthorizationSuspended(true)
        invalidateActiveSubmitRequests()
    }

    /// New authority is available only after the first authoritative preference
    /// load and while at least one app window is genuinely user-facing. This is
    /// separate from the visible lock bit and from Cloud's revision fence.
    private func reconcileAuthorizationSuspension() {
        sessionLockBox?.setAuthorizationSuspended(
            !initialSecurityLoadCompleted
                || !session.isPreferencesReady
                || scenePresence() != .userFacing
        )
    }

    /// 恢复事务每个不可逆提交边界都同时核对真实桌面焦点与页面 generation。
    /// 不能只等 deferred reconciliation：持久化链和 Keychain 删除都可能在认证结束后继续 await。
    private func authorizeRecoveryCommit(
        _ request: AppPasswordSubmitContext,
        step: AppPasswordSubmitStep
    ) throws {
        try requireForegroundForAuthenticationCommit()
        try request.authorize(step)
    }

    /// 提交边界核对的是落盘策略，不能只信尚未 start/同步的内存会话。
    private func snapshotOpenedRevealPolicy() async -> RevealPolicy {
        if let stored = try? await preferences.load() {
            return RevealPolicyPersistence.canonical(stored.revealPolicy)
        }
        return RevealPolicyPersistence.canonical(session.preferences.revealPolicy)
    }

    /// 同组闲置：若开了切换器隐藏，允许先盖再摘，结束态不得留白锁屏、不得开始计时。
    private func flashSwitcherCoverThenReleaseIdle(now: Date) {
        guard session.hasBecomeActiveOnce else { return }
        guard session.preferences.hideInAppSwitcher || session.isSessionLocked else { return }
        var next = session
        next.noteWillResignActive(now: now)
        session = next
        syncSnapshotCoverImmediately()
        next = session
        next.releaseOnScreenIdle()
        session = next
        syncSnapshotCoverImmediately()
    }

    private func isHostApplicationFrontmost() -> Bool {
        scenePresence() == .userFacing
    }

    private func promptUnlockIfNeeded(force: Bool = false) {
        guard enablesUnlockPrompt else { return }
        guard !AppRuntime.isRunningTests else { return }
        guard session.needsUnlockPrompt else { return }
        guard !usesMasterPasswordUnlock else { return }
        guard force || !cancelledCurrentLock else { return }
        guard !isUnlocking else { return }
        // Mac 回到前台、或 iPad 台前同组切焦点：生命周期不得自己弹系统框。点本窗「解锁」带 force。
        if !force {
            guard shouldAutomaticallyPromptUnlock() else { return }
        }
        Task { await promptUnlock(force: force) }
    }

    // Internal so lifecycle regression tests can exercise the real async unlock path.
    func promptUnlock(force: Bool = false) async {
        AuthenticationTrace.emit("unlock requested; needsPrompt=\(session.needsUnlockPrompt) busy=\(isUnlocking)")
        guard session.needsUnlockPrompt, !isUnlocking else { return }
        if usesMasterPasswordUnlock { return }
        if !force, !shouldAutomaticallyPromptUnlock() { return }
        isUnlocking = true
        unlockError = nil
        defer { isUnlocking = false }
        do {
            switch session.preferences.revealPolicy {
            case .masterPassword:
                return
            case .noVerification:
                finishUnlockSucceeded()
                return
            case .biometricOrPasscode:
                try await gate.confirm(
                    reason: String(localized: "gate.unlockApp"),
                    policy: .biometricOrPasscode,
                    purpose: .unlockApp
                )
            case .biometryOrAppPassword:
                try await gate.confirm(
                    reason: String(localized: "gate.unlockApp"),
                    policy: .biometryOrAppPassword,
                    purpose: .unlockApp
                )
            }
            try requireForegroundForAuthenticationCommit()
            finishUnlockSucceeded()
        } catch let error as ApiRelayError {
            if case .authenticationCancelled = error {
                cancelledCurrentLock = true
                unlockError = String(localized: "appLock.unlockInterrupted")
            } else if case .biometryUnavailable = error {
                biometryUnavailableForUnlock = true
                cancelledCurrentLock = true
                unlockError = nil
            } else if case .biometryLockout = error {
                biometryUnavailableForUnlock = true
                cancelledCurrentLock = true
                unlockError = nil
            } else {
                cancelledCurrentLock = true
                unlockError = error.localizedDescription
            }
        } catch {
            cancelledCurrentLock = true
            unlockError = error.localizedDescription
        }
    }

    private func finishUnlockSucceeded() {
        AuthenticationTrace.emit("app unlock succeeded")
        var next = session
        next.unlockSucceeded()
        session = next
        cancelledCurrentLock = false
        unlockError = nil
        snapshotCoverTask?.cancel()
        snapshotCoverTask = nil
        // 解锁后仍只按窗揭罩：离屏窗保持快照。
        syncSnapshotCoverImmediately()
    }

    /// `willResignActive` on desktop is ambiguous while Touch ID / the system
    /// password panel is visible, so lifecycle handling defers the decision. The
    /// successful authentication result still must not cross a real app switch:
    /// settle that deferred boundary synchronously before unlock, policy writes,
    /// or credential deletion can commit.
    private func requireForegroundForAuthenticationCommit() throws {
        // Older unit harnesses that intentionally omit a session box model no
        // lifecycle authority on iOS. Production and the lifecycle regression
        // harness always provide one. Desktop retains its stricter historical
        // check even in lightweight harnesses.
        guard treatsApplicationResignAsBackground || sessionLockBox != nil else { return }
        if isHostApplicationFrontmost() {
            deferredDesktopLeaveAt = nil
            desktopLeaveReconciliationTask?.cancel()
            desktopLeaveReconciliationTask = nil
            hostFocusReconciliationTask?.cancel()
            hostFocusReconciliationTask = nil
            return
        }
        if treatsApplicationResignAsBackground {
            let leftAt = deferredDesktopLeaveAt ?? Date()
            handleDesktopApplicationDidLeave(now: leftAt)
        } else {
            shouldAutoPromptOnBecomeActive = false
            revokeNonUserFacingAuthorizations()
            syncSnapshotCoverImmediately()
        }
        throw ApiRelayError.authenticationCancelled
    }

    private func syncSnapshotCoverImmediately() {
        snapshotCoverTask?.cancel()
        snapshotCoverTask = nil
        windowPrivacy = currentWindowPrivacy()
        applySnapshotCovers(coveredIDs: windowPrivacy.coveredIDs, removesUncovered: true)
    }

    /// 真正回到前台后再摘遮罩；若在延迟内又 inactive，则保持遮罩（切换器截屏窗口）。
    /// 离屏窗立刻盖上；操作窗延迟揭开，避免切换器那一帧拍到明文。
    private func scheduleSnapshotCoverSyncAfterActivation() {
        snapshotCoverTask?.cancel()
        windowPrivacy = currentWindowPrivacy()
        applySnapshotCovers(coveredIDs: windowPrivacy.coveredIDs, removesUncovered: false)
        snapshotCoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            syncSnapshotCoverImmediately()
        }
    }

    private func currentWindowPrivacy() -> WindowPrivacyReduction {
        let snapshot = windowsSnapshot()
        let effectiveSnapshot: [WindowPrivacyInput]
        if (treatsApplicationResignAsBackground && applicationIsInactiveForPrivacy)
            || mobileLifecyclePrivacyOverride {
            effectiveSnapshot = snapshot.isEmpty
                ? [WindowPrivacyInput(id: WindowPrivacyInput.syntheticProcessID, presence: .offScreen)]
                : snapshot.map { WindowPrivacyInput(id: $0.id, presence: .offScreen) }
        } else {
            effectiveSnapshot = snapshot
        }
        return WindowPrivacyReducer.reduce(
            windows: effectiveSnapshot,
            hideInAppSwitcher: session.preferences.hideInAppSwitcher,
            isSessionLocked: session.isSessionLocked,
            hasBecomeActiveOnce: session.hasBecomeActiveOnce
        )
    }

    private func applySnapshotCovers(coveredIDs: Set<String>, removesUncovered: Bool) {
        #if canImport(UIKit)
        guard installsSnapshotCover else { return }
        guard !AppRuntime.isRunningTests else { return }
        AppSwitcherSnapshotCover.sync(
            coveredIDs: coveredIDs,
            showsLockMark: session.isSessionLocked,
            removesUncovered: removesUncovered
        )
        #elseif canImport(AppKit)
        guard installsSnapshotCover else { return }
        guard !AppRuntime.isRunningTests else { return }
        AppSwitcherSnapshotCover.sync(
            coveredIDs: coveredIDs,
            showsLockMark: session.isSessionLocked,
            removesUncovered: removesUncovered
        )
        #endif
    }

    /// 桌面环境没有可靠的“真正后台”边界：切到其它 App 后窗口仍可见，但明文已经不该继续展示。
    /// 因此 resign 同时完成遮挡和后台计时；重复收到 didEnterBackground 也保持幂等。
    private func handleDesktopApplicationDidLeave(now: Date) {
        deferredDesktopLeaveAt = nil
        desktopLeaveReconciliationTask?.cancel()
        desktopLeaveReconciliationTask = nil
        guard !applicationIsInactiveForPrivacy else {
            syncSnapshotCoverImmediately()
            return
        }
        applicationIsInactiveForPrivacy = true
        sessionLockBox?.setAuthorizationSuspended(true)
        snapshotCoverTask?.cancel()
        snapshotCoverTask = nil
        var next = session
        next.noteWillResignActive(now: now)
        next.noteDidEnterBackground(now: now, uptime: ProcessInfo.processInfo.systemUptime)
        session = next
        shouldAutoPromptOnBecomeActive = false
        invalidateActiveSubmitRequests()
        cancelledCurrentLock = false
        gate.cancelAllAuthentication()
        syncSnapshotCoverImmediately()
    }

    /// `willResignActive` 本身无法区分系统认证面板与真的切换 App。认证请求在
    /// RevealGate 内会一直保持 active，直到原窗口重新可用；因此等它收口后再看
    /// 实际焦点，既不会让 Touch ID 自锁，也不会漏掉认证面板期间的 Cmd-Tab。
    private func deferDesktopLeaveUntilAuthenticationSettles(now: Date) {
        if deferredDesktopLeaveAt == nil {
            deferredDesktopLeaveAt = now
        }
        desktopLeaveReconciliationTask?.cancel()
        desktopLeaveReconciliationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.gate.isAuthenticationInProgress() {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, let leftAt = self.deferredDesktopLeaveAt else { return }
            self.desktopLeaveReconciliationTask = nil
            if self.isHostApplicationFrontmost() {
                self.deferredDesktopLeaveAt = nil
            } else {
                self.handleDesktopApplicationDidLeave(now: leftAt)
            }
        }
    }

    /// Stage Manager/key-window notifications can stop after the one emitted by
    /// the authentication sheet itself. Delay only while LA really owns the
    /// transient focus loss, then revoke if another app still owns the focus.
    private func deferHostFocusRevocationUntilAuthenticationSettles() {
        hostFocusReconciliationTask?.cancel()
        hostFocusReconciliationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.gate.isAuthenticationInProgress() {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            self.hostFocusReconciliationTask = nil
            guard !self.isHostApplicationFrontmost() else { return }
            self.revokeNonUserFacingAuthorizations()
            self.shouldAutoPromptOnBecomeActive = false
            self.syncSnapshotCoverImmediately()
        }
    }

    /// 应用级通知只订一次。`ContentView` 每扇窗一份时不得再 `onReceive` 同一组。
    /// `queue: nil`：与 UIKit 投递同步，才能在 `willResignActive` 返回前盖上切换器遮罩。
    func armLifecycleObservers() {
        guard !AppRuntime.isRunningTests else { return }
        startObservingHostFocus()
        installApplicationLifecycleObservers()
    }

    func installApplicationLifecycleObservers(on center: NotificationCenter = .default) {
        guard applicationLifecycleObservers.isEmpty else { return }
        #if canImport(UIKit)
        applicationLifecycleObservers = [
            observe(center, UIApplication.willResignActiveNotification) { $0.handleWillResignActive() },
            observe(center, UIApplication.didEnterBackgroundNotification) { $0.handleDidEnterBackground() },
            observeSceneDidEnterBackground(center),
            observe(center, UIApplication.willEnterForegroundNotification) { $0.handleWillEnterForeground() },
            observe(center, UIApplication.didBecomeActiveNotification) { $0.handleDidBecomeActive() }
        ]
        #elseif canImport(AppKit)
        applicationLifecycleObservers = [
            observe(center, NSApplication.willResignActiveNotification) { $0.handleWillResignActive() },
            observe(center, NSApplication.willBecomeActiveNotification) { $0.handleWillEnterForeground() },
            observe(center, NSApplication.didBecomeActiveNotification) { $0.handleDidBecomeActive() },
            observe(center, NSApplication.willTerminateNotification) { _ in
                ClipboardTerminationGuard.clearIfStillOursOnTerminate()
            }
        ]
        #endif
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ handler: @escaping @MainActor (AppPrivacyController) -> Void
    ) -> NSObjectProtocol {
        center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    handler(self)
                }
            } else {
                Task { @MainActor in handler(self) }
            }
        }
    }

    #if canImport(UIKit)
    /// UIKit posts scene lifecycle notifications on the main thread. Read the
    /// scene identity synchronously so the non-Sendable `Notification` never
    /// crosses an actor boundary and the confirmed background fact is not lost.
    private func observeSceneDidEnterBackground(_ center: NotificationCenter) -> NSObjectProtocol {
        center.addObserver(
            forName: UIScene.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            guard Thread.isMainThread else {
                Task { @MainActor in
                    self.handleSceneDidEnterBackground(confirmedSceneID: nil)
                }
                return
            }
            let lifecycle = MainThreadLifecycleNotification(value: notification)
            MainActor.assumeIsolated {
                let sceneID = (lifecycle.value.object as? UIScene)?.session.persistentIdentifier
                self.handleSceneDidEnterBackground(confirmedSceneID: sceneID)
            }
        }
    }
    #endif

    /// iPadOS 26 同组切主窗不走应用级 resign。听 Key 与 `activeAppearance`，才能把 Face ID 从别人头上收掉。
    private func startObservingHostFocus() {
        guard !AppRuntime.isRunningTests else { return }
        guard hostFocusCancellables.isEmpty else { return }
        #if canImport(UIKit)
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIWindow.didBecomeKeyNotification,
            UIWindow.didResignKeyNotification,
            UIScene.didActivateNotification
        ]
        for name in names {
            center.publisher(for: name)
                .sink { [weak self] _ in
                    guard let self else { return }
                    if Thread.isMainThread {
                        MainActor.assumeIsolated {
                            self.refreshHostTraitObservations()
                            self.handleHostFocusDidChange()
                        }
                    } else {
                        Task { @MainActor in
                            self.refreshHostTraitObservations()
                            self.handleHostFocusDidChange()
                        }
                    }
                }
                .store(in: &hostFocusCancellables)
        }
        refreshHostTraitObservations()
        #endif
    }

    #if canImport(UIKit)
    private func refreshHostTraitObservations() {
        hostTraitRegistrations.removeAll()
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows {
            let registration = window.registerForTraitChanges([UITraitActiveAppearance.self]) { [weak self] (_: UIWindow, _: UITraitCollection) in
                guard let self else { return }
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        // Consume the transient inactive appearance before a
                        // rapid icon tap can enqueue didBecomeActive and erase it.
                        self.handleHostFocusDidChange()
                    }
                } else {
                    Task { @MainActor in
                        self.handleHostFocusDidChange()
                    }
                }
            }
            hostTraitRegistrations.append(registration)
        }
    }
    #endif
}

#if canImport(UIKit)
/// 盖在现有窗口上，保证 `willResignActive` 返回前图层里已有遮罩。
enum AppSwitcherSnapshotCover {
    static let viewTag = 71_080_301

    static func sync(
        coveredIDs: Set<String>,
        showsLockMark: Bool = false,
        removesUncovered: Bool = true
    ) {
        let scenes = allScenes()
        let coverAll = coveredIDs.contains(WindowPrivacyInput.syntheticProcessID)
        for scene in scenes {
            let shouldShow = coverAll || coveredIDs.contains(scene.session.persistentIdentifier)
            for window in visibleWindows(in: scene) {
                apply(shouldShow: shouldShow, to: window, showsLockMark: showsLockMark, removesUncovered: removesUncovered)
            }
        }
    }

    private static func apply(
        shouldShow: Bool,
        to window: UIWindow,
        showsLockMark: Bool,
        removesUncovered: Bool
    ) {
        let existing = window.viewWithTag(viewTag) as? SnapshotCoverView
        if shouldShow {
            if let existing {
                existing.setShowsLockMark(showsLockMark)
                existing.isHidden = false
                window.bringSubviewToFront(existing)
            } else {
                let cover = SnapshotCoverView(frame: window.bounds)
                cover.setShowsLockMark(showsLockMark)
                window.addSubview(cover)
            }
            window.layoutIfNeeded()
        } else if removesUncovered {
            existing?.removeFromSuperview()
        }
    }

    private static func allScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }

    private static func visibleWindows(in scene: UIWindowScene) -> [UIWindow] {
        let visible = scene.windows.filter { !$0.isHidden }
        if !visible.isEmpty { return visible }
        return scene.windows.filter(\.isKeyWindow)
    }
}

private final class SnapshotCoverView: UIView {
    private let lockView: UIImageView = {
        let image = UIImageView(image: UIImage(systemName: AppSymbols.Settings.appLock))
        image.tintColor = .secondaryLabel
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        image.translatesAutoresizingMaskIntoConstraints = false
        image.isHidden = true
        return image
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        tag = AppSwitcherSnapshotCover.viewTag
        backgroundColor = .systemBackground
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // 只挡系统截屏，不抢触摸。否则回到前台后会盖住 SwiftUI 解锁按钮，点了没反应。
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityLabel = String(localized: "appLock.coverTitle")
        addSubview(lockView)
        NSLayoutConstraint.activate([
            lockView.centerXAnchor.constraint(equalTo: centerXAnchor),
            lockView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func setShowsLockMark(_ shows: Bool) {
        lockView.isHidden = !shows
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
/// 原生 macOS 没有 UIKit 的 scene 快照层；在每扇窗口 contentView 顶部同步放置无交互遮罩。
enum AppSwitcherSnapshotCover {
    static let viewIdentifier = NSUserInterfaceItemIdentifier("ApiRelay.AppSwitcherSnapshotCover")

    static func id(for window: NSWindow) -> String {
        "nswindow:\(window.windowNumber)"
    }

    static func sync(
        coveredIDs: Set<String>,
        showsLockMark: Bool = false,
        removesUncovered: Bool = true
    ) {
        let coverAll = coveredIDs.contains(WindowPrivacyInput.syntheticProcessID)
        for window in NSApplication.shared.windows where window.isVisible && !window.isMiniaturized {
            guard let contentView = window.contentView else { continue }
            let existing = contentView.subviews.first { $0.identifier == viewIdentifier } as? SnapshotCoverView
            let shouldShow = coverAll || coveredIDs.contains(id(for: window))
            if shouldShow {
                if let existing {
                    existing.setShowsLockMark(showsLockMark)
                    existing.isHidden = false
                    contentView.addSubview(existing, positioned: .above, relativeTo: nil)
                } else {
                    let cover = SnapshotCoverView(frame: contentView.bounds)
                    cover.setShowsLockMark(showsLockMark)
                    contentView.addSubview(cover, positioned: .above, relativeTo: nil)
                }
                contentView.layoutSubtreeIfNeeded()
            } else if removesUncovered {
                existing?.removeFromSuperview()
            }
        }
    }
}

private final class SnapshotCoverView: NSView {
    private let lockView: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(
            systemSymbolName: AppSymbols.Settings.appLock,
            accessibilityDescription: String(localized: "appLock.coverTitle")
        )
        view.imageScaling = .scaleProportionallyUpOrDown
        view.contentTintColor = .secondaryLabelColor
        view.isHidden = true
        return view
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = AppSwitcherSnapshotCover.viewIdentifier
        autoresizingMask = [.width, .height]
        wantsLayer = true
        updateBackgroundColor()
        addSubview(lockView)
    }

    override func layout() {
        super.layout()
        let side: CGFloat = 52
        lockView.frame = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func setShowsLockMark(_ shows: Bool) {
        lockView.isHidden = !shows
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
#endif
