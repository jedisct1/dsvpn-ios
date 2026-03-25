// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation
import Network
import NetworkExtension

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}

/// Manages the TCP connection to the dsvpn server and bridges packets
/// between the TUN interface (NEPacketFlow) and the encrypted TCP stream.
/// All mutable state is accessed exclusively on the main queue.
final class TunnelConnection {
    private let serverHost: String
    private let serverPort: UInt16
    private let key: [UInt8]
    private let packetFlow: NEPacketTunnelFlow

    private var connection: NWConnection?
    private var codec: PacketCodec?
    private var kxState: [UInt32]

    private var congestion = false
    private var outstandingBytes = 0
    private var isRunning = false
    private var shouldReconnect = false
    private var reconnectTask: Task<Void, Never>?

    var onReconnectExhausted: (() -> Void)?
    var onResolvedIPChanged: ((_ newIP: String) -> Void)?
    var profileID: UUID?

    private var pendingDisconnect: (code: DisconnectInfo.Code, detail: String)?

    init(serverHost: String, serverPort: UInt16, key: [UInt8], packetFlow: NEPacketTunnelFlow) {
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.key = key
        self.packetFlow = packetFlow
        kxState = Handshake.deriveKXState(from: key)
    }

    /// The resolved numeric IP address of the server, available after connect.
    private(set) var resolvedServerIP: String?

    /// Phase 1: TCP connect + handshake. Does NOT start packet bridging.
    func connectAndHandshake() async throws {
        shouldReconnect = true
        try await connectOnceNoReaders()
    }

    /// Phase 2: Start TUN↔TCP packet bridging. Call after tunnel settings are configured.
    func startBridging() {
        isRunning = true
        startTUNReader()
        startTCPReader()
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        teardownConnection()
    }

    private func setPendingDisconnect(_ code: DisconnectInfo.Code, detail: String) {
        if pendingDisconnect == nil {
            pendingDisconnect = (code, detail)
        }
    }

    func persistPendingDisconnectInfo() {
        guard let pending = pendingDisconnect else { return }
        DisconnectInfo.save(DisconnectInfo(
            code: pending.code,
            detail: pending.detail,
            timestamp: Date(),
            profileID: profileID
        ))
        pendingDisconnect = nil
    }

    // MARK: - Connection lifecycle

    private func connectOnceNoReaders() async throws {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.keepaliveIdle = 60
        tcpOptions.keepaliveCount = 3
        tcpOptions.keepaliveInterval = 10
        tcpOptions.connectionTimeout = 60

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        let conn = NWConnection(
            host: NWEndpoint.Host(serverHost),
            port: NWEndpoint.Port(rawValue: serverPort)!,
            using: params
        )

        connection = conn

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumeGate = ResumeGate()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGate.claim() else { return }
                    dlog("TCP connected")
                    continuation.resume()
                case let .failed(error):
                    guard resumeGate.claim() else { return }
                    continuation.resume(throwing: error)
                case let .waiting(error):
                    dlog("Connection waiting: \(error)")
                default:
                    break
                }
            }
            conn.start(queue: .main)
        }

        let previousIP = resolvedServerIP
        if case let .hostPort(host, _) = conn.currentPath?.remoteEndpoint {
            switch host {
            case let .ipv4(addr):
                resolvedServerIP = "\(addr)"
            case let .ipv6(addr):
                resolvedServerIP = "\(addr)"
            default:
                break
            }
        }

        try await performHandshake()

        if let newIP = resolvedServerIP, previousIP != nil, newIP != previousIP {
            dlog("Server IP changed: \(previousIP ?? "nil") → \(newIP)")
            onResolvedIPChanged?(newIP)
        }
    }

    private func teardownConnection() {
        isRunning = false
        connection?.cancel()
        connection = nil
        codec = nil
        outstandingBytes = 0
        congestion = false
    }

    private func reconnect() {
        guard shouldReconnect else { return }
        if let existing = reconnectTask, !existing.isCancelled {
            return
        }

        teardownConnection()

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            for attempt in 0 ..< DSVPNConstants.reconnectAttempts {
                guard self.shouldReconnect, !Task.isCancelled else { return }

                let delay = min(attempt, 3)
                if delay > 0 {
                    dlog("Reconnecting in \(delay)s (attempt \(attempt + 1)/\(DSVPNConstants.reconnectAttempts))")
                    do {
                        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                    } catch {
                        return
                    }
                }

                guard self.shouldReconnect, !Task.isCancelled else { return }

                do {
                    try await self.connectOnceNoReaders()
                    self.startBridging()
                    dlog("Reconnected successfully")
                    self.pendingDisconnect = nil
                    self.reconnectTask = nil
                    return
                } catch {
                    dlog("Reconnect attempt \(attempt + 1) failed: \(error)")
                    self.teardownConnection()
                }
            }

            dlog("All reconnect attempts exhausted")
            self.shouldReconnect = false
            self.reconnectTask = nil
            self.persistPendingDisconnectInfo()
            self.onReconnectExhausted?()
        }
    }

    // MARK: - Handshake

    private func performHandshake() async throws {
        guard let connection else { throw HandshakeError.timeout }

        let result = Handshake.buildPkt1(kxState: kxState)
        let pkt1 = result.pkt1
        var handshakeState = result.state

        try await withThrowingTimeout(seconds: DSVPNConstants.timeout / 1000) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: Data(pkt1), completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        }

        let pkt2Data: Data = try await withThrowingTimeout(seconds: DSVPNConstants.timeout / 1000) {
            try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 64, maximumLength: 64) { data, _, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, data.count == 64 {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: HandshakeError.invalidServerResponse)
                    }
                }
            }
        }

        let pkt2 = Array(pkt2Data)
        guard Handshake.verifyPkt2(pkt2, state: &handshakeState) else {
            throw HandshakeError.authenticationFailed
        }

        let (encState, decState) = Handshake.deriveSessionKeys(state: &handshakeState)
        codec = PacketCodec(encryptState: encState, decryptState: decState)
        dlog("Handshake succeeded")
    }

    // MARK: - TUN → TCP (outbound)

    private func startTUNReader() {
        guard isRunning else { return }

        packetFlow.readPackets { [weak self] packets, _ in
            DispatchQueue.main.async {
                guard let self, self.isRunning, let codec = self.codec, let conn = self.connection else {
                    return
                }

                for packet in packets {
                    if self.congestion {
                        self.congestion = false
                        continue
                    }

                    let encrypted = codec.encode(packet)
                    let byteCount = encrypted.count
                    self.outstandingBytes += byteCount

                    conn.send(content: encrypted, completion: .contentProcessed { [weak self] error in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.outstandingBytes -= byteCount
                            if let error {
                                dlog("TCP send error: \(error)")
                                self.setPendingDisconnect(
                                    .tcpConnectFailed, detail: "TCP send: \(error.localizedDescription)"
                                )
                                self.reconnect()
                            }
                        }
                    })

                    guard self.isRunning else { return }

                    if self.outstandingBytes > DSVPNConstants.notsentLowat {
                        self.congestion = true
                    }
                }

                self.startTUNReader()
            }
        }
    }

    // MARK: - TCP → TUN (inbound)

    private func startTCPReader() {
        guard isRunning, let conn = connection else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            DispatchQueue.main.async {
                guard let self, let codec = self.codec else { return }

                if let data, !data.isEmpty {
                    switch codec.decode(data) {
                    case let .packets(decoded):
                        var validPackets = [Data]()
                        var protos = [NSNumber]()
                        validPackets.reserveCapacity(decoded.count)
                        protos.reserveCapacity(decoded.count)

                        for packet in decoded where !packet.isEmpty {
                            let version = (packet[0] >> 4) & 0x0F
                            guard version == 4 || version == 6 else { continue }
                            validPackets.append(packet)
                            protos.append(NSNumber(value: version == 4 ? AF_INET : AF_INET6))
                        }

                        if !validPackets.isEmpty {
                            self.packetFlow.writePackets(validPackets, withProtocols: protos)
                        }

                    case .corrupted:
                        dlog("Corrupted stream — reconnecting")
                        self.setPendingDisconnect(.decryptFailed, detail: "Decrypt tag verification failed")
                        self.reconnect()
                        return
                    }
                }

                if isComplete {
                    dlog("TCP connection closed by server")
                    self.setPendingDisconnect(.tcpConnectFailed, detail: "Server closed connection")
                    self.reconnect()
                    return
                }
                if let error {
                    dlog("TCP read error: \(error) — reconnecting")
                    self.setPendingDisconnect(.tcpConnectFailed, detail: "TCP read: \(error.localizedDescription)")
                    self.reconnect()
                    return
                }

                self.startTCPReader()
            }
        }
    }
}

// MARK: - Timeout helper

private func withThrowingTimeout<T>(seconds: Int, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            throw HandshakeError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
