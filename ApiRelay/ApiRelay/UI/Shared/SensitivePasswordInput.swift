import SwiftUI

/// Password semantics shared by every SwiftUI credential field.
///
/// `SecureField` provides the obscured editor. This modifier additionally tells
/// the platform not to alter credential bytes and gives Password AutoFill the
/// correct existing/new-password semantic without mislabelling the value as an
/// OTP or another content type.
enum SensitivePasswordInputRole: Sendable {
    case existingCredential
    case newCredential
}

private struct SensitivePasswordInputModifier: ViewModifier {
    let role: SensitivePasswordInputRole

    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .existingCredential:
            credentialInput(content.textContentType(.password))
        case .newCredential:
            credentialInput(content.textContentType(.newPassword))
        }
    }

    @ViewBuilder
    private func credentialInput<Content: View>(_ content: Content) -> some View {
        content
            .autocorrectionDisabled(true)
            #if os(iOS) || targetEnvironment(macCatalyst)
            .textInputAutocapitalization(.never)
            #endif
    }
}

extension View {
    func sensitivePasswordInput(
        _ role: SensitivePasswordInputRole = .existingCredential
    ) -> some View {
        modifier(SensitivePasswordInputModifier(role: role))
    }
}
