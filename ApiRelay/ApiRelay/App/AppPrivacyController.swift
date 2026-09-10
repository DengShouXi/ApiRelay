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
/// 「离开」只认整个 ApiRelay 离开当前空间。台前调度同一组里点 Xcode / Cursor：
/// 窗还在屏上，那不是离开——不得上锁、不得盖白屏、不得弹触控 ID。
/// 本 App 的 sheet / 另一扇窗切换同样不是离开。
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
    private let sessionLockBox: SessionLockBox?
    private var didStart = false
    private var cancelledCurrentLock = false
    private var snapshotCoverTask: Task<Void, Never>?
    /// 只有经历过 `willEnterForeground` 且当前人正在用我们，才自动弹系统验证。
    private var shouldAutoPromptOnBecomeActive = false

    init(
        gate: any RevealGateServing,
        preferences: any PreferencesServing,
        masterPassword: any MasterPasswordServing,
        installsSnapshotCover: Bool = true,
        enablesUnlockPrompt: Bool = true,
        launchAppLockEnabled: Bool? = nil,
        autoPromptsSystemAuth: Bool = AppPrivacyController.defaultAutoPromptsSystemAuth,
        scenePresence: @escaping @MainActor () -> AppLockScenePresence = AppPrivacyController.liveScenePresence,
        sessionLockBox: SessionLockBox? = nil
    ) {
        self.gate = gate
        self.preferences = preferences
        self.masterPassword = masterPassword
        self.installsSnapshotCover = installsSnapshotCover
        self.enablesUnlockPrompt = enablesUnlockPrompt
        self.autoPromptsSystemAuth = autoPromptsSystemAuth
        self.scenePresence = scenePresence
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
        #if canImport(UIKit)
        let states = UIApplication.shared.connectedScenes.map(\.activationState)
        if states.contains(.foregroundActive) { return .userFacing }
        if states.contains(.foregroundInactive) { return .onScreenIdle }
        return .offScreen
        #else
        return .userFacing
        #endif
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
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
        // 台前同一组里点了 Xcode：窗还在当前空间，只是失去 Key。
        // 触控 ID 系统框也会让本 App resign。这两种都不是「离开 App」。
        if scenePresence() != .offScreen {
            cancelAuthenticationIfUserMovedToAnotherApp()
            return
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

    func handleDidBecomeActive(now: Date = Date()) {
        var next = session
        next.noteWillEnterForeground(now: now, uptime: ProcessInfo.processInfo.systemUptime)
        next.noteDidBecomeActive(now: now)
        session = next
        if session.isSessionLocked {
            // 路径 2：已锁 — 立刻拿掉 UIKit 截屏遮罩，把点击交给 SwiftUI 解锁层；
            // 系统 Face ID / 点「解锁」成功后 finishUnlockSucceeded 自动进内容。
            // MUST NOT 延迟摘罩：遮罩若还能点，会把解锁按钮挡死，表现为「解锁了进不去」。
            snapshotCoverTask?.cancel()
            snapshotCoverTask = nil
            applySnapshotCover(shouldShow: false)
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
    /// 触控 ID 框弹出时本进程仍是前台，不得当成「点走了」去取消。
    private func cancelAuthenticationIfUserMovedToAnotherApp() {
        guard !isHostApplicationFrontmost() else { return }
        cancelledCurrentLock = true
        gate.cancelCurrentAuthentication()
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
        // 强制摘掉截屏层，确保解锁后立刻进入内容（路径 2）。
        applySnapshotCover(shouldShow: false)
    }

    private func syncSnapshotCoverImmediately() {
        snapshotCoverTask?.cancel()
        snapshotCoverTask = nil
        applySnapshotCover(shouldShow: session.showsSnapshotCover)
    }

    /// 真正回到前台后再摘遮罩；若在延迟内又 inactive，则保持遮罩（切换器截屏窗口）。
    private func scheduleSnapshotCoverSyncAfterActivation() {
        if session.showsSnapshotCover {
            syncSnapshotCoverImmediately()
            return
        }
        snapshotCoverTask?.cancel()
        snapshotCoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            guard !session.isInactive else {
                applySnapshotCover(shouldShow: session.showsSnapshotCover)
                return
            }
            applySnapshotCover(shouldShow: session.showsSnapshotCover)
        }
    }

    private func applySnapshotCover(shouldShow: Bool) {
        #if canImport(UIKit)
        guard installsSnapshotCover else { return }
        guard !AppRuntime.isRunningTests else { return }
        AppSwitcherSnapshotCover.sync(
            shouldShow: shouldShow,
            showsLockMark: session.isSessionLocked
        )
        #endif
    }
}

#if canImport(UIKit)
/// 盖在现有窗口上，保证 `willResignActive` 返回前图层里已有遮罩。
enum AppSwitcherSnapshotCover {
    static let viewTag = 71_080_301

    static func sync(shouldShow: Bool, showsLockMark: Bool = false) {
        let windows = allWindows()
        for window in windows {
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
            } else {
                existing?.removeFromSuperview()
            }
        }
    }

    private static func allWindows() -> [UIWindow] {
        var windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden }
        // 切后台瞬间部分窗口可能暂时 isHidden；至少保住 keyWindow。
        if windows.isEmpty {
            windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .filter(\.isKeyWindow)
        }
        return windows
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
