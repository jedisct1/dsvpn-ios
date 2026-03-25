// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation

struct DisconnectInfo: Codable {
    let code: Code
    let detail: String
    let timestamp: Date
    let profileID: UUID?

    enum Code: String, Codable {
        case tcpConnectFailed = "tcp_connect_failed"
        case handshakeFailed = "handshake_failed"
        case decryptFailed = "decrypt_failed"
        case stoppedByUser = "stopped_by_user"
    }

    var userMessage: String {
        switch code {
        case .tcpConnectFailed: return "Couldn't reach the server."
        case .handshakeFailed: return "Couldn't complete the secure handshake."
        case .decryptFailed: return "Connection became corrupted and was closed."
        case .stoppedByUser: return "Disconnected."
        }
    }

    private static let storageKey = "lastDisconnectInfo"
    private static let defaults = UserDefaults(suiteName: ServerConfig.appGroupID)

    static func load() -> DisconnectInfo? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(DisconnectInfo.self, from: data)
    }

    static func save(_ info: DisconnectInfo) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        defaults?.set(data, forKey: storageKey)
    }

    static func clear() {
        defaults?.removeObject(forKey: storageKey)
    }
}
