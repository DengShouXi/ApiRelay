import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        PrivacyGatedVault(privacy: environment.appPrivacy)
            .preferredColorScheme(environment.appearance.preferredColorScheme)
    }
}

private struct PrivacyGatedVault: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var privacy: AppPrivacyController
    @State private var isContinuingErase = false
    @State private var eraseRecoveryError: String?
    @State private var eraseRecoveryRevision: UInt64 = 0
    @State private var hasStartedPrivacy = false

    private var eraseRecoveryRequired: Bool {
        _ = eraseRecoveryRevision
        return environment.dataLifecycle.hasPendingErase()
    }

    private var crossStoreRecoveryRequired: Bool {
        _ = eraseRecoveryRevision
        return environment.crossStoreRecoveryRequired
    }

    private var hidesVault: Bool {
        eraseRecoveryRequired
            || crossStoreRecoveryRequired
            || !privacy.session.isPreferencesReady
            || privacy.session.isSessionLocked
    }

    /// 解锁层跟全局锁走，但只出现在正在操作的那一扇。
    private var showsUnlockChrome: Bool {
        (eraseRecoveryRequired || crossStoreRecoveryRequired || privacy.session.isSessionLocked)
            && scenePhase == .active
    }

    /// Before authoritative preferences load, render the same opaque privacy
    /// surface without a lock icon or controls. This prevents a single-frame
    /// vault disclosure while avoiding a fake authentication policy.
    private var showsPrivacyBarrier: Bool {
        eraseRecoveryRequired
            || crossStoreRecoveryRequired
            || !privacy.session.isPreferencesReady
            || showsUnlockChrome
    }

    var body: some View {
        ZStack {
            VaultRoot(environment: environment)
                .opacity(hidesVault ? 0 : 1)
                .allowsHitTesting(!hidesVault)
                .accessibilityHidden(hidesVault)
                .animation(nil, value: hidesVault)

            AppLockCoverView(
                showsUnlockChrome: showsUnlockChrome && (eraseRecoveryRequired || crossStoreRecoveryRequired || privacy.session.needsUnlockPrompt || privacy.securityPreferencesUnavailable),
                showsLockMark: (eraseRecoveryRequired || crossStoreRecoveryRequired || privacy.session.isSessionLocked) && scenePhase == .active,
                eraseRecoveryRequired: eraseRecoveryRequired,
                storageRecoveryRequired: crossStoreRecoveryRequired,
                usesMasterPassword: privacy.usesMasterPasswordUnlock,
                masterPasswordMissing: privacy.masterPasswordMissing,
                biometryUnavailableForUnlock: privacy.biometryUnavailableForUnlock,
                securityPreferencesUnavailable: privacy.securityPreferencesUnavailable,
                isBusy: isContinuingErase || environment.isRecoveringCrossStore || privacy.isUnlocking || privacy.isRecovering,
                errorText: eraseRecoveryError ?? environment.crossStoreRecoveryError ?? privacy.unlockError,
                onContinueEraseRecovery: {
                    guard !isContinuingErase else { return }
                    isContinuingErase = true
                    eraseRecoveryError = nil
                    Task { @MainActor in
                        defer { isContinuingErase = false }
                        do {
                            try await environment.dataLifecycle.eraseAllUserData()
                            await privacy.reloadAfterErase()
                        } catch {
                            eraseRecoveryError = error.localizedDescription
                        }
                    }
                },
                onRetryStorageRecovery: {
                    Task { @MainActor in
                        let ready = await environment.prepareProtectedStorage()
                        guard ready, !hasStartedPrivacy else { return }
                        hasStartedPrivacy = true
                        await privacy.start()
                    }
                },
                onEraseStorageRecovery: {
                    guard !isContinuingErase else { return }
                    isContinuingErase = true
                    eraseRecoveryError = nil
                    Task { @MainActor in
                        defer { isContinuingErase = false }
                        do {
                            try await environment.dataLifecycle
                                .eraseAllUserDataForStorageRecovery()
                            await privacy.reloadAfterErase()
                        } catch {
                            eraseRecoveryError = error.localizedDescription
                        }
                    }
                },
                onUnlock: { privacy.requestUnlock() },
                onRetrySecurityPreferences: {
                    Task { await privacy.retrySecurityPreferences() }
                },
                onUnlockWithMasterPassword: { password in
                    Task { await privacy.unlockWithMasterPassword(password) }
                },
                onRecoverFromLostMasterPassword: {
                    Task { await privacy.recoverFromLostMasterPassword() }
                },
                onRecoverFromUnavailableBiometry: {
                    Task { await privacy.recoverFromUnavailableBiometry() }
                }
            )
            .opacity(showsPrivacyBarrier ? 1 : 0)
            .allowsHitTesting(showsUnlockChrome)
            .accessibilityHidden(!showsPrivacyBarrier)
            .animation(nil, value: showsPrivacyBarrier)
        }
        .task {
            guard !hasStartedPrivacy else { return }
            // 生命周期观察必须先于任何异步启动准备。否则冷启动后立刻回主屏幕时，
            // prepareProtectedStorage 尚未结束，整轮后台事件会无人接收。
            privacy.armLifecycleObservers()
            let ready = await environment.prepareProtectedStorage()
            guard ready else { return }
            hasStartedPrivacy = true
            await privacy.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDataDidErase)) { _ in
            Task { await privacy.reloadAfterErase() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .userDataEraseRecoveryStateDidChange)
        ) { _ in
            // `hasPendingErase()` is deliberately a synchronous, durable read,
            // not an ObservableObject property. Bump this view-local revision
            // whenever the coordinator crosses or leaves that boundary.
            eraseRecoveryRevision &+= 1
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .crossStoreRecoveryStateDidChange)
        ) { _ in
            eraseRecoveryRevision &+= 1
        }
    }
}

private extension AppearancePreference {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct VaultRoot: View {
    @StateObject private var viewModel: VaultHomeViewModel

    init(environment: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: VaultHomeViewModel(environment: environment))
    }

    var body: some View {
        VaultHomeView(viewModel: viewModel)
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(AppEnvironment.makePreview())
}
#endif
