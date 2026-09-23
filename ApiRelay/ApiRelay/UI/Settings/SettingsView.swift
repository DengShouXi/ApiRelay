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
    @Environment(\.scenePhase) private var scenePhase
    @State private var prefs: PreferencesDTO?
    @State private var masterPasswordMaterial: AppPasswordMaterialStatus = .unset
    @State private var backupPassphraseIsSet = false
    @State private var confirmErase = false
    @State private var eraseStatus = ""
    @State private var restoreStatus = ""
    @State private var isRestoringPurchases = false
    @State private var showPaywall = false
    @State private var entitlementTier: EntitlementTier = .free
    @State private var persistError = ""
    @State private var pendingWeakenPatch: PreferencesPatch?
    @State private var weakenPassword = ""
    @State private var showWeakenPasswordPrompt = false
    @State private var showEraseAppPassword = false
    @State private var eraseAppPasswordInput = ""
    @State private var eraseFlowTrace = SettingsEraseAllFlow.Trace()
    @State private var combinationNeedsSetup = false
    @State private var eraseAwaitingIdentity = false
    /// Ordinary security downgrades use the same page-generation discipline as
    /// password setup. It stays alive until the queued repository commit ends.
    @State private var securityPreferenceAuthorization: SecurityPreferenceAuthorization?
    @State private var authenticationScope: AuthenticationRequestScope?
    /// 子页退出或场景离开会推进代次；任何 await 后迟到的选档请求都不得重建提示或提交。
    @State private var securityPreferenceRequestRevision: UInt64 = 0

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
                        Task { await confirmEraseAfterDestructiveDialog() }
                    }
                } message: {
                    Text("settings.eraseAll.message")
                }
                .onReceive(NotificationCenter.default.publisher(for: .securityPreferencesPersistFailed)) { _ in
                    persistError = String(localized: "settings.securityPersistFailed.message")
                    Task { await reload() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .securityPreferencesDidPersist)) { _ in
                    Task { await reload() }
                }
                .onDisappear {
                    abandonSettingsCombinationPending()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        clearSettingsSensitiveInputs()
                    }
                    if phase == .inactive && environment.gate.isAuthenticationInProgress() {
                        return
                    }
                    if phase != .active {
                        abandonSettingsCombinationPending()
                    }
                }
                .onReceive(environment.appPrivacy.$session) { session in
                    if session.isSessionLocked {
                        abandonSettingsCombinationPending()
                    }
                }
                .alert(
                    String(localized: "settings.weakenConfirm.appPassword.title"),
                    isPresented: $showEraseAppPassword
                ) {
                    SecureField("vault.masterPassword", text: $eraseAppPasswordInput)
                        .sensitivePasswordInput()
                    Button("settings.done") {
                        let password = eraseAppPasswordInput
                        eraseAppPasswordInput = ""
                        Task { await submitEraseAppPassword(password) }
                    }
                    Button("settings.cancel", role: .cancel) {
                        var trace = eraseFlowTrace
                        _ = SettingsEraseAllFlow.afterAppPasswordCancel(trace: &trace)
                        eraseFlowTrace = trace
                        eraseAppPasswordInput = ""
                        eraseAwaitingIdentity = false
                    }
                } message: {
                    Text("settings.weakenConfirm.appPassword.message")
                }
        }
        .alert("settings.securityPersistFailed.title", isPresented: Binding(
            get: { !persistError.isEmpty },
            set: { if !$0 { persistError = "" } }
        )) {
            Button("settings.done", role: .cancel) {}
        } message: {
            Text(persistError)
        }
        // 安全降档可能从 NavigationStack 的任意子页发起。确认框必须挂在
        // 整个栈上，否则在「验证方式」页选择设备验证时，输入应用密码的
        // 提示会滞留在已经离场的设置首页，直到用户返回才出现。
        .alert(
            String(localized: "settings.weakenConfirm.appPassword.title"),
            isPresented: $showWeakenPasswordPrompt
        ) {
            SecureField("vault.masterPassword", text: $weakenPassword)
                .sensitivePasswordInput()
            Button("settings.done") {
                let password = weakenPassword
                weakenPassword = ""
                Task { await confirmPendingWeakenWithAppPassword(password) }
            }
            Button("settings.cancel", role: .cancel) {
                abandonSettingsCombinationPending()
            }
        } message: {
            Text("settings.weakenConfirm.appPassword.message")
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
                                set: { v in
                                    if var current = self.prefs {
                                        current.appearance = v
                                        self.prefs = current
                                    }
                                    Task { await save(PreferencesPatch(appearance: v)) }
                                }
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

                    VStack(alignment: .leading, spacing: 7) {
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
                                        await persistSyncedPatchAsync(PreferencesPatch(revealPolicy: value))
                                        await refreshMasterPasswordStatus()
                                    },
                                    onAppPasswordCommitted: {
                                        await reload()
                                        await refreshMasterPasswordStatus()
                                    }
                                )
                                .id("reveal-policy-settings")
                                .onDisappear {
                                    abandonSettingsCombinationPending()
                                    // MUST NOT 在这里 reload：返回时同步写入可能还没落盘，
                                    // 读回旧值会把刚选好的验证方式弹回去。内存里已是最新值。
                                    Task { await refreshMasterPasswordStatus() }
                                }
                            }

                            if CombinationExplicitAuth.shouldShowExplicitEntry(
                                hasBoundOperation: pendingWeakenPatch != nil,
                                policy: prefs.revealPolicy
                            ) {
                                settingsDivider()
                                Button("appLock.useAppPassword") {
                                    Task { await beginSettingsCombinationPassword() }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .accessibilityLabel(Text("appLock.useAppPassword"))
                                .accessibilityHint(Text("appLock.combination.hint"))
                            }

                            settingsDivider()

                            settingsDisclosureRow(
                                icon: AppSymbols.Settings.autoLock,
                                tint: .purple,
                                title: "settings.autoLock.label",
                                detail: "settings.autoLock.rowDetail",
                                status: autoLockHomeStatus(prefs)
                            ) {
                                DurationFeatureSettingsView(
                                    kind: .autoLock,
                                    prefs: prefsBinding,
                                    persist: persistSyncedPatch
                                )
                            }

                            settingsDivider()

                            settingsToggleRow(
                                icon: AppSymbols.Action.reveal,
                                tint: .orange,
                                title: "settings.revealAuth",
                                detail: "settings.revealAuth.rowDetail",
                                isOn: Binding(
                                    get: { prefs.revealAuthEnabled },
                                    set: { persistSyncedPatch(PreferencesPatch(revealAuthEnabled: $0)) }
                                )
                            )

                            // 仅当前已成功保存为应用密码或组合档时显示管理行。
                            if AppPasswordSettingsRouting.showsHomeManagementRow(
                                currentPolicy: prefs.revealPolicy
                            ) {
                                settingsDivider()

                                settingsDisclosureRow(
                                    icon: AppSymbols.Settings.masterPassword,
                                    tint: .indigo,
                                    title: "settings.masterPassword",
                                    detail: "settings.masterPassword.rowDetail",
                                    status: AppPasswordSettingsRouting.homeRowStatus(masterPasswordMaterial)
                                ) {
                                    MasterPasswordSettingsView(
                                        environment: environment,
                                        target: prefs.revealPolicy,
                                        currentPolicy: prefs.revealPolicy,
                                        onCommitted: {
                                            await refreshMasterPasswordStatus()
                                            await reload()
                                        }
                                    )
                                }
                            }
                        }
                        if prefs.revealPolicy == .noVerification,
                           prefs.appLockEnabled || prefs.revealAuthEnabled {
                            SettingsFooterNote(text: "settings.pausedWhileNoVerification")
                        }
                    }

                    settingsGroup(title: "settings.section.lockTiming") {
                        settingsDisclosureRow(
                            icon: AppSymbols.Settings.clipboardClear,
                            tint: .pink,
                            title: "settings.clipboardClear.label",
                            detail: SettingsChrome.isMacDesktop
                                ? "settings.clipboardClear.rowDetail.mac"
                                : "settings.clipboardClear.rowDetail",
                            status: clipboardClearHomeStatus(prefs)
                        ) {
                            DurationFeatureSettingsView(
                                kind: .clipboardClear,
                                prefs: prefsBinding,
                                persist: persistSyncedPatch
                            )
                        }
                    }

                    settingsGroup(
                        title: "settings.section.clipboardPrivacy",
                        detail: SettingsChrome.isMacDesktop
                            ? LocalizedStringResource("settings.section.clipboardPrivacy.macLimits")
                            : nil
                    ) {
                        settingsToggleRow(
                            icon: AppSymbols.Settings.clipboardLocalOnly,
                            tint: .cyan,
                            title: SettingsChrome.isNativeMac
                                ? LocalizedStringKey("settings.clipboardLocalOnly.mac")
                                : LocalizedStringKey("settings.clipboardLocalOnly"),
                            detail: SettingsChrome.isNativeMac
                                ? LocalizedStringResource("settings.clipboardLocalOnly.rowDetail.mac")
                                : LocalizedStringResource("settings.clipboardLocalOnly.rowDetail"),
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
                    HStack(alignment: .center, spacing: 6) {
                        Button {
                            showPaywall = true
                        } label: {
                            settingsLeading(
                                icon: AppSymbols.Settings.upgrade,
                                tint: .orange,
                                title: "settings.upgrade"
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(
                            Text(
                                hasUnlimitedKeys
                                    ? "settings.upgrade.status.owned"
                                    : "settings.upgrade.status.action"
                            )
                        )
                        InlineHelpButton(
                            title: "settings.upgrade",
                            message: hasUnlimitedKeys
                                ? "settings.upgrade.rowDetail.owned"
                                : "settings.upgrade.rowDetail",
                            showsTitle: false
                        )
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 8) {
                                Spacer(minLength: 8)
                                Text(
                                    hasUnlimitedKeys
                                        ? String(localized: "settings.upgrade.status.owned")
                                        : String(localized: "settings.upgrade.status.action")
                                )
                                .font(.subheadline)
                                .foregroundStyle(hasUnlimitedKeys ? .secondary : Color.accentColor)
                                .lineLimit(1)
                                .layoutPriority(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
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

                    HStack(alignment: .center, spacing: 6) {
                        Button {
                            Task { await restorePurchasesFromSettings() }
                        } label: {
                            settingsLeading(
                                icon: AppSymbols.Settings.restorePurchases,
                                tint: .indigo,
                                title: "settings.restorePurchases"
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestoringPurchases)
                        InlineHelpButton(
                            title: "settings.restorePurchases",
                            message: "settings.restorePurchases.rowDetail",
                            showsTitle: false
                        )
                        Button {
                            Task { await restorePurchasesFromSettings() }
                        } label: {
                            HStack(spacing: 0) {
                                Spacer(minLength: 8)
                                if isRestoringPurchases {
                                    ProgressView()
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestoringPurchases)
                        .accessibilityHidden(true)
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
                    HStack(alignment: .center, spacing: 6) {
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
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if CombinationExplicitAuth.shouldShowExplicitEntry(
                        hasBoundOperation: eraseAwaitingIdentity,
                        policy: prefs?.revealPolicy ?? .noVerification
                    ) {
                        settingsDivider()
                        Button("appLock.useAppPassword") {
                            Task { await beginSettingsCombinationPassword() }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .accessibilityLabel(Text("appLock.useAppPassword"))
                    }

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
        detail: LocalizedStringResource? = nil,
        danger: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    // 系统设置分组标题：13pt 常规、次要色，不和行标题抢字重。
                    .font(.footnote)
                    .foregroundStyle(danger ? Color.red.opacity(0.85) : Color.secondary)
                if let detail {
                    InlineHelpButton(title: title, message: detail)
                }
                Spacer(minLength: 0)
            }
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

    /// 子页行：`标题　ⓘ　当前值　〉`。ⓘ 紧贴标题；〉 在最右；点 ⓘ 只出说明。
    private func settingsDisclosureRow<Destination: View>(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringResource,
        status: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            NavigationLink {
                destination()
            } label: {
                settingsLeading(icon: icon, tint: tint, title: title)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityValue(Text(status ?? ""))
            InlineHelpButton(title: title, message: detail, showsTitle: false)
            NavigationLink {
                destination()
            } label: {
                HStack(spacing: 6) {
                    Spacer(minLength: 8)
                    if let status {
                        Text(status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(1)
                    }
                    Image(systemName: AppSymbols.Settings.disclosure)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 图标 + 标题。标题按内容宽度排布，好让 ⓘ 紧贴文字，而不是被拉到行尾。
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
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, alignment: .leading)
        }
    }

    private func revealPolicySummary(_ policy: RevealPolicy) -> String {
        RevealPolicyDisplayName.summary(
            policy,
            biometry: environment.gate.availableBiometry(),
            isMac: SettingsChrome.isMacDesktop
        )
    }

    private func settingsToggleRow(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringResource,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            settingsLeading(icon: icon, tint: tint, title: title)
            InlineHelpButton(title: title, message: detail, showsTitle: false)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .layoutPriority(1)
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
        HStack(alignment: .center, spacing: 6) {
            settingsLeading(icon: icon, tint: tint, title: title)
            InlineHelpButton(title: title, message: detail, showsTitle: false)
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
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
                    persistSyncedPatch(PreferencesPatch(appLockEnabled: newValue))
                case \.hideInAppSwitcher:
                    persistSyncedPatch(PreferencesPatch(hideInAppSwitcher: newValue))
                case \.clipboardLocalOnly:
                    persistSyncedPatch(PreferencesPatch(clipboardLocalOnly: newValue))
                default:
                    break
                }
            }
        )
    }

    private var prefsBinding: Binding<PreferencesDTO> {
        Binding(
            get: { prefs! },
            set: { prefs = $0 }
        )
    }

    private func autoLockHomeStatus(_ prefs: PreferencesDTO) -> String {
        guard prefs.appLockEnabled else {
            return String(localized: "settings.duration.off")
        }
        if prefs.revealPolicy == .noVerification {
            return String(localized: "settings.pausedWhileNoVerification")
        }
        return DurationOptionList.displayName(prefs.autoLockSeconds)
    }

    private func clipboardClearHomeStatus(_ prefs: PreferencesDTO) -> String {
        guard prefs.clipboardClearEnabled else {
            return String(localized: "settings.duration.off")
        }
        return DurationOptionList.displayName(prefs.clipboardClearSeconds)
    }

    /// 写同步那份偏好（`UserPreferences` → CloudKit）的唯一入口。
    /// 加强安全：先改内存让控件立刻跟手，再 `persist`（内部 `Task.detached`）。
    /// 降低已同步等级（FR-069）：只 persist；成功通知到达后 `reload` 才改锁态与缓存。
    /// MUST NOT 在 MainActor 上 `await update`：`mainContext` 与 `@ModelActor` 的 save 互相等待，整窗转圈。
    /// 加强路径也 MUST NOT 在写完后 `reload`，那会用尚未落盘的旧值把开关弹回去。
    private func persistSyncedPatch(_ patch: PreferencesPatch) {
        persistSyncedPatch(patch, skipReauth: false)
    }

    private func persistSyncedPatch(_ patch: PreferencesPatch, skipReauth: Bool) {
        Task { await persistSyncedPatchAsync(patch, skipReauth: skipReauth) }
    }

    private func persistSyncedPatchAsync(
        _ patch: PreferencesPatch,
        skipReauth: Bool = false,
        submittedAppPassword: String? = nil
    ) async {
        securityPreferenceRequestRevision &+= 1
        let requestRevision = securityPreferenceRequestRevision
        guard let current = prefs else { return }
        securityPreferenceAuthorization?.invalidate()
        securityPreferenceAuthorization = nil
        if AppPasswordPolicyGate.requiresMaterialLookup(for: patch) {
            let material = await environment.masterPassword.materialStatus()
            guard requestRevision == securityPreferenceRequestRevision else { return }
            if let rejection = AppPasswordPolicyGate.persistRejection(patch, material: material) {
                persistError = rejection.localizedDescription
                pendingWeakenPatch = nil
                weakenPassword = ""
                return
            }
        }
        var authorization: SecurityPreferenceAuthorization?
        if !skipReauth, SecurityPolicyChange.weakens(patch, relativeTo: current) {
            let currentPolicy = RevealPolicyPersistence.canonical(current.revealPolicy)
            let submitted: String? = {
                let raw = submittedAppPassword ?? weakenPassword
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()
            if currentPolicy == .masterPassword, submitted == nil {
                pendingWeakenPatch = patch
                showWeakenPasswordPrompt = true
                return
            }
            do {
                if combinationNeedsSetup {
                    persistError = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
                    pendingWeakenPatch = nil
                    weakenPassword = ""
                    return
                }
                let captured = try environment.appPrivacy.makeSecurityPreferenceAuthorization(
                    currentPolicy: currentPolicy,
                    targetPolicy: patch.revealPolicy
                )
                authorization = captured
                securityPreferenceAuthorization = captured
                try await performWithPageAuthenticationScope {
                    try await CurrentRevealPolicyAuth.confirm(
                        current.revealPolicy,
                        gate: environment.gate,
                        reason: String(localized: "gate.changeSecuritySettings"),
                        purpose: .settings,
                        appPassword: submitted
                    )
                }
                guard requestRevision == securityPreferenceRequestRevision else {
                    authorization?.invalidate()
                    securityPreferenceAuthorization = nil
                    return
                }
                try environment.appPrivacy.requireUserFacingForAuthenticatedSettingsCommit()
                try captured.authorize()
            } catch let error as ApiRelayError
                where CombinationExplicitAuth.isCombination(current.revealPolicy)
                    && CombinationExplicitAuth.shouldOfferAppPassword(after: error)
                    && submitted == nil
            {
                authorization?.invalidate()
                securityPreferenceAuthorization = nil
                guard requestRevision == securityPreferenceRequestRevision else { return }
                pendingWeakenPatch = patch
                showWeakenPasswordPrompt = true
                return
            } catch ApiRelayError.authenticationCancelled {
                authorization?.invalidate()
                securityPreferenceAuthorization = nil
                guard requestRevision == securityPreferenceRequestRevision else { return }
                pendingWeakenPatch = nil
                weakenPassword = ""
                return
            } catch {
                authorization?.invalidate()
                securityPreferenceAuthorization = nil
                guard requestRevision == securityPreferenceRequestRevision else { return }
                persistError = error.localizedDescription
                pendingWeakenPatch = nil
                weakenPassword = ""
                return
            }
        }
        guard requestRevision == securityPreferenceRequestRevision else {
            authorization?.invalidate()
            securityPreferenceAuthorization = nil
            return
        }
        pendingWeakenPatch = nil
        weakenPassword = ""
        SecurityPreferenceCommit.persist(
            patch,
            relativeTo: current,
            using: environment.preferences,
            authorization: authorization
        ) { next in
            prefs = next
            environment.appPrivacy.applyLivePreferences(AppLockPreferences(next))
        }
    }

    private func confirmPendingWeakenWithAppPassword(_ password: String) async {
        guard let patch = pendingWeakenPatch else { return }
        await persistSyncedPatchAsync(patch, submittedAppPassword: password)
    }

    private func clearSettingsSensitiveInputs() {
        weakenPassword = ""
        eraseAppPasswordInput = ""
    }

    private func abandonSettingsCombinationPending() {
        securityPreferenceRequestRevision &+= 1
        securityPreferenceAuthorization?.invalidate()
        securityPreferenceAuthorization = nil
        authenticationScope?.cancel()
        authenticationScope = nil
        pendingWeakenPatch = nil
        clearSettingsSensitiveInputs()
        showWeakenPasswordPrompt = false
        eraseAwaitingIdentity = false
        showEraseAppPassword = false
        combinationNeedsSetup = false
    }

    private func beginSettingsCombinationPassword() async {
        guard CombinationExplicitAuth.isCombination(prefs?.revealPolicy ?? .noVerification) else { return }
        guard pendingWeakenPatch != nil || eraseAwaitingIdentity else { return }
        authenticationScope?.cancel()
        authenticationScope = nil
        let material = await environment.gate.appPasswordMaterialStatus()
        guard AppPasswordPolicyGate.canUseAppPasswordEntry(material: material) else {
            persistError = AppPasswordPolicyGate.ordinaryEntryUnavailableMessage(material: material)
            abandonSettingsCombinationPending()
            return
        }
        combinationNeedsSetup = false
        if pendingWeakenPatch != nil {
            showWeakenPasswordPrompt = true
        }
        if eraseAwaitingIdentity {
            showEraseAppPassword = true
        }
    }

    private func confirmEraseAfterDestructiveDialog() async {
        eraseStatus = ""
        let policy = await currentErasePolicy()
        var trace = eraseFlowTrace
        let command = SettingsEraseAllFlow.afterDestructiveConfirm(
            policy: policy,
            trace: &trace
        )
        eraseFlowTrace = trace
        switch command {
        case .promptAppPassword:
            eraseAwaitingIdentity = true
            eraseAppPasswordInput = ""
            showEraseAppPassword = true
        case .erase(let password):
            eraseAwaitingIdentity = true
            await performErase(appPassword: password)
        case .none:
            return
        }
    }

    private func submitEraseAppPassword(_ password: String) async {
        var trace = eraseFlowTrace
        let command = SettingsEraseAllFlow.afterAppPasswordEntry(password, trace: &trace)
        eraseFlowTrace = trace
        switch command {
        case .erase(let value):
            await performErase(appPassword: value)
        case .none, .promptAppPassword:
            return
        }
    }

    private func performErase(appPassword: String?) async {
        var trace = eraseFlowTrace
        SettingsEraseAllFlow.noteEraseStarted(trace: &trace)
        eraseFlowTrace = trace
        do {
            if combinationNeedsSetup {
                persistError = AppPasswordPolicyGate.ordinaryEntryMissingMaterialMessage()
                eraseAwaitingIdentity = false
                return
            }
            try await performWithPageAuthenticationScope {
                try await environment.dataLifecycle.eraseAllUserData(appPassword: appPassword)
            }
            eraseStatus = String(localized: "settings.eraseAll.done")
            eraseAwaitingIdentity = false
            await reload()
            await refreshMasterPasswordStatus()
            await refreshBackupPassphraseStatus()
            await refreshEntitlementTier()
            await environment.refreshAppearance()
        } catch let error as ApiRelayError where SettingsEraseAllFlow.isPasswordPrompt(error) {
            showEraseAppPassword = true
        } catch let error as ApiRelayError
            where CombinationExplicitAuth.shouldOfferAppPassword(after: error)
        {
            var offerTrace = eraseFlowTrace
            let command = SettingsEraseAllFlow.afterCombinationBiometricEnded(trace: &offerTrace)
            eraseFlowTrace = offerTrace
            if command == .promptAppPassword {
                eraseAwaitingIdentity = true
            }
        } catch ApiRelayError.authenticationCancelled {
            eraseAwaitingIdentity = false
            return
        } catch {
            eraseStatus = error.localizedDescription
            eraseAwaitingIdentity = false
        }
    }

    private func currentErasePolicy() async -> RevealPolicy {
        if let loaded = try? await environment.preferences.load() {
            return loaded.revealPolicy
        }
        return prefs?.revealPolicy ?? .biometricOrPasscode
    }

    /// 只用于本机 `DevicePreferences`（外观 / 默认视角 / 指派筛选），不经 CloudKit，故可直接 `await`。
    /// 三个调用点都已先改内存，这里 MUST NOT 再 `reload`：那会顺带用旧值盖掉尚未落盘的同步开关。
    private func save(_ patch: PreferencesPatch) async {
        try? await environment.preferences.update(patch)
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
        masterPasswordMaterial = await environment.masterPassword.materialStatus()
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
            let tier = try await environment.entitlements.restorePurchases()
            entitlementTier = tier
            restoreStatus = tier == .free
                ? String(localized: "settings.restorePurchases.none")
                : String(localized: "settings.restorePurchases.done")
        } catch {
            restoreStatus = error.localizedDescription
        }
    }

    private func performWithPageAuthenticationScope<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let scope = AuthenticationRequestScope()
        authenticationScope?.cancel()
        authenticationScope = scope
        defer {
            if authenticationScope === scope { authenticationScope = nil }
        }
        return try await scope.perform(operation)
    }
}

// MARK: - Reveal policy

private enum RevealPolicyDisplayName {
    static func deviceTitle(
        biometry: BiometryKind,
        isMac: Bool
    ) -> LocalizedStringKey {
        "settings.policy.deviceVerification"
    }

    static func summary(
        _ policy: RevealPolicy,
        biometry: BiometryKind,
        isMac: Bool
    ) -> String {
        switch policy {
        case .biometricOrPasscode:
            return String(localized: "settings.policy.deviceVerification")
        case .masterPassword:
            return String(localized: "settings.policy.masterPassword")
        case .noVerification:
            return String(localized: "settings.policy.none")
        case .biometryOrAppPassword:
            return String(localized: "settings.policy.biometryOrAppPassword")
        }
    }
}

private struct RevealPolicySettingsView: View {
    let environment: AppEnvironment
    let currentPolicy: RevealPolicy
    /// 设备验证 / 不验证：上层改内存并 persist。密码依赖档不走这里。
    let applyPolicy: (RevealPolicy) async -> Void
    /// 应用密码页自己 persist 成功后刷新摘要，MUST NOT 再 applyPolicy 以免二次确认或写错目标。
    let onAppPasswordCommitted: () async -> Void

    @State private var goAppPasswordPage = false
    @State private var pendingTarget: RevealPolicy = .masterPassword
    @State private var highlightedPolicy: RevealPolicy
    /// Navigation destinations may retain the value captured when this page was
    /// first pushed. Keep the policy used by the next authentication flow in
    /// step with the authoritative persisted value, not just the visible checkmark.
    @State private var effectiveCurrentPolicy: RevealPolicy

    init(
        environment: AppEnvironment,
        currentPolicy: RevealPolicy,
        applyPolicy: @escaping (RevealPolicy) async -> Void,
        onAppPasswordCommitted: @escaping () async -> Void
    ) {
        self.environment = environment
        self.currentPolicy = currentPolicy
        self.applyPolicy = applyPolicy
        self.onAppPasswordCommitted = onAppPasswordCommitted
        _highlightedPolicy = State(initialValue: currentPolicy)
        _effectiveCurrentPolicy = State(initialValue: currentPolicy)
    }

    var body: some View {
        SettingsSubpage(title: "settings.revealPolicy") {
            SettingsCard {
                policyRow(
                    .biometricOrPasscode,
                    title: RevealPolicyDisplayName.deviceTitle(
                        biometry: environment.gate.availableBiometry(),
                        isMac: SettingsChrome.isMacDesktop
                    ),
                    detail: "settings.policy.biometricOrPasscode.detail",
                    subtitle: "settings.policy.recommended"
                )
                SettingsCardDivider()
                policyRow(
                    .masterPassword,
                    title: "settings.policy.masterPassword",
                    detail: "settings.policy.masterPassword.detail"
                )
                SettingsCardDivider()
                policyRow(
                    .biometryOrAppPassword,
                    title: "settings.policy.biometryOrAppPassword",
                    detail: "settings.policy.biometryOrAppPassword.detail"
                )
                SettingsCardDivider()
                policyRow(
                    .noVerification,
                    title: "settings.policy.none",
                    detail: "settings.policy.none.detail"
                )
            }
        }
        .navigationDestination(isPresented: $goAppPasswordPage) {
            MasterPasswordSettingsView(
                environment: environment,
                target: pendingTarget,
                currentPolicy: effectiveCurrentPolicy,
                onCommitted: {
                    await onAppPasswordCommitted()
                    await refreshHighlightedPolicyFromPersistence()
                }
            )
        }
        .task {
            await refreshHighlightedPolicyFromPersistence()
        }
        .onReceive(NotificationCenter.default.publisher(for: .securityPreferencesDidPersist)) { _ in
            // 降低安全等级只允许在持久化成功后改变可见选中项。
            // NavigationLink 的 destination 会保留首次构造值，因此不能只依赖
            // 上一级页面重建；当前页直接从唯一持久化来源回读。
            Task { await refreshHighlightedPolicyFromPersistence() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .securityPreferencesPersistFailed)) { _ in
            Task { await refreshHighlightedPolicyFromPersistence() }
        }
        .onChange(of: currentPolicy) { _, newValue in
            highlightedPolicy = newValue
            effectiveCurrentPolicy = newValue
        }
    }

    private func policyRow(
        _ value: RevealPolicy,
        title: LocalizedStringKey,
        detail: LocalizedStringResource,
        subtitle: LocalizedStringKey? = nil
    ) -> some View {
        SettingsChoiceRow(
            title: title,
            selected: highlightedPolicy == value,
            subtitle: subtitle,
            helpTitle: title,
            helpMessage: detail
        ) {
            Task { await selectPolicy(value) }
        }
    }

    /// 两种密码依赖档都进入同一页并绑定原目标；进入本身不改当前策略。
    private func selectPolicy(_ value: RevealPolicy) async {
        switch AppPasswordSettingsRouting.destination(selected: value) {
        case .appPasswordPage(let target):
            pendingTarget = target
            goAppPasswordPage = true
        case .persistPolicy(let policy):
            await applyPolicy(policy)
        }
    }

    @MainActor
    private func refreshHighlightedPolicyFromPersistence() async {
        guard let stored = try? await environment.preferences.load() else { return }
        let persistedPolicy = RevealPolicyPersistence.canonical(stored.revealPolicy)
        highlightedPolicy = persistedPolicy
        effectiveCurrentPolicy = persistedPolicy
    }
}

// MARK: - App password

private struct MasterPasswordSettingsView: View {
    let environment: AppEnvironment
    let target: RevealPolicy
    let currentPolicy: RevealPolicy
    let onCommitted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var lease: AppPasswordPageLease
    @State private var currentPassword = ""
    @State private var combinationAppPassword = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var isSaving = false
    @State private var material: AppPasswordMaterialStatus?
    @State private var showSuccessAlert = false
    @State private var showFailureAlert = false
    @State private var showResetDoneAlert = false
    @State private var failureReason = ""
    @State private var didAttemptSave = false
    @State private var successMessage = ""
    @State private var showsPasswordChangeForm = false
    @State private var authenticationScope: AuthenticationRequestScope?

    init(
        environment: AppEnvironment,
        target: RevealPolicy,
        currentPolicy: RevealPolicy,
        onCommitted: @escaping () async -> Void
    ) {
        self.environment = environment
        self.target = target
        self.currentPolicy = currentPolicy
        self.onCommitted = onCommitted
        _lease = State(initialValue: AppPasswordPageLease(target: target, currentPolicy: currentPolicy))
    }

    private var surface: AppPasswordPageSurface {
        AppPasswordPageSurface(
            target: target,
            currentPolicy: currentPolicy,
            material: material
        )
    }

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

    var body: some View {
        SettingsSubpage(title: "settings.masterPassword") {
            if surface.showsLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            if surface.showsUnreadableBanner {
                SettingsStatusBanner(
                    text: String(localized: "settings.appPassword.status.unreadable"),
                    isError: true
                )
            }
            if surface.showsRetry {
                SettingsPrimaryButton(title: "settings.appPassword.retry", disabled: isSaving) {
                    Task { await reloadMaterial() }
                }
            }

            if surface.showsSetStatus {
                SettingsStatusBanner(
                    text: String(localized: "settings.masterPassword.status.set"),
                    isError: false
                )
            }
            if !successMessage.isEmpty {
                SettingsStatusBanner(text: successMessage, isError: false)
            }
            if surface.showsChangePassword {
                Button {
                    showsPasswordChangeForm.toggle()
                    currentPassword = ""
                    password = ""
                    confirm = ""
                    didAttemptSave = false
                } label: {
                    Label(String(localized: "settings.appPassword.change"), systemImage: "pencil")
                }
                .disabled(isSaving)
            }

            if surface.showsKeepExisting && !showsPasswordChangeForm {
                if surface.showsCurrentMasterPasswordField {
                    SettingsCard {
                        SettingsSecureField(
                            title: "settings.masterPassword.current",
                            text: $currentPassword
                        )
                    }
                }
                if surface.showsComboExplicitPasswordField {
                    SettingsCard {
                        SettingsSecureField(
                            title: "settings.masterPassword.current",
                            text: $combinationAppPassword
                        )
                    }
                }
                SettingsPrimaryButton(
                    title: "settings.appPassword.keepExisting",
                    disabled: isSaving
                ) {
                    Task { await keepExistingAndContinue(prefersCombinationAppPassword: false) }
                }
                if surface.showsComboExplicitPasswordField {
                    SettingsPrimaryButton(
                        title: "appLock.useAppPassword",
                        disabled: isSaving
                    ) {
                        Task { await keepExistingAndContinue(prefersCombinationAppPassword: true) }
                    }
                }
            }

            if surface.showsCreateForm || (surface.showsChangePassword && showsPasswordChangeForm) {
                SettingsCard {
                    if surface.showsChangePassword {
                        SettingsSecureField(title: "settings.masterPassword.current", text: $currentPassword)
                        SettingsCardDivider()
                    }
                    SettingsSecureField(
                        title: "vault.masterPassword",
                        text: $password,
                        role: .newCredential
                    )
                    SettingsCardDivider()
                    SettingsSecureField(
                        title: "settings.masterPassword.confirm",
                        text: $confirm,
                        role: .newCredential
                    )
                }

                MasterPasswordRulesList(
                    evaluation: evaluation,
                    highlightUnmet: highlightUnmetRules
                )
                if highlightUnmetRules {
                    SettingsStatusBanner(text: unmetRulesSummary, isError: true)
                }
                SettingsPrimaryButton(
                    title: "settings.masterPassword.save",
                    disabled: isSaving
                ) {
                    Task { await save() }
                }
            }

            SettingsFooterNote(text: "vault.masterPassword.disclosure")
            if surface.showsCreateForm {
                SettingsFooterNote(text: "settings.policy.masterPassword.setupHint")
            }

            if surface.showsRecover {
                SettingsCard {
                    Button(role: .destructive) {
                        Task { await reset() }
                    } label: {
                        Text("settings.appPassword.recover")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    .disabled(isSaving)
                }
            }
        }
        .overlay {
            if isSaving { ProgressView() }
        }
        .task {
            await reloadMaterial()
        }
        .onChange(of: currentPolicy) { _, newValue in
            handleCurrentPolicyChange(newValue)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                clearSensitiveInputs()
            }
            // The system authentication sheet transiently deactivates our scene.
            // Real backgrounding still revokes the request and all write authority.
            if phase == .inactive && environment.gate.isAuthenticationInProgress() {
                lease.noteSceneActive(false)
                return
            }
            lease.noteSceneActive(phase == .active)
            if phase != .active {
                abandonPageRequest()
            }
        }
        .onReceive(environment.appPrivacy.$session) { session in
            if session.isSessionLocked {
                abandonPageRequest()
            }
        }
        .onDisappear {
            abandonPageRequest()
        }
        .alert("settings.masterPassword.saveSuccess.title", isPresented: $showSuccessAlert) {
            Button("settings.done", role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .alert("settings.masterPassword.saveFailed.title", isPresented: $showFailureAlert) {
            Button("settings.done", role: .cancel) {}
        } message: {
            Text(failureReason)
        }
        .alert("settings.masterPassword.resetDone", isPresented: $showResetDoneAlert) {
            Button("settings.done") {
                dismiss()
            }
        }
    }

    private func handleCurrentPolicyChange(_ newValue: RevealPolicy) {
        if RevealPolicyPersistence.canonical(newValue) == RevealPolicyPersistence.canonical(target) {
            lease.noteOpenedPolicy(newValue)
            return
        }
        if !lease.matchesOpenedPolicy(newValue) {
            abandonPageRequest(newCurrentPolicy: newValue)
        }
    }

    private func abandonPageRequest(newCurrentPolicy: RevealPolicy? = nil) {
        lease.invalidate(newCurrentPolicy: newCurrentPolicy)
        authenticationScope?.cancel()
        authenticationScope = nil
        clearSensitiveInputs()
        isSaving = false
    }

    private func clearSensitiveInputs() {
        currentPassword = ""
        combinationAppPassword = ""
        password = ""
        confirm = ""
    }

    private func reloadMaterial() async {
        material = await environment.masterPassword.materialStatus()
    }

    private func beginPageRequest() -> UInt64? {
        lease.noteSceneActive(scenePhase == .active)
        guard scenePhase == .active, !isSaving else { return nil }
        return lease.begin()
    }

    private func makeConfirmCurrent(
        token: UInt64,
        currentPassword: String,
        combinationAppPassword: String?,
        prefersCombinationAppPassword: Bool
    ) -> @Sendable () async throws -> Void {
        let lease = self.lease
        let gate = environment.gate
        let master = environment.masterPassword
        let policy = currentPolicy
        return {
            try lease.authorize(token, step: .proceed, currentPolicy: policy)
            try await AppPasswordSettingsFlow.confirmCurrent(
                gate: gate,
                master: master,
                currentPolicy: policy,
                currentPassword: currentPassword,
                combinationAppPassword: combinationAppPassword,
                prefersCombinationAppPassword: prefersCombinationAppPassword
            )
            try lease.authorize(token, step: .proceed, currentPolicy: policy)
        }
    }

    private func finishPageRequest(
        _ token: UInt64,
        showSuccess: Bool,
        success: String?,
        showReset: Bool,
        failure: String?
    ) {
        let stillFresh = lease.isFresh(token, sceneActive: scenePhase == .active)
        lease.end(token)
        guard stillFresh else { return }
        if let success, showSuccess {
            successMessage = success
            showSuccessAlert = true
        }
        if showReset {
            showResetDoneAlert = true
        }
        if let failure {
            failureReason = failure
            showFailureAlert = true
        }
    }

    private func keepExistingAndContinue(prefersCombinationAppPassword: Bool) async {
        guard let token = beginPageRequest() else { return }
        isSaving = true
        defer { isSaving = false }
        let currentPW = currentPassword
        let comboPW = combinationAppPassword
        clearSensitiveInputs()
        do {
            try await performWithPageAuthenticationScope {
                try await environment.persistPasswordDependentPolicyKeepingMaterial(
                    target: target,
                    request: AppPasswordSubmitContext(lease: lease, token: token),
                    confirmCurrentIfNeeded: makeConfirmCurrent(
                        token: token,
                        currentPassword: currentPW,
                        combinationAppPassword: comboPW,
                        prefersCombinationAppPassword: prefersCombinationAppPassword
                    )
                )
            }
            await reloadMaterial()
            await onCommitted()
            finishPageRequest(
                token,
                showSuccess: true,
                success: String(localized: "settings.masterPassword.saved"),
                showReset: false,
                failure: nil
            )
        } catch ApiRelayError.authenticationCancelled {
            lease.end(token)
        } catch {
            await reloadMaterial()
            await onCommitted()
            finishPageRequest(
                token,
                showSuccess: false,
                success: nil,
                showReset: false,
                failure: staleOrLocalized(error)
            )
        }
    }

    private func save() async {
        successMessage = ""
        didAttemptSave = true
        if surface.showsCreateForm || surface.showsChangePassword {
            guard evaluation.canSave else { return }
        }
        guard let token = beginPageRequest() else { return }
        isSaving = true
        defer { isSaving = false }
        let currentPW = currentPassword
        let comboPW = combinationAppPassword
        let newPassword = password
        clearSensitiveInputs()
        do {
            if surface.showsChangePassword {
                try lease.requireFreshForConfirm(
                    token,
                    currentPolicy: currentPolicy,
                    sceneActive: scenePhase == .active
                )
                try await performWithPageAuthenticationScope {
                    try await environment.changeAppPassword(
                        current: currentPW,
                        new: newPassword,
                        request: AppPasswordSubmitContext(lease: lease, token: token)
                    )
                }
                showsPasswordChangeForm = false
                didAttemptSave = false
                await reloadMaterial()
                await onCommitted()
                finishPageRequest(
                    token,
                    showSuccess: true,
                    success: String(localized: "settings.masterPassword.saved"),
                    showReset: false,
                    failure: nil
                )
                return
            }
            try await performWithPageAuthenticationScope {
                try await environment.createAppPasswordMaterialThenPersist(
                    password: newPassword,
                    target: target,
                    request: AppPasswordSubmitContext(lease: lease, token: token),
                    confirmCurrentIfNeeded: makeConfirmCurrent(
                        token: token,
                        currentPassword: currentPW,
                        combinationAppPassword: comboPW,
                        prefersCombinationAppPassword: false
                    )
                )
            }
            didAttemptSave = false
            await reloadMaterial()
            await onCommitted()
            finishPageRequest(
                token,
                showSuccess: true,
                success: String(localized: "settings.appPassword.saveSuccess.create"),
                showReset: false,
                failure: nil
            )
        } catch ApiRelayError.authenticationCancelled {
            await reloadMaterial()
            finishPageRequest(
                token,
                showSuccess: false,
                success: nil,
                showReset: false,
                failure: String(localized: "settings.appPassword.saveCancelled")
            )
        } catch let ApiRelayError.validationFailed(_, reason) where reason == "too_short" {
            lease.end(token)
            didAttemptSave = true
        } catch {
            await reloadMaterial()
            await onCommitted()
            let message: String
            if material == .set,
               RevealPolicyPersistence.canonical(currentPolicy) != RevealPolicyPersistence.canonical(target)
            {
                message = String(localized: "settings.appPassword.partialPersist")
            } else {
                message = staleOrLocalized(error)
            }
            finishPageRequest(
                token,
                showSuccess: false,
                success: nil,
                showReset: false,
                failure: message
            )
        }
    }

    private func reset() async {
        guard let token = beginPageRequest() else { return }
        clearSensitiveInputs()
        isSaving = true
        defer { isSaving = false }
        do {
            try lease.authorize(
                token,
                step: .proceed,
                currentPolicy: currentPolicy
            )
            try await performWithPageAuthenticationScope {
                try await environment.resetAppPasswordAndFallToDeviceAuth(
                    request: AppPasswordSubmitContext(lease: lease, token: token)
                )
            }
            password = ""
            confirm = ""
            currentPassword = ""
            combinationAppPassword = ""
            didAttemptSave = false
            await reloadMaterial()
            await onCommitted()
            finishPageRequest(
                token,
                showSuccess: false,
                success: nil,
                showReset: true,
                failure: nil
            )
        } catch ApiRelayError.authenticationCancelled {
            lease.end(token)
        } catch {
            await reloadMaterial()
            await onCommitted()
            finishPageRequest(
                token,
                showSuccess: false,
                success: nil,
                showReset: false,
                failure: staleOrLocalized(error)
            )
        }
    }

    private func staleOrLocalized(_ error: Error) -> String {
        if case ApiRelayError.validationFailed(_, let reason) = error, reason == "stale_page_request" {
            return String(localized: "settings.appPassword.requestExpired")
        }
        return error.localizedDescription
    }

    private func performWithPageAuthenticationScope<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let scope = AuthenticationRequestScope()
        authenticationScope?.cancel()
        authenticationScope = scope
        defer {
            if authenticationScope === scope { authenticationScope = nil }
        }
        return try await scope.perform(operation)
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
        } catch {
            alreadyOwned = false
        }

        do {
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
            let tier = try await environment.entitlements.purchaseUnlimitedKeys()
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
            let tier = try await environment.entitlements.restorePurchases()
            alreadyOwned = (tier == .unlimitedKeys || tier == .relay)
            message = alreadyOwned
                ? String(localized: "paywall.restored")
                : String(localized: "paywall.restore.none")
        } catch {
            message = error.localizedDescription
        }
    }
}

/// 清空全部数据的界面顺序。设置页必须走这里；测试可直接驱动，观察
/// 「破坏性确认 → 身份验证 → 删除」且应用密码档在口令前不得调用删除。
enum SettingsEraseAllFlow: Sendable {
    enum Command: Equatable, Sendable {
        case none
        case promptAppPassword
        case erase(appPassword: String?)
    }

    struct Trace: Equatable, Sendable {
        var steps: [String] = []
    }

    static func isPasswordPrompt(_ error: ApiRelayError) -> Bool {
        if case .validationFailed(_, let reason) = error {
            return reason == "master_password_prompt_required" || reason == "required"
        }
        return false
    }

    static func afterDestructiveConfirm(
        policy: RevealPolicy,
        trace: inout Trace
    ) -> Command {
        trace.steps.append("destructiveConfirmed")
        switch RevealPolicyPersistence.canonical(policy) {
        case .masterPassword:
            trace.steps.append("identityPrompt")
            return .promptAppPassword
        case .noVerification, .biometricOrPasscode, .biometryOrAppPassword:
            trace.steps.append("identityStarted")
            return .erase(appPassword: nil)
        }
    }

    static func afterCombinationBiometricEnded(trace: inout Trace) -> Command {
        trace.steps.append("combinationOffer")
        return .promptAppPassword
    }

    static func afterAppPasswordEntry(_ password: String, trace: inout Trace) -> Command {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            trace.steps.append("identityRejected.empty")
            return .none
        }
        trace.steps.append("identityStarted")
        return .erase(appPassword: trimmed)
    }

    static func afterAppPasswordCancel(trace: inout Trace) -> Command {
        trace.steps.append("identityCancelled")
        return .none
    }

    static func noteEraseStarted(trace: inout Trace) {
        trace.steps.append("eraseStarted")
    }
}

#if DEBUG
#Preview("Settings") {
    let environment = AppEnvironment.makePreview()
    SettingsView(environment: environment, showsDismissButton: false)
        .environmentObject(environment)
}
#endif
