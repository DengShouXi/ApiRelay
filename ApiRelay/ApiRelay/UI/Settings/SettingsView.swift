import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct SettingsView: View {
    let environment: AppEnvironment
    /// Tab 内嵌时不显示「完成」；sheet 弹出时保留。
    var showsDismissButton: Bool = true
    /// 左上角账号头像（与密钥列表页同一入口）。
    var onShowAccount: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var prefs: PreferencesDTO?
    @State private var masterPasswordIsSet = false
    @State private var confirmErase = false
    @State private var eraseStatus = ""

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("settings.title")
                #if os(iOS) || targetEnvironment(macCatalyst)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(settingsGroupedBackground, for: .navigationBar)
                #endif
                .toolbar {
                    if let onShowAccount {
                        ToolbarItem(placement: .navigation) {
                            Button(action: onShowAccount) {
                                Image(systemName: AppSymbols.Settings.account)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.title3)
                            }
                            .accessibilityLabel(Text("vault.sync.title"))
                        }
                    }
                    if showsDismissButton {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("settings.done") { dismiss() }
                        }
                    }
                }
                .task {
                    await reload()
                    await refreshMasterPasswordStatus()
                }
                .confirmationDialog("settings.eraseAll.confirm", isPresented: $confirmErase) {
                    Button("settings.eraseAll", role: .destructive) {
                        Task {
                            do {
                                try await environment.dataLifecycle.eraseAllUserData()
                                eraseStatus = String(localized: "settings.eraseAll.done")
                                await refreshMasterPasswordStatus()
                            } catch {
                                eraseStatus = error.localizedDescription
                            }
                        }
                    }
                } message: {
                    Text("settings.eraseAll.message")
                }
        }
        .background(settingsGroupedBackground.ignoresSafeArea())
    }

    /// 参考「钱迹」式分组：圆角卡片 + 彩色图标行 + 卡片间距拉开。
    @ViewBuilder
    private var settingsForm: some View {
        ScrollView {
            // 组与组：浅灰缝分开；组内各行：同一白卡片、零间距紧贴（仅细分割线）。
            VStack(alignment: .leading, spacing: 18) {
                if let prefs {
                    settingsGroup(title: "settings.section.appearance", footer: "settings.appearance.footer") {
                        settingsPickerRow(
                            icon: AppSymbols.Settings.appearance,
                            tint: .orange,
                            title: "settings.appearance",
                            detail: "settings.appearance.rowDetail",
                            selection: Binding(
                                get: { prefs.appearance },
                                set: { v in Task { await save(PreferencesPatch(appearance: v)) } }
                            )
                        ) {
                            Text("settings.appearance.system").tag(AppearancePreference.system)
                            Text("settings.appearance.light").tag(AppearancePreference.light)
                            Text("settings.appearance.dark").tag(AppearancePreference.dark)
                        }

                        settingsDivider()

                        settingsPickerRow(
                            icon: AppSymbols.Settings.defaultGrouping,
                            tint: .blue,
                            title: "settings.defaultGrouping",
                            detail: "settings.defaultGrouping.rowDetail",
                            selection: Binding(
                                get: { prefs.defaultGrouping },
                                set: { v in
                                    // 先乐观更新 UI，避免异步 save 完成前 Picker 弹回旧值。
                                    if var current = self.prefs {
                                        current.defaultGrouping = v
                                        self.prefs = current
                                    }
                                    Task { await save(PreferencesPatch(defaultGrouping: v)) }
                                }
                            )
                        ) {
                            Text("vault.grouping.platform").tag(GroupingMode.byPlatform)
                            Text("vault.grouping.consumer").tag(GroupingMode.byConsumer)
                        }
                    }

                    settingsGroup(
                        title: "settings.section.assign",
                        footer: "settings.section.assign.footer"
                    ) {
                        settingsPickerRow(
                            icon: AppSymbols.Settings.assignFilter,
                            tint: .mint,
                            title: "settings.assignPickerFilter",
                            detail: "settings.assignPickerFilter.rowDetail",
                            selection: Binding(
                                get: { prefs.assignPickerFilter },
                                set: { v in
                                    if var current = self.prefs {
                                        current.assignPickerFilter = v
                                        self.prefs = current
                                    }
                                    Task { await save(PreferencesPatch(assignPickerFilter: v)) }
                                }
                            )
                        ) {
                            Text("settings.assignPickerFilter.unassignedOnly")
                                .tag(AssignPickerFilter.unassignedOnly)
                            Text("settings.assignPickerFilter.allowShared")
                                .tag(AssignPickerFilter.allowShared)
                        }
                    }

                    settingsGroup(title: "settings.section.password", footer: "settings.section.password.footer") {
                        NavigationLink {
                            RevealPolicySettingsView(
                                environment: environment,
                                selection: Binding(
                                    get: { self.prefs?.revealPolicy ?? .biometricOrPasscode },
                                    set: { value in
                                        if var current = self.prefs {
                                            current.revealPolicy = value
                                            self.prefs = current
                                        }
                                        Task { await save(PreferencesPatch(revealPolicy: value)) }
                                    }
                                )
                            )
                        } label: {
                            settingsLeading(
                                icon: AppSymbols.Settings.revealPolicy,
                                tint: .green,
                                title: "settings.revealPolicy",
                                detail: "settings.revealPolicy.rowDetail"
                            )
                            Spacer(minLength: 8)
                            Text(revealPolicySummary(prefs.revealPolicy))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        settingsDivider()

                        NavigationLink {
                            MasterPasswordSettingsView(environment: environment) {
                                await refreshMasterPasswordStatus()
                            }
                        } label: {
                            settingsLeading(
                                icon: AppSymbols.Settings.masterPassword,
                                tint: .indigo,
                                title: "settings.masterPassword",
                                detail: "settings.masterPassword.rowDetail"
                            )
                            Spacer(minLength: 12)
                            Text(
                                masterPasswordIsSet
                                    ? String(localized: "settings.masterPassword.status.set")
                                    : String(localized: "settings.masterPassword.status.unset")
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        settingsDivider()

                        settingsToggleRow(
                            icon: AppSymbols.Settings.appLock,
                            tint: .teal,
                            title: "settings.appLock",
                            detail: "settings.appLock.rowDetail",
                            isOn: binding(\.appLockEnabled, prefs.appLockEnabled)
                        )
                    }

                    settingsGroup(title: "settings.section.lockTiming", footer: "settings.section.lockTiming.footer") {
                        settingsStepperRow(
                            icon: AppSymbols.Settings.autoLock,
                            tint: .purple,
                            title: "settings.autoLock.label",
                            detail: "settings.autoLock.rowDetail",
                            seconds: prefs.autoLockSeconds,
                            value: Binding(
                                get: { prefs.autoLockSeconds },
                                set: { v in Task { await save(PreferencesPatch(autoLockSeconds: v)) } }
                            ),
                            range: 0...600,
                            step: 30
                        )

                        settingsDivider()

                        settingsStepperRow(
                            icon: AppSymbols.Settings.clipboardClear,
                            tint: .pink,
                            title: "settings.clipboardClear.label",
                            detail: "settings.clipboardClear.rowDetail",
                            seconds: prefs.clipboardClearSeconds,
                            value: Binding(
                                get: { prefs.clipboardClearSeconds },
                                set: { v in Task { await save(PreferencesPatch(clipboardClearSeconds: v)) } }
                            ),
                            range: 30...600,
                            step: 30
                        )
                    }

                    settingsGroup(
                        title: "settings.section.clipboardPrivacy",
                        footer: "settings.section.clipboardPrivacy.footer"
                    ) {
                        settingsToggleRow(
                            icon: AppSymbols.Settings.clipboardLocalOnly,
                            tint: .cyan,
                            title: "settings.clipboardLocalOnly",
                            detail: "settings.clipboardLocalOnly.rowDetail",
                            isOn: binding(\.clipboardLocalOnly, prefs.clipboardLocalOnly)
                        )

                        settingsDivider()

                        settingsToggleRow(
                            icon: AppSymbols.Settings.hideInAppSwitcher,
                            tint: .gray,
                            title: "settings.hideInAppSwitcher",
                            detail: "settings.hideInAppSwitcher.rowDetail",
                            isOn: binding(\.hideInAppSwitcher, prefs.hideInAppSwitcher)
                        )
                    }
                }

                settingsGroup(title: "settings.section.backup", footer: "settings.section.backup.footer") {
                    NavigationLink {
                        ConsumerToolsView(environment: environment)
                    } label: {
                        settingsLeading(
                            icon: AppSymbols.Settings.manageTools,
                            tint: .blue,
                            title: "vault.tools.manage",
                            detail: "settings.tools.rowDetail"
                        )
                        Spacer(minLength: 8)
                        Image(systemName: AppSymbols.Settings.disclosure)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    settingsDivider()

                    NavigationLink {
                        BackupSettingsView(environment: environment)
                    } label: {
                        settingsLeading(
                            icon: AppSymbols.Settings.backup,
                            tint: .orange,
                            title: "settings.backup",
                            detail: "settings.backup.rowDetail"
                        )
                        Spacer(minLength: 8)
                        Image(systemName: AppSymbols.Settings.disclosure)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                settingsGroup(title: "settings.section.danger", footer: "settings.eraseAll.footer", danger: true) {
                    Button {
                        confirmErase = true
                    } label: {
                        settingsLeading(
                            icon: AppSymbols.Settings.eraseAll,
                            tint: .red,
                            title: "settings.eraseAll",
                            detail: "settings.eraseAll.rowDetail",
                            titleColor: .red
                        )
                        Spacer(minLength: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if !eraseStatus.isEmpty {
                        settingsDivider()
                        Text(eraseStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: shouldUseCompactSettingsColumn ? 560 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(settingsGroupedBackground.ignoresSafeArea())
    }

    /// 浅灰底：贴近白卡片，不要「一块深灰底板」那种反差。
    private var settingsGroupedBackground: Color {
        if colorScheme == .dark {
            return Color(white: 0.14)
        }
        #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        // 约 #F2F2F7，比 underPageBackground 更浅、更接近钱迹。
        return Color(red: 0.949, green: 0.949, blue: 0.969)
        #endif
    }

    /// 卡片近白；与灰底只差一档。
    private var settingsCardFill: Color {
        if colorScheme == .dark {
            return Color(white: 0.18)
        }
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color.white
        #endif
    }

    private func settingsGroup<Content: View>(
        title: LocalizedStringKey,
        footer: LocalizedStringKey,
        danger: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(danger ? Color.red.opacity(0.9) : Color.secondary)
                .padding(.horizontal, 4)

            // 同一功能区：一行贴一行，中间只有细分隔线，不留灰缝。
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(settingsCardFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // 极轻阴影：略托起卡片即可，不要深灰「掉下去」感。
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 2, y: 1)

            Text(footer)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func settingsDivider() -> some View {
        Divider()
            .opacity(0.7)
            .padding(.leading, 54)
    }

    private func settingsLeading(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        titleColor: Color = .primary
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .layoutPriority(1)
    }

    private func revealPolicySummary(_ policy: RevealPolicy) -> String {
        switch policy {
        case .biometricOrPasscode:
            return String(localized: "settings.policy.biometricOrPasscode.short")
        case .biometricOnly:
            switch environment.gate.availableBiometry() {
            case .faceID:
                return String(localized: "settings.policy.faceID")
            case .touchID:
                return String(localized: "settings.policy.touchID")
            case .none:
                return String(localized: "settings.policy.none")
            }
        case .masterPassword:
            return String(localized: "settings.policy.masterPassword")
        case .none:
            return String(localized: "settings.policy.none")
        }
    }

    private func settingsToggleRow(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            settingsLeading(icon: icon, tint: tint, title: title, detail: detail)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func settingsStepperRow(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        seconds: Int,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            settingsLeading(icon: icon, tint: tint, title: title, detail: detail)
            // 数字与「秒」、步进器同一行横排，避免 120 被挤成竖着断行。
            HStack(spacing: 6) {
                Text("\(seconds)")
                    .font(.body.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("settings.duration.unit")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Stepper(title, value: value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("settings.duration.seconds \(seconds)"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func settingsPickerRow<Selection: Hashable, Content: View>(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            settingsLeading(icon: icon, tint: tint, title: title, detail: detail)
            Picker(title, selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// iPad / Mac 宽屏：居中窄栏，避免一行拉满整个窗口。
    private var shouldUseCompactSettingsColumn: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private func binding(_ keyPath: WritableKeyPath<PreferencesDTO, Bool>, _ value: Bool) -> Binding<Bool> {
        Binding(
            get: { prefs?[keyPath: keyPath] ?? value },
            set: { newValue in
                Task {
                    var patch = PreferencesPatch()
                    switch keyPath {
                    case \.appLockEnabled: patch.appLockEnabled = newValue
                    case \.clipboardLocalOnly: patch.clipboardLocalOnly = newValue
                    case \.hideInAppSwitcher: patch.hideInAppSwitcher = newValue
                    default: break
                    }
                    await save(patch)
                }
            }
        )
    }

    private func save(_ patch: PreferencesPatch) async {
        try? await environment.preferences.update(patch)
        await reload()
        if patch.appearance != nil {
            await environment.refreshAppearance()
        }
    }

    private func reload() async {
        prefs = try? await environment.preferences.load()
    }

    private func refreshMasterPasswordStatus() async {
        masterPasswordIsSet = (try? await environment.masterPassword.isSet()) ?? false
    }
}

// MARK: - Reveal policy

private struct RevealPolicySettingsView: View {
    let environment: AppEnvironment
    @Binding var selection: RevealPolicy
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                policyRow(
                    .biometricOrPasscode,
                    title: "settings.policy.biometricOrPasscode",
                    detail: "settings.policy.biometricOrPasscode.detail"
                )
                biometryOnlyOption
                policyRow(
                    .masterPassword,
                    title: "settings.policy.masterPassword",
                    detail: "settings.policy.masterPassword.detail"
                )
                policyRow(
                    .none,
                    title: "settings.policy.none",
                    detail: "settings.policy.none.detail"
                )
            } footer: {
                Text("settings.section.password.footer")
            }
        }
        .navigationTitle("settings.revealPolicy")
        #if os(iOS) || targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var biometryOnlyOption: some View {
        switch environment.gate.availableBiometry() {
        case .faceID:
            policyRow(
                .biometricOnly,
                title: "settings.policy.faceID",
                detail: "settings.policy.biometricOnly.detail"
            )
        case .touchID:
            policyRow(
                .biometricOnly,
                title: "settings.policy.touchID",
                detail: "settings.policy.biometricOnly.detail"
            )
        case .none:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.policy.biometricOnly.unavailable")
                        .foregroundStyle(.secondary)
                    Text("settings.policy.biometricOnly.unavailable.detail")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    private func policyRow(
        _ value: RevealPolicy,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if selection == value {
                    Image(systemName: AppSymbols.Settings.checkmark)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Master password

private struct MasterPasswordSettingsView: View {
    let environment: AppEnvironment
    let onChanged: () async -> Void

    @State private var password = ""
    @State private var confirm = ""
    @State private var status = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                SecureField("vault.masterPassword", text: $password)
                SecureField("settings.masterPassword.confirm", text: $confirm)
                Button("settings.masterPassword.save") {
                    Task { await save() }
                }
                .disabled(isSaving || password.isEmpty || confirm.isEmpty)
            } footer: {
                Text("vault.masterPassword.disclosure")
            }

            Section {
                Button("settings.masterPassword.reset", role: .destructive) {
                    Task { await reset() }
                }
            }

            if !status.isEmpty {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("settings.masterPassword")
        #if os(iOS) || targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func save() async {
        status = ""
        guard password == confirm else {
            status = String(localized: "settings.masterPassword.mismatch")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await environment.masterPassword.setPassword(password)
            password = ""
            confirm = ""
            status = String(localized: "settings.masterPassword.saved")
            await onChanged()
        } catch {
            status = error.localizedDescription
        }
    }

    private func reset() async {
        status = ""
        do {
            try await environment.gate.confirmMandatory(
                reason: String(localized: "gate.resetMasterPassword")
            )
            try await environment.masterPassword.reset()
            password = ""
            confirm = ""
            status = String(localized: "settings.masterPassword.resetDone")
            await onChanged()
        } catch {
            status = error.localizedDescription
        }
    }
}

// MARK: - Backup

private struct BackupSettingsView: View {
    let environment: AppEnvironment
    @State private var passphrase = ""
    @State private var status = ""
    @State private var isExporting = false

    var body: some View {
        Form {
            Section {
                SecureField("settings.backup.passphrase", text: $passphrase)
                Button("settings.backup.export") {
                    Task { await export() }
                }
                .disabled(isExporting || passphrase.isEmpty)
            } footer: {
                Text("settings.backup.format.footer")
            }

            if !status.isEmpty {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("settings.backup")
        #if os(iOS) || targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func export() async {
        status = ""
        isExporting = true
        defer { isExporting = false }
        do {
            _ = try await environment.backups.exportBackup(
                passphrase: passphrase,
                purpose: .fullBackup
            )
            status = String(localized: "settings.backup.exported")
        } catch {
            status = error.localizedDescription
        }
    }
}

struct PaywallView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("paywall.title").font(.title2.bold())
                Text("paywall.body").multilineTextAlignment(.center)
                Button("paywall.buy") {
                    Task {
                        do {
                            try await environment.entitlements.purchaseUnlimitedKeys()
                            message = String(localized: "paywall.success")
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("paywall.restore") {
                    Task {
                        do {
                            try await environment.entitlements.restorePurchases()
                            message = String(localized: "paywall.restored")
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                #if DEBUG
                Button("paywall.debugUnlimited") {
                    Task {
                        try? await environment.entitlements.debugOverride(tier: .unlimitedKeys)
                        message = "DEBUG unlimited"
                    }
                }
                #endif
                if !message.isEmpty {
                    Text(message).font(.footnote)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("paywall.nav")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
        }
    }
}
