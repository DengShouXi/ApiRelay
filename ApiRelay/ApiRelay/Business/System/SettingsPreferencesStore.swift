import Foundation

/// The repository owns committed settings; the view may display an optimistic
/// draft until a later repository load confirms or rolls it back. A reload that
/// began before a newer user edit must not replace that edit on completion.
struct SettingsPreferencesStore {
    private(set) var committed: PreferencesDTO?
    private(set) var draft: PreferencesDTO?
    private(set) var revision: UInt64 = 0
    private(set) var draftRevision: UInt64 = 0

    var presented: PreferencesDTO? { draft ?? committed }

    mutating func presentDraft(_ value: PreferencesDTO?) {
        revision &+= 1
        draftRevision &+= 1
        draft = value
    }

    mutating func beginReload() -> UInt64 {
        revision &+= 1
        return revision
    }

    @discardableResult
    mutating func completeReload(_ value: PreferencesDTO?, revision loadedRevision: UInt64) -> Bool {
        guard loadedRevision == revision else { return false }
        committed = value
        draft = nil
        return true
    }
}

/// A settings page may have one sensitive user action awaiting authentication.
/// Erase and a security-policy downgrade must never both own the same prompt.
struct SettingsPendingActionState {
    private enum Action {
        case weaken(PreferencesPatch)
        case erase
    }

    private var action: Action?

    var weakenPatch: PreferencesPatch? {
        guard case .weaken(let patch) = action else { return nil }
        return patch
    }

    var eraseAwaitingIdentity: Bool {
        if case .erase = action { return true }
        return false
    }

    mutating func setWeakenPatch(_ patch: PreferencesPatch?) {
        if let patch {
            action = .weaken(patch)
        } else if case .weaken = action {
            action = nil
        }
    }

    mutating func setEraseAwaitingIdentity(_ awaiting: Bool) {
        if awaiting {
            action = .erase
        } else if case .erase = action {
            action = nil
        }
    }

    mutating func clear() {
        action = nil
    }
}
