import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var timer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // ── Hero: status + power + listener endpoint ─────────────
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            StatusOrb(status: app.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.status.label)
                                    .font(.system(size: 18, weight: .semibold))
                                    .lineLimit(1)
                                Text(secondaryLabel)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                
                                if app.settings.enableLoadBalancing && app.status.isRunning {
                                    ClusterPulse()
                                        .padding(.top, 4)
                                }
                            }
                            Spacer()
                            PowerButton(isRunning: app.status.isRunning,
                                        isBusy: app.status.isTransitioning) {
                                Task {
                                    if app.status.isRunning { await app.stop() }
                                    else { await app.start() }
                                }
                            }
                            .disabled(!canStart && !app.status.isRunning)
                            .opacity(!canStart && !app.status.isRunning ? 0.5 : 1)
                        }

                        Divider().opacity(0.15)

                        HStack(spacing: 10) {
                            Image(systemName: "arrow.down.forward.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.cyan)
                            Text(verbatim: listenerLine)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text("HTTP · SOCKS5")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.white.opacity(0.08)))
                        }
                    }
                }

                // ── Speed & traffic meter (only while running) ────────────────
                if app.status.isRunning {
                    SpeedMeterCard()
                }

                // ── Profile ──────────────────────────────────────────────
                CredentialsCard()

                // ── Connectivity row (only while running) ─────────────────
                if app.status.isRunning {
                    HStack(alignment: .top, spacing: 14) {
                        ConnectivityTestCard()
                            .frame(maxWidth: .infinity, alignment: .top)
                        RouteIPCard()
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 14) {
                    SystemProxyCard()
                    YouTubeRelayCard()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: app.status.isRunning)
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private var canStart: Bool {
        !app.settings.scriptID.trimmingCharacters(in: .whitespaces).isEmpty &&
        !app.settings.authKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var listenerLine: String {
        let httpPort  = app.activeHTTPPort  > 0 ? app.activeHTTPPort  : app.settings.listenPort
        let socksPort = app.activeSOCKSPort > 0 ? app.activeSOCKSPort : app.settings.socksPort
        let host = app.settings.listenHost
        return "HTTP \(host):\(httpPort)  ·  SOCKS5 \(host):\(socksPort)"
    }

    private var secondaryLabel: String {
        if case .running = app.status, let started = app.startedAt {
            if !app.hasShownCertRestartSucceeded {
                return "Running! Restart your browser before testing."
            }
            return "Up \(format(interval: Date().timeIntervalSince(started)))"
        }
        if !canStart { return "Add and select a profile to get started." }
        return "Ready: SOCKS5/HTTP proxy on \(app.settings.listenHost):\(app.settings.listenPort)."
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if app.startedAt != nil { objectWillChange() }
            }
        }
    }

    private func objectWillChange() { }   // triggers body re-eval via timer

    private func format(interval: TimeInterval) -> String {
        let t = Int(interval)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }
}

// MARK: - Credentials card

private struct CredentialsCard: View {
    @EnvironmentObject var app: AppState
    @State private var showPicker = false
    @State private var showAddSheet = false
    @State private var editTarget: Credential? = nil

    private var active: Credential? { app.settings.activeCredential }
    private var lbEnabled: Bool { app.settings.enableLoadBalancing }
    private var lbPoolCount: Int { app.settings.effectiveLBPool.count }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {

                // ── Header row ───────────────────────────────────────────
                HStack(spacing: 8) {
                    Label("Profile", systemImage: "key.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.purple)
                        .frame(width: 60, alignment: .leading)

                    if app.settings.enableLoadBalancing {
                        PremiumStrategyPicker()
                            .disabled(app.status.isRunning || app.status.isTransitioning)
                            .opacity(app.status.isRunning || app.status.isTransitioning ? 0.6 : 1.0)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.9)),
                                removal: .opacity
                            ))
                    }

                    Spacer(minLength: 4)

                    // Load-balance toggle
                    HStack(spacing: 6) {
                        Text("LB")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(app.settings.enableLoadBalancing ? .purple : .secondary)
                        Toggle("", isOn: Binding(
                            get: { app.settings.enableLoadBalancing },
                            set: { newValue in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    app.settings.enableLoadBalancing = newValue
                                }
                                app.saveSettings()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.05)))
                    .disabled(app.status.isRunning || app.status.isTransitioning)
                    .opacity(app.status.isRunning || app.status.isTransitioning ? 0.6 : 1.0)

                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    .help("Add new profile")
                }
                .padding(.bottom, 2)

                // ── Fallback banner ──────────────────────────────────────
                if let msg = app.lbFallbackMessage {
                    LBFallbackBanner(message: msg)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if app.settings.credentials.isEmpty {
                    // Empty state
                    VStack(spacing: 10) {
                        Text("No profiles yet")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("Add your Script ID and Auth Key as a named profile.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add First Profile", systemImage: "plus.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.purple)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                } else {
                    // Profile selector button
                    Button { showPicker = true } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(lbEnabled ? "Load-balanced pool" : (active?.name ?? "No profile selected"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    if !lbEnabled && active?.usesCloudflare == true {
                                        CloudflareBadge()
                                    }
                                    if !lbEnabled && active?.usesFullTunnel == true {
                                        FullTunnelBadge()
                                    }
                                }
                                if lbEnabled {
                                    Text("\(lbPoolCount) profile(s) in current strategy pool")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                } else if let cred = active, !cred.scriptID.isEmpty {
                                    Text(cred.scriptID.count > 28
                                         ? String(cred.scriptID.prefix(28)) + "…"
                                         : cred.scriptID)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.black.opacity(0.25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(app.status.isRunning || app.status.isTransitioning)
                    .opacity(app.status.isRunning || app.status.isTransitioning ? 0.7 : 1.0)

                    if active != nil {
                        HStack {
                            Spacer()
                            Button {
                                editTarget = active
                            } label: {
                                Label("Edit profile", systemImage: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            CredentialPickerSheet()
                .environmentObject(app)
        }
        .sheet(item: $editTarget) { cred in
            CredentialEditSheet(credential: cred)
                .environmentObject(app)
        }
        .sheet(isPresented: $showAddSheet) {
            CredentialEditSheet(credential: nil)
                .environmentObject(app)
        }
    }
}

// MARK: - Credential picker sheet

struct CredentialPickerSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var showAddSheet = false
    @State private var editTarget: Credential? = nil

    private enum RouteTag {
        case cloudflare, fullTunnel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Profiles")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.purple)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().opacity(0.3)

            if app.settings.enableLoadBalancing {
                HStack(spacing: 12) {
                    Button("Select all") {
                        for i in app.settings.credentials.indices {
                            app.settings.credentials[i].isEnabledForLB = true
                        }
                        app.saveSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)

                    Spacer()

                    Button("Deselect all") {
                        for i in app.settings.credentials.indices {
                            app.settings.credentials[i].isEnabledForLB = false
                        }
                        app.saveSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                Divider().opacity(0.3)
            }

            ScrollView {
                VStack(spacing: 8) {
                    let strategy = app.settings.lbStrategy
                    let isLBon = app.settings.enableLoadBalancing
                    
                    let fullTagged = app.settings.credentials.filter(\.usesFullTunnel)
                    let filteredCredentials: [Credential] = {
                        // When Full Tunnel is enabled, users expect tunnel-capable
                        // deployments to be selectable regardless of LB strategy.
                        if app.settings.useFullTunnel, !fullTagged.isEmpty, isLBon {
                            return fullTagged
                        }
                        return app.settings.credentials.filter { cred in
                            if !isLBon { return true }
                            switch strategy {
                            case .cfOnly: return cred.usesCloudflare
                            case .normalOnly: return !cred.usesCloudflare
                            case .valOnly: return false
                            default: return true
                            }
                        }
                    }()

                    ForEach(filteredCredentials) { cred in
                        CredentialRow(
                            credential: cred,
                            isActive: isLBon
                                ? cred.isEnabledForLB
                                : cred.id == app.settings.activeCredential?.id,
                            isLB: isLBon,
                            onSelect: {
                                if app.settings.enableLoadBalancing {
                                    if let idx = app.settings.credentials.firstIndex(where: { $0.id == cred.id }) {
                                        app.settings.credentials[idx].isEnabledForLB.toggle()
                                    }
                                } else {
                                    app.settings.activeCredentialID = cred.id
                                }
                                app.saveSettings()
                                if !app.settings.enableLoadBalancing { dismiss() }
                            },
                            onToggleCloudflare: { setRouteTag(.cloudflare, for: cred.id) },
                            onToggleFullTunnel: { setRouteTag(.fullTunnel, for: cred.id) },
                            onEdit: {
                                editTarget = cred
                            },
                            onDelete: {
                                app.settings.credentials.removeAll { $0.id == cred.id }
                                if app.settings.activeCredentialID == cred.id {
                                    app.settings.activeCredentialID =
                                        app.settings.credentials.first?.id
                                }
                                app.saveSettings()
                            }
                        )
                    }
                }
                .padding(16)
            }

            Divider().opacity(0.3)

            Button {
                showAddSheet = true
            } label: {
                Label("Add New Profile", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .frame(width: 340, height: 440)
        .sheet(item: $editTarget) { cred in
            CredentialEditSheet(credential: cred)
                .environmentObject(app)
        }
        .sheet(isPresented: $showAddSheet) {
            CredentialEditSheet(credential: nil)
                .environmentObject(app)
        }
    }

    private func setRouteTag(_ tag: RouteTag, for id: UUID) {
        guard let idx = app.settings.credentials.firstIndex(where: { $0.id == id }) else { return }
        let currentlyOn: Bool
        switch tag {
        case .cloudflare: currentlyOn = app.settings.credentials[idx].usesCloudflare
        case .fullTunnel: currentlyOn = app.settings.credentials[idx].usesFullTunnel
        }
        if currentlyOn {
            app.settings.credentials[idx].usesCloudflare = false
            app.settings.credentials[idx].usesFullTunnel = false
            app.settings.credentials[idx].usesValTunnel = false
        } else {
            app.settings.credentials[idx].usesCloudflare = (tag == .cloudflare)
            app.settings.credentials[idx].usesFullTunnel = (tag == .fullTunnel)
            app.settings.credentials[idx].usesValTunnel = false
        }
        app.saveSettings()
    }
}

// MARK: - Credential row

private struct CredentialRow: View {
    let credential: Credential
    let isActive:   Bool
    var isLB:       Bool = false
    let onSelect:   () -> Void
    let onToggleCloudflare: () -> Void
    let onToggleFullTunnel: () -> Void
    let onEdit:     () -> Void
    let onDelete:   () -> Void

    private var accent: Color {
        if credential.usesCloudflare { return .orange }
        if credential.usesFullTunnel { return .cyan }
        return .purple
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Image(systemName: isLB
                          ? (isActive ? "checkmark.square.fill" : "square")
                          : (isActive ? "checkmark.circle.fill" : "circle"))
                        .foregroundStyle(isActive ? accent : .secondary)
                        .font(.system(size: 17))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(credential.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            if credential.usesCloudflare {
                                CloudflareBadge()
                            }
                            if credential.usesFullTunnel {
                                FullTunnelBadge()
                            }
                        }
                        Text(credential.scriptID.isEmpty ? "No Script ID set"
                             : (credential.scriptID.count > 26
                                ? String(credential.scriptID.prefix(26)) + "…"
                                : credential.scriptID))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Button(action: onToggleCloudflare) {
                    TagChipIcon(
                        icon: "cloud.fill",
                        tint: .orange,
                        isEnabled: credential.usesCloudflare
                    )
                }
                .buttonStyle(.plain)
                .help(credential.usesCloudflare ? "Remove Cloudflare tag" : "Assign Cloudflare tag")

                Button(action: onToggleFullTunnel) {
                    TagChipIcon(
                        icon: "point.3.connected.trianglepath.dotted",
                        tint: .cyan,
                        isEnabled: credential.usesFullTunnel
                    )
                }
                .buttonStyle(.plain)
                .help(credential.usesFullTunnel ? "Remove Full Tunnel tag" : "Assign Full Tunnel tag")

            }

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.7))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? accent.opacity(0.15) : .white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isActive ? accent.opacity(0.3) : .white.opacity(0.06),
                                lineWidth: 1)
                )
        )
    }
}

// MARK: - Credential edit / add sheet

struct CredentialEditSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss

    let credential: Credential?   // nil → add mode

    @State private var name:     String = ""
    @State private var scriptID: String = ""
    @State private var authKey:  String = ""
    @State private var usesCloudflare: Bool = false
    @State private var usesFullTunnel: Bool = false
    @State private var isAuthKeyVisible: Bool = false

    private var isNew: Bool { credential == nil }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isNew ? "New Profile" : "Edit Profile")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSave ? .purple : .secondary)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(spacing: 18) {
                    EditField(label: "PROFILE NAME", hint: "e.g. Home, School, Work") {
                        TextField("Default", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .editFieldStyle()
                    }

                    EditField(label: "SCRIPT ID",
                              hint: "Deployment ID from your Google Apps Script web app") {
                        TextField("AKfycb…", text: $scriptID)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .editFieldStyle()
                    }

                    EditField(label: "AUTH KEY",
                              hint: "The same AUTH_KEY you set in Code.gs") {
                        HStack(spacing: 0) {
                            if isAuthKeyVisible {
                                TextField("", text: $authKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                            } else {
                                SecureField("", text: $authKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                            }

                            Button {
                                isAuthKeyVisible.toggle()
                            } label: {
                                Image(systemName: isAuthKeyVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .editFieldStyle()
                    }

                    CloudflareToggle(isOn: Binding(
                        get: { usesCloudflare },
                        set: { newValue in
                            if newValue {
                                usesCloudflare = true
                                usesFullTunnel = false
                            } else {
                                usesCloudflare = false
                            }
                        }
                    ))
                    FullTunnelToggle(isOn: Binding(
                        get: { usesFullTunnel },
                        set: { newValue in
                            if newValue {
                                usesFullTunnel = true
                                usesCloudflare = false
                            } else {
                                usesFullTunnel = false
                            }
                        }
                    ))
                }
                .padding(20)
            }
        }
        .frame(width: 360, height: 520)
        .onAppear {
            if let cred = credential {
                name           = cred.name
                scriptID       = cred.scriptID
                authKey        = cred.authKey
                usesCloudflare = cred.usesCloudflare
                usesFullTunnel = cred.usesFullTunnel
            }
        }
    }

    private var canSave: Bool {
        !scriptID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let resolvedName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Profile \(app.settings.credentials.count + 1)"
            : name
        var resolvedCloudflare = usesCloudflare
        var resolvedFullTunnel = usesFullTunnel
        if resolvedCloudflare {
            resolvedFullTunnel = false
        } else if resolvedFullTunnel {
            resolvedCloudflare = false
        }

        if let existing = credential,
           let idx = app.settings.credentials.firstIndex(where: { $0.id == existing.id }) {
            app.settings.credentials[idx].name           = resolvedName
            app.settings.credentials[idx].scriptID       = scriptID
            app.settings.credentials[idx].authKey        = authKey
            app.settings.credentials[idx].usesCloudflare = resolvedCloudflare
            app.settings.credentials[idx].usesFullTunnel = resolvedFullTunnel
            app.settings.credentials[idx].usesValTunnel  = false
        } else {
            let cred = Credential(name: resolvedName, scriptID: scriptID, authKey: authKey,
                                  usesCloudflare: resolvedCloudflare, usesFullTunnel: resolvedFullTunnel,
                                  usesValTunnel: false)
            app.settings.credentials.append(cred)
            app.settings.activeCredentialID = cred.id
        }
        app.saveSettings()
        dismiss()
    }
}

// MARK: - Connectivity test card

struct ConnectivityTestCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 18))
                        .foregroundStyle(.mint)
                    Text("Connection test")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }

                HStack(alignment: .center) {
                    statusView
                    Spacer(minLength: 8)
                    Button {
                        Task { await app.testYouTubeDelay() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill").font(.system(size: 13))
                            Text("Test").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [.mint, .cyan.opacity(0.8)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(app.testResult == .testing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if case .testing = app.testResult {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else if case .success(let ms) = app.testResult {
            HStack(spacing: 4) {
                Circle()
                    .fill(ms < 1500 ? Color.green : (ms < 4000 ? Color.yellow : Color.red))
                    .frame(width: 8, height: 8)
                Text("\(ms) ms")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(ms < 1500 ? Color.green : (ms < 4000 ? Color.yellow : Color.red))
            }
        } else if case .failure(let msg) = app.testResult {
            Text(msg)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(1)
        } else {
            Text("Not tested yet")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

struct RouteIPCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.cyan)
                    Text("Egress IP")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }

                HStack(alignment: .center) {
                    egressStatusView
                    Spacer(minLength: 8)
                    Button {
                        Task { await app.checkProxyEgressIP() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13))
                            Text("Check").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [.cyan, .mint.opacity(0.85)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(app.isCheckingProxyEgressIP)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var egressStatusView: some View {
        if app.isCheckingProxyEgressIP {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else {
            switch app.proxyEgressIP {
            case .success(let ip):
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(ip)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            case .failure(let msg):
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            case .unavailable(let msg):
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .idle:
                Text("Not checked yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - System proxy card

struct SystemProxyCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                    Text("System proxy")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { app.settings.useSystemProxy },
                        set: { newValue in Task { await app.setSystemProxy(newValue) } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                
                Text("Route all macOS traffic.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - YouTube Relay card

struct YouTubeRelayCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                    Text("YouTube Relay")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { app.settings.youtubeViaRelay },
                        set: { newValue in
                            app.settings.youtubeViaRelay = newValue
                            app.saveSettings()
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                
                Text("Bypass IP blocks for YT.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Speed Meter card

struct SpeedMeterCard: View {
    @EnvironmentObject var app: AppState
    @State private var pulse = false

    var body: some View {
        if app.status.isRunning {
            Card {
                VStack(spacing: 12) {

                    // ── Header row ────────────────────────────────────────
                    HStack(spacing: 10) {
                        // Animated live indicator dot
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .shadow(color: .green.opacity(0.8), radius: pulse ? 5 : 2)
                            .scaleEffect(pulse ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                       value: pulse)
                            .onAppear { pulse = true }

                        Text("Connection Meter")
                            .font(.system(size: 13, weight: .semibold))

                        Spacer()

                        // Live total
                        Text(app.traffic.formattedTotal)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("total")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }

                    // ── Speed bars ────────────────────────────────────────
                    VStack(spacing: 8) {
                        LiveSpeedBar(
                            label: "↓  Down",
                            color: Color(hue: 0.60, saturation: 0.8, brightness: 0.9),
                            speedLabel: app.traffic.formattedSpeedDown,
                            bps: app.traffic.speedDown
                        )
                        LiveSpeedBar(
                            label: "↑  Up",
                            color: Color(hue: 0.78, saturation: 0.75, brightness: 0.95),
                            speedLabel: app.traffic.formattedSpeedUp,
                            bps: app.traffic.speedUp
                        )
                    }

                    // ── Totals row ────────────────────────────────────────
                    HStack(spacing: 0) {
                        TrafficPill(
                            icon: "arrow.down.circle.fill",
                            color: Color(hue: 0.60, saturation: 0.8, brightness: 0.9),
                            label: "Downloaded",
                            value: app.traffic.formattedDown
                        )
                        Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 36)
                        TrafficPill(
                            icon: "arrow.up.circle.fill",
                            color: Color(hue: 0.78, saturation: 0.75, brightness: 0.95),
                            label: "Uploaded",
                            value: app.traffic.formattedUp
                        )
                        Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 36)
                        TrafficPill(
                            icon: "sum",
                            color: .cyan,
                            label: "Session Total",
                            value: app.traffic.formattedTotal
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }
}

// MARK: - Live speed bar

private struct LiveSpeedBar: View {
    let label:      String
    let color:      Color
    let speedLabel: String
    let bps:        Int64

    private let maxBps: Double = 2 * 1024 * 1024
    private var fill: Double { bps <= 0 ? 0 : min(Double(bps) / maxBps, 1.0) }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.5), color],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * fill, fill > 0 ? 8 : 0))
                        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: fill)
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(bps > 0 ? speedLabel : "0 KB/s")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(bps > 0 ? color : .secondary)
                .frame(width: 72, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Traffic pill

private struct TrafficPill: View {
    let icon:  String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}


// MARK: - Google IP Scanner card

struct GoogleIPScannerCard: View {
    @EnvironmentObject var app: AppState
    @State private var showLog = false

    private var isScanning: Bool { app.scanState == .scanning }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {

                // ── Header row ────────────────────────────────────
                HStack(spacing: 14) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22))
                        .foregroundStyle(.cyan)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Google IP Scanner")
                            .font(.system(size: 13, weight: .semibold))
                        Text(headerSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Spinner while scanning
                    if isScanning {
                        ProgressView().controlSize(.small).padding(.trailing, 4)
                    }

                    // Main action button
                    Button {
                        if isScanning {
                            app.cancelScan()
                        } else {
                            showLog = true
                            Task { await app.runIPScan() }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isScanning ? "xmark.circle.fill" : "magnifyingglass")
                                .font(.system(size: 13))
                            Text(isScanning ? "Cancel" : "Scan")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(
                                    colors: isScanning
                                        ? [.red.opacity(0.75), .pink.opacity(0.75)]
                                        : [.cyan.opacity(0.85), .teal.opacity(0.85)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                    }
                    .buttonStyle(.plain)
                }

                // ── Current IP badge ──────────────────────────────
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 11))
                        .foregroundStyle(.cyan.opacity(0.8))
                    Text("Current: ")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(app.settings.googleIP.isEmpty ? "default" : app.settings.googleIP)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Spacer()
                    if !app.scanLog.isEmpty {
                        Button(showLog ? "Hide log" : "Show log") { showLog.toggle() }
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                    }
                }

                // ── Result / Apply row ────────────────────────────
                if case .done(let ip) = app.scanState {
                    Divider().opacity(0.15)
                    HStack(spacing: 10) {
                        if let ip {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Best IP found")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(ip)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                            Spacer()
                            Button("Apply") { app.applyScanResult(ip) }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(LinearGradient(
                                            colors: [.green.opacity(0.85), .teal.opacity(0.85)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .buttonStyle(.plain)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("No reachable IPs found on this network.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }

                if app.scanState == .failed {
                    Divider().opacity(0.15)
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                        Text("Scan failed. Check that the core binary is available.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                // ── Live log ──────────────────────────────────────
                if showLog && !app.scanLog.isEmpty {
                    Divider().opacity(0.15)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(app.scanLog.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(logColor(for: line))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 160)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.black.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.07), lineWidth: 1)
                                )
                        )
                        .onChange(of: app.scanLog.count) { _ in
                            withAnimation { proxy.scrollTo("bottom") }
                        }
                    }
                }
            }
        }
    }

    private var headerSubtitle: String {
        switch app.scanState {
        case .idle:             return "Find the fastest Google IP for your network"
        case .scanning:         return "Probing Google IPs…"
        case .done(let ip):     return ip != nil ? "Scan complete: tap Apply to use the best IP" : "Scan complete"
        case .failed:           return "Scan failed"
        }
    }

    private func logColor(for line: String) -> Color {
        if line.contains("ms") && !line.contains("-") { return .green }
        if line.contains("timeout") || line.contains("error") || line.contains("refused") { return .red.opacity(0.8) }
        if line.contains("Recommended") { return .cyan }
        if line.contains("Top") || line.contains("Result") { return .yellow.opacity(0.9) }
        return .secondary
    }
}

// MARK: - Shared building blocks

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

struct StatusOrb: View {
    let status: AppState.Status
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25)).frame(width: 54, height: 54)
                .scaleEffect(pulse ? 1.15 : 0.9)
                .opacity(status.isRunning ? 1 : 0.5)
                .animation(status.isRunning
                           ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                           : .default, value: pulse)
            Circle().fill(color).frame(width: 18, height: 18)
                .shadow(color: color.opacity(0.6), radius: 8)
        }
        .onAppear { pulse = true }
    }
    var color: Color {
        switch status {
        case .running:              return .green
        case .starting, .stopping:  return .yellow
        case .error:                return .red
        case .stopped:              return .gray
        }
    }
}

struct PowerButton: View {
    let isRunning: Bool
    let isBusy:    Bool
    let action:    () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(isRunning ? "Stop" : "Start")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(
                        colors: isRunning
                            ? [Color(hue: 0.0,  saturation: 0.85, brightness: 0.85),
                               Color(hue: 0.95, saturation: 0.8,  brightness: 0.80)]
                            : [Color(red: 0.33, green: 0.56, blue: 0.98),
                               Color(red: 0.23, green: 0.44, blue: 0.90)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: (isRunning
                                ? Color(hue: 0.0, saturation: 0.85, brightness: 0.85)
                                : Color(red: 0.33, green: 0.56, blue: 0.98))
                                .opacity(hover ? 0.55 : 0.28),
                            radius: hover ? 16 : 8, y: 4)
            )
            .scaleEffect(hover ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { hover = $0 }
    }
}

// MARK: - EditField helper (used inside sheets)

struct EditField<Content: View>: View {
    let label: String
    var hint:  String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            content()
        }
    }
}

// MARK: - Cluster visualize
struct ClusterPulse: View {
    @EnvironmentObject var app: AppState

    // Show all enabled credentials, but we'll dim those not in the current active pool.
    private var allEnabled: [Credential] {
        app.settings.credentials.filter { $0.isEnabledForLB }
    }
    
    private var currentPoolIDs: Set<String> {
        Set(app.settings.effectiveLBPool.map { $0.scriptID })
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(allEnabled) { cred in
                PulseDot(
                    sid: cred.scriptID,
                    isActive: app.activeSIDs.contains(cred.scriptID),
                    isUnhealthy: app.unhealthySIDs.contains(cred.scriptID),
                    isInCurrentPool: currentPoolIDs.contains(cred.scriptID),
                    isStrategyPrimary: app.settings.isLBPulsePrimaryFocus(cred),
                    accent: app.pulseAccent(for: cred),
                    exitReady: false
                        && !app.settings.effectiveExitNodePool.isEmpty
                        && app.exitCapableSIDs.contains(cred.scriptID)
                )
            }
            if allEnabled.isEmpty {
                Text("Select profiles to balance")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PulseDot: View {
    let sid: String
    let isActive: Bool
    let isUnhealthy: Bool
    var isInCurrentPool: Bool = true
    /// Preferred tier for the current LB strategy (e.g. plain Apps Script under Apps Script First).
    var isStrategyPrimary: Bool = true
    var accent: Color = .purple
    /// True when val routing is active and this script reported exit-aware relay JSON.
    var exitReady: Bool = false

    @State private var breathing = false

    private var dotColor: Color {
        if isActive {
            return isStrategyPrimary ? accent : accent.opacity(0.45)
        }
        if isUnhealthy { return Color.red.opacity(0.55) }
        let emphasized = isInCurrentPool && isStrategyPrimary
        return emphasized ? Color.white.opacity(0.25) : Color.white.opacity(0.08)
    }

    private var dimmedInactive: Bool {
        (!isInCurrentPool && !isActive)
            || (isInCurrentPool && !isStrategyPrimary && !isActive)
    }

    var body: some View {
        ZStack {
            if isActive, isStrategyPrimary {
                Circle()
                    .fill(dotColor)
                    .frame(width: 16, height: 16)
                    .blur(radius: 6)
                    .transition(.opacity.combined(with: .scale))
            }

            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.white.opacity(isStrategyPrimary ? 0.5 : 0.35) : Color.clear, lineWidth: 1)
                )
                .scaleEffect(isActive ? (isStrategyPrimary ? 1.3 : 1.08) : 1.0)
                .opacity(dimmedInactive ? 0.4 : (isUnhealthy && !isActive ? 0.7 : 1.0))
        }
        .frame(width: 16, height: 16)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isUnhealthy)
        .animation(.easeInOut(duration: 0.3), value: isInCurrentPool)
        .animation(.easeInOut(duration: 0.3), value: isStrategyPrimary)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .help(isUnhealthy
              ? "Script \(sid.prefix(8))… health check failed"
              : (exitReady
                 ? "Script \(sid.prefix(8))… exit relay active"
                 : "Script \(sid.prefix(8))…"))
    }
}

// MARK: - LBStrategy view helpers

extension LBStrategy {
    /// Whether this strategy predominantly routes through Cloudflare (drives accent color).
    var cfFacing: Bool { self == .cfPreferred || self == .cfOnly }
    var valFacing: Bool { false }
    /// Visual ordering in the strategy picker: broad/default first, then preferred, then strict-only.
    static var displayOrder: [LBStrategy] {
        [
            .balanced,
            .normalPreferred,
            .cfPreferred,
            .normalOnly,
            .cfOnly,
        ]
    }
}

// MARK: - Cloudflare badge / toggle / LB banner

struct CloudflareBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 8, weight: .bold))
            Text("Cloudflare")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(.orange.opacity(0.15))
                .overlay(Capsule().stroke(.orange.opacity(0.35), lineWidth: 0.5))
        )
        .fixedSize()
    }
}

struct FullTunnelBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 8, weight: .bold))
            Text("Full Tunnel")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.cyan)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(.cyan.opacity(0.15))
                .overlay(Capsule().stroke(.cyan.opacity(0.35), lineWidth: 0.5))
        )
        .fixedSize()
    }
}

private struct TagChipIcon: View {
    let icon: String
    let tint: Color
    let isEnabled: Bool

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isEnabled ? tint : .secondary.opacity(0.75))
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isEnabled ? tint.opacity(0.16) : .white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isEnabled ? tint.opacity(0.35) : .white.opacity(0.08), lineWidth: 0.8)
                    )
            )
    }
}

struct CloudflareToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 14))
                .foregroundStyle(isOn ? .orange : .secondary)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Routes through Cloudflare Worker")
                    .font(.system(size: 11, weight: .semibold))
                Text("Enable for profiles whose Apps Script forwards to a Cloudflare Worker. Affects load-balancing grouping and dashboard color.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(.orange)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOn ? .orange.opacity(0.08) : .white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isOn ? .orange.opacity(0.3) : .white.opacity(0.06),
                                lineWidth: 1)
                )
        )
    }
}

struct FullTunnelToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 14))
                .foregroundStyle(isOn ? .cyan : .secondary)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Full Tunnel capable")
                    .font(.system(size: 11, weight: .semibold))
                Text("When enabled for a profile, Shade will treat it as safe for Full Tunnel Mode (expects CodeFull.gs).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(.cyan)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOn ? .cyan.opacity(0.08) : .white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isOn ? .cyan.opacity(0.3) : .white.opacity(0.06),
                                lineWidth: 1)
                )
        )
    }
}

// MARK: - Premium Strategy Picker

private struct PremiumStrategyPicker: View {
    @EnvironmentObject var app: AppState
    @State private var showInfo = false
    @Namespace private var pickerNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LBStrategy.displayOrder) { strategy in
                StrategyIconToggle(
                    strategy: strategy,
                    isSelected: app.settings.lbStrategy == strategy,
                    namespace: pickerNamespace,
                    onSelect: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            app.settings.lbStrategy = strategy
                        }
                        app.saveSettings()
                    }
                )
            }

            Button {
                showInfo = true
            } label: {
                HStack(spacing: 4) {
                    Text(app.settings.lbStrategy.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .opacity(0.5)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.white.opacity(0.03))
                        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
                )
                .padding(.leading, 4)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfo) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.settings.lbStrategy.label)
                        .font(.system(size: 12, weight: .bold))
                    Text(app.settings.lbStrategy.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 200, alignment: .leading)
                }
                .padding(12)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(.black.opacity(0.2))
                .overlay(Capsule().stroke(.white.opacity(0.05), lineWidth: 0.5))
        )
    }
}

private struct StrategyIconToggle: View {
    let strategy: LBStrategy
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void

    private var accent: Color {
        if strategy.cfFacing { return .orange }
        if strategy.valFacing { return .mint }
        return .purple
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(accent.opacity(0.2))
                        .matchedGeometryEffect(id: "bg", in: namespace)
                }
                Image(systemName: strategy.icon)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? accent : .secondary.opacity(0.6))
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(strategy.label)
    }
}

// MARK: - LB fallback banner

struct LBFallbackBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fallback active")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.yellow.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.yellow.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

extension View {
    func editFieldStyle() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
