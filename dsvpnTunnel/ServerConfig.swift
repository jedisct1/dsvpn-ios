// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation

struct ServerConfig: Codable {
    var serverAddress: String
    var serverPort: UInt16
    var localTunIP: String
    var remoteTunIP: String
    var dnsServers: [String]?

    static let `default` = ServerConfig(
        serverAddress: "",
        serverPort: 443,
        localTunIP: "192.168.192.1",
        remoteTunIP: "192.168.192.254",
        dnsServers: nil
    )

    static let appGroupID = "group.org.pureftpd.ios.dsvpn"
}
