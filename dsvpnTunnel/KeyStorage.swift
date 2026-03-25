// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

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

    static func load(for profileID: UUID) -> [UInt8]? {
        var q = query(for: profileID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              data.count == DSVPNConstants.keyLength
        else {
            return nil
        }
        return Array(data)
    }
}
