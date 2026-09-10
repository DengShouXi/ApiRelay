import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// 把 `AppLockSession` 接到生命周期、门闩与切换器快照。
///
/// 没开 App 锁：冷启动直接进内容，软件不画锁。
/// 开了 App 锁：冷启动与离开再进都走软件锁。
/// 多任务遮罩只盖在 UIKit 窗口上、不画锁，避免被当成解锁页。
///
/// 「离开」只认整个 ApiRelay 离开当前空间。台前同一组里点别的软件
/// （Mac 的 Xcode / Cursor，iPadOS 26 的 Safari / 备忘录）：窗还在屏上，那不是离开——
/// 不得上锁、不得盖白屏、不得弹系统验证。本 App 的 sheet / 另一扇窗同样不是离开。
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
    /// 策略是「仅生物识别」，本机却没有可用生物识别。反复点解锁永远过不去，只能走恢复出口。
    @Published private(set) var biometryUnavailableForUnlock = false
    /// 安全偏好读失败：保持已知锁态，不得落到默认关锁。
    @Published private(set) var securityPreferencesUnavailable = false

    /// 主密码档只出应用口令框，MUST NOT 再弹系统「iPhone 密码」。
    var usesMasterPasswordUnlock: Bool {
        session.preferences.revealPolicy == .masterPassword
    }

    private let gate: any RevealGateServing
    private let preferences: any PreferencesServing
    private let masterPassword: any MasterPasswordServing
    private let installsSnapshotCover: Bool
    private let enablesUnlockPrompt: Bool
    /// Mac 上不得从生命周期自动弹出触控 ID：台前同一组里的其它软件也会收到 foreground。
    private let autoPromptsSystemAuth: Bool
    private let scenePresence: @MainActor () -> AppLockScenePresence
    private let windowsSnapshot: @MainActor () -> [WindowPrivacyInput]
    private let sessionLockBox: SessionLockBox?
    private var didStart = false
    private var cancelledCurrentLock = false
    private var snapshotCoverTask: Task<Void, Never>?
    /// 只有经历过 `willEnterForeground` 且当前人正在用我们，才自动弹系统验证。
    private var shouldAutoPromptOnBecomeActive = false
    private var hostFocusCancellables: Set<AnyCancellable> = []
    private var applicationLifecycleObservers: [NSObjectProtocol] = []
    /// 最近一次按窗汇总。测试读 `coveredIDs` / `unlockChromeIDs`。
    private(set) var windowPrivacy = WindowPrivacyReduction(
        processPresence: .offScreen,
        startIdleTimer: true,
        surfaces: [:]
    )
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
        scenePresence: @escaping @MainActor () -> AppLockScenePresence = AppPrivacyController.liveScenePresence,
        windowsSnapshot: (@MainActor () -> [WindowPrivacyInput])? = nil,
        sessionLockBox: SessionLockBox? = nil
    ) {
        self.gate = gate
        self.preferences = preferences
        self.masterPassword = masterPassword
        self.installsSnapshotCover = installsSnapshotCover
        self.enablesUnlockPrompt = enablesUnlockPrompt
        self.autoPromptsSystemAuth = autoPromptsSystemAuth
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
        } else {
            // 关着或从未写过：按产品默认没开锁进界面。等 CloudKit 再挡会画出假锁。
            launch.completeColdStart(with: .defaults)
        }
        self.session = launch
        sessionLockBox?.setLocked(launch.isSessionLocked)
    }

    /// Mac（含 Catalyst）：切到台前同一组的其它软件也会 foreground，不得自动弹系统验证。
    /// 用户点本窗「解锁」仍走 `requestUnlock`。
    nonisolated static var defaultAutoPromptsSystemAuth: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        !ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    static func liveScenePresence() -> AppLockScenePresence {
        WindowPrivacyReducer.processPresence(of: liveWindowsSnapshot())
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
        #else
        return [WindowPrivacyInput(id: WindowPrivacyInput.syntheticProcessID, presence: .userFacing)]
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
            authenticationInProgress: authenticationInProgress
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
        startObservingHostFocus()
        if !AppRuntime.isRunningTests {
            installApplicationLifecycleObservers()
        }
        await reloadSecurityPreferences(isStart: true)
        await refreshMasterPasswordAvailability()
        refreshBiometryAvailability()
        syncSnapshotCoverImmediately()
        promptUnlockIfNeeded()
    }

    func retrySecurityPreferences() async {
        await reloadSecurityPreferences(isStart: false)
        await refreshMasterPasswordAvailability()
        refreshBiometryAvailability()
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
        // 读 Keychain 失败时按「有」处理。MUST NOT 因为一次读不到就把门打开。
        guard let isSet = try? await masterPassword.isSet() else { return }
        masterPasswordMissing = !isSet
    }

    /// 「仅生物识别」但本机没有 Face ID / Touch ID：与缺主密码同属死局。
    /// 设置页已禁止新选这档，但 iCloud 同步或先前登记过的偏好仍可能带着它。
    private func refreshBiometryAvailability() {
        guard session.preferences.revealPolicy == .biometricOnly else {
            biometryUnavailableForUnlock = false
            return
        }
        biometryUnavailableForUnlock = gate.availableBiometry() == .none
    }

    func applyLivePreferences(_ prefs: AppLockPreferences) {
        guard session.isPreferencesReady else { return }
        var next = session
        next.applyLivePreferences(prefs)
        session = next
        AppLockLaunchCache.write(prefs.appLockEnabled)
        if !prefs.appLockEnabled {
            unlockError = nil
            cancelledCurrentLock = false
        }
        if prefs.revealPolicy != .masterPassword {
            masterPasswordMissing = false
        }
        refreshBiometryAvailability()
        syncSnapshotCoverImmediately()
    }

    /// `start()` 读到真实偏好之后：未就绪则按冷启动上锁；已经按「没开锁」进过界面则不得再 `completeColdStart`（会把刚解开的锁重新锁上）。
    private func applyStartPreferences(_ prefs: AppLockPreferences) {
        if session.isPreferencesReady {
            if prefs.appLockEnabled && !session.hasBecomeActiveOnce {
                var next = session
                next.completeColdStart(with: prefs)
                session = next
                AppLockLaunchCache.write(prefs.appLockEnabled)
            } else {
                applyLivePreferences(prefs)
            }
            return
        }
        var next = session
        next.completeColdStart(with: prefs)
        session = next
        AppLockLaunchCache.write(prefs.appLockEnabled)
    }

    func reloadAfterErase() async {
        await reloadSecurityPreferences(isStart: false)
    }

    func handleWillResignActive(now: Date = Date()) {
        switch scenePresence() {
        case .userFacing:
            // 控制中心 / Face ID 抢前台：本窗仍在操作。不得当离开去 cancel。
            // 其它已离屏的窗仍按汇总盖快照。
            syncSnapshotCoverImmediately()
            return
        case .onScreenIdle:
            cancelAuthenticationIfUserMovedToAnotherApp()
            flashSwitcherCoverThenReleaseIdle(now: now)
            return
        case .offScreen:
            break
        }
        snapshotCoverTask?.cancel()
        snapshotCoverTask = nil
        var next = session
        next.noteWillResignActive(now: now)
        session = next
        if !isUnlocking && !isRecovering {
            cancelledCurrentLock = false
            gate.cancelCurrentAuthentication()
        }
        syncSnapshotCoverImmediately()
    }

    /// 应用已进后台。控制中心不会走到这里。
    /// Catalyst 在台前同一组点别的软件时也会发 background——窗还在则忽略。
    func handleDidEnterBackground(now: Date = Date()) {
        guard scenePresence() == .offScreen else {
            shouldAutoPromptOnBecomeActive = false
            cancelAuthenticationIfUserMovedToAnotherApp()
            syncSnapshotCoverImmediately()
            return
        }
        var next = session
        next.noteDidEnterBackground(now: now, uptime: ProcessInfo.processInfo.systemUptime)
        session = next
        shouldAutoPromptOnBecomeActive = false
        gate.cancelCurrentAuthentication()
        syncSnapshotCoverImmediately()
    }

    func handleWillEnterForeground(now: Date = Date()) {
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
        switch scenePresence() {
        case .userFacing:
            return
        case .onScreenIdle, .offScreen:
            shouldAutoPromptOnBecomeActive = false
            cancelAuthenticationIfUserMovedToAnotherApp()
            syncSnapshotCoverImmediately()
        }
    }

    func handleDidBecomeActive(now: Date = Date()) {
        var next = session
        next.noteWillEnterForeground(now: now, uptime: ProcessInfo.processInfo.systemUptime)
        next.noteDidBecomeActive(now: now)
        session = next
        if session.isSessionLocked {
            // 路径 2：已锁 — 只揭当前操作窗的截屏遮罩，把点击交给 SwiftUI 解锁层。
            // MUST NOT 一次摘掉其它显示器上的罩。
            snapshotCoverTask?.cancel()
            snapshotCoverTask = nil
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
        Task {
            await refreshMasterPasswordAvailability()
            refreshBiometryAvailability()
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
                password: trimmed
            )
            finishUnlockSucceeded()
        } catch {
            cancelledCurrentLock = true
            if isMasterPasswordNotSet(error) {
                masterPasswordMissing = true
                unlockError = String(localized: "appLock.masterPassword.notSet")
            } else {
                unlockError = String(localized: "appLock.masterPassword.incorrect")
            }
        }
    }

    /// 忘记主密码的唯一出口。门槛是设备主人验证（Face ID / 本机密码），与设置页
    /// 「重置主密码」同一道门，MUST NOT 更低——否则 App 锁形同虚设。
    ///
    /// 主密码只是门闩、不是加密密钥，清掉它不会让任何已存明文变得读不出来。
    /// 验证方式落到 `.biometricOrPasscode`：用户刚刚已经过了这道验证，必定可用；
    /// MUST NOT 落到 `.noVerification`，那会顺手把「取出明文」的门闩也一并废掉。
    func recoverFromLostMasterPassword() async {
        guard !isRecovering, !isUnlocking else { return }
        isRecovering = true
        unlockError = nil
        defer { isRecovering = false }

        do {
            try await gate.confirmMandatory(
                reason: String(localized: "gate.resetMasterPassword"),
                purpose: .recovery
            )
        } catch ApiRelayError.authenticationCancelled {
            unlockError = nil
            return
        } catch {
            unlockError = error.localizedDescription
            return
        }

        try? await masterPassword.reset()

        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        preferences.persist(patch)

        var next = session.preferences
        next.revealPolicy = .biometricOrPasscode
        applyLivePreferences(next)

        finishUnlockSucceeded()
    }

    /// 「仅生物识别」不可用时的唯一出口。门槛与忘记主密码相同：设备主人验证。
    /// 验证方式落到 `.biometricOrPasscode`（可用本机密码），MUST NOT 落到 `.noVerification`。
    func recoverFromUnavailableBiometry() async {
        guard !isRecovering, !isUnlocking else { return }
        isRecovering = true
        unlockError = nil
        defer { isRecovering = false }

        do {
            try await gate.confirmMandatory(
                reason: String(localized: "gate.resetMasterPassword"),
                purpose: .recovery
            )
        } catch ApiRelayError.authenticationCancelled {
            unlockError = nil
            return
        } catch {
            unlockError = error.localizedDescription
            return
        }

        var patch = PreferencesPatch()
        patch.revealPolicy = .biometricOrPasscode
        preferences.persist(patch)

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

    private func reloadSecurityPreferences(isStart: Bool) async {
        do {
            let prefs = AppLockPreferences(try await preferences.load())
            securityPreferencesUnavailable = false
            if isStart {
                applyStartPreferences(prefs)
            } else {
                applyLivePreferences(prefs)
            }
        } catch {
            securityPreferencesUnavailable = true
            if AppLockLaunchCache.read() == true {
                var next = session
                next.applyCachedLockEnabled()
                session = next
            }
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
        gate.cancelCurrentAuthentication()
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
        // Mac / 台前同一组：生命周期不得自己弹出系统框。点本窗「解锁」带 force。
        if !force {
            guard shouldAutomaticallyPromptUnlock() else { return }
        }
        Task { await promptUnlock(force: force) }
    }

    private func promptUnlock(force: Bool = false) async {
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
                // App 锁开着但验证方式为「不验证」时，仍须有一次身份确认，否则开关空转。
                try await gate.confirmMandatory(
                    reason: String(localized: "gate.unlockApp"),
                    purpose: .unlockApp
                )
            case .biometricOrPasscode:
                try await gate.confirm(
                    reason: String(localized: "gate.unlockApp"),
                    policy: .biometricOrPasscode,
                    purpose: .unlockApp
                )
            case .biometricOnly:
                // 预先识别死局，避免用户反复点解锁、每次都收到同一句「生物识别不可用」。
                if gate.availableBiometry() == .none {
                    biometryUnavailableForUnlock = true
                    cancelledCurrentLock = true
                    unlockError = nil
                    return
                }
                try await gate.confirm(
                    reason: String(localized: "gate.unlockApp"),
                    policy: .biometricOnly,
                    purpose: .unlockApp
                )
            }
            finishUnlockSucceeded()
        } catch let error as ApiRelayError {
            if case .authenticationCancelled = error {
                cancelledCurrentLock = true
                unlockError = nil
            } else if case .biometryUnavailable = error {
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
        WindowPrivacyReducer.reduce(
            windows: windowsSnapshot(),
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
        #endif
    }

    /// 应用级通知只订一次。`ContentView` 每扇窗一份时不得再 `onReceive` 同一组。
    /// `queue: nil`：与 UIKit 投递同步，才能在 `willResignActive` 返回前盖上切换器遮罩。
    func installApplicationLifecycleObservers(on center: NotificationCenter = .default) {
        guard applicationLifecycleObservers.isEmpty else { return }
        #if canImport(UIKit)
        applicationLifecycleObservers = [
            observe(center, UIApplication.willResignActiveNotification) { $0.handleWillResignActive() },
            observe(center, UIApplication.didEnterBackgroundNotification) { $0.handleDidEnterBackground() },
            observe(center, UIApplication.willEnterForegroundNotification) { $0.handleWillEnterForeground() },
            observe(center, UIApplication.didBecomeActiveNotification) { $0.handleDidBecomeActive() }
        ]
        #endif
    }

    #if canImport(UIKit)
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
                    Task { @MainActor in
                        self?.refreshHostTraitObservations()
                        self?.handleHostFocusDidChange()
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
                Task { @MainActor in
                    self?.handleHostFocusDidChange()
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
