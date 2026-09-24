import SwiftUI

private struct VaultPossibleDuplicateAlert: ViewModifier {
    @Binding var existingName: String?
    var onConfirm: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "vault.key.duplicate.title",
                isPresented: Binding(
                    get: { existingName != nil },
                    set: { if !$0 { existingName = nil } }
                )
            ) {
                Button("vault.key.duplicate.confirm") {
                    Task { await onConfirm() }
                }
                Button("gate.cancel", role: .cancel) {
                    existingName = nil
                }
            } message: {
                Text("vault.key.duplicate.body \(existingName ?? "")")
            }
    }
}

extension View {
    func vaultPossibleDuplicateAlert(
        existingName: Binding<String?>,
        onConfirm: @escaping () async -> Void
    ) -> some View {
        modifier(VaultPossibleDuplicateAlert(existingName: existingName, onConfirm: onConfirm))
    }
}
