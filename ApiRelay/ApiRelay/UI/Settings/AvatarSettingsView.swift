import SwiftUI

struct AvatarSettingsView: View {
    let environment: AppEnvironment
    @State private var prefs: PreferencesDTO?

    var body: some View {
        SettingsSubpage(title: "settings.avatars") {
            if let prefs {
                SettingsCard(title: "settings.avatars.key") {
                    avatarEditor(
                        choice: AvatarChoice.parse(
                            symbol: prefs.defaultKeyAvatarSymbol,
                            color: prefs.defaultKeyAvatarColor
                        ) ?? .key,
                        builtIn: .key
                    ) { next in
                        persistKey(next)
                    }
                }
                SettingsFooterNote(text: "settings.avatars.key.footer")

                SettingsCard(title: "settings.avatars.account") {
                    avatarEditor(
                        choice: AvatarChoice.parse(
                            symbol: prefs.defaultCustomAccountAvatarSymbol,
                            color: prefs.defaultCustomAccountAvatarColor
                        ) ?? .customAccount,
                        builtIn: .customAccount
                    ) { next in
                        persistAccount(next)
                    }
                }
                SettingsFooterNote(text: "settings.avatars.account.footer")

                SettingsCard(title: "settings.avatars.tool") {
                    avatarEditor(
                        choice: AvatarChoice.parse(
                            symbol: prefs.defaultCustomToolAvatarSymbol,
                            color: prefs.defaultCustomToolAvatarColor
                        ) ?? .customTool,
                        builtIn: .customTool
                    ) { next in
                        persistTool(next)
                    }
                }
                SettingsFooterNote(text: "settings.avatars.tool.footer")
            }
        }
        .task { await reload() }
    }

    private func avatarEditor(
        choice: AvatarChoice,
        builtIn: AvatarChoice,
        onChange: @escaping (AvatarChoice?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VaultAvatarView(choice: choice, size: 36, cornerRadius: 8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            AvatarPicker(
                choice: Binding(
                    get: { choice },
                    set: { onChange($0) }
                )
            )
            .padding(.horizontal, 16)
            if choice != builtIn {
                Button("settings.avatars.restore") {
                    onChange(nil)
                }
                .padding(.horizontal, 16)
            }
            Color.clear.frame(height: 8)
        }
    }

    private func persistKey(_ choice: AvatarChoice?) {
        var patch = PreferencesPatch()
        patch.defaultKeyAvatarSymbol = choice?.symbol ?? ""
        patch.defaultKeyAvatarColor = choice?.color.rawValue ?? ""
        apply(patch) { prefs in
            prefs.defaultKeyAvatarSymbol = choice?.symbol
            prefs.defaultKeyAvatarColor = choice?.color.rawValue
        }
    }

    private func persistAccount(_ choice: AvatarChoice?) {
        var patch = PreferencesPatch()
        patch.defaultCustomAccountAvatarSymbol = choice?.symbol ?? ""
        patch.defaultCustomAccountAvatarColor = choice?.color.rawValue ?? ""
        apply(patch) { prefs in
            prefs.defaultCustomAccountAvatarSymbol = choice?.symbol
            prefs.defaultCustomAccountAvatarColor = choice?.color.rawValue
        }
    }

    private func persistTool(_ choice: AvatarChoice?) {
        var patch = PreferencesPatch()
        patch.defaultCustomToolAvatarSymbol = choice?.symbol ?? ""
        patch.defaultCustomToolAvatarColor = choice?.color.rawValue ?? ""
        apply(patch) { prefs in
            prefs.defaultCustomToolAvatarSymbol = choice?.symbol
            prefs.defaultCustomToolAvatarColor = choice?.color.rawValue
        }
    }

    private func apply(_ patch: PreferencesPatch, mutate: (inout PreferencesDTO) -> Void) {
        if var current = prefs {
            mutate(&current)
            prefs = current
        }
        environment.preferences.persist(patch)
    }

    private func reload() async {
        prefs = try? await environment.preferences.load()
    }
}
