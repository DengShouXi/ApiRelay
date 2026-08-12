import SwiftUI

struct ApiRelayCommands: Commands {
    var body: some Commands {
        // Designed for iPad on Mac builds the menu bar via UIKitMainMenuController.
        // CommandGroup(replacing: .appSettings) throws there and aborts launch
        // (EXC_BREAKPOINT / NSApplication _crashOnException). Skip customization
        // for that runtime; iPhone/iPad + Mac Catalyst keep the shortcuts.
        if ProcessInfo.processInfo.isiOSAppOnMac {
            EmptyCommands()
        } else {
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
}

extension Notification.Name {
    static let openSettings = Notification.Name("com.apirelay.openSettings")
    static let newKey = Notification.Name("com.apirelay.newKey")
}
