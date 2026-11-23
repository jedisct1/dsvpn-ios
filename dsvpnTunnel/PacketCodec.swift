// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation

enum DecodeResult {
    /// Successfully decoded zero or more packets (may need more data).
    case packets([Data])
    /// Stream is corrupted — decrypt tag verification failed.
    /// The cipher state is now desynchronized and the connection must be torn down.
    case corrupted
}

/// Encodes and decodes dsvpn tunnel packets.
///
/// Wire format per packet:
///   [2 bytes: length (little-endian)] [6 bytes: tag prefix] [N bytes: encrypted data]
///
/// The codec maintains a reassembly buffer for inbound TCP data, since TCP
/// is a stream protocol and packets may arrive fragmented or coalesced.
class PacketCodec {
    private var encryptState: [UInt32]
    private var decryptState: [UInt32]
    private var reassemblyBuffer = [UInt8]()

    init(encryptState: [UInt32], decryptState: [UInt32]) {
        self.encryptState = encryptState
        self.decryptState = decryptState
    }

    /// Encode a raw IP packet for transmission over TCP.
    /// Returns the framed, encrypted data ready to send.
    func encode(_ packet: Data) -> Data {
        var plaintext = Array(packet)
        let len = UInt16(plaintext.count)
        let tagFull = Charm.encrypt(state: &encryptState, message: &plaintext)

        var frame = [UInt8](repeating: 0, count: 2 + DSVPNConstants.tagLen + plaintext.count)
        var leLen = len
        withUnsafeBytes(of: &leLen) { frame[0] = $0[0]; frame[1] = $0[1] }
        frame[2 ..< (2 + DSVPNConstants.tagLen)] = tagFull[0 ..< DSVPNConstants.tagLen]
        frame[(2 + DSVPNConstants.tagLen)...] = plaintext[0...]

        return Data(frame)
    }

    /// Decode incoming TCP data. May return zero or more decrypted IP packets,
    /// or `.corrupted` if a tag verification fails.
    ///
    /// On `.corrupted`, the cipher state is desynchronized (uc_decrypt advances
    /// state even on failure). The caller MUST tear down this connection and
    /// reconnect — continuing to decode will produce garbage. This matches
    /// upstream vpn.c:466-472 which reconnects on decrypt failure.
    func decode(_ data: Data) -> DecodeResult {
        reassemblyBuffer.append(contentsOf: data)
        var packets = [Data]()
        var cursor = 0

        while true {
            let headerLen = 2 + DSVPNConstants.tagLen // 8 bytes
            let remaining = reassemblyBuffer.count - cursor

            guard remaining >= headerLen else { break }

            let payloadLen = Int(reassemblyBuffer[cursor]) | (Int(reassemblyBuffer[cursor + 1]) << 8)

            guard payloadLen > 0, payloadLen <= DSVPNConstants.maxPacketLen else {
                return .corrupted
            }

            let totalLen = headerLen + payloadLen
            guard remaining >= totalLen else { break }

            let tag = Array(reassemblyBuffer[(cursor + 2) ..< (cursor + headerLen)])
            var ciphertext = Array(reassemblyBuffer[(cursor + headerLen) ..< (cursor + totalLen)])

            guard Charm.decrypt(state: &decryptState, message: &ciphertext, tag: tag) else {
                return .corrupted
            }

            packets.append(Data(ciphertext))
            cursor += totalLen
        }

        if cursor > 0 {
            reassemblyBuffer.removeFirst(cursor)
        }

        return .packets(packets)
    }
}
