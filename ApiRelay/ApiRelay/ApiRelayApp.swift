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
        }
        .modelContainer(environment.modelContainer)
    }
}
