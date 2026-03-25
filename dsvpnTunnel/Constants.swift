// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation

enum DSVPNConstants {
    static let tagLen = 6
    static let maxPacketLen = 65536
    static let timeout: Int = 60000 // ms
    static let reconnectAttempts = 100
    static let defaultMTU = 1400
    static let notsentLowat = 128 * 1024 // bytes
    static let keyExchangeIV: [UInt8] = Array("VPN Key Exchange".utf8)
    static let keyLength = 32
}
