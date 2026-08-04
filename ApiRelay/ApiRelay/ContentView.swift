//
//  ContentView.swift
//  ApiRelay
//
//  Phase 2 占位：正式 Vault UI 在 Phase 3。
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "ApiRelay",
                systemImage: "key.fill",
                description: Text("vault.placeholder.description")
            )
        }
    }
}

#Preview {
    ContentView()
}
