import SwiftUI

enum MacSidebarChrome {
    static let trafficLightLeading: CGFloat = 78
}

private struct MacSidebarHiddenKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var macSidebarHidden: Binding<Bool>? {
        get { self[MacSidebarHiddenKey.self] }
        set { self[MacSidebarHiddenKey.self] = newValue }
    }
}

struct MacSidebarToggleButton: View {
    @Binding var isHidden: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isHidden.toggle()
            }
        } label: {
            Image(systemName: AppSymbols.Action.sidebarLeading)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isHidden ? "vault.sidebar.show" : "vault.sidebar.hide"))
        .help(isHidden ? String(localized: "vault.sidebar.show") : String(localized: "vault.sidebar.hide"))
    }
}
