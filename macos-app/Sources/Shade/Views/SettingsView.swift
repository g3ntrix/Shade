import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var isRepairingCert = false
    @State private var certRepairStatus = ""

    private func savePartial(_ mutate: (inout AppSettings) -> Void) {
        var s = app.settings
        mutate(&s)
        if !s.exitRoutingAllowed { s.exitRelayActive = false }
        guard s != app.settings else { return }
        app.settings = s
        app.saveSettings()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                
                networkSection
                
                frontingSection

                googleIPScannerSection

                let pairedCardHeight: CGFloat = 160
                HStack(alignment: .top, spacing: 14) {
                    advancedSection
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                    certificateSection
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, minHeight: pairedCardHeight, maxHeight: pairedCardHeight, alignment: .top)

                footer
            }
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Everything here has sensible defaults. Changes save automatically.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var networkSection: some View {
        SettingsCard(title: "Network", icon: "network") {
            VStack(alignment: .leading, spacing: 12) {
                NetworkModePicker(listenHost: Binding(
                    get: { app.settings.listenHost },
                    set: { new in
                        guard app.settings.listenHost != new else { return }
                        savePartial { $0.listenHost = new }
                    }
                ))

                HStack(spacing: 12) {
                    SField(label: "HTTP Port") {
                        TextField("1080", text: Binding(
                            get: { String(app.settings.listenPort) },
                            set: { v in
                                let n = Int(v.filter(\.isNumber)) ?? app.settings.listenPort
                                guard n != app.settings.listenPort else { return }
                                savePartial { $0.listenPort = n }
                            }
                        ))
                        .monoField()
                    }
                    SField(label: "SOCKS5 Port") {
                        TextField("8080", text: Binding(
                            get: { String(app.settings.socksPort) },
                            set: { v in
                                let n = Int(v.filter(\.isNumber)) ?? app.settings.socksPort
                                guard n != app.settings.socksPort else { return }
                                savePartial { $0.socksPort = n }
                            }
                        ))
                        .monoField()
                    }
                }
            }
        }
    }

    private var frontingSection: some View {
        SettingsCard(title: "Fronting", icon: "arrow.triangle.branch") {
            HStack(spacing: 12) {
                SField(label: "Front Domain", hint: "SNI shown to network") {
                    TextField("www.google.com", text: Binding(
                        get: { app.settings.frontDomain },
                        set: { new in
                            guard app.settings.frontDomain != new else { return }
                            savePartial { $0.frontDomain = new }
                        }
                    ))
                    .monoField()
                }
                SField(label: "Google IP", hint: "Edge IP for relay") {
                    TextField("216.239.38.120", text: Binding(
                        get: { app.settings.googleIP },
                        set: { new in
                            guard app.settings.googleIP != new else { return }
                            savePartial { $0.googleIP = new }
                        }
                    ))
                    .monoField()
                }
            }
        }
    }

    private var googleIPScannerSection: some View {
        GoogleIPScannerCard()
    }

    private var advancedSection: some View {
        SettingsCard(title: "Advanced", icon: "slider.horizontal.3", expandToFitParent: true) {
            VStack(spacing: 12) {
                HStack {
                    Text("Log Level")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { app.settings.logLevel },
                        set: { new in
                            guard app.settings.logLevel != new else { return }
                            savePartial { $0.logLevel = new }
                        }
                    )) {
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
                    Toggle("", isOn: Binding(
                        get: { app.settings.verifySSL },
                        set: { new in
                            guard app.settings.verifySSL != new else { return }
                            savePartial { $0.verifySSL = new }
                        }
                    ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var certificateSection: some View {
        SettingsCard(title: "TLS / Certificate", icon: "cross.case", expandToFitParent: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("If sites show SSL errors, refresh the MITM certificate here.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
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
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var footer: some View {
        Group {
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
}

// MARK: - Card with title

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon:  String
    /// When true, card fills vertical space from parent (paired tiles stay equal height).
    var expandToFitParent: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card {
            Group {
                if expandToFitParent {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(title, systemImage: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        content()
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(title, systemImage: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        content()
                    }
                }
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

// MARK: - Network mode picker (Local-only / Share on LAN)

private struct NetworkModePicker: View {
    @Binding var listenHost: String

    private enum Mode: String, CaseIterable, Identifiable {
        case local, lan, custom
        var id: String { rawValue }
    }

    private var mode: Mode {
        switch listenHost {
        case "127.0.0.1", "localhost": return .local
        case "0.0.0.0", "::":          return .lan
        default:                       return .custom
        }
    }

    private var lanIP: String { NetworkInfo.primaryLANAddress() ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Access")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Who can connect to this proxy.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary.opacity(0.7))

            HStack(spacing: 8) {
                ModeTile(
                    title: "Local only",
                    subtitle: "127.0.0.1",
                    icon: "lock.shield.fill",
                    accent: .blue,
                    selected: mode == .local
                ) { listenHost = "127.0.0.1" }

                ModeTile(
                    title: "Share on LAN",
                    subtitle: mode == .lan ? lanIP : "All interfaces",
                    icon: "wifi",
                    accent: .blue,
                    selected: mode == .lan
                ) { listenHost = "0.0.0.0" }
            }

            if mode == .custom {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 10))
                    Text("Custom bind: \(listenHost)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Local") { listenHost = "127.0.0.1" }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.orange.opacity(0.08))
                )
            }
        }
    }
}

private struct ModeTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? accent : .secondary)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? .primary : .secondary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accent)
                            .font(.system(size: 12))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? accent.opacity(0.12)
                                   : .white.opacity(hover ? 0.06 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selected ? accent.opacity(0.45)
                                              : .white.opacity(0.08),
                                    lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.18), value: selected)
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
