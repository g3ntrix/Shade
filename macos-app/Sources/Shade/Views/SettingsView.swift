import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var draft: AppSettings = .default
    @State private var saved = false
    @State private var isRepairingCert = false
    @State private var certRepairStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Everything here has sensible defaults. Only touch it if you know why.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // ── Network ───────────────────────────────────────────────
                SettingsCard(title: "Network", icon: "network") {
                    SField(label: "Listen Host", hint: "Bind address for HTTP + SOCKS5") {
                        TextField("127.0.0.1", text: $draft.listenHost)
                            .monoField()
                    }
                    HStack(spacing: 12) {
                        SField(label: "HTTP Port") {
                            TextField("1080", text: Binding(
                                get: { String(draft.listenPort) },
                                set: { draft.listenPort = Int($0.filter(\.isNumber)) ?? draft.listenPort }
                            ))
                            .monoField()
                        }
                        SField(label: "SOCKS5 Port") {
                            TextField("8080", text: Binding(
                                get: { String(draft.socksPort) },
                                set: { draft.socksPort = Int($0.filter(\.isNumber)) ?? draft.socksPort }
                            ))
                            .monoField()
                        }
                    }
                }

                // ── Fronting ──────────────────────────────────────────────
                SettingsCard(title: "Fronting", icon: "arrow.triangle.branch") {
                    HStack(spacing: 12) {
                        SField(label: "Front Domain", hint: "SNI shown to network") {
                            TextField("www.google.com", text: $draft.frontDomain)
                                .monoField()
                        }
                        SField(label: "Google IP", hint: "Edge IP for relay") {
                            TextField("216.239.38.120", text: $draft.googleIP)
                                .monoField()
                        }
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    // ── Advanced ──────────────────────────────────────────────
                    SettingsCard(title: "Advanced", icon: "slider.horizontal.3") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Log Level")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("", selection: $draft.logLevel) {
                                    ForEach(AppSettings.LogLevel.allCases) { l in
                                        Text(l.rawValue).tag(l)
                                    }
                                }
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(width: 80)
                            }

                            Divider().opacity(0.1)

                            HStack {
                                Text("Verify SSL")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Toggle("", isOn: $draft.verifySSL)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)

                    // ── TLS / Certificate repair ───────────────────────────
                    SettingsCard(title: "TLS / Certificate", icon: "cross.case") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("If sites fail with SSL errors, use this to refresh the MITM certificate.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)

                            Button {
                                Task {
                                    isRepairingCert = true
                                    certRepairStatus = ""
                                    certRepairStatus = await app.repairCertificateNow()
                                    isRepairingCert = false
                                }
                            } label: {
                                Label("Repair Certificate", systemImage: "wrench.and.screwdriver")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isRepairingCert)

                            if isRepairingCert {
                                ProgressView().controlSize(.small)
                            }

                            if !certRepairStatus.isEmpty {
                                Text(certRepairStatus)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                }

                // ── Save / Revert ─────────────────────────────────────────
                HStack {
                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    Spacer()
                    Button("Revert") { draft = app.settings }
                        .buttonStyle(.bordered)
                    Button("Save") { doSave() }
                        .buttonStyle(.borderedProminent)
                        .disabled(settingsDraft == app.settings)
                }

                if app.status.isRunning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Changes take effect after Stop → Start.")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
                }
            }
        }
        .onAppear { draft = app.settings }
        // Keep draft credentials in sync if user edits them via picker
        .onChange(of: app.settings.credentials) { _ in syncCredentials() }
        .onChange(of: app.settings.activeCredentialID) { _ in syncCredentials() }
    }

    /// A copy of draft with credentials/TUN overwritten — used only for equality check.
    private var settingsDraft: AppSettings {
        var s = draft
        s.credentials        = app.settings.credentials
        s.activeCredentialID = app.settings.activeCredentialID
        return s
    }

    private func doSave() {
        var merged = draft
        // Preserve fields managed elsewhere
        merged.credentials        = app.settings.credentials
        merged.activeCredentialID = app.settings.activeCredentialID
        app.settings = merged
        app.saveSettings()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { saved = false }
        }
    }

    private func syncCredentials() {
        draft.credentials        = app.settings.credentials
        draft.activeCredentialID = app.settings.activeCredentialID
    }
}

// MARK: - Card with title

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon:  String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                content()
            }
        }
    }
}

// MARK: - Compact stacked field (label above input)

private struct SField<Content: View>: View {
    let label:   String
    var hint:    String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            if let hint {
                Text(hint)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Monospaced text field style helper

private extension View {
    func monoField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}
