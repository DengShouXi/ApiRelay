import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// 会话锁与切换器遮罩的不透明盖层。禁止对底下列表做半透明模糊（名称会漏）。
///
/// 触屏（iPhone / iPad）与 Mac 不是同一套输入：触屏必须弹出软件键盘，表单靠上，把下半屏留给键盘。
/// SwiftUI `FocusState` 强行聚焦在 iOS 上常常只出光标、不出键盘，触屏主密码框改走 UIKit `becomeFirstResponder`。
struct AppLockCoverView: View {
    var showsUnlockChrome: Bool
    /// 未就绪 / 多任务遮罩只铺底色。锁图标只在真的 App 锁开着时出现。
    var showsLockMark: Bool = false
    var usesMasterPassword: Bool
    /// 策略要主密码但本机没有：此时 MUST NOT 再摆输入框，直接把恢复出口摆到主位。
    var masterPasswordMissing: Bool
    /// 策略是「仅生物识别」但本机没有可用生物识别：同样把恢复出口摆到主位。
    var biometryUnavailableForUnlock: Bool = false
    var securityPreferencesUnavailable: Bool = false
    var isBusy: Bool
    var errorText: String?
    var onUnlock: () -> Void
    var onRetrySecurityPreferences: () -> Void = {}
    var onUnlockWithMasterPassword: (String) -> Void
    var onRecoverFromLostMasterPassword: () -> Void
    var onRecoverFromUnavailableBiometry: () -> Void = {}

    @State private var masterPassword = ""
    @State private var showsRecoveryConfirm = false
    @FocusState private var macPasswordFocused: Bool

    private var usesTouchKeyboard: Bool { !SettingsChrome.isMacDesktop }
    private var showsPasswordField: Bool { usesMasterPassword && !masterPasswordMissing }

    var body: some View {
        ZStack {
            coverBackground.ignoresSafeArea(.container)
            if showsUnlockChrome {
                if usesTouchKeyboard {
                    touchKeyboardForm
                } else {
                    physicalKeyboardForm
                }
            } else if showsLockMark {
                lockMark
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onChange(of: showsUnlockChrome) { _, visible in
            if !visible {
                masterPassword = ""
                macPasswordFocused = false
            } else if !usesTouchKeyboard, showsPasswordField {
                macPasswordFocused = true
            }
        }
    }

    private var lockMark: some View {
        Image(systemName: AppSymbols.Settings.appLock)
            .font(.system(size: 44, weight: .medium))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    /// iPhone / iPad：顶对齐，键盘从底部顶上来时字段仍在可见区。
    private var touchKeyboardForm: some View {
        ScrollView {
            VStack(spacing: 16) {
                lockMark
                titleAndHint
                if showsPasswordField {
                    touchPasswordField
                }
                errorLabel
                unlockButton
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                forgotMasterPasswordButton
            }
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Mac：物理键盘，表单居中即可。
    private var physicalKeyboardForm: some View {
        VStack(spacing: 16) {
            lockMark
            titleAndHint
            if showsPasswordField {
                SecureField("vault.masterPassword", text: $masterPassword)
                    .textFieldStyle(.roundedBorder)
                    .focused($macPasswordFocused)
                    .submitLabel(.go)
                    .disabled(isBusy)
                    .frame(maxWidth: 280)
                    .onSubmit(submitMasterPassword)
            }
            errorLabel
            unlockButton
            forgotMasterPasswordButton
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var titleAndHint: some View {
        Text(titleKey)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
        if let hintKey {
            Text(hintKey)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var titleKey: LocalizedStringKey {
        if securityPreferencesUnavailable { return "appLock.preferencesUnavailable.title" }
        if masterPasswordMissing { return "appLock.masterPassword.missing.title" }
        if biometryUnavailableForUnlock { return "appLock.biometry.unavailable.title" }
        return usesMasterPassword ? "vault.masterPassword.title" : "appLock.coverTitle"
    }

    private var hintKey: LocalizedStringKey? {
        if securityPreferencesUnavailable { return "appLock.preferencesUnavailable.hint" }
        if masterPasswordMissing { return "appLock.masterPassword.missing.hint" }
        if biometryUnavailableForUnlock { return "appLock.biometry.unavailable.hint" }
        return usesMasterPassword ? "appLock.masterPassword.hint" : nil
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let errorText, !errorText.isEmpty {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var unlockButton: some View {
        Button(unlockButtonTitle) {
            if securityPreferencesUnavailable {
                onRetrySecurityPreferences()
            } else if masterPasswordMissing {
                onRecoverFromLostMasterPassword()
            } else if biometryUnavailableForUnlock {
                onRecoverFromUnavailableBiometry()
            } else if usesMasterPassword {
                submitMasterPassword()
            } else {
                onUnlock()
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBusy)
    }

    private var unlockButtonTitle: LocalizedStringKey {
        if securityPreferencesUnavailable { return "appLock.preferencesUnavailable.retry" }
        if masterPasswordMissing { return "appLock.masterPassword.missing.action" }
        if biometryUnavailableForUnlock { return "appLock.biometry.unavailable.action" }
        return "appLock.unlock"
    }

    /// 忘了主密码就再也进不来，等于数据被自己锁死。这个出口 MUST 一直可达。
    /// 本机压根没有主密码时它已是主按钮，不必再重复一次。
    @ViewBuilder
    private var forgotMasterPasswordButton: some View {
        if showsPasswordField {
            Button("appLock.masterPassword.forgot") {
                showsRecoveryConfirm = true
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(isBusy)
            .confirmationDialog(
                "appLock.masterPassword.forgot.title",
                isPresented: $showsRecoveryConfirm,
                titleVisibility: .visible
            ) {
                Button("appLock.masterPassword.forgot.confirm") {
                    onRecoverFromLostMasterPassword()
                }
                Button("gate.cancel", role: .cancel) {}
            } message: {
                Text("appLock.masterPassword.forgot.message")
            }
        }
    }

    @ViewBuilder
    private var touchPasswordField: some View {
        #if canImport(UIKit)
        AppLockTouchPasswordField(
            text: $masterPassword,
            placeholder: String(localized: "vault.masterPassword"),
            isEnabled: !isBusy,
            activateKeyboard: showsUnlockChrome && showsPasswordField,
            onSubmit: submitMasterPassword
        )
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        #else
        SecureField("vault.masterPassword", text: $masterPassword)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.go)
            .disabled(isBusy)
            .onSubmit(submitMasterPassword)
        #endif
    }

    private func submitMasterPassword() {
        onUnlockWithMasterPassword(masterPassword)
    }

    private var coverBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.black
        #endif
    }
}

#if canImport(UIKit)
/// 触屏主密码输入：进窗口后 `becomeFirstResponder`，才会真正弹出软件键盘。
private struct AppLockTouchPasswordField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool
    var activateKeyboard: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = WindowAwareTextField()
        field.isSecureTextEntry = true
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.returnKeyType = .go
        field.enablesReturnKeyAutomatically = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.keyboardType = .asciiCapable
        field.textContentType = nil
        field.clearButtonMode = .whileEditing
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.onAttachedToWindow = { [weak field] in
            guard let field else { return }
            context.coordinator.claimKeyboardIfNeeded(field)
        }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.wantsKeyboard = activateKeyboard && isEnabled
        field.isEnabled = isEnabled
        field.placeholder = placeholder
        if field.text != text {
            field.text = text
        }
        context.coordinator.claimKeyboardIfNeeded(field)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var wantsKeyboard = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        @objc func editingChanged(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            return false
        }

        func claimKeyboardIfNeeded(_ field: UITextField) {
            if wantsKeyboard {
                guard field.window != nil else { return }
                guard !field.isFirstResponder else { return }
                DispatchQueue.main.async { [weak field] in
                    guard let field, self.wantsKeyboard else { return }
                    _ = field.becomeFirstResponder()
                }
            } else if field.isFirstResponder {
                field.resignFirstResponder()
            }
        }
    }
}

private final class WindowAwareTextField: UITextField {
    var onAttachedToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onAttachedToWindow?()
        }
    }
}
#endif
