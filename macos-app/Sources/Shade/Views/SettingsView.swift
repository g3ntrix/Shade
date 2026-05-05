import SwiftUI

private enum ExitNodeBlockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var draft: AppSettings = .default
    @State private var saved = false
    @State private var isRepairingCert = false
    @State private var certRepairStatus = ""
    /// Matches stacked right column height to measured Exit node column (no dead zone under short cards).
    @State private var exitNodeBlockHeight: CGFloat = 0

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
                }
                .onPreferenceChange(ExitNodeBlockHeightKey.self) { exitNodeBlockHeight = $0 }

                footer
            }
        }
        .onAppear { draft = app.settings }
        .onChange(of: app.settings.credentials) { _ in syncCredentials() }
        .onChange(of: app.settings.activeCredentialID) { _ in syncCredentials() }
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Everything here has sensible defaults. Only touch it if you know why.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var networkSection: some View {
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
    }

    private var frontingSection: some View {
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
    }

    private var googleIPScannerSection: some View {
        GoogleIPScannerCard()
    }

    private var exitNodeSection: some View {
        SettingsCard(title: "Exit node", icon: "arrow.turn.up.right") {
            ExitNodeSettingsPanel(settings: $draft)
        }
    }

    /// Advanced + TLS: equal height when the Exit node column height is known; shared column matches left.
    @ViewBuilder
    private var rightSettingsColumn: some View {
        let pair = VStack(spacing: 14) {
            advancedSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            certificateSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .top)

        if exitNodeBlockHeight > 1 {
            pair
                .frame(
                    maxWidth: .infinity,
                    minHeight: exitNodeBlockHeight,
                    maxHeight: exitNodeBlockHeight,
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
                    Toggle("", isOn: $draft.useFullTunnel)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var loadBalancingSection: some View {
        SettingsCard(title: "Load Balancing", icon: "square.grid.3x1.below.line.grid.1x2") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Enable LB Mode")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $draft.enableLoadBalancing)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                
                Text("Distribute traffic across all selected profiles.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                if draft.enableLoadBalancing {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach($draft.credentials) { $cred in
                                HStack {
                                    Image(systemName: cred.isEnabledForLB ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(cred.isEnabledForLB ? Color.accentColor : .secondary)
                                    Text(cred.name)
                                        .font(.system(size: 10))
                                    Spacer()
                                }
                                .padding(4)
                                .background(.white.opacity(0.03))
                                .cornerRadius(4)
                                .onTapGesture {
                                    cred.isEnabledForLB.toggle()
                                }
                            }
                        }
                    }
                    .frame(height: 60)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
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
        VStack(spacing: 12) {
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

    /// A copy of draft with credentials/TUN overwritten — used only for equality check.
    private var settingsDraft: AppSettings {
        var s = draft
        // activeCredentialID is managed by the picker on Dashboard/DashboardView
        s.activeCredentialID = app.settings.activeCredentialID
        if !s.exitRoutingAllowed {
            s.valRelayEnabled = false
        }
        return s
    }

    private func doSave() {
        var merged = draft
        // Preserve activeCredentialID which is managed elsewhere
        merged.activeCredentialID = app.settings.activeCredentialID
        if !merged.exitRoutingAllowed {
            merged.valRelayEnabled = false
        }

        app.settings = merged
        app.saveSettings()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { saved = false }
        }
    }

    private func syncCredentials() {
        // Keep the master list of credentials in sync, but preserve the draft's toggle state 
        // if we are currently editing it? Actually, usually simple sync is best.
        draft.credentials        = app.settings.credentials
        draft.activeCredentialID = app.settings.activeCredentialID
        draft.enableLoadBalancing = app.settings.enableLoadBalancing
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
