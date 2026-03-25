// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation
import NetworkExtension

@MainActor
class VPNManager: ObservableObject {
    @Published var status: NEVPNStatus = .disconnected
    @Published var connectedDate: Date?
    @Published var lastError: String?
    @Published var lastDisconnect: DisconnectInfo?
    @Published var connectedProfileID: UUID? {
        didSet {
            if connectedProfileID != oldValue {
                Self.persistConnectedProfileID(connectedProfileID)
            }
        }
    }

    private static let connectedProfileKey = "connectedProfileID"

    private(set) var connectionInitiated = false

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    func loadOrCreate() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        dlog("Found \(managers.count) existing VPN managers")

        if let existing = managers.first {
            manager = existing
            dlog("Reusing existing manager, enabled=\(existing.isEnabled)")
        } else {
            dlog("Creating new VPN manager")
            let m = NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "org.pureftpd.ios.dsvpn.tunnel"
            proto.serverAddress = "dsvpn"
            m.protocolConfiguration = proto
            m.localizedDescription = "dsvpn"
            m.isEnabled = true
            try await m.saveToPreferences()
            try await m.loadFromPreferences()
            manager = m
            dlog("Created and saved new manager")
        }

        if let m = manager {
            if !m.isEnabled {
                m.isEnabled = true
                try await m.saveToPreferences()
                try await m.loadFromPreferences()
            }
        }

        // Restore connectedProfileID if tunnel is already active
        if let m = manager {
            let s = m.connection.status
            if s == .connected || s == .connecting || s == .reasserting {
                connectedProfileID = Self.loadConnectedProfileID()
                    ?? VPNProfile.loadSelectedID()
                dlog("Restored connectedProfileID=\(connectedProfileID?.uuidString ?? "nil") for active tunnel")
            }
        }

        if let m = manager {
            let s = m.connection.status
            if s == .disconnected || s == .invalid {
                lastDisconnect = DisconnectInfo.load()
            }
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager?.connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }

        updateStatus()
    }

    func connect() throws {
        guard let manager else {
            dlog("Cannot connect: no manager")
            lastError = "VPN not configured"
            return
        }
        dlog("Starting VPN tunnel, status=\(manager.connection.status.rawValue)")
        lastError = nil
        lastDisconnect = nil
        DisconnectInfo.clear()
        connectionInitiated = true
        do {
            try manager.connection.startVPNTunnel()
            dlog("startVPNTunnel succeeded")
        } catch {
            dlog("startVPNTunnel FAILED: \(error)")
            lastError = error.localizedDescription
            connectionInitiated = false
            throw error
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    func updateConfig(_ config: ServerConfig) async throws {
        guard let manager else { return }
        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
            proto.providerBundleIdentifier = "org.pureftpd.ios.dsvpn.tunnel"
            proto.serverAddress = config.serverAddress
        }
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        dlog("Config updated: server=\(config.serverAddress)")
    }

    private func updateStatus() {
        guard let manager else { return }
        let newStatus = manager.connection.status
        dlog("VPN status: \(newStatus.rawValue)")
        status = newStatus
        if newStatus == .connected || newStatus == .connecting || newStatus == .reasserting {
            if newStatus == .connected {
                connectedDate = connectedDate ?? Date()
            }
            if connectedProfileID == nil {
                connectedProfileID = VPNProfile.loadSelectedID()
                dlog("Inferred connectedProfileID=\(connectedProfileID?.uuidString ?? "nil") from selectedID")
            }
        } else if newStatus == .disconnected || newStatus == .invalid {
            connectedDate = nil
            connectedProfileID = nil
            connectionInitiated = false
            lastDisconnect = DisconnectInfo.load()
        }
    }

    private static func persistConnectedProfileID(_ id: UUID?) {
        guard let defaults = UserDefaults(suiteName: ServerConfig.appGroupID) else { return }
        defaults.set(id?.uuidString, forKey: connectedProfileKey)
    }

    private static func loadConnectedProfileID() -> UUID? {
        guard let defaults = UserDefaults(suiteName: ServerConfig.appGroupID),
              let str = defaults.string(forKey: connectedProfileKey),
              let id = UUID(uuidString: str) else { return nil }
        return id
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
