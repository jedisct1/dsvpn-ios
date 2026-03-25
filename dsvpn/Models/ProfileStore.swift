// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation

class ProfileStore: ObservableObject {
    @Published var profiles: [VPNProfile] = []
    @Published var selectedID: UUID?

    init() {
        let loaded = VPNProfile.loadAll()
        let loadedID = VPNProfile.loadSelectedID()
        profiles = loaded
        if let id = loadedID, loaded.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = loaded.first?.id
        }
    }

    var selectedProfile: VPNProfile? {
        guard let id = selectedID else { return nil }
        return profiles.first { $0.id == id }
    }

    func add(_ profile: VPNProfile) {
        profiles.append(profile)
        if selectedID == nil {
            selectedID = profile.id
        }
        save()
    }

    func update(_ profile: VPNProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    func delete(_ profile: VPNProfile) {
        profiles.removeAll { $0.id == profile.id }
        KeyStorage.delete(for: profile.id)
        if selectedID == profile.id {
            selectedID = profiles.first?.id
        }
        save()
    }

    func markConnected(_ id: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].lastConnected = Date()
        save()
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
        VPNProfile.saveSelectedID(id)
    }

    private func save() {
        VPNProfile.saveAll(profiles)
        VPNProfile.saveSelectedID(selectedID)
    }
}
