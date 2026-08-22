import SwiftUI
import StoreKit
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var prefs: PreferencesDTO?
    @State private var masterPasswordIsSet = false
    @State private var backupPassphraseIsSet = false
    @State private var confirmErase = false
    @State private var eraseStatus = ""
    @State private var restoreStatus = ""
    @State private var isRestoringPurchases = false
    @State private var showPaywall = false
    @State private var entitlementTier: EntitlementTier = .free

    var body: some View {
        NavigationStack {
            settingsRoot
                .navigationTitle(SettingsChrome.isMacDesktop ? "" : "settings.title")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(SettingsChrome.isMacDesktop)
                .toolbar(SettingsChrome.isMacDesktop ? .hidden : .automatic, for: .navigationBar)
                #if !targetEnvironment(macCatalyst)
                .toolbarBackground(SettingsChrome.groupedBackground(colorScheme), for: .navigationBar)
                #endif
                #endif
                .toolbar {
                    if !SettingsChrome.isMacDesktop, let onShowAccount {
                        ToolbarItem(placement: .navigation) {
                            Button(action: onShowAccount) {
                                Image(systemName: AppSymbols.Settings.account)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.title3)
                            }
                            .accessibilityLabel(Text("vault.sync.title"))
                        }
                    }
                    if !SettingsChrome.isMacDesktop, showsDismissButton {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("settings.done") { dismiss() }
                        }
                    }
                }
                .task {
                    await reload()
                    await refreshMasterPasswordStatus()
                    await refreshBackupPassphraseStatus()
                    await refreshEntitlementTier()
                }
                .sheet(isPresented: $showPaywall, onDismiss: {
                    Task { await refreshEntitlementTier() }
                }) {
                    PaywallView(environment: environment)
                        .settingsTaskSheet()
                }
                .confirmationDialog("settings.eraseAll.confirm", isPresented: $confirmErase) {
                    Button("settings.eraseAll", role: .destructive) {
                        Task {
                            do {
                                try await environment.dataLifecycle.eraseAllUserData()
                                eraseStatus = String(localized: "settings.eraseAll.done")
                                await reload()
                                await refreshMasterPasswordStatus()
                                await refreshBackupPassphraseStatus()
                                await refreshEntitlementTier()
                                await environment.refreshAppearance()
                            } catch {
                                eraseStatus = error.localizedDescription
                            }
                        }
                    }
                } message: {
                    Text("settings.eraseAll.message")
                }
        }
        .background(SettingsChrome.groupedBackground(colorScheme).ignoresSafeArea())
    }

    @ViewBuilder
    private var settingsRoot: some View {
        if SettingsChrome.isMacDesktop {
            VStack(spacing: 0) {
                SettingsMacChromeBar(title: "settings.title")
                settingsForm
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            settingsForm
        }
    }

    /// 参考「钱迹」式分组：圆角卡片 + 彩色图标行 + 卡片间距拉开。
    @ViewBuilder
    private var settingsForm: some View {
        SettingsColumnScroll {
                if let prefs {
                    settingsGroup(title: "settings.section.appearance") {
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

                        settingsDisclosureRow(
                            icon: AppSymbols.Settings.avatars,
                            tint: .pink,
                            title: "settings.avatars",
                            detail: "settings.avatars.rowDetail"
                        ) {
                            AvatarSettingsView(environment: environment)
                                .onDisappear {
                                    Task { await reload() }
                                }
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

                    settingsGroup(title: "settings.section.assign") {
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

                    settingsGroup(title: "settings.section.password") {
                        settingsDisclosureRow(
                            icon: AppSymbols.Settings.revealPolicy,
                            tint: .green,
                            title: "settings.revealPolicy",
                            detail: "settings.revealPolicy.rowDetail",
                            status: revealPolicySummary(prefs.revealPolicy)
                        ) {
                            RevealPolicySettingsView(
                                environment: environment,
                                currentPolicy: prefs.revealPolicy,
                                applyPolicy: { value in
                                    environment.preferences.persist(PreferencesPatch(revealPolicy: value))
                                    if var current = self.prefs {
                                        current.revealPolicy = value
                                        self.prefs = current
                                        environment.appPrivacy.applyLivePreferences(AppLockPreferences(current))
                                    }
                                    await refreshMasterPasswordStatus()
                                }
                            )
                            .id("reveal-policy-settings")
                            .onDisappear {
                                Task {
                                    await reload()
                                    await refreshMasterPasswordStatus()
                                }
                            }
                        }

                        // 仅在选用「主密码」验证时显示管理入口；Face ID 等策略下不单独挂「设主密码」。
                        if prefs.revealPolicy == .masterPassword {
                            settingsDivider()

                            settingsDisclosureRow(
                                icon: AppSymbols.Settings.masterPassword,
                                tint: .indigo,
                                title: "settings.masterPassword",
                                detail: "settings.masterPassword.rowDetail",
                                status: masterPasswordIsSet
                                    ? String(localized: "settings.masterPassword.status.set")
                                    : String(localized: "settings.masterPassword.status.unset")
                            ) {
                                MasterPasswordSettingsView(
                                    environment: environment,
                                    role: .manage
                                ) {
                                    await refreshMasterPasswordStatus()
                                    // 重置后若仍卡在主密码档，回退验证方式，避免无法查看/复制。
                                    let stillSet = (try? await environment.masterPassword.isSet()) ?? false
                                    if !stillSet, self.prefs?.revealPolicy == .masterPassword {
                                        if var current = self.prefs {
                                            current.revealPolicy = RevealPolicy.none
                                            self.prefs = current
                                        }
                                        await save(PreferencesPatch(revealPolicy: RevealPolicy.none))
                                    }
                                }
                            }
                        }

                        settingsDivider()

                        settingsToggleRow(
                            icon: AppSymbols.Settings.appLock,
                            tint: .teal,
                            title: "settings.appLock",
                            detail: "settings.appLock.rowDetail",
                            isOn: binding(\.appLockEnabled, prefs.appLockEnabled)
                        )
                    }

                    // 页脚紧贴卡片（7pt，与分组标题同距），说明 Mac 端清除的真实边界。
                    VStack(alignment: .leading, spacing: 7) {
                        settingsGroup(title: "settings.section.lockTiming") {
                            settingsStepperRow(
                                icon: AppSymbols.Settings.autoLock,
                                tint: .purple,
                                title: "settings.autoLock.label",
                                detail: "settings.autoLock.rowDetail",
                                seconds: prefs.autoLockSeconds,
                                value: Binding(
                                    get: { prefs.autoLockSeconds },
                                    set: { persistPrivacyPatch(PreferencesPatch(autoLockSeconds: $0)) }
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

                        SettingsFooterNote(text: "settings.section.lockTiming.footer")
                    }

                    settingsGroup(title: "settings.section.clipboardPrivacy") {
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

                settingsGroup(title: "settings.section.backup") {
                    settingsDisclosureRow(
                        icon: AppSymbols.Settings.backupPassphrase,
                        tint: .indigo,
                        title: "settings.backup.passphrase.setDefault",
                        detail: "settings.backup.passphrase.rowDetail",
                        status: backupPassphraseIsSet
                            ? String(localized: "settings.backup.passphrase.status.set")
                            : String(localized: "settings.backup.passphrase.status.unset")
                    ) {
                        BackupPassphraseSettingsView(environment: environment) {
                            await refreshBackupPassphraseStatus()
                        }
                    }

                    settingsDivider()

                    settingsDisclosureRow(
                        icon: AppSymbols.Settings.backupExport,
                        tint: .orange,
                        title: "settings.backup.export",
                        detail: "settings.backup.export.rowDetail"
                    ) {
                        BackupExportView(environment: environment)
                    }

                    settingsDivider()

                    settingsDisclosureRow(
                        icon: AppSymbols.Settings.backupImport,
                        tint: .teal,
                        title: "settings.backup.import",
                        detail: "settings.backup.import.rowDetail"
                    ) {
                        BackupImportView(environment: environment)
                    }
                }

                settingsGroup(title: "settings.section.purchases") {
                    HStack(alignment: .center, spacing: 8) {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 12) {
                                settingsLeading(
                                    icon: AppSymbols.Settings.upgrade,
                                    tint: .orange,
                                    title: "settings.upgrade"
                                )
                                Text(
                                    hasUnlimitedKeys
                                        ? String(localized: "settings.upgrade.status.owned")
                                        : String(localized: "settings.upgrade.status.action")
                                )
                                .font(.subheadline)
                                .foregroundStyle(hasUnlimitedKeys ? .secondary : Color.accentColor)
                                .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        InlineHelpButton(
                            title: "settings.upgrade",
                            message: hasUnlimitedKeys
                                ? "settings.upgrade.rowDetail.owned"
                                : "settings.upgrade.rowDetail",
                            showsTitle: false
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityHint(
                        Text(
                            hasUnlimitedKeys
                                ? "settings.upgrade.rowDetail.owned"
                                : "settings.upgrade.rowDetail"
                        )
                    )

                    settingsDivider()

                    HStack(alignment: .center, spacing: 8) {
                        Button {
                            Task { await restorePurchasesFromSettings() }
                        } label: {
                            HStack(spacing: 12) {
                                settingsLeading(
                                    icon: AppSymbols.Settings.restorePurchases,
                                    tint: .indigo,
                                    title: "settings.restorePurchases"
                                )
                                if isRestoringPurchases {
                                    ProgressView()
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestoringPurchases)
                        InlineHelpButton(
                            title: "settings.restorePurchases",
                            message: "settings.restorePurchases.rowDetail",
                            showsTitle: false
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityHint(Text("settings.restorePurchases.rowDetail"))

                    if !restoreStatus.isEmpty {
                        settingsDivider()
                        Text(restoreStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }

                settingsGroup(title: "settings.section.danger", danger: true) {
                    HStack(alignment: .center, spacing: 8) {
                        Button {
                            confirmErase = true
                        } label: {
                            settingsLeading(
                                icon: AppSymbols.Settings.eraseAll,
                                tint: .red,
                                title: "settings.eraseAll",
                                titleColor: .red
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        InlineHelpButton(
                            title: "settings.eraseAll",
                            message: "settings.eraseAll.rowDetail",
                            showsTitle: false
                        )
                    }
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
    }

    private func settingsGroup<Content: View>(
        title: LocalizedStringKey,
        danger: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                // 系统设置分组标题：13pt 常规、次要色，不和行标题抢字重。
                .font(.footnote)
                .foregroundStyle(danger ? Color.red.opacity(0.85) : Color.secondary)
                .padding(.horizontal, 16)

            // 同一功能区：一行贴一行，中间只有细分隔线，不留灰缝。
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsChrome.cardFill(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SettingsChrome.cardStroke(colorScheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(
                color: SettingsChrome.isMacDesktop
                    ? Color.clear
                    : Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04),
                radius: 2,
                y: 1
            )
        }
    }

    private func settingsDivider() -> some View {
        Divider()
            .opacity(0.7)
            .padding(.leading, 54)
    }

    /// 子页行：`标题　当前值　ⓘ　〉`。〉 在最右；点 ⓘ 只出说明。
    private func settingsDisclosureRow<Destination: View>(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringResource,
        status: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            NavigationLink {
                destination()
            } label: {
                HStack(spacing: 12) {
                    settingsLeading(icon: icon, tint: tint, title: title)
                    if let status {
                        Text(status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            InlineHelpButton(title: title, message: detail, showsTitle: false)
            NavigationLink {
                destination()
            } label: {
                Image(systemName: AppSymbols.Settings.disclosure)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func settingsLeading(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
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

            Text(title)
                .font(.body)
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
        detail: LocalizedStringResource,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            settingsLeading(icon: icon, tint: tint, title: title)
            InlineHelpButton(title: title, message: detail, showsTitle: false)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func settingsStepperRow(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringResource,
        seconds: Int,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            settingsLeading(icon: icon, tint: tint, title: title)
            InlineHelpButton(title: title, message: detail, showsTitle: false)
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
        detail: LocalizedStringResource,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            settingsLeading(icon: icon, tint: tint, title: title)
            InlineHelpButton(title: title, message: detail, showsTitle: false)
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

    private func binding(_ keyPath: WritableKeyPath<PreferencesDTO, Bool>, _ value: Bool) -> Binding<Bool> {
        Binding(
            get: { prefs?[keyPath: keyPath] ?? value },
            set: { newValue in
                switch keyPath {
                case \.appLockEnabled:
                    persistPrivacyPatch(PreferencesPatch(appLockEnabled: newValue))
                case \.hideInAppSwitcher:
                    persistPrivacyPatch(PreferencesPatch(hideInAppSwitcher: newValue))
                case \.clipboardLocalOnly:
                    Task {
                        var patch = PreferencesPatch()
                        patch.clipboardLocalOnly = newValue
                        await save(patch)
                    }
                default:
                    break
                }
            }
        )
    }

    /// App 锁三项：先改内存再 persist，避免等 CloudKit save 卡住，并让遮罩/锁立即跟开关走。
    private func persistPrivacyPatch(_ patch: PreferencesPatch) {
        guard var current = prefs else { return }
        if let value = patch.appLockEnabled { current.appLockEnabled = value }
        if let value = patch.autoLockSeconds { current.autoLockSeconds = value }
        if let value = patch.hideInAppSwitcher { current.hideInAppSwitcher = value }
        prefs = current
        environment.appPrivacy.applyLivePreferences(AppLockPreferences(current))
        environment.preferences.persist(patch)
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
        if let prefs {
            environment.appPrivacy.applyLivePreferences(AppLockPreferences(prefs))
        }
    }

    private func refreshMasterPasswordStatus() async {
        masterPasswordIsSet = (try? await environment.masterPassword.isSet()) ?? false
    }

    private func refreshBackupPassphraseStatus() async {
        backupPassphraseIsSet = (try? await environment.backupPassphrase.isSet()) ?? false
    }

    private var hasUnlimitedKeys: Bool {
        entitlementTier == .unlimitedKeys || entitlementTier == .relay
    }

    private func refreshEntitlementTier() async {
        entitlementTier = (try? await environment.entitlements.currentTier()) ?? .free
    }

    /// FR-028：设置内始终可达的恢复购买（不依赖免费额度条 / 付费墙）。
    private func restorePurchasesFromSettings() async {
        restoreStatus = ""
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        do {
            try await environment.entitlements.restorePurchases()
            await refreshEntitlementTier()
            restoreStatus = String(localized: "settings.restorePurchases.done")
        } catch {
            restoreStatus = error.localizedDescription
        }
    }
}

// MARK: - Reveal policy

private struct RevealPolicySettingsView: View {
    let environment: AppEnvironment
    let currentPolicy: RevealPolicy
    /// 仅主密码设密成功后调用；选档本身走 `persist`，不在此等待 SwiftData。
    let applyPolicy: (RevealPolicy) async -> Void

    /// 选「主密码」且尚未设密 → 推进到下一步设密页（不是先改策略）。
    @State private var goSetMasterPassword = false
    @State private var highlightedPolicy: RevealPolicy

    init(
        environment: AppEnvironment,
        currentPolicy: RevealPolicy,
        applyPolicy: @escaping (RevealPolicy) async -> Void
    ) {
        self.environment = environment
        self.currentPolicy = currentPolicy
        self.applyPolicy = applyPolicy
        _highlightedPolicy = State(initialValue: currentPolicy)
    }

    var body: some View {
        SettingsSubpage(title: "settings.revealPolicy") {
            SettingsCard {
                policyRow(
                    .biometricOrPasscode,
                    title: "settings.policy.biometricOrPasscode",
                    detail: "settings.policy.biometricOrPasscode.detail"
                )
                SettingsCardDivider()
                biometryOnlyOption
                SettingsCardDivider()
                policyRow(
                    .masterPassword,
                    title: "settings.policy.masterPassword",
                    detail: "settings.policy.masterPassword.detail"
                )
                SettingsCardDivider()
                policyRow(
                    .none,
                    title: "settings.policy.none",
                    detail: "settings.policy.none.detail"
                )
            }
        }
        .navigationDestination(isPresented: $goSetMasterPassword) {
            // 与设置页「主密码」同一界面：首次设密也走这里，避免两套表单。
            MasterPasswordSettingsView(
                environment: environment,
                role: .setupForPolicy,
                onChanged: {},
                onSetupComplete: {
                    await applyPolicy(.masterPassword)
                    highlightedPolicy = .masterPassword
                }
            )
        }
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
            HStack(alignment: .center, spacing: 8) {
                Text("settings.policy.biometricOnly.unavailable")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                InlineHelpButton(
                    title: "settings.policy.biometricOnly.unavailable",
                    message: "settings.policy.biometricOnly.unavailable.detail",
                    showsTitle: false
                )
                Color.clear
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, SettingsChrome.isMacDesktop ? 10 : 12)
        }
    }

    private func policyRow(
        _ value: RevealPolicy,
        title: LocalizedStringKey,
        detail: LocalizedStringResource
    ) -> some View {
        SettingsChoiceRow(
            title: title,
            selected: highlightedPolicy == value,
            helpTitle: title,
            helpMessage: detail
        ) {
            Task { await selectPolicy(value) }
        }
    }

    /// 未设主密码时：只进入设密下一步，不改 `revealPolicy`。
    /// 写入走 `persist`：不在 MainActor 上等待 CloudKit/SwiftData save，否则会整窗转圈。
    private func selectPolicy(_ value: RevealPolicy) async {
        if value == .masterPassword {
            let isSet = (try? await environment.masterPassword.isSet()) ?? false
            if !isSet {
                goSetMasterPassword = true
                return
            }
        }
        highlightedPolicy = value
        environment.preferences.persist(PreferencesPatch(revealPolicy: value))
    }
}

// MARK: - Master password

/// 主密码唯一界面：首次设密（从验证方式进入）与日常修改/重置共用。
private enum MasterPasswordScreenRole {
    /// 验证方式 → 主密码：尚未设密时的下一步。
    case setupForPolicy
    /// 设置页「主密码」行：修改 / 重置。
    case manage
}

private struct MasterPasswordSettingsView: View {
    let environment: AppEnvironment
    var role: MasterPasswordScreenRole = .manage
    let onChanged: () async -> Void
    /// 仅 `setupForPolicy`：设密成功并落盘策略后调用。
    var onSetupComplete: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var isSaving = false
    @State private var passwordAlreadySet = false
    @State private var showSuccessAlert = false
    @State private var showFailureAlert = false
    @State private var showResetDoneAlert = false
    @State private var failureReason = ""
    @State private var didAttemptSave = false

    private var evaluation: MasterPasswordPolicy.Evaluation {
        MasterPasswordPolicy.evaluate(password: password, confirm: confirm)
    }

    private var highlightUnmetRules: Bool {
        didAttemptSave && !evaluation.canSave
    }

    private var unmetRulesSummary: String {
        var lines: [String] = []
        if !evaluation.meetsMinimumLength {
            lines.append(
                String(localized: "settings.masterPassword.rule.length.unmet \(Int64(evaluation.trimmedLength))")
            )
        }
        if !evaluation.confirmMatches {
            lines.append(String(localized: "settings.masterPassword.rule.match.unmet"))
        }
        return lines.joined(separator: "\n")
    }

    private var showsReset: Bool {
        role == .manage && passwordAlreadySet
    }

    var body: some View {
        SettingsSubpage(title: "settings.masterPassword") {
            SettingsCard {
                SettingsSecureField(title: "vault.masterPassword", text: $password)
                SettingsCardDivider()
                SettingsSecureField(title: "settings.masterPassword.confirm", text: $confirm)
            }

            MasterPasswordRulesList(
                evaluation: evaluation,
                highlightUnmet: highlightUnmetRules
            )

            if highlightUnmetRules {
                SettingsStatusBanner(text: unmetRulesSummary, isError: true)
            }

            SettingsFooterNote(text: "vault.masterPassword.disclosure")
            if role == .setupForPolicy {
                SettingsFooterNote(text: "settings.policy.masterPassword.setupHint")
            }

            SettingsPrimaryButton(
                title: "settings.masterPassword.save",
                disabled: isSaving
            ) {
                Task { await save() }
            }

            if showsReset {
                SettingsCard {
                    Button(role: .destructive) {
                        Task { await reset() }
                    } label: {
                        Text("settings.masterPassword.reset")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
        .overlay {
            if isSaving { ProgressView() }
        }
        .task {
            passwordAlreadySet = (try? await environment.masterPassword.isSet()) ?? false
        }
        .alert("settings.masterPassword.saveSuccess.title", isPresented: $showSuccessAlert) {
            Button("settings.done") {
                if role == .setupForPolicy {
                    dismiss()
                }
            }
        } message: {
            Text(
                role == .setupForPolicy
                    ? "settings.masterPassword.saveSuccess.message"
                    : "settings.masterPassword.saved"
            )
        }
        .alert("settings.masterPassword.saveFailed.title", isPresented: $showFailureAlert) {
            Button("settings.done", role: .cancel) {}
        } message: {
            Text(failureReason)
        }
        .alert("settings.masterPassword.resetDone", isPresented: $showResetDoneAlert) {
            Button("settings.done", role: .cancel) {}
        }
    }

    private func save() async {
        didAttemptSave = true
        guard evaluation.canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await environment.masterPassword.setPassword(password)
            password = ""
            confirm = ""
            didAttemptSave = false
            passwordAlreadySet = true
            switch role {
            case .setupForPolicy:
                await onSetupComplete?()
            case .manage:
                await onChanged()
            }
            showSuccessAlert = true
        } catch let ApiRelayError.validationFailed(_, reason) where reason == "too_short" {
            didAttemptSave = true
        } catch {
            failureReason = error.localizedDescription
            showFailureAlert = true
        }
    }

    private func reset() async {
        do {
            try await environment.gate.confirmMandatory(
                reason: String(localized: "gate.resetMasterPassword")
            )
            try await environment.masterPassword.reset()
            password = ""
            confirm = ""
            passwordAlreadySet = false
            didAttemptSave = false
            await onChanged()
            showResetDoneAlert = true
        } catch ApiRelayError.authenticationCancelled {
            // 用户取消设备验证，无提示
        } catch {
            failureReason = error.localizedDescription
            showFailureAlert = true
        }
    }
}

private struct MasterPasswordRulesList: View {
    var evaluation: MasterPasswordPolicy.Evaluation
    var highlightUnmet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.masterPassword.rules.title")
                .font(.subheadline.weight(.semibold))
            ruleRow(
                title: lengthRuleTitle,
                isMet: evaluation.meetsMinimumLength,
                isUnmetFailure: highlightUnmet && !evaluation.meetsMinimumLength
            )
            ruleRow(
                title: String(localized: "settings.masterPassword.rule.match"),
                isMet: evaluation.confirmMatches,
                isUnmetFailure: highlightUnmet && !evaluation.confirmMatches
            )
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: AppSymbols.Action.info)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
                Text("settings.masterPassword.rule.charset")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var lengthRuleTitle: String {
        if highlightUnmet && !evaluation.meetsMinimumLength {
            return String(localized: "settings.masterPassword.rule.length.unmet \(Int64(evaluation.trimmedLength))")
        }
        return String(localized: "settings.masterPassword.rule.length")
    }

    private func ruleRow(title: String, isMet: Bool, isUnmetFailure: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isMet ? AppSymbols.Action.checked : AppSymbols.Action.unchecked)
                .font(.body)
                .foregroundStyle(isUnmetFailure ? Color.red : (isMet ? Color.accentColor : Color.secondary))
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isUnmetFailure ? Color.red : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(
            Text(isMet
                 ? String(localized: "settings.masterPassword.rule.met")
                 : String(localized: "settings.masterPassword.rule.unmet"))
        )
    }
}

struct PaywallView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var message = ""
    @State private var product: Product?
    @State private var isLoadingProduct = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var alreadyOwned = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("paywall.body")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isLoadingProduct {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        unlimitedPlanCard
                        relayComingSoonCard
                    }

                    Button {
                        Task { await purchase() }
                    } label: {
                        Group {
                            if isPurchasing {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else if alreadyOwned {
                                Text("paywall.owned")
                                    .frame(maxWidth: .infinity)
                            } else if let product {
                                Text("paywall.upgradeWithPrice \(product.displayPrice)")
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("paywall.upgrade")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isPurchasing || isRestoring || product == nil || alreadyOwned)

                    Button("paywall.restore") {
                        Task { await restore() }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isPurchasing || isRestoring)

                    if !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(paywallBackground.ignoresSafeArea())
            .navigationTitle("paywall.nav")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #if !targetEnvironment(macCatalyst)
            .toolbarBackground(paywallBackground, for: .navigationBar)
            #endif
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
            .task {
                await loadProductAndTier()
            }
            #if targetEnvironment(macCatalyst)
            .frame(minWidth: 520, minHeight: 620)
            #endif
        }
    }

    private var unlimitedPlanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("paywall.plan.unlimited.title")
                    .font(.headline)
                Spacer(minLength: 8)
                if alreadyOwned {
                    Text("paywall.plan.badge.owned")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.green.opacity(0.15))
                        )
                } else {
                    Text("paywall.plan.badge.current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
            }

            Text("paywall.plan.unlimited.detail")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let product {
                    Text(product.displayPrice)
                        .font(.title2.weight(.bold))
                    Text("paywall.plan.once")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("paywall.productUnavailable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(paywallCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(alreadyOwned ? 0.15 : 0.35), lineWidth: 1)
        )
    }

    private var relayComingSoonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("paywall.plan.relay.title")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("paywall.plan.badge.comingSoon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            Text("paywall.plan.relay.detail")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(paywallCardFill.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .opacity(0.85)
        .accessibilityElement(children: .combine)
    }

    private var paywallBackground: Color {
        if colorScheme == .dark {
            return Color(white: 0.14)
        }
        #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(red: 0.949, green: 0.949, blue: 0.969)
        #endif
    }

    private var paywallCardFill: Color {
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

    private func loadProductAndTier() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let tier = try await environment.entitlements.currentTier()
            alreadyOwned = (tier == .unlimitedKeys || tier == .relay)
            let products = try await Product.products(
                for: [EntitlementService.unlimitedKeysProductID]
            )
            product = products.first
            if products.isEmpty {
                message = String(localized: "paywall.productUnavailable")
            }
        } catch {
            message = error.localizedDescription
            product = nil
        }
    }

    private func purchase() async {
        message = ""
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await environment.entitlements.purchaseUnlimitedKeys()
            let tier = try await environment.entitlements.currentTier()
            alreadyOwned = (tier == .unlimitedKeys || tier == .relay)
            message = String(localized: "paywall.success")
            if alreadyOwned {
                dismiss()
            }
        } catch ApiRelayError.authenticationCancelled {
            // 用户取消，不刷错误文案
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() async {
        message = ""
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await environment.entitlements.restorePurchases()
            let tier = try await environment.entitlements.currentTier()
            alreadyOwned = (tier == .unlimitedKeys || tier == .relay)
            message = String(localized: "paywall.restored")
        } catch {
            message = error.localizedDescription
        }
    }
}
