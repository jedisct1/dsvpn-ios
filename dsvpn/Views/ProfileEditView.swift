// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import SwiftUI

struct ProfileEditView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @ObservedObject var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID?

    @State private var name = ""
    @State private var serverAddress = ""
    @State private var serverPort = String(ServerConfig.default.serverPort)
    @State private var localTunIP = ServerConfig.default.localTunIP
    @State private var remoteTunIP = ServerConfig.default.remoteTunIP
    @State private var dnsServers = ""
    @State private var showingKeyImport = false
    @State private var stagedKey: [UInt8]?

    private var isNew: Bool {
        profileID == nil
    }

    private var hasKey: Bool {
        guard let id = profileID else { return false }
        return KeyStorage.hasKey(for: id)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Profile name", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Server") {
                    TextField("Address", text: $serverAddress)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $serverPort)
                        .keyboardType(.numberPad)
                }

                Section("Tunnel") {
                    TextField("Local IP", text: $localTunIP)
                        .keyboardType(.decimalPad)
                    TextField("Remote IP", text: $remoteTunIP)
                        .keyboardType(.decimalPad)
                }

                Section(header: Text("DNS"), footer: Text("Comma-separated. Leave blank to use system DNS.")) {
                    TextField("DNS Servers", text: $dnsServers)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                }

                Section("Key") {
                    HStack {
                        if stagedKey != nil {
                            Label("New key staged", systemImage: "key.fill")
                                .symbolRenderingMode(.multicolor)
                        } else if hasKey {
                            Label("Key loaded", systemImage: "checkmark.shield.fill")
                                .symbolRenderingMode(.multicolor)
                        } else {
                            Label("No key", systemImage: "exclamationmark.triangle.fill")
                                .symbolRenderingMode(.multicolor)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Import") {
                            showingKeyImport = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("AccentColor"))
                    }
                }
            }
            .navigationTitle(isNew ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadCurrent() }
            .sheet(isPresented: $showingKeyImport) {
                KeyImportView(stagedKey: $stagedKey)
            }
        }
    }

    private func loadCurrent() {
        guard let id = profileID,
              let profile = profileStore.profiles.first(where: { $0.id == id })
        else {
            return
        }
        name = profile.name
        serverAddress = profile.serverConfig.serverAddress
        serverPort = String(profile.serverConfig.serverPort)
        localTunIP = profile.serverConfig.localTunIP
        remoteTunIP = profile.serverConfig.remoteTunIP
        dnsServers = profile.serverConfig.dnsServers?.joined(separator: ", ") ?? ""
    }

    private func save() {
        let dns: [String]? = dnsServers.isEmpty ? nil :
            dnsServers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = ServerConfig(
            serverAddress: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            serverPort: UInt16(serverPort) ?? 443,
            localTunIP: localTunIP,
            remoteTunIP: remoteTunIP,
            dnsServers: dns
        )

        let id: UUID
        if let existingID = profileID {
            id = existingID
            let profile = VPNProfile(id: existingID, name: trimmedName, serverConfig: config)
            profileStore.update(profile)
        } else {
            let profile = VPNProfile(name: trimmedName, serverConfig: config)
            id = profile.id
            profileStore.add(profile)
        }

        if let key = stagedKey {
            if !KeyStorage.save(key: key, for: id) {
                dlog("Failed to save key for profile \(id)")
            }
        }

        if profileStore.selectedID == id {
            Task {
                try? await vpnManager.updateConfig(config)
            }
        }

        dismiss()
    }
}
