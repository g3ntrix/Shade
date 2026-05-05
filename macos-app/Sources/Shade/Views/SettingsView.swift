import SwiftUI

private enum ExitNodeBlockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum RightColumnHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var isRepairingCert = false
    @State private var certRepairStatus = ""
    /// Measured natural height of each side; the larger one drives the matched min-height.
    @State private var exitNodeBlockHeight: CGFloat = 0
    @State private var rightColumnHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                networkSection

                frontingSection

                googleIPScannerSection

                HStack(alignment: .top, spacing: 14) {
                    exitNodeSection
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ExitNodeBlockHeightKey.self,
                                    value: geometry.size.height
                                )
                            }
                        )

                    rightSettingsColumn
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: RightColumnHeightKey.self,
                                    value: geometry.size.height
                                )
                            }
                        )
                }
                .onPreferenceChange(ExitNodeBlockHeightKey.self) { exitNodeBlockHeight = $0 }
                .onPreferenceChange(RightColumnHeightKey.self) { rightColumnHeight = $0 }

                runningHint
            }
        }
        .onChange(of: app.settings) { _ in app.saveSettings() }
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Changes apply automatically. Most also need a Stop → Start to take effect on a running session.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var networkSection: some View {
        SettingsCard(title: "Network", icon: "network") {
            SField(label: "Listen Host", hint: "Bind address for HTTP + SOCKS5") {
                TextField("127.0.0.1", text: $app.settings.listenHost)
                    .monoField()
            }
            HStack(spacing: 12) {
                SField(label: "HTTP Port") {
                    TextField("1080", text: Binding(
                        get: { String(app.settings.listenPort) },
                        set: { app.settings.listenPort = Int($0.filter(\.isNumber)) ?? app.settings.listenPort }
                    ))
                    .monoField()
                }
                SField(label: "SOCKS5 Port") {
                    TextField("8080", text: Binding(
                        get: { String(app.settings.socksPort) },
                        set: { app.settings.socksPort = Int($0.filter(\.isNumber)) ?? app.settings.socksPort }
                    ))
                    .monoField()
                }
            }
        }
    }

    private var frontingSection: some View {
        SettingsCard(title: "Fronting", icon: "arrow.triangle.branch") {
            HStack(spacing: 12) {
                SField(label: "Front Domain", hint: "SNI shown to network") {
                    TextField("www.google.com", text: $app.settings.frontDomain)
                        .monoField()
                }
                SField(label: "Google IP", hint: "Edge IP for relay") {
                    TextField("216.239.38.120", text: $app.settings.googleIP)
                        .monoField()
                }
            }
        }
    }

    private var googleIPScannerSection: some View {
        GoogleIPScannerCard()
    }

    private var exitNodeSection: some View {
        SettingsCard(title: "Full Tunnel Servers", icon: "server.rack", expandToFitParent: true) {
            ExitNodeSettingsPanel(settings: $app.settings)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: matchedColumnHeight,
            maxHeight: matchedColumnHeight == 0 ? nil : matchedColumnHeight,
            alignment: .top
        )
    }

    /// Both columns match the taller side so the Exit node card visually anchors to the right column when the right column is bigger, and vice-versa.
    private var matchedColumnHeight: CGFloat {
        let h = max(exitNodeBlockHeight, rightColumnHeight)
        return h > 1 ? h : 0
    }

    /// Advanced + TLS: equal height, stacked on the right.
    @ViewBuilder
    private var rightSettingsColumn: some View {
        let pair = VStack(spacing: 14) {
            advancedSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            certificateSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)

        if matchedColumnHeight > 1 {
            pair
                .frame(
                    maxWidth: .infinity,
                    minHeight: matchedColumnHeight,
                    maxHeight: matchedColumnHeight,
                    alignment: .top
                )
        } else {
            pair
        }
    }

    private var advancedSection: some View {
        SettingsCard(title: "Advanced", icon: "slider.horizontal.3", expandToFitParent: true) {
            VStack(spacing: 12) {
                HStack {
                    Text("Log Level")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $app.settings.logLevel) {
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
                    Toggle("", isOn: $app.settings.verifySSL)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }

                Divider().opacity(0.1)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Tunnel Mode")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("No client certificate needed for shared SOCKS traffic.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    Spacer()
                    Toggle("", isOn: $app.settings.useFullTunnel)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }

                if app.settings.useFullTunnel,
                   !app.settings.credentials.contains(where: { $0.usesFullTunnel }) {
                    Text("Full Tunnel expects CodeFull.gs deployments. Tag your Apps Script profiles with \"Full Tunnel capable\" (Dashboard -> chips).")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder
    private var runningHint: some View {
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
