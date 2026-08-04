import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var prefs: PreferencesDTO?
    @State private var masterPassword = ""
    @State private var backupPassphrase = ""
    @State private var status = ""
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            Form {
                if let prefs {
                    Section("settings.security") {
                        Toggle("settings.appLock", isOn: binding(\.appLockEnabled, prefs.appLockEnabled))
                        Picker("settings.revealPolicy", selection: Binding(
                            get: { prefs.revealPolicy },
                            set: { value in Task { await save(PreferencesPatch(revealPolicy: value)) } }
                        )) {
                            Text("settings.policy.biometricOrPasscode").tag(RevealPolicy.biometricOrPasscode)
                            biometryOnlyRow
                            Text("settings.policy.masterPassword").tag(RevealPolicy.masterPassword)
                            Text("settings.policy.none").tag(RevealPolicy.none)
                        }
                        Stepper(
                            "settings.clipboardSeconds \(prefs.clipboardClearSeconds)",
                            value: Binding(
                                get: { prefs.clipboardClearSeconds },
                                set: { v in Task { await save(PreferencesPatch(clipboardClearSeconds: v)) } }
                            ),
                            in: 30...600,
                            step: 30
                        )
                        Toggle("settings.clipboardLocalOnly", isOn: binding(\.clipboardLocalOnly, prefs.clipboardLocalOnly))
                        Toggle("settings.hideInAppSwitcher", isOn: binding(\.hideInAppSwitcher, prefs.hideInAppSwitcher))
                        Stepper(
                            "settings.autoLock \(prefs.autoLockSeconds)",
                            value: Binding(
                                get: { prefs.autoLockSeconds },
                                set: { v in Task { await save(PreferencesPatch(autoLockSeconds: v)) } }
                            ),
                            in: 0...600,
                            step: 30
                        )
                    }

                    Section("settings.appearance") {
                        Picker("settings.appearance", selection: Binding(
                            get: { prefs.appearance },
                            set: { v in Task { await save(PreferencesPatch(appearance: v)) } }
                        )) {
                            Text("settings.appearance.system").tag(AppearancePreference.system)
                            Text("settings.appearance.light").tag(AppearancePreference.light)
                            Text("settings.appearance.dark").tag(AppearancePreference.dark)
                        }
                        Picker("settings.defaultGrouping", selection: Binding(
                            get: { prefs.defaultGrouping },
                            set: { v in Task { await save(PreferencesPatch(defaultGrouping: v)) } }
                        )) {
                            Text("vault.grouping.platform").tag(GroupingMode.byPlatform)
                            Text("vault.grouping.consumer").tag(GroupingMode.byConsumer)
                        }
                    }
                }

                Section("settings.masterPassword") {
                    SecureField("vault.masterPassword", text: $masterPassword)
                    Button("settings.masterPassword.set") {
                        Task {
                            try? await environment.masterPassword.setPassword(masterPassword)
                            masterPassword = ""
                            status = String(localized: "settings.masterPassword.saved")
                        }
                    }
                    Button("settings.masterPassword.reset", role: .destructive) {
                        Task {
                            try? await environment.gate.confirmMandatory(
                                reason: String(localized: "gate.resetMasterPassword")
                            )
                            try? await environment.masterPassword.reset()
                            status = String(localized: "settings.masterPassword.resetDone")
                        }
                    }
                    Text("vault.masterPassword.disclosure")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("settings.backup") {
                    SecureField("settings.backup.passphrase", text: $backupPassphrase)
                    Button("settings.backup.export") {
                        Task {
                            do {
                                _ = try await environment.backups.exportBackup(
                                    passphrase: backupPassphrase,
                                    purpose: .fullBackup
                                )
                                status = String(localized: "settings.backup.exported")
                            } catch {
                                status = error.localizedDescription
                            }
                        }
                    }
                }

                Section {
                    Button("settings.eraseAll", role: .destructive) {
                        confirmErase = true
                    }
                }

                if !status.isEmpty {
                    Text(status).font(.footnote)
                }
            }
            .navigationTitle("settings.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("gate.cancel") { dismiss() }
                }
            }
            .task { await reload() }
            .confirmationDialog("settings.eraseAll.confirm", isPresented: $confirmErase) {
                Button("settings.eraseAll", role: .destructive) {
                    Task {
                        try? await environment.dataLifecycle.eraseAllUserData()
                        status = String(localized: "settings.eraseAll.done")
                    }
                }
            } message: {
                Text("settings.eraseAll.message")
            }
        }
    }

    @ViewBuilder
    private var biometryOnlyRow: some View {
        switch environment.gate.availableBiometry() {
        case .faceID:
            Text("settings.policy.faceID").tag(RevealPolicy.biometricOnly)
        case .touchID:
            Text("settings.policy.touchID").tag(RevealPolicy.biometricOnly)
        case .none:
            Text("settings.policy.biometricOnly.unavailable")
                .foregroundStyle(.secondary)
        }
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
    }

    private func reload() async {
        prefs = try? await environment.preferences.load()
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
