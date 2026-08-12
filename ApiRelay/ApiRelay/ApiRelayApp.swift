//
//  ApiRelayApp.swift
//  ApiRelay
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@main
struct ApiRelayApp: App {
    @StateObject private var environment = AppEnvironment.bootstrap()
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(MacWindowSizingAppDelegate.self) private var macWindowSizing
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                #if os(macOS) || targetEnvironment(macCatalyst)
                .frame(minWidth: 720, minHeight: 480)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .defaultSize(width: 1100, height: 740)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            ApiRelayCommands()
        }
        .modelContainer(environment.modelContainer)
    }
}
