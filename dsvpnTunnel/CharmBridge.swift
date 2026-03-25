// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation

/// Thin Swift wrappers around the C charm.c functions.
enum Charm {
    /// Initialize Xoodoo state from a 32-byte key and 16-byte IV.
    static func stateInit(state: inout [UInt32], key: [UInt8], iv: [UInt8]) {
        precondition(state.count == 12)
        precondition(key.count == 32)
        precondition(iv.count == 16)
        state.withUnsafeMutableBufferPointer { stBuf in
            key.withUnsafeBufferPointer { keyBuf in
                iv.withUnsafeBufferPointer { ivBuf in
                    uc_state_init(stBuf.baseAddress!, keyBuf.baseAddress!, ivBuf.baseAddress!)
                }
            }
        }
    }

    /// Encrypt message in-place, producing a 16-byte tag.
    /// Returns the full 16-byte tag.
    static func encrypt(state: inout [UInt32], message: inout [UInt8]) -> [UInt8] {
        precondition(state.count == 12)
        var tag = [UInt8](repeating: 0, count: 16)
        state.withUnsafeMutableBufferPointer { stBuf in
            message.withUnsafeMutableBufferPointer { msgBuf in
                tag.withUnsafeMutableBufferPointer { tagBuf in
                    uc_encrypt(stBuf.baseAddress!, msgBuf.baseAddress!, msgBuf.count, tagBuf.baseAddress!)
                }
            }
        }
        return tag
    }

    /// Decrypt message in-place, verifying the tag.
    /// Returns true on success, false if tag verification fails.
    static func decrypt(state: inout [UInt32], message: inout [UInt8], tag: [UInt8]) -> Bool {
        precondition(state.count == 12)
        let result = state.withUnsafeMutableBufferPointer { stBuf in
            message.withUnsafeMutableBufferPointer { msgBuf in
                tag.withUnsafeBufferPointer { tagBuf in
                    uc_decrypt(stBuf.baseAddress!, msgBuf.baseAddress!, msgBuf.count,
                               tagBuf.baseAddress!, tagBuf.count)
                }
            }
        }
        return result == 0
    }

    /// Hash data using the Xoodoo sponge, producing a 32-byte hash.
    /// Mutates state (this is intentional — handshake chains hash calls).
    static func hash(state: inout [UInt32], message: [UInt8]?) -> [UInt8] {
        precondition(state.count == 12)
        var h = [UInt8](repeating: 0, count: 32)
        state.withUnsafeMutableBufferPointer { stBuf in
            h.withUnsafeMutableBufferPointer { hBuf in
                if let message = message, !message.isEmpty {
                    message.withUnsafeBufferPointer { msgBuf in
                        uc_hash(stBuf.baseAddress!, hBuf.baseAddress!, msgBuf.baseAddress!, msgBuf.count)
                    }
                } else {
                    uc_hash(stBuf.baseAddress!, hBuf.baseAddress!, nil, 0)
                }
            }
        }
        return h
    }

    /// Fill buffer with cryptographically secure random bytes.
    static func randomBytes(count: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: count)
        buf.withUnsafeMutableBufferPointer { bufPtr in
            uc_randombytes_buf(bufPtr.baseAddress!, bufPtr.count)
        }
        return buf
    }

    /// Securely zero memory.
    static func memzero(_ buffer: inout [UInt8]) {
        buffer.withUnsafeMutableBufferPointer { bufPtr in
            uc_memzero(bufPtr.baseAddress!, bufPtr.count)
        }
    }

    /// Constant-time comparison of two byte arrays.
    static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0 ..< a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }
}
