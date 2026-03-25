// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation

struct VPNProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var serverConfig: ServerConfig
    var lastConnected: Date?

    init(id: UUID = UUID(), name: String, serverConfig: ServerConfig, lastConnected: Date? = nil) {
        self.id = id
        self.name = name
        self.serverConfig = serverConfig
        self.lastConnected = lastConnected
    }

    static let storageKey = "vpnProfiles"
    static let selectedKey = "selectedProfileID"

    private static let defaults = UserDefaults(suiteName: ServerConfig.appGroupID)

    static func loadAll() -> [VPNProfile] {
        guard let data = defaults?.data(forKey: storageKey),
              let profiles = try? JSONDecoder().decode([VPNProfile].self, from: data)
        else {
            return []
        }
        return profiles
    }

    static func saveAll(_ profiles: [VPNProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults?.set(data, forKey: storageKey)
    }

    static func loadSelectedID() -> UUID? {
        guard let str = defaults?.string(forKey: selectedKey),
              let id = UUID(uuidString: str) else { return nil }
        return id
    }

    static func saveSelectedID(_ id: UUID?) {
        defaults?.set(id?.uuidString, forKey: selectedKey)
    }
}
