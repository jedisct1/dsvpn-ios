// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation

enum HandshakeError: Error {
    case invalidServerResponse
    case authenticationFailed
    case timeout
}

/// Manages the dsvpn key exchange handshake.
/// All operations use charm.c via CharmBridge.
enum Handshake {
    /// Derive the key exchange state from the raw 32-byte PSK.
    /// This is the first thing that happens — the raw key is never used directly.
    /// Matches vpn.c:503: uc_state_init(uc_kx_st, key, "VPN Key Exchange")
    static func deriveKXState(from key: [UInt8]) -> [UInt32] {
        precondition(key.count == DSVPNConstants.keyLength)
        var state = [UInt32](repeating: 0, count: 12)
        Charm.stateInit(state: &state, key: key, iv: DSVPNConstants.keyExchangeIV)
        return state
    }

    /// Build pkt1 (72 bytes): client hello.
    /// Returns (pkt1 bytes, mutated state copy for further handshake steps).
    static func buildPkt1(kxState: [UInt32]) -> (pkt1: [UInt8], state: [UInt32]) {
        var st = kxState
        let nonce = Charm.randomBytes(count: 32)

        var now = UInt64(Date().timeIntervalSince1970)
        let timestamp = withUnsafeBytes(of: &now) { Array($0) }

        // pkt1 = nonce(32) || timestamp(8) || hash(32)
        var pkt1 = [UInt8](repeating: 0, count: 72)
        pkt1[0 ..< 32] = nonce[0 ..< 32]
        pkt1[32 ..< 40] = timestamp[0 ..< 8]

        // Hash the first 40 bytes (nonce + timestamp), mutating st
        let hash = Charm.hash(state: &st, message: Array(pkt1[0 ..< 40]))
        pkt1[40 ..< 72] = hash[0 ..< 32]

        return (pkt1, st)
    }

    /// Verify pkt2 (64 bytes): server response.
    /// Returns mutated state on success, nil on verification failure.
    static func verifyPkt2(_ pkt2: [UInt8], state: inout [UInt32]) -> Bool {
        guard pkt2.count == 64 else { return false }

        let serverNonce = Array(pkt2[0 ..< 32])
        let serverHash = Array(pkt2[32 ..< 64])
        let expected = Charm.hash(state: &state, message: serverNonce)
        return Charm.constantTimeEqual(expected, serverHash)
    }

    /// Derive session encryption states after successful handshake.
    /// Returns (encryptState, decryptState) for the client.
    static func deriveSessionKeys(state: inout [UInt32]) -> (encrypt: [UInt32], decrypt: [UInt32]) {
        var k = Charm.hash(state: &state, message: nil)

        let ivEncrypt = [UInt8](repeating: 0, count: 16)
        var encryptState = [UInt32](repeating: 0, count: 12)
        Charm.stateInit(state: &encryptState, key: k, iv: ivEncrypt)

        var ivDecrypt = [UInt8](repeating: 0, count: 16)
        ivDecrypt[0] = 1
        var decryptState = [UInt32](repeating: 0, count: 12)
        Charm.stateInit(state: &decryptState, key: k, iv: ivDecrypt)

        Charm.memzero(&k)

        return (encryptState, decryptState)
    }
}
