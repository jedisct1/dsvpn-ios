// SPDX-License-Identifier: ISC
// Copyright (c) 2024-2026, Frank Denis <github@pureftpd.org>

import SwiftUI
import UniformTypeIdentifiers

struct KeyImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var stagedKey: [UInt8]?

    @State private var keyInput = ""
    @State private var showingFilePicker = false
    @State private var errorMessage: String?
    @State private var fingerprint: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Image(systemName: "key.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color("AccentColor"))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section(header: Text("Import from file"), footer: Text("Select a 32-byte binary key file.")) {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Choose File", systemImage: "doc")
                    }
                }

                Section(header: Text("Or paste key"), footer: Text("Base64 or hex (64 hex chars).")) {
                    TextField("Key", text: $keyInput, axis: .vertical)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .lineLimit(3 ... 6)
                    Button("Import") {
                        importKey()
                    }
                    .disabled(keyInput.isEmpty)
                    .tint(Color("AccentColor"))
                }

                if let fingerprint {
                    Section("Key fingerprint") {
                        HStack {
                            Text(fingerprint)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                UIPasteboard.general.string = fingerprint
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .tint(Color("AccentColor"))
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color("AccentColor").opacity(0.08))
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
        }
    }

    private func importKey() {
        let stripped = keyInput.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        let cleaned = String(stripped)

        // Try hex first: exactly 64 hex characters = 32 bytes
        if cleaned.count == 64, cleaned.allSatisfy(\.isHexDigit) {
            var bytes = [UInt8]()
            bytes.reserveCapacity(32)
            var index = cleaned.startIndex
            for _ in 0 ..< 32 {
                let next = cleaned.index(index, offsetBy: 2)
                guard let byte = UInt8(cleaned[index ..< next], radix: 16) else {
                    errorMessage = "Invalid key: expected base64 or 64-char hex."
                    return
                }
                bytes.append(byte)
                index = next
            }
            saveKey(bytes)
            return
        }

        // Try base64
        guard let data = Data(base64Encoded: cleaned), data.count == 32 else {
            errorMessage = "Invalid key: expected base64 or 64-char hex."
            return
        }
        saveKey(Array(data))
    }

    private func importFile(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Cannot access file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                guard data.count == 32 else {
                    errorMessage = "Invalid key file: must be exactly 32 bytes (got \(data.count))."
                    return
                }
                saveKey(Array(data))
            } catch {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        case let .failure(error):
            errorMessage = "File picker error: \(error.localizedDescription)"
        }
    }

    private func saveKey(_ key: [UInt8]) {
        stagedKey = key
        fingerprint = KeyStorage.fingerprint(of: key)
        errorMessage = nil
    }
}
