//
//  ApiRelayApp.swift
//  ApiRelay
//

import SwiftUI
import SwiftData

@main
struct ApiRelayApp: App {
    @StateObject private var environment = AppEnvironment.bootstrap()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                #if os(macOS) || targetEnvironment(macCatalyst)
                .frame(minWidth: 800, minHeight: 600)
                #endif
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .defaultSize(width: 900, height: 700)
        #endif
        .commands {
            ApiRelayCommands()
        }
        .modelContainer(environment.modelContainer)
    }
}
