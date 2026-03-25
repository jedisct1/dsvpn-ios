// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import SwiftUI

struct ProfileDetailView: View {
    let profile: VPNProfile
    let readiness: ProfileReadiness
    var disconnectInfo: DisconnectInfo?

    @Environment(\.dismiss) private var dismiss

    private var config: ServerConfig {
        profile.serverConfig
    }

    private var keyFingerprint: String? {
        KeyStorage.fingerprint(for: profile.id)
    }

    var body: some View {
        NavigationStack {
            List {
                readinessSection
                if let disconnectInfo {
                    disconnectSection(disconnectInfo)
                }
                serverSection
                tunnelSection
                dnsSection
                keySection
            }
            .navigationTitle(profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var readinessSection: some View {
        Section {
            Label(readiness.message, systemImage: readiness.isReady ? "checkmark.circle" : "info.circle")
                .foregroundStyle(readiness.isReady ? .primary : .secondary)
            if let last = profile.lastConnected {
                HStack {
                    Text("Last connected")
                    Spacer()
                    Text(last, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func disconnectSection(_ info: DisconnectInfo) -> some View {
        Section("Last Disconnect") {
            Label(info.userMessage, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            HStack {
                Text("Time")
                Spacer()
                Text(info.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Detail")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(info.detail)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var serverSection: some View {
        Section("Server") {
            row("Host", value: config.serverAddress.isEmpty ? "Not set" : config.serverAddress)
            row("Port", value: String(config.serverPort))
        }
    }

    private var tunnelSection: some View {
        Section("Tunnel") {
            row("Local IP", value: config.localTunIP)
            row("Remote IP", value: config.remoteTunIP)
        }
    }

    private var dnsSection: some View {
        Section("DNS") {
            if let servers = config.dnsServers, !servers.isEmpty {
                ForEach(servers, id: \.self) { server in
                    Text(server)
                        .font(.system(.body, design: .monospaced))
                }
            } else {
                Text("System default")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var keySection: some View {
        Section("Key") {
            if let fp = keyFingerprint {
                Label("Loaded", systemImage: "checkmark.shield.fill")
                    .symbolRenderingMode(.multicolor)
                HStack(alignment: .top) {
                    Text(fp)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = fp
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .tint(Color("AccentColor"))
                }
            } else {
                Label("No key", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}
