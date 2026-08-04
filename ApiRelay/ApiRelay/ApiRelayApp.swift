//
//  ApiRelayApp.swift
//  ApiRelay
//

import SwiftUI
import SwiftData

@main
struct ApiRelayApp: App {
    var sharedModelContainer: ModelContainer = {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        do {
            if isTesting {
                return try AppSchema.makeInMemoryContainer()
            }
            return try AppSchema.makeProductionContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
