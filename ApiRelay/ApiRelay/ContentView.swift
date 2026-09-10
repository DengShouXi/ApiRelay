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

    private var hidesVault: Bool {
        privacy.session.isSessionLocked
    }

    /// 解锁层跟全局锁走，但只出现在正在操作的那一扇。
    private var showsUnlockChrome: Bool {
        privacy.session.isSessionLocked && scenePhase == .active
    }

    var body: some View {
        ZStack {
            VaultRoot(environment: environment)
                .opacity(hidesVault ? 0 : 1)
                .allowsHitTesting(!hidesVault)
                .accessibilityHidden(hidesVault)
                .animation(nil, value: hidesVault)

            AppLockCoverView(
                showsUnlockChrome: showsUnlockChrome && (privacy.session.needsUnlockPrompt || privacy.securityPreferencesUnavailable),
                showsLockMark: hidesVault && scenePhase == .active,
                usesMasterPassword: privacy.usesMasterPasswordUnlock,
                masterPasswordMissing: privacy.masterPasswordMissing,
                biometryUnavailableForUnlock: privacy.biometryUnavailableForUnlock,
                securityPreferencesUnavailable: privacy.securityPreferencesUnavailable,
                isBusy: privacy.isUnlocking || privacy.isRecovering,
                errorText: privacy.unlockError,
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
            .opacity(showsUnlockChrome ? 1 : 0)
            .allowsHitTesting(showsUnlockChrome)
            .accessibilityHidden(!showsUnlockChrome)
            .animation(nil, value: showsUnlockChrome)
        }
        .task {
            await privacy.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDataDidErase)) { _ in
            Task { await privacy.reloadAfterErase() }
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
