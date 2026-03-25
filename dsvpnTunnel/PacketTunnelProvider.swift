// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var tunnelConnection: TunnelConnection?
    private var currentProfileID: UUID?

    override func startTunnel(options _: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void)
    {
        dlog("startTunnel called")

        let selectedID = VPNProfile.loadSelectedID()
        currentProfileID = selectedID
        let (config, key) = loadConfigAndKey(profileID: selectedID)
        guard let config, !config.serverAddress.isEmpty else {
            dlog("ERROR: No configuration found")
            completionHandler(DSVPNError.missingConfiguration)
            return
        }
        dlog("Config loaded: server=\(config.serverAddress):\(config.serverPort)")

        guard let key else {
            dlog("ERROR: No key found in Keychain")
            completionHandler(DSVPNError.missingKey)
            return
        }
        dlog("Key loaded (\(key.count) bytes)")

        Task {
            do {
                let conn = TunnelConnection(
                    serverHost: config.serverAddress,
                    serverPort: config.serverPort,
                    key: key,
                    packetFlow: self.packetFlow
                )
                conn.profileID = selectedID
                await MainActor.run { self.tunnelConnection = conn }

                conn.onReconnectExhausted = { [weak self] in
                    dlog("Reconnect exhausted — cancelling tunnel")
                    self?.cancelTunnelWithError(DSVPNError.reconnectExhausted)
                }
                conn.onResolvedIPChanged = { [weak self] newIP in
                    guard let self else { return }
                    dlog("Updating tunnel settings for new server IP \(newIP)")
                    self.configureTunnelCB(config: config, resolvedServerIP: newIP) { error in
                        if let error {
                            dlog("Failed to update tunnel settings: \(error)")
                        }
                    }
                }

                try await conn.connectAndHandshake()
                DisconnectInfo.clear()
                dlog("Connected and handshake done")
                let resolvedIP = conn.resolvedServerIP ?? config.serverAddress
                dlog("Resolved IP: \(resolvedIP)")

                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self.configureTunnelCB(config: config, resolvedServerIP: resolvedIP) { error in
                        if let error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume()
                        }
                    }
                }
                dlog("Tunnel settings configured")

                completionHandler(nil)
                await MainActor.run { conn.startBridging() }
                dlog("Bridging started")
            } catch {
                dlog("Tunnel start FAILED: \(error)")
                self.persistDisconnect(for: error)
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void)
    {
        dlog("stopTunnel reason=\(reason.rawValue)")
        if reason == .userInitiated || reason == .appUpdate || reason == .none {
            DisconnectInfo.save(DisconnectInfo(
                code: .stoppedByUser,
                detail: "Stop reason: \(reason.rawValue)",
                timestamp: Date(),
                profileID: currentProfileID
            ))
        }
        Task {
            self.tunnelConnection?.disconnect()
            await MainActor.run { self.tunnelConnection = nil }
            completionHandler()
        }
    }

    override func handleAppMessage(_: Data,
                                   completionHandler: ((Data?) -> Void)?)
    {
        completionHandler?(nil)
    }

    // MARK: - Configuration

    /// Callback-based tunnel configuration to avoid MainActor/async deadlock
    /// with setTunnelNetworkSettings.
    private func configureTunnelCB(config: ServerConfig, resolvedServerIP: String,
                                   completion: @escaping (Error?) -> Void)
    {
        dlog("configureTunnel: remoteAddr=\(resolvedServerIP) localIP=\(config.localTunIP)")
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: resolvedServerIP)

        let ipv4 = NEIPv4Settings(
            addresses: [config.localTunIP],
            subnetMasks: ["255.255.255.255"]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]

        if !resolvedServerIP.contains(":") {
            let serverRoute = NEIPv4Route(destinationAddress: resolvedServerIP,
                                          subnetMask: "255.255.255.255")
            ipv4.excludedRoutes = [serverRoute]
        }
        settings.ipv4Settings = ipv4

        let octets = config.localTunIP.split(separator: ".").compactMap { UInt8($0) }
        if octets.count == 4 {
            let localIP6 = String(format: "64:ff9b::%02x%02x:%02x%02x",
                                  octets[0], octets[1], octets[2], octets[3])
            dlog("IPv6 tunnel address: \(localIP6)")
            let ipv6 = NEIPv6Settings(
                addresses: [localIP6],
                networkPrefixLengths: [128]
            )
            ipv6.includedRoutes = [NEIPv6Route.default()]
            if resolvedServerIP.contains(":") {
                let serverRoute = NEIPv6Route(destinationAddress: resolvedServerIP,
                                              networkPrefixLength: 128)
                ipv6.excludedRoutes = [serverRoute]
            }
            settings.ipv6Settings = ipv6
        }

        if let dnsServers = config.dnsServers, !dnsServers.isEmpty {
            settings.dnsSettings = NEDNSSettings(servers: dnsServers)
        }

        settings.mtu = NSNumber(value: DSVPNConstants.defaultMTU)

        dlog("Calling setTunnelNetworkSettings")
        setTunnelNetworkSettings(settings) { error in
            if let error {
                dlog("setTunnelNetworkSettings FAILED: \(error)")
            } else {
                dlog("setTunnelNetworkSettings succeeded")
            }
            completion(error)
        }
    }

    private func persistDisconnect(for error: Error) {
        let code: DisconnectInfo.Code
        switch error {
        case HandshakeError.authenticationFailed,
             HandshakeError.invalidServerResponse,
             HandshakeError.timeout:
            code = .handshakeFailed
        default:
            code = .tcpConnectFailed
        }
        DisconnectInfo.save(DisconnectInfo(
            code: code,
            detail: error.localizedDescription,
            timestamp: Date(),
            profileID: currentProfileID
        ))
    }

    private func loadConfigAndKey(profileID: UUID?) -> (ServerConfig?, [UInt8]?) {
        guard let selectedID = profileID else { return (nil, nil) }
        let profiles = VPNProfile.loadAll()
        guard let profile = profiles.first(where: { $0.id == selectedID }) else { return (nil, nil) }
        let key = KeyStorage.load(for: selectedID)
        dlog("Using profile '\(profile.name)' (\(selectedID))")
        return (profile.serverConfig, key)
    }
}

enum DSVPNError: Error, LocalizedError {
    case missingConfiguration
    case missingKey
    case reconnectExhausted

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "No server configuration found"
        case .missingKey: return "No VPN key found"
        case .reconnectExhausted: return "All reconnection attempts failed"
        }
    }
}
