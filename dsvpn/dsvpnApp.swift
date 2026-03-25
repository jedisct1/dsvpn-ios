// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import SwiftUI

@main
struct dsvpnApp: App {
    @StateObject private var vpnManager = VPNManager()
    @StateObject private var profileStore = ProfileStore()

    var body: some Scene {
        WindowGroup {
            ProfileListView(profileStore: profileStore)
                .environmentObject(vpnManager)
                .task {
                    do {
                        try await vpnManager.loadOrCreate()
                    } catch {
                        vpnManager.lastError = "Setup failed: \(error.localizedDescription)"
                    }
                }
        }
    }
}
