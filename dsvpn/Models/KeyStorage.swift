// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import CryptoKit
import Foundation
import Security

enum KeyStorage {
    private static let accountPrefix = "dsvpn-key-"

    private static func query(for profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(accountPrefix)\(profileID.uuidString)",
            kSecAttrAccessGroup as String: ServerConfig.appGroupID,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func save(key: [UInt8], for profileID: UUID) -> Bool {
        let data = Data(key)
        let base = query(for: profileID)
        SecItemDelete(base as CFDictionary)
        var addQuery = base
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func hasKey(for profileID: UUID) -> Bool {
        var q = query(for: profileID)
        q[kSecReturnData as String] = false
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func load(for profileID: UUID) -> [UInt8]? {
        var q = query(for: profileID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return Array(data)
    }

    static func fingerprint(of key: [UInt8]) -> String {
        let hash = SHA256.hash(data: key)
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    static func fingerprint(for profileID: UUID) -> String? {
        guard let key = load(for: profileID) else { return nil }
        return fingerprint(of: key)
    }

    static func delete(for profileID: UUID) {
        SecItemDelete(query(for: profileID) as CFDictionary)
    }
}
