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
    /// A durable full-erase journal exists. Normal preferences/password state
    /// may already be gone, so this mode exposes only device-owner recovery.
    var eraseRecoveryRequired: Bool = false
    /// An interrupted create/import transaction must be rolled back or rolled
    /// forward before preferences and vault data can be observed.
    var storageRecoveryRequired: Bool = false
    var usesMasterPassword: Bool
    /// 策略要主密码但本机没有：此时 MUST NOT 再摆输入框，直接把恢复出口摆到主位。
    var masterPasswordMissing: Bool
    /// 兼容底层明确报告生物不可用/锁定的旧错误源；正常组合档由同一系统流程直接回落设备密码。
    var biometryUnavailableForUnlock: Bool = false
    var securityPreferencesUnavailable: Bool = false
    var isBusy: Bool
    var errorText: String?
    var onContinueEraseRecovery: () -> Void = {}
    var onRetryStorageRecovery: () -> Void = {}
    var onEraseStorageRecovery: () -> Void = {}
    var onUnlock: () -> Void
    var onRetrySecurityPreferences: () -> Void = {}
    var onUnlockWithMasterPassword: (String) -> Void
    var onRecoverFromLostMasterPassword: () -> Void
    var onRecoverFromUnavailableBiometry: () -> Void = {}

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var masterPassword = ""
    @State private var showsRecoveryConfirm = false
    @State private var showsStorageEraseConfirm = false
    @State private var showsCombinationPasswordEntry = false
    @State private var combinationNeedsSetup = false
    @FocusState private var macPasswordFocused: Bool

    private var usesTouchKeyboard: Bool { !SettingsChrome.isMacDesktop }
    private var combinationPolicy: Bool { environment.appPrivacy.usesCombinationUnlock }
    private var showsPasswordField: Bool {
        !eraseRecoveryRequired && !storageRecoveryRequired && ((usesMasterPassword && !masterPasswordMissing)
            || (combinationPolicy && showsCombinationPasswordEntry && !combinationNeedsSetup)
        )
    }

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
        .onAppear {
            if !usesTouchKeyboard, showsUnlockChrome, showsPasswordField {
                macPasswordFocused = true
            }
            if showsUnlockChrome {
                offerCombinationPasswordIfBiometryDead()
            }
        }
        .onChange(of: showsUnlockChrome) { _, visible in
            if !visible {
                clearSensitiveInput()
                showsCombinationPasswordEntry = false
                combinationNeedsSetup = false
            } else if !usesTouchKeyboard, showsPasswordField {
                macPasswordFocused = true
            } else if visible {
                offerCombinationPasswordIfBiometryDead()
            }
        }
        .onChange(of: showsPasswordField) { _, visible in
            guard !usesTouchKeyboard, showsUnlockChrome else { return }
            macPasswordFocused = visible
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                clearSensitiveInput()
            }
        }
        .onReceive(environment.appPrivacy.$session) { session in
            if session.isSessionLocked {
                masterPassword = ""
                if !usesTouchKeyboard, showsUnlockChrome, showsPasswordField {
                    macPasswordFocused = true
                }
            }
        }
        .onDisappear {
            clearSensitiveInput()
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
                storageRecoveryEraseButton
                useAppPasswordButton
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
                    .sensitivePasswordInput()
                    .textFieldStyle(.roundedBorder)
                    .focused($macPasswordFocused)
                    .submitLabel(.go)
                    .disabled(isBusy)
                    .frame(maxWidth: 280)
                    .onSubmit(submitVisiblePassword)
            }
            errorLabel
            unlockButton
            storageRecoveryEraseButton
            useAppPasswordButton
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
        if eraseRecoveryRequired { return "appLock.eraseRecovery.title" }
        if storageRecoveryRequired { return "appLock.storageRecovery.title" }
        if securityPreferencesUnavailable { return "appLock.preferencesUnavailable.title" }
        if masterPasswordMissing { return "appLock.masterPassword.missing.title" }
        if combinationNeedsSetup && showsCombinationPasswordEntry {
            return "appLock.combination.notSet"
        }
        if showsCombinationPasswordEntry { return "vault.masterPassword.title" }
        if biometryUnavailableForUnlock { return "appLock.biometry.unavailable.title" }
        return usesMasterPassword ? "vault.masterPassword.title" : "appLock.coverTitle"
    }

    private var hintKey: LocalizedStringKey? {
        if eraseRecoveryRequired { return "appLock.eraseRecovery.hint" }
        if storageRecoveryRequired { return "appLock.storageRecovery.hint" }
        if securityPreferencesUnavailable { return "appLock.preferencesUnavailable.hint" }
        if masterPasswordMissing { return "appLock.masterPassword.missing.hint" }
        if combinationNeedsSetup && showsCombinationPasswordEntry {
            return "appLock.masterPassword.missing.hint"
        }
        if showsCombinationPasswordEntry { return "appLock.combination.hint" }
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
            if eraseRecoveryRequired {
                onContinueEraseRecovery()
            } else if storageRecoveryRequired {
                onRetryStorageRecovery()
            } else if securityPreferencesUnavailable {
                onRetrySecurityPreferences()
            } else if masterPasswordMissing {
                onRecoverFromLostMasterPassword()
            } else if biometryUnavailableForUnlock && !(combinationPolicy && showsCombinationPasswordEntry) {
                onRecoverFromUnavailableBiometry()
            } else if usesMasterPassword {
                submitMasterPassword()
            } else if combinationPolicy && showsCombinationPasswordEntry, combinationNeedsSetup {
                onRecoverFromLostMasterPassword()
            } else if combinationPolicy && showsCombinationPasswordEntry {
                submitCombinationPassword()
            } else {
                onUnlock()
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBusy)
    }

    private var unlockButtonTitle: LocalizedStringKey {
        if eraseRecoveryRequired { return "appLock.eraseRecovery.action" }
        if storageRecoveryRequired { return "appLock.storageRecovery.action" }
        if securityPreferencesUnavailable { return "appLock.preferencesUnavailable.retry" }
        if masterPasswordMissing { return "appLock.masterPassword.missing.action" }
        if biometryUnavailableForUnlock && !(combinationPolicy && showsCombinationPasswordEntry) {
            return "appLock.biometry.unavailable.action"
        }
        if combinationNeedsSetup && showsCombinationPasswordEntry {
            return "appLock.masterPassword.missing.action"
        }
        return "appLock.unlock"
    }

    /// If a corrupt or repeatedly failing marker cannot be replayed, the app
    /// must not become a permanent brick. This deliberately destructive escape
    /// remains secondary, requires an explicit confirmation here, and requires
    /// device-owner authentication again inside DataLifecycleService.
    @ViewBuilder
    private var storageRecoveryEraseButton: some View {
        if storageRecoveryRequired {
            Button("appLock.storageRecovery.erase.action", role: .destructive) {
                showsStorageEraseConfirm = true
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(isBusy)
            .confirmationDialog(
                "appLock.storageRecovery.erase.title",
                isPresented: $showsStorageEraseConfirm,
                titleVisibility: .visible
            ) {
                Button("appLock.storageRecovery.erase.confirm", role: .destructive) {
                    clearSensitiveInput()
                    onEraseStorageRecovery()
                }
                Button("gate.cancel", role: .cancel) {}
            } message: {
                Text("appLock.storageRecovery.erase.message")
            }
        }
    }

    @ViewBuilder
    private var useAppPasswordButton: some View {
        if !eraseRecoveryRequired,
           !storageRecoveryRequired,
           combinationPolicy,
           !showsCombinationPasswordEntry,
           !securityPreferencesUnavailable,
           !masterPasswordMissing {
            Button("appLock.useAppPassword") {
                Task { await enterCombinationPassword() }
            }
            .font(.body)
            .disabled(isBusy)
            .accessibilityLabel(Text("appLock.useAppPassword"))
        }
    }

    /// 忘了主密码就再也进不来，等于数据被自己锁死。这个出口 MUST 一直可达。
    /// 本机压根没有主密码时它已是主按钮，不必再重复一次。
    @ViewBuilder
    private var forgotMasterPasswordButton: some View {
        if !eraseRecoveryRequired, !storageRecoveryRequired, showsPasswordField {
            Button("appLock.masterPassword.forgot") {
                clearSensitiveInput()
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
                    clearSensitiveInput()
                    onRecoverFromLostMasterPassword()
                }
                Button("gate.cancel", role: .cancel) {
                    clearSensitiveInput()
                }
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
            onSubmit: submitVisiblePassword
        )
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        #else
        SecureField("vault.masterPassword", text: $masterPassword)
            .sensitivePasswordInput()
            .textFieldStyle(.roundedBorder)
            .submitLabel(.go)
            .disabled(isBusy)
            .onSubmit(submitVisiblePassword)
        #endif
    }

    private func submitVisiblePassword() {
        if combinationPolicy && showsCombinationPasswordEntry {
            submitCombinationPassword()
        } else {
            submitMasterPassword()
        }
    }

    private func submitMasterPassword() {
        let password = masterPassword
        clearSensitiveInput(resignFocus: false)
        onUnlockWithMasterPassword(password)
    }

    private func submitCombinationPassword() {
        if combinationNeedsSetup {
            onRecoverFromLostMasterPassword()
            return
        }
        let password = masterPassword
        clearSensitiveInput(resignFocus: false)
        Task { await environment.appPrivacy.unlockWithCombinationAppPassword(password) }
    }

    private func clearSensitiveInput(resignFocus: Bool = true) {
        masterPassword = ""
        if resignFocus {
            macPasswordFocused = false
        }
    }

    private func enterCombinationPassword() async {
        await environment.appPrivacy.beginCombinationAppPasswordEntry()
        combinationNeedsSetup = environment.appPrivacy.combinationAppPasswordMissing
        showsCombinationPasswordEntry = true
    }

    private func offerCombinationPasswordIfBiometryDead() {
        guard combinationPolicy, biometryUnavailableForUnlock else { return }
        Task { await enterCombinationPassword() }
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
        field.accessibilityLabel = placeholder
        field.borderStyle = .roundedRect
        field.returnKeyType = .go
        field.enablesReturnKeyAutomatically = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.inlinePredictionType = .no
        field.mathExpressionCompletionType = .no
        field.keyboardType = .default
        field.textContentType = .password
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
        field.accessibilityLabel = placeholder
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
