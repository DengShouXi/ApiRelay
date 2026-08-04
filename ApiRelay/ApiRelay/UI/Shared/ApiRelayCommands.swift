import SwiftUI

struct ApiRelayCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("settings.title") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Button("vault.key.add") {
                NotificationCenter.default.post(name: .newKey, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("com.apirelay.openSettings")
    static let newKey = Notification.Name("com.apirelay.newKey")
}
