// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import NetworkExtension
import SwiftUI

enum ProfileReadiness {
    case ready
    case noProfile
    case noServer
    case noKey

    var message: String {
        switch self {
        case .ready: return "Ready to connect"
        case .noProfile: return "No profile selected"
        case .noServer: return "Selected profile has no server"
        case .noKey: return "Selected profile has no key"
        }
    }

    var isReady: Bool {
        self == .ready
    }
}

struct ProfileListView: View {
    @EnvironmentObject var vpnManager: VPNManager
    @ObservedObject var profileStore: ProfileStore

    @State private var editingProfileID: UUID?
    @State private var showingNewProfile = false
    @State private var showingDetail = false
    @State private var pendingDeleteProfile: VPNProfile?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isTunnelActive: Bool {
        switch vpnManager.status {
        case .connected, .connecting, .reasserting, .disconnecting: true
        default: false
        }
    }

    private var disconnectInfoForSelectedProfile: DisconnectInfo? {
        guard let info = vpnManager.lastDisconnect,
              info.code != .stoppedByUser,
              info.profileID == profileStore.selectedID
        else { return nil }
        return info
    }

    private var readiness: ProfileReadiness {
        guard let profile = profileStore.selectedProfile else { return .noProfile }
        if profile.serverConfig.serverAddress
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .noServer }
        if !KeyStorage.hasKey(for: profile.id) { return .noKey }
        return .ready
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrandHeader(profileCount: profileStore.profiles.count)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                if profileStore.profiles.isEmpty {
                    emptyState
                } else {
                    profileList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingDetail = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .tint(Color("AccentColor"))
                    .disabled(profileStore.selectedProfile == nil)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewProfile = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Color("AccentColor"))
                }
            }
            .sheet(isPresented: $showingNewProfile) {
                ProfileEditView(profileStore: profileStore, profileID: nil)
            }
            .sheet(item: $editingProfileID) { id in
                ProfileEditView(profileStore: profileStore, profileID: id)
            }
            .sheet(isPresented: $showingDetail) {
                if let profile = profileStore.selectedProfile {
                    ProfileDetailView(
                        profile: profile,
                        readiness: readiness,
                        disconnectInfo: disconnectInfoForSelectedProfile
                    )
                }
            }
            .onChange(of: vpnManager.status) { newStatus in
                if newStatus == .connected, vpnManager.connectionInitiated,
                   let id = vpnManager.connectedProfileID
                {
                    profileStore.markConnected(id)
                }
                if let pending = pendingDeleteProfile,
                   newStatus == .disconnected || newStatus == .invalid
                {
                    profileStore.delete(pending)
                    pendingDeleteProfile = nil
                }
            }
        }
        .tint(Color("AccentColor"))
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            BrandBadge(size: 92)

            Text("No profiles configured")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Create a profile to route traffic through your own dsvpn server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button {
                showingNewProfile = true
            } label: {
                Label("Add Profile", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentColor"))
            Spacer()
        }
    }

    private var profileList: some View {
        List {
            ForEach(profileStore.profiles) { profile in
                ProfileRow(
                    profile: profile,
                    isSelected: profile.id == profileStore.selectedID,
                    isActive: profile.id == vpnManager.connectedProfileID && isTunnelActive,
                    hasKey: KeyStorage.hasKey(for: profile.id)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isTunnelActive {
                        profileStore.select(profile.id)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteProfile(profile)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        editingProfileID = profile.id
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(Color("AccentColor"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            statusCard
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    private func deleteProfile(_ profile: VPNProfile) {
        let isActiveProfile = profile.id == vpnManager.connectedProfileID && isTunnelActive
        if isActiveProfile {
            vpnManager.disconnect()
            pendingDeleteProfile = profile
        } else {
            profileStore.delete(profile)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusString)
                        .font(.subheadline.weight(.medium))
                    if vpnManager.status == .connected, let date = vpnManager.connectedDate {
                        Text("Since \(date, format: .dateTime.hour().minute()) (\(date, style: .relative) ago)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !isTunnelActive, let profile = profileStore.selectedProfile,
                              let last = profile.lastConnected
                    {
                        Text("Last connected \(last, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let error = vpnManager.lastError {
                warningLabel(error)
            } else if !isTunnelActive, let info = disconnectInfoForSelectedProfile {
                warningLabel(info.userMessage)
            }

            if !isTunnelActive, !readiness.isReady {
                Label(readiness.message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            Button {
                toggleConnection()
            } label: {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(buttonColor)
            .disabled(!readiness.isReady && !isTunnelActive
                || vpnManager.status == .disconnecting)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color("Surface"))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
        .animation(.easeInOut(duration: 0.4), value: vpnManager.status)
    }

    private var statusDot: some View {
        PulsingDot(color: statusColor, pulsing: isConnecting && !reduceMotion)
    }

    private var isConnecting: Bool {
        vpnManager.status == .connecting || vpnManager.status == .reasserting
    }

    private var statusColor: Color {
        switch vpnManager.status {
        case .connected: Color("StatusGreen")
        case .connecting, .reasserting, .disconnecting: Color("StatusAmber")
        default: .gray
        }
    }

    private var statusString: String {
        switch vpnManager.status {
        case .connected:
            if let activeID = vpnManager.connectedProfileID,
               let profile = profileStore.profiles.first(where: { $0.id == activeID })
            {
                return "Connected — \(profile.name)"
            }
            return "Connected"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .reasserting: return "Reconnecting…"
        default: return "Disconnected"
        }
    }

    private var buttonTitle: String {
        switch vpnManager.status {
        case .connected, .connecting, .reasserting: "Disconnect"
        default: "Connect"
        }
    }

    private var buttonColor: Color {
        switch vpnManager.status {
        case .connected, .connecting, .reasserting: Color("StatusRed")
        default: Color("AccentColor")
        }
    }

    private func warningLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.multicolor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func toggleConnection() {
        switch vpnManager.status {
        case .disconnected, .invalid:
            guard let profile = profileStore.selectedProfile,
                  readiness.isReady else { return }
            Task {
                try? await vpnManager.updateConfig(profile.serverConfig)
                vpnManager.connectedProfileID = profile.id
                do {
                    try vpnManager.connect()
                } catch {
                    // error stored in vpnManager.lastError
                }
            }
        default:
            vpnManager.disconnect()
        }
    }
}

struct ProfileRow: View {
    let profile: VPNProfile
    let isSelected: Bool
    let isActive: Bool
    let hasKey: Bool

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? Color("AccentColor") : .clear)
                .frame(width: 3)
                .padding(.vertical, 4)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline.weight(.semibold))
                Text(verbatim: profile.serverConfig.serverAddress.isEmpty
                    ? "No server"
                    : "\(profile.serverConfig.serverAddress):\(profile.serverConfig.serverPort)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !hasKey || isActive {
                    HStack(spacing: 6) {
                        if !hasKey {
                            StatusBadge(text: "no key", color: Color("StatusAmber"))
                        }
                        if isActive {
                            StatusBadge(text: "active", color: Color("StatusGreen"))
                        }
                    }
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color("AccentColor"))
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct PulsingDot: View {
    let color: Color
    let pulsing: Bool

    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay {
                if pulsing {
                    Circle()
                        .fill(color.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .opacity(animating ? 0.0 : 1.0)
                }
            }
            .onChange(of: pulsing) { newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                        animating = true
                    }
                } else {
                    animating = false
                }
            }
            .onAppear {
                if pulsing {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                        animating = true
                    }
                }
            }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID {
        self
    }
}
