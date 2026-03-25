// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import Foundation
import os.log

private let tunnelLog = OSLog(subsystem: "org.pureftpd.ios.dsvpn.tunnel", category: "tunnel")

func dlog(_ message: String) {
    os_log("%{public}@", log: tunnelLog, type: .default, message)
}
