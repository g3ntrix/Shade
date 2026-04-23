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

                // ── Profile ──────────────────────────────────────────────
                CredentialsCard()

                // ── Connectivity test (only while running) ───────────────
                if app.status.isRunning {
                    ConnectivityTestCard()
                }

                // ── System proxy toggle ──────────────────────────────────
                SystemProxyCard()
            }
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
        return "Ready — SOCKS5/HTTP proxy on \(app.settings.listenHost):\(app.settings.listenPort)."
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
    @State private var showEdit   = false
    @State private var editTarget: Credential? = nil

    private var active: Credential? { app.settings.activeCredential }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Label("Profile", systemImage: "key.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple)
                    
                    Spacer()
                    
                    // New LB Toggle directly on Dashboard
                    HStack(spacing: 6) {
                        Text("Load Balance")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: Binding(
                            get: { app.settings.enableLoadBalancing },
                            set: { app.settings.enableLoadBalancing = $0; app.saveSettings() }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .background(Capsule().fill(.white.opacity(0.05)))
                    .disabled(app.status.isRunning || app.status.isTransitioning)
                    .opacity(app.status.isRunning || app.status.isTransitioning ? 0.6 : 1.0)
                    
                    Button {
                        editTarget = nil
                        showEdit   = true
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
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
                            editTarget = nil
                            showEdit   = true
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
                                Text(active?.name ?? "No profile selected")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                if let cred = active, !cred.scriptID.isEmpty {
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
                                showEdit   = true
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
        .sheet(isPresented: $showEdit) {
            CredentialEditSheet(credential: editTarget)
                .environmentObject(app)
        }
    }
}

// MARK: - Credential picker sheet

struct CredentialPickerSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var showEdit    = false
    @State private var editTarget: Credential? = nil

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

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(app.settings.credentials) { cred in
                        CredentialRow(
                            credential: cred,
                            isActive: app.settings.enableLoadBalancing 
                                ? cred.isEnabledForLB 
                                : cred.id == app.settings.activeCredential?.id,
                            isLB: app.settings.enableLoadBalancing,
                            onSelect: {
                                if app.settings.enableLoadBalancing {
                                    // Toggle for LB
                                    if let idx = app.settings.credentials.firstIndex(where: { $0.id == cred.id }) {
                                        app.settings.credentials[idx].isEnabledForLB.toggle()
                                    }
                                } else {
                                    // Normal single selection
                                    app.settings.activeCredentialID = cred.id
                                }
                                app.saveSettings()
                                if !app.settings.enableLoadBalancing { dismiss() }
                            },
                            onEdit: {
                                editTarget = cred
                                showEdit   = true
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
                editTarget = nil
                showEdit   = true
            } label: {
                Label("Add New Profile", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .frame(width: 340, height: 400)
        .sheet(isPresented: $showEdit) {
            CredentialEditSheet(credential: editTarget)
                .environmentObject(app)
        }
    }
}

// MARK: - Credential row

private struct CredentialRow: View {
    let credential: Credential
    let isActive:   Bool
    var isLB:       Bool = false
    let onSelect:   () -> Void
    let onEdit:     () -> Void
    let onDelete:   () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Image(systemName: isLB 
                          ? (isActive ? "checkmark.square.fill" : "square")
                          : (isActive ? "checkmark.circle.fill" : "circle"))
                        .foregroundStyle(isActive ? .purple : .secondary)
                        .font(.system(size: 17))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(credential.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
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
                .fill(isActive ? .purple.opacity(0.15) : .white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isActive ? .purple.opacity(0.3) : .white.opacity(0.06),
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
                    SecureField("", text: $authKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .editFieldStyle()
                }
            }
            .padding(20)

            Spacer()
        }
        .frame(width: 360, height: 360)
        .onAppear {
            if let cred = credential {
                name     = cred.name
                scriptID = cred.scriptID
                authKey  = cred.authKey
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

        if let existing = credential,
           let idx = app.settings.credentials.firstIndex(where: { $0.id == existing.id }) {
            app.settings.credentials[idx].name     = resolvedName
            app.settings.credentials[idx].scriptID = scriptID
            app.settings.credentials[idx].authKey  = authKey
        } else {
            let cred = Credential(name: resolvedName, scriptID: scriptID, authKey: authKey)
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
            HStack(spacing: 14) {
                Image(systemName: "speedometer")
                    .font(.system(size: 22))
                    .foregroundStyle(.mint)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection test")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Measures round-trip time to YouTube through the proxy.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if case .testing = app.testResult {
                    ProgressView().controlSize(.small).padding(.trailing, 8)
                }
                if case .success(let ms) = app.testResult {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ms < 1500 ? Color.green : (ms < 4000 ? Color.yellow : Color.red))
                            .frame(width: 8, height: 8)
                        Text("\(ms) ms")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(ms < 1500 ? Color.green : (ms < 4000 ? Color.yellow : Color.red))
                    }
                    .padding(.trailing, 8)
                }
                if case .failure(let msg) = app.testResult {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .trailing)
                        .padding(.trailing, 8)
                }

                Button {
                    Task { await app.testYouTubeDelay() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill").font(.system(size: 14))
                        Text("Test").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
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
    }
}

// MARK: - System proxy card

struct SystemProxyCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 10) {
                    Text("System proxy")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Automatically route all macOS traffic through Shade's SOCKS5 port. When enabled, every app on this Mac uses the proxy without manual configuration.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Set as system proxy", isOn: Binding(
                        get: { app.settings.useSystemProxy },
                        set: { newValue in Task { await app.setSystemProxy(newValue) } }
                    ))
                    .toggleStyle(.switch)
                    if app.settings.useSystemProxy && app.status.isRunning {
                        let host = app.settings.listenHost == "0.0.0.0"
                            ? "127.0.0.1" : app.settings.listenHost
                        let port = app.activeSOCKSPort > 0
                            ? app.activeSOCKSPort : app.settings.socksPort
                        Label {
                            Text(verbatim: "SOCKS5 \(host):\(port)")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
                Spacer(minLength: 0)
            }
        }
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
                            ? [Color.red.opacity(0.85), Color.pink.opacity(0.85)]
                            : [Color.accentColor, .purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: (isRunning ? Color.red : Color.accentColor)
                                .opacity(hover ? 0.5 : 0.25),
                            radius: hover ? 14 : 8, y: 4)
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

private struct EditField<Content: View>: View {
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
    
    // We only show dots for scripts that are ENABLED for LB
    private var enabledScripts: [Credential] {
        app.settings.credentials.filter { $0.isEnabledForLB }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(enabledScripts) { cred in
                PulseDot(sid: cred.scriptID, 
                         isActive: app.activeSIDs.contains(cred.scriptID))
            }
            if enabledScripts.isEmpty {
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
    
    @State private var breathing = false

    var body: some View {
        ZStack {
            // Stronger Glow for hits
            if isActive {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 16, height: 16)
                    .blur(radius: 6)
                    .transition(.opacity.combined(with: .scale))
            }
            
            // Core
            Circle()
                .fill(isActive ? Color.purple : Color.white.opacity(0.15))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .scaleEffect(isActive ? 1.3 : 1.0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .help("Script \(sid.prefix(8))...")
    }
}

private extension View {
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
