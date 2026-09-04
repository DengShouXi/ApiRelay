import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// 把 `AppLockSession` 接到生命周期、门闩与切换器快照。
/// UIKit 遮罩在 `willResignActive` 里同步盖上，避免 SwiftUI 还没提交就被系统拍照。
@MainActor
final class AppPrivacyController: ObservableObject {
    @Published private(set) var session: AppLockSession = .unready()
    @Published private(set) var isUnlocking = false
    @Published private(set) var unlockError: String?
    /// 走「忘记主密码」出口的过程中。
    @Published private(set) var isRecovering = false
    /// 策略要主密码、本机却没有存主密码。此时口令框永远验不过，只能走恢复出口。
    @Published private(set) var masterPasswordMissing = false

    /// 主密码档只出应用口令框，MUST NOT 再弹系统「iPhone 密码」。
    var usesMasterPasswordUnlock: Bool {
        session.preferences.revealPolicy == .masterPassword
    }

    private let gate: any RevealGateServing
    private let preferences: any PreferencesServing
    private let masterPassword: any MasterPasswordServing
    private let installsSnapshotCover: Bool
    private let enablesUnlockPrompt: Bool
    private var didStart = false
    private var cancelledCurrentLock = false

    init(
        gate: any RevealGateServing,
        preferences: any PreferencesServing,
        masterPassword: any MasterPasswordServing,
        installsSnapshotCover: Bool = true,
        enablesUnlockPrompt: Bool = true
    ) {
        self.gate = gate
        self.preferences = preferences
        self.masterPassword = masterPassword
        self.installsSnapshotCover = installsSnapshotCover
        self.enablesUnlockPrompt = enablesUnlockPrompt
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        let prefs = await loadPreferencesOrDefaults()
        var next = session
        next.completeColdStart(with: prefs)
        session = next
        await refreshMasterPasswordAvailability()
        syncSnapshotCover()
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

    func applyLivePreferences(_ prefs: AppLockPreferences) {
        guard session.isPreferencesReady else { return }
        var next = session
        next.applyLivePreferences(prefs)
        session = next
        if !prefs.appLockEnabled {
            unlockError = nil
            cancelledCurrentLock = false
        }
        if prefs.revealPolicy != .masterPassword {
            masterPasswordMissing = false
        }
        syncSnapshotCover()
    }

    func reloadAfterErase() async {
        applyLivePreferences(await loadPreferencesOrDefaults())
    }

    func handleWillResignActive() {
        cancelledCurrentLock = false
        var next = session
        next.noteWillResignActive(now: Date())
        session = next
        syncSnapshotCover()
    }

    func handleWillEnterForeground() {
        var next = session
        next.noteWillEnterForeground(now: Date())
        session = next
        syncSnapshotCover()
    }

    func handleDidBecomeActive() {
        var next = session
        next.noteWillEnterForeground(now: Date())
        next.noteDidBecomeActive()
        session = next
        syncSnapshotCover()
        promptUnlockIfNeeded()
        // 主密码可能在别处（设置页、另一台设备）被清掉，回前台时重查一次。
        Task { await refreshMasterPasswordAvailability() }
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
            try await gate.confirmMandatory(reason: String(localized: "gate.resetMasterPassword"))
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

    /// 「本机没有主密码」是死局、要走恢复；「密码输错」重试即可。
    /// 两者 MUST NOT 共用一句提示——用户无从判断该重试还是该找出口。
    private func isMasterPasswordNotSet(_ error: Error) -> Bool {
        guard case let ApiRelayError.validationFailed(_, reason) = error else { return false }
        return reason == "master_password_not_set"
    }

    private func loadPreferencesOrDefaults() async -> AppLockPreferences {
        guard let dto = try? await preferences.load() else {
            return .defaults
        }
        return AppLockPreferences(dto)
    }

    private func promptUnlockIfNeeded(force: Bool = false) {
        guard enablesUnlockPrompt else { return }
        guard !AppRuntime.isRunningTests else { return }
        guard session.needsUnlockPrompt else { return }
        guard !usesMasterPasswordUnlock else { return }
        guard force || !cancelledCurrentLock else { return }
        guard !isUnlocking else { return }
        Task { await promptUnlock() }
    }

    private func promptUnlock() async {
        guard session.needsUnlockPrompt, !isUnlocking else { return }
        if usesMasterPasswordUnlock { return }
        isUnlocking = true
        unlockError = nil
        defer { isUnlocking = false }
        do {
            switch session.preferences.revealPolicy {
            case .masterPassword:
                return
            case .noVerification:
                // App 锁开着但验证方式为「不验证」时，仍须有一次身份确认，否则开关空转。
                try await gate.confirmMandatory(reason: String(localized: "gate.unlockApp"))
            case .biometricOrPasscode, .biometricOnly:
                try await gate.confirm(
                    reason: String(localized: "gate.unlockApp"),
                    policy: session.preferences.revealPolicy
                )
            }
            finishUnlockSucceeded()
        } catch let error as ApiRelayError {
            if case .authenticationCancelled = error {
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
        syncSnapshotCover()
    }

    private func syncSnapshotCover() {
        #if canImport(UIKit)
        guard installsSnapshotCover else { return }
        guard !AppRuntime.isRunningTests else { return }
        AppSwitcherSnapshotCover.sync(shouldShow: session.showsSnapshotCover)
        #endif
    }
}

#if canImport(UIKit)
/// 盖在现有窗口上，保证 `willResignActive` 返回前图层里已有遮罩。
enum AppSwitcherSnapshotCover {
    static let viewTag = 71_080_301

    static func sync(shouldShow: Bool) {
        for window in allWindows() {
            let existing = window.viewWithTag(viewTag)
            if shouldShow {
                if let existing {
                    existing.isHidden = false
                    window.bringSubviewToFront(existing)
                } else {
                    let cover = SnapshotCoverView(frame: window.bounds)
                    window.addSubview(cover)
                }
                window.layoutIfNeeded()
            } else {
                existing?.removeFromSuperview()
            }
        }
    }

    private static func allWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden }
    }
}

private final class SnapshotCoverView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tag = AppSwitcherSnapshotCover.viewTag
        backgroundColor = .systemBackground
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isUserInteractionEnabled = true
        accessibilityViewIsModal = true
        accessibilityLabel = String(localized: "appLock.coverTitle")

        let image = UIImageView(image: UIImage(systemName: AppSymbols.Settings.appLock))
        image.tintColor = .secondaryLabel
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
#endif
