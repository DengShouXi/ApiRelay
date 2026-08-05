import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VaultRoot(environment: environment)
            .preferredColorScheme(environment.appearance.preferredColorScheme)
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
        .environmentObject(AppEnvironment.bootstrap())
}
