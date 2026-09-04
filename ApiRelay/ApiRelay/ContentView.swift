import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        PrivacyGatedVault(privacy: environment.appPrivacy)
            .preferredColorScheme(environment.appearance.preferredColorScheme)
    }
}

private struct PrivacyGatedVault: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var privacy: AppPrivacyController
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            VaultRoot(environment: environment)
                .opacity(privacy.session.blocksContent ? 0 : 1)
                .allowsHitTesting(!privacy.session.blocksContent)
                .accessibilityHidden(privacy.session.blocksContent)
                .animation(nil, value: privacy.session.blocksContent)

            AppLockCoverView(
                showsUnlockChrome: privacy.session.needsUnlockPrompt,
                usesMasterPassword: privacy.usesMasterPasswordUnlock,
                masterPasswordMissing: privacy.masterPasswordMissing,
                isBusy: privacy.isUnlocking || privacy.isRecovering,
                errorText: privacy.unlockError,
                onUnlock: { privacy.requestUnlock() },
                onUnlockWithMasterPassword: { password in
                    Task { await privacy.unlockWithMasterPassword(password) }
                },
                onRecoverFromLostMasterPassword: {
                    Task { await privacy.recoverFromLostMasterPassword() }
                }
            )
            .opacity(privacy.session.blocksContent ? 1 : 0)
            .allowsHitTesting(privacy.session.blocksContent)
            .accessibilityHidden(!privacy.session.blocksContent)
            .animation(nil, value: privacy.session.blocksContent)
        }
        .task {
            await privacy.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                privacy.handleDidBecomeActive()
            case .inactive, .background:
                privacy.handleWillResignActive()
            @unknown default:
                privacy.handleWillResignActive()
            }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            privacy.handleWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            privacy.handleWillEnterForeground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            privacy.handleDidBecomeActive()
        }
        #endif
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

#Preview {
    ContentView()
        .environmentObject(AppEnvironment.makePreview())
}
