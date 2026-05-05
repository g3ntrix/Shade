import SwiftUI
import AppKit

/// Top-level setup wizard: Apps Script, Cloudflare Worker, and Full Tunnel (VPS + Apps Script).
struct SetupView: View {
    enum Mode { case chooser, appsScript, cloudflare, fullTunnel }
    @State private var mode: Mode = .chooser

    var body: some View {
        switch mode {
        case .chooser:
            SetupChooserView(onPick: { picked in
                withAnimation(.easeOut(duration: 0.2)) { mode = picked }
            })
        case .appsScript:
            AppsScriptSetupView(onBack: {
                withAnimation(.easeOut(duration: 0.2)) { mode = .chooser }
            })
        case .cloudflare:
            CloudflareSetupView(onBack: {
                withAnimation(.easeOut(duration: 0.2)) { mode = .chooser }
            })
        case .fullTunnel:
            FullTunnelSetupView(onBack: {
                withAnimation(.easeOut(duration: 0.2)) { mode = .chooser }
            })
        }
    }
}

// MARK: - Chooser

private struct SetupChooserView: View {
    let onPick: (SetupView.Mode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                VStack(alignment: .leading, spacing: 6) {
                    Text("Setup Guide")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Pick your main relay path. Full Tunnel includes VPS + Apps Script in one guided flow.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 14) {
                    ChooserCard(
                        title: "Apps Script",
                        subtitle: "Standard + optional Full Tunnel",
                        details: "Deploy standard Code.gs or tunnel-capable CodeFull.gs from the same guide. Traffic exits from Google IPs (standard) or your tunnel-node path (full mode).",
                        icon: "doc.text.fill",
                        accent: .purple
                    ) {
                        onPick(.appsScript)
                    }

                    ChooserCard(
                        title: "Cloudflare Worker",
                        subtitle: "Apps Script + Worker, 7 steps",
                        details: "Apps Script forwards to a Worker. Traffic exits from Cloudflare IPs.",
                        icon: "cloud.fill",
                        accent: .orange
                    ) {
                        onPick(.cloudflare)
                    }

                    ChooserCard(
                        title: "Full Tunnel",
                        subtitle: "VPS + CodeFull.gs, end-to-end",
                        details: "Set up your VPS tunnel-node first, then deploy CodeFull.gs with tunnel URL + key, then add the resulting deployment profile in Shade.",
                        icon: "server.rack",
                        accent: .teal
                    ) {
                        onPick(.fullTunnel)
                    }
                }
            }
        }
    }
}

private struct ChooserCard: View {
    let title: String
    let subtitle: String
    let details: String
    let icon: String
    let accent: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(accent.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accent)
                }

                Text(details)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Text("Start guide")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(hover ? 0.07 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(hover ? accent.opacity(0.45) : .white.opacity(0.08),
                                    lineWidth: 1)
                    )
                    .shadow(color: accent.opacity(hover ? 0.25 : 0),
                            radius: hover ? 12 : 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Apps-Script-only branch (existing flow)

private struct AppsScriptSetupView: View {
    @EnvironmentObject var app: AppState
    let onBack: () -> Void
    @State private var step: Int = 0
    @State private var authKeyDraft: String = ""
    @State private var authKeyConfirmed: Bool = false
    @State private var preferFullTunnelScript = false
    @State private var deploymentIDDraft: String = ""
    @State private var autoAddedScriptID: String? = nil
    @State private var useExistingTunnelConfig = false
    @State private var selectedTunnelProfileID: UUID? = nil
    @State private var manualTunnelURL: String = ""
    @State private var manualTunnelKey: String = ""
    @State private var justAddedTunnel = false

    private let accent: Color = .purple

    private let steps: [WizardStep] = [
        .init(
            title: "Create a new Apps Script project",
            body:
                """
                Open script.google.com and click New project (top-left). \
                You'll get an empty editor with a single Code.gs file already open.
                """,
            link: URL(string: "https://script.google.com/home/projects/create")
        ),
        .init(
            title: "Paste the Code.gs contents",
            body:
                """
                Select everything in the default Code.gs, delete it, then paste the \
                code below. Before saving, change the AUTH_KEY constant at the top \
                to a strong secret of your choice: you'll enter the same value into
                Shade as your Auth Key. Save with ⌘S.

                This guide is for normal Apps Script mode (Code.gs).
                For Full Tunnel Mode (CodeFull.gs + VPS tunnel-node), use the
                dedicated "Full Tunnel" guide from Setup.
                """,
            showAuthKey: true
        ),
        .init(
            title: "Deploy as a Web app",
            body:
                """
                Click Deploy → New deployment (top-right). For "Select type" click the \
                gear icon and pick Web app. Configure it like this:

                  • Description: anything you want (e.g. "Shade relay")
                  • Execute as: Me
                  • Who has access: Anyone

                Google may ask you to authorize the script the first time:
                review the permissions and continue.
                """
        ),
        .init(
            title: "Copy the Deployment ID",
            body:
                """
                After deploying, Google shows a "Deployment ID" and a "Web app URL". \
                Copy the Deployment ID (it starts with AKfycb…). That's your Script ID.

                Optional: paste it into the box on this step to auto-add the profile later.

                You now have everything:
                  • Script ID → the Deployment ID you just copied
                  • Auth Key  → the AUTH_KEY string you set in step 2
                """
        ),
        .init(
            title: "Add the profile to Shade",
            body:
                """
                If you pasted a Deployment ID above, Shade will add the profile automatically.

                Otherwise, head back to the Dashboard, click + Add next to Profile, \
                paste your Script ID and Auth Key, and save. Hit Start and you're connected.

                If later you want Full Tunnel quality, run the dedicated
                Full Tunnel guide and deploy CodeFull.gs instead.
                """
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WizardHeader(
                    title: "Apps Script Setup",
                    subtitle: "Get your Google Apps Script deployment running in five short steps.",
                    onBack: onBack
                )
                StepperBar(count: steps.count, current: step, accent: accent)
                stepCard
            }
        }
    }

    private var stepCard: some View {
        let s = steps[step]
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                StepCardHeader(index: step, total: steps.count, title: s.title, accent: accent)

                Text(s.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if step == 3 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Optional: paste your Deployment ID here for auto-add.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("AKfycb…", text: $deploymentIDDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Text("If filled, the profile will be created/updated automatically on the last step.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if step == steps.count - 1 {
                    let trimmed = deploymentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, autoAddedScriptID == trimmed {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Profile added automatically to your Dashboard.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if s.showAuthKey {
                    if authKeyConfirmed {
                        VStack(alignment: .leading, spacing: 8) {
                            ConfirmedHint(
                                text: "Auth key embedded: copy and paste the code below.",
                                accent: accent,
                                onChange: { authKeyConfirmed = false }
                            )
                            CodeSnippet(
                                filename: "Code.gs",
                                code: renderedAppsScriptCode(),
                                accent: accent
                            )
                        }
                    } else {
                        AuthKeyPrompt(authKey: $authKeyDraft, accent: accent) {
                            authKeyConfirmed = true
                        }
                    }
                }

                if let link = s.link {
                    Link(destination: link) {
                        Label(link.absoluteString, systemImage: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
                    }
                }

                StepNavBar(
                    step: $step,
                    total: steps.count,
                    accent: accent,
                    nextDisabled: step == 1 && !authKeyConfirmed
                )
            }
        }
        .onChange(of: step) { _ in
            // When reaching the final step, optionally auto-add using the
            // pasted Deployment ID.
            tryAutoAddProfile()
        }
    }

    private func renderedAppsScriptCode() -> String {
        let key = authKeyDraft.replacingOccurrences(of: "\"", with: "\\\"")
        return codeGS_AppsScriptOnly
            .replacingOccurrences(
                of: "CHANGE_ME_TO_A_STRONG_SECRET",
                with: key
            )
    }

    private var tunnelConfigBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tunnel node settings for CodeFull.gs")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle("Use saved Exit node profile as tunnel-node config", isOn: $useExistingTunnelConfig)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Only use this if that profile is your tunnel-node endpoint + tunnel auth key (not the standard exit relay URL/PSK).")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if useExistingTunnelConfig, !validTunnelProfiles.isEmpty {
                Picker("Tunnel", selection: Binding(
                    get: { selectedTunnelProfileID ?? validTunnelProfiles.first?.id },
                    set: { selectedTunnelProfileID = $0 }
                )) {
                    ForEach(validTunnelProfiles) { p in
                        Text(p.name.isEmpty ? p.relayURL : p.name).tag(Optional(p.id))
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .onAppear {
                    if selectedTunnelProfileID == nil {
                        selectedTunnelProfileID = activeOrFirstValidTunnelProfile()?.id
                    }
                }
            } else {
                TextField("Tunnel URL (https://...)", text: $manualTunnelURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                SecureField("Tunnel auth key", text: $manualTunnelKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

                if canSaveManualTunnel {
                    Button("Add this tunnel to Exit node profiles") {
                        addManualTunnelProfile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if justAddedTunnel {
                    Text("Tunnel added. It is now selected and saved.")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.04))
        )
    }

    private var validTunnelProfiles: [ExitNodeProfile] {
        app.settings.validExitNodeProfiles()
    }

    private func activeOrFirstValidTunnelProfile() -> ExitNodeProfile? {
        let valid = validTunnelProfiles
        guard !valid.isEmpty else { return nil }
        if let id = app.settings.activeExitNodeProfileID,
           let active = valid.first(where: { $0.id == id }) {
            return active
        }
        return valid.first
    }

    private func effectiveTunnelConfig() -> (url: String, key: String) {
        if useExistingTunnelConfig,
           let id = selectedTunnelProfileID,
           let selected = validTunnelProfiles.first(where: { $0.id == id }) {
            return (
                selected.relayURL.trimmingCharacters(in: .whitespacesAndNewlines),
                selected.psk.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let fallbackURL = manualTunnelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackKey = manualTunnelKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            fallbackURL.isEmpty ? "https://YOUR_TUNNEL_NODE_URL" : fallbackURL,
            fallbackKey.isEmpty ? "YOUR_TUNNEL_AUTH_KEY" : fallbackKey
        )
    }

    private var canSaveManualTunnel: Bool {
        let url = manualTunnelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = manualTunnelKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (url.hasPrefix("https://") || url.hasPrefix("http://")), key.count >= 8 else {
            return false
        }
        return !app.settings.exitNodeProfiles.contains {
            $0.relayURL.trimmingCharacters(in: .whitespacesAndNewlines) == url &&
            $0.psk.trimmingCharacters(in: .whitespacesAndNewlines) == key
        }
    }

    private func addManualTunnelProfile() {
        let url = manualTunnelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = manualTunnelKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (url.hasPrefix("https://") || url.hasPrefix("http://")), key.count >= 8 else { return }
        let profile = ExitNodeProfile(
            name: "Tunnel \(app.settings.exitNodeProfiles.count + 1)",
            relayURL: url,
            psk: key
        )
        app.settings.exitNodeProfiles.append(profile)
        app.settings.activeExitNodeProfileID = profile.id
        app.saveSettings()
        selectedTunnelProfileID = profile.id
        useExistingTunnelConfig = true
        justAddedTunnel = true
    }

    private func tryAutoAddProfile() {
        guard step == steps.count - 1 else { return }
        guard authKeyConfirmed else { return }

        let scriptID = deploymentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scriptID.isEmpty else { return }
        guard autoAddedScriptID != scriptID else { return }

        let key = authKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 8 else { return }

        let usesFullTunnel = false
        let resolvedName = "Apps Script Relay"

        if let idx = app.settings.credentials.firstIndex(where: { $0.scriptID == scriptID }) {
            app.settings.credentials[idx].authKey = key
            app.settings.credentials[idx].usesFullTunnel = usesFullTunnel
            if app.settings.credentials[idx].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                app.settings.credentials[idx].name = resolvedName
            }
            app.settings.activeCredentialID = app.settings.credentials[idx].id
        } else {
            let cred = Credential(
                name: resolvedName,
                scriptID: scriptID,
                authKey: key,
                isEnabledForLB: true,
                usesCloudflare: false,
                usesFullTunnel: usesFullTunnel,
                usesValTunnel: false
            )
            app.settings.credentials.append(cred)
            app.settings.activeCredentialID = cred.id
        }

        app.settings.useFullTunnel = usesFullTunnel
        app.saveSettings()
        autoAddedScriptID = scriptID
    }
}

// MARK: - Cloudflare branch

private struct CloudflareSetupView: View {
    let onBack: () -> Void

    @State private var step: Int = 0
    @State private var workerURLDraft: String = ""
    @State private var workerURLConfirmed: Bool = false
    @State private var authKeyDraft: String = ""
    @State private var authKeyConfirmed: Bool = false

    private let accent: Color = .orange

    private let steps: [WizardStep] = [
        .init(
            title: "Open Cloudflare and create a Worker",
            body:
                """
                Sign in to the Cloudflare dashboard. From the sidebar, open \
                Compute → Workers & Pages, click Create application, choose \
                Hello World, and click Deploy.
                """,
            link: URL(string: "https://dash.cloudflare.com/")
        ),
        .init(
            title: "Open the Worker editor",
            body:
                """
                On the Worker overview page click Edit code. Select everything \
                in the editor and delete it — you'll paste a fresh script next.
                """
        ),
        .init(
            title: "Paste the worker.js script",
            body:
                """
                Enter the Worker URL Cloudflare gave you (e.g. \
                myworker.workers.dev). We'll bake it into the script so the \
                Worker can detect self-fetch loops. Then copy the result, paste \
                it into the Cloudflare editor, and click Deploy.
                """,
            showWorkerURL: true,
            codeKind: .workerJS
        ),
        .init(
            title: "Open Apps Script",
            body:
                """
                Open script.google.com and click New project (top-left). Delete \
                everything in the default Code.gs editor.
                """,
            link: URL(string: "https://script.google.com/home/projects/create")
        ),
        .init(
            title: "Paste the Code.gs script",
            body:
                """
                Choose a strong password (≥ 8 characters). It will be baked into \
                the script as AUTH_KEY, and you'll use the same value in Shade \
                as your Auth Key. Copy the result, paste it into the Apps Script \
                editor, and save with ⌘S.
                """,
            showAuthKey: true,
            codeKind: .codeGS_CF
        ),
        .init(
            title: "Deploy Apps Script as a Web app",
            body:
                """
                Click Deploy → New deployment. For "Select type" click the gear \
                icon and pick Web app. Configure it like this:

                  • Description: anything you want
                  • Execute as: Me
                  • Who has access: Anyone

                Authorize the script when Google asks. After deploying, copy the \
                Deployment ID — that's your Script ID.
                """
        ),
        .init(
            title: "Add the profile to Shade",
            body:
                """
                Head back to the Dashboard, click + Add next to Profile, paste \
                your Script ID and the password from step 5, and turn on the \
                "Routes through Cloudflare Worker" toggle so this profile is \
                tagged correctly. Save and hit Start.
                """
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WizardHeader(
                    title: "Cloudflare Worker Setup",
                    subtitle: "Walks you through deploying both a Cloudflare Worker and a Google Apps Script that forwards to it. About 7 steps.",
                    onBack: onBack,
                    accent: accent
                )
                StepperBar(count: steps.count, current: step, accent: accent)
                stepCard
            }
        }
    }

    private var stepCard: some View {
        let s = steps[step]
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                StepCardHeader(index: step, total: steps.count, title: s.title, accent: accent)

                Text(s.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if s.showWorkerURL {
                    if workerURLConfirmed {
                        ConfirmedHint(
                            text: "Worker URL embedded: \(normalizedWorkerHost)",
                            accent: accent,
                            onChange: { workerURLConfirmed = false }
                        )
                    } else {
                        WorkerURLPrompt(workerURL: $workerURLDraft, accent: accent) {
                            workerURLConfirmed = true
                        }
                    }
                }

                if s.showAuthKey {
                    if authKeyConfirmed {
                        ConfirmedHint(
                            text: "Auth key embedded: copy and paste the code below.",
                            accent: accent,
                            onChange: { authKeyConfirmed = false }
                        )
                    } else {
                        AuthKeyPrompt(authKey: $authKeyDraft, accent: accent) {
                            authKeyConfirmed = true
                        }
                    }
                }

                if let kind = s.codeKind, isCodeReady(for: kind) {
                    CodeSnippet(
                        filename: kind.filename,
                        code: renderedCode(for: kind),
                        accent: accent
                    )
                }

                if let link = s.link {
                    Link(destination: link) {
                        Label(link.absoluteString, systemImage: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
                    }
                }

                if step == steps.count - 1 {
                    CloudflareTagReminder(accent: accent)
                }

                StepNavBar(
                    step: $step,
                    total: steps.count,
                    accent: accent,
                    nextDisabled: nextBlocked
                )
            }
        }
    }

    // ── State helpers ────────────────────────────────────────────────

    private var nextBlocked: Bool {
        switch step {
        case 2: return !workerURLConfirmed
        case 4: return !authKeyConfirmed
        default: return false
        }
    }

    private func isCodeReady(for kind: WizardStep.CodeKind) -> Bool {
        switch kind {
        case .workerJS:  return workerURLConfirmed
        case .codeGS_CF: return authKeyConfirmed && workerURLConfirmed
        }
    }

    private func renderedCode(for kind: WizardStep.CodeKind) -> String {
        switch kind {
        case .workerJS:
            return workerJS.replacingOccurrences(
                of: "myworker.workers.dev",
                with: normalizedWorkerHost
            )
        case .codeGS_CF:
            return codeGS_Cloudflare
                .replacingOccurrences(
                    of: "STRONG_SECRET_KEY",
                    with: authKeyDraft.replacingOccurrences(of: "\"", with: "\\\"")
                )
                .replacingOccurrences(
                    of: "https://example.workers.dev",
                    with: "https://" + normalizedWorkerHost
                )
        }
    }

    /// Strips scheme + trailing slash so we end with `myworker.workers.dev`.
    private var normalizedWorkerHost: String {
        var s = workerURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

// MARK: - Full tunnel (VPS + CodeFull.gs)

private struct FullTunnelSetupView: View {
    @EnvironmentObject var app: AppState
    let onBack: () -> Void
    @State private var step: Int = 0
    @State private var authKeyDraft: String = ""
    @State private var authKeyConfirmed: Bool = false
    @State private var tunnelURLDraft: String = ""
    @State private var tunnelKeyDraft: String = ""
    @State private var deploymentIDDraft: String = ""
    @State private var autoAddedScriptID: String? = nil
    private let accent: Color = .teal

    private let steps: [WizardStep] = [
        .init(title: "Set up VPS tunnel-node", body: "Run the VPS install/build commands in the code block below. This creates your tunnel endpoint and key."),
        .init(title: "Confirm tunnel URL + key", body: "After VPS setup, paste your tunnel URL and tunnel auth key here. These will be baked into CodeFull.gs."),
        .init(title: "Create Apps Script + paste CodeFull.gs", body: "Create a new Apps Script project, replace default Code.gs with generated CodeFull.gs, and save."),
        .init(title: "Deploy as Web app", body: "Deploy as Web app (Execute as Me, Anyone). Then copy Deployment ID."),
        .init(title: "Add profile to Shade", body: "Paste Deployment ID here to auto-add profile, then Start.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WizardHeader(title: "Full Tunnel Setup", subtitle: "VPS first, then CodeFull.gs deploy, then add profile.", onBack: onBack, accent: accent)
                StepperBar(count: steps.count, current: step, accent: accent)
                stepCard
            }
        }
    }

    private var stepCard: some View {
        let s = steps[step]
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                StepCardHeader(index: step, total: steps.count, title: s.title, accent: accent)
                Text(s.body).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                if step == 0 {
                    CodeSnippet(filename: "VPS tunnel-node setup", code: fullTunnelVPSSnippet, accent: accent)
                }
                if step == 1 {
                    TextField("Tunnel URL (e.g. http://YOUR_VPS_IP:18080)", text: $tunnelURLDraft).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                    SecureField("Tunnel auth key", text: $tunnelKeyDraft).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                }
                if step == 2 {
                    if authKeyConfirmed {
                        ConfirmedHint(text: "Auth key embedded. Copy generated CodeFull.gs.", accent: accent, onChange: { authKeyConfirmed = false })
                        CodeSnippet(filename: "CodeFull.gs", code: renderedCodeFull(), accent: accent)
                    } else {
                        AuthKeyPrompt(authKey: $authKeyDraft, accent: accent) { authKeyConfirmed = true }
                    }
                    Link(destination: URL(string: "https://script.google.com/home/projects/create")!) {
                        Label("https://script.google.com/home/projects/create", systemImage: "arrow.up.right.square").font(.system(size: 11, weight: .medium))
                    }
                }
                if step == 4 {
                    TextField("Deployment ID (AKfycb...)", text: $deploymentIDDraft).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                    if autoAddedScriptID == deploymentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines), !deploymentIDDraft.isEmpty {
                        Text("Profile added automatically. You can Start now.").font(.system(size: 11)).foregroundStyle(.green)
                    }
                }

                StepNavBar(step: $step, total: steps.count, accent: accent, nextDisabled: step == 2 && !authKeyConfirmed)
            }
        }
        .onChange(of: step) { _ in tryAutoAddProfile() }
    }

    private var fullTunnelVPSSnippet: String {
        """
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source "$HOME/.cargo/env"
        git clone https://github.com/therealaleph/MasterHttpRelayVPN-RUST.git
        cd MasterHttpRelayVPN-RUST/tunnel-node
        cargo build --release
        export TUNNEL_KEY='REPLACE_WITH_A_RANDOM_HEX_KEY'
        TUNNEL_AUTH_KEY="$TUNNEL_KEY" PORT=18080 nohup ./target/release/tunnel-node >/var/log/tunnel-node.log 2>&1 &
        curl -i http://127.0.0.1:18080/health
        """
    }

    private func renderedCodeFull() -> String {
        let auth = authKeyDraft.replacingOccurrences(of: "\"", with: "\\\"")
        let tURL = tunnelURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tKey = tunnelKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return codeGS_Full
            .replacingOccurrences(of: "CHANGE_ME_TO_A_STRONG_SECRET", with: auth)
            .replacingOccurrences(of: "https://YOUR_TUNNEL_NODE_URL", with: tURL.isEmpty ? "https://YOUR_TUNNEL_NODE_URL" : tURL.replacingOccurrences(of: "\"", with: "\\\""))
            .replacingOccurrences(of: "YOUR_TUNNEL_AUTH_KEY", with: tKey.isEmpty ? "YOUR_TUNNEL_AUTH_KEY" : tKey.replacingOccurrences(of: "\"", with: "\\\""))
    }

    private func tryAutoAddProfile() {
        guard step == steps.count - 1 else { return }
        let sid = deploymentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = authKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty, key.count >= 8 else { return }
        guard autoAddedScriptID != sid else { return }
        if let idx = app.settings.credentials.firstIndex(where: { $0.scriptID == sid }) {
            app.settings.credentials[idx].authKey = key
            app.settings.credentials[idx].usesFullTunnel = true
            app.settings.credentials[idx].usesCloudflare = false
            app.settings.credentials[idx].usesValTunnel = false
            app.settings.activeCredentialID = app.settings.credentials[idx].id
        } else {
            let cred = Credential(name: "Full Tunnel Relay", scriptID: sid, authKey: key, usesCloudflare: false, usesFullTunnel: true, usesValTunnel: false)
            app.settings.credentials.append(cred)
            app.settings.activeCredentialID = cred.id
        }
        app.settings.useFullTunnel = true
        app.saveSettings()
        autoAddedScriptID = sid
    }
}

// MARK: - Shared wizard chrome

private struct WizardStep {
    let title: String
    let body:  String
    var link:  URL?    = nil
    var showAuthKey:    Bool = false
    var showWorkerURL:  Bool = false
    var codeKind:       CodeKind? = nil

    enum CodeKind {
        case workerJS, codeGS_CF
        var filename: String {
            switch self {
            case .workerJS:  return "worker.js"
            case .codeGS_CF: return "Code.gs"
            }
        }
    }
}

private struct WizardHeader: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Choose another setup")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StepperBar: View {
    let count: Int
    let current: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? accent : .white.opacity(0.12))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
    }
}

private struct StepCardHeader: View {
    let index: Int
    let total: Int
    let title: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(accent.opacity(0.18))
                    .frame(width: 26, height: 26)
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text("Step \(index + 1) of \(total)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StepNavBar: View {
    @Binding var step: Int
    let total: Int
    let accent: Color
    var nextDisabled: Bool = false

    var body: some View {
        HStack {
            Button {
                if step > 0 { withAnimation { step -= 1 } }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(step > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.secondary.opacity(0.4)))
            .disabled(step == 0)

            Spacer()

            if step < total - 1 {
                Button {
                    withAnimation { step += 1 }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(nextDisabled)
                .opacity(nextDisabled ? 0.5 : 1.0)
            }
        }
    }
}

private struct ConfirmedHint: View {
    let text: String
    let accent: Color
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Change", action: onChange)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent)
        }
    }
}

private struct CloudflareTagReminder: View {
    let accent: Color
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 14))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Don't forget the Cloudflare toggle")
                    .font(.system(size: 12, weight: .semibold))
                Text("In the Add Profile sheet, turn on \"Routes through Cloudflare Worker\". Tagged profiles get an orange marker on the dashboard and load-balance only with other Cloudflare profiles.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Auth key prompt

private struct AuthKeyPrompt: View {
    @Binding var authKey: String
    var accent: Color = .accentColor
    var title: String = "Choose an Auth Key"
    var detail: String =
        "Pick a strong secret (at least 8 characters). It will be baked into the snippet below: the same value goes into Shade's profile as the Auth Key."
    var onConfirm: () -> Void
    @State private var isVisible: Bool = false
    @State private var copied: Bool = false

    private var trimmed: String {
        authKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool { trimmed.count >= 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    if isVisible {
                        TextField("Strong secret", text: $authKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("Strong secret", text: $authKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    Button {
                        isVisible.toggle()
                    } label: {
                        Image(systemName: isVisible ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(authKey, forType: .string)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )

                Button {
                    authKey = Self.generateRandomKey()
                } label: {
                    Label("Generate", systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Generate a strong random key")

                Button {
                    onConfirm()
                } label: {
                    Text("Use This Key")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)
                .disabled(!isValid)
            }

            if !authKey.isEmpty && !isValid {
                Text("Too short: use 8 or more characters.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private static func generateRandomKey(length: Int = 32) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
    }
}

// MARK: - Worker URL prompt

private struct WorkerURLPrompt: View {
    @Binding var workerURL: String
    var accent: Color = .orange
    var onConfirm: () -> Void

    private var trimmed: String {
        var s = workerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Anything ending in .workers.dev (or a custom hostname with a dot) passes.
    private var isValid: Bool {
        let t = trimmed.lowercased()
        guard t.contains(".") else { return false }
        guard !t.contains(" ") else { return false }
        return t.count >= 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your Worker URL")
                .font(.system(size: 12, weight: .semibold))

            Text("This is the address Cloudflare assigned your Worker — typically yourname.workers.dev. Paste it with or without https:// — we'll normalize it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("myworker.workers.dev", text: $workerURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                    )

                Button {
                    onConfirm()
                } label: {
                    Text("Use This URL")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)
                .disabled(!isValid)
            }

            if !workerURL.isEmpty && !isValid {
                Text("That doesn't look like a valid hostname.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Code snippet

private struct CodeSnippet: View {
    let filename: String
    let code: String
    var accent: Color = .accentColor
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(filename)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? .green : accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.04))

            Divider().opacity(0.3)

            ScrollView([.vertical]) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 260)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Embedded scripts

/// Apps-Script-only Code.gs — fetches target URLs directly from Google.
private let codeGS_AppsScriptOnly: String = #"""
const AUTH_KEY = "CHANGE_ME_TO_A_STRONG_SECRET";

const SKIP_HEADERS = {
  host: 1, connection: 1, "content-length": 1,
  "transfer-encoding": 1, "proxy-connection": 1, "proxy-authorization": 1,
  "priority": 1, te: 1,
  "x-forwarded-for": 1, "x-forwarded-host": 1, "x-forwarded-proto": 1,
  "x-forwarded-port": 1, "x-real-ip": 1, "forwarded": 1, "via": 1,
};

const SAFE_REPLAY_METHODS = { GET: 1, HEAD: 1, OPTIONS: 1 };

function _fetchViaExitNode(req) {
  try {
    var en = req.en;
    if (!en || typeof en !== "object") return null;
    var relayUrl = en.relay_url;
    var exitPsk = en.psk;
    if (
      !relayUrl ||
      typeof relayUrl !== "string" ||
      !relayUrl.match(/^https?:\/\//i) ||
      !exitPsk ||
      typeof exitPsk !== "string"
    ) {
      return null;
    }
    var inner = {
      k: exitPsk,
      u: req.u,
      m: (req.m || "GET").toUpperCase(),
    };
    if (req.h && typeof req.h === "object") inner.h = req.h;
    if (req.b) inner.b = req.b;
    var resp = UrlFetchApp.fetch(relayUrl, {
      method: "post",
      contentType: "application/json",
      payload: JSON.stringify(inner),
      muteHttpExceptions: true,
      followRedirects: true,
    });
    var text = resp.getContentText();
    var data = JSON.parse(text);
    if (data.e) return null;
    if (typeof data.s !== "number") return null;
    if (!data.h || typeof data.h !== "object") return null;
    if (typeof data.b !== "string") return null;
    return data;
  } catch (err) {
    return null;
  }
}

function doPost(e) {
  try {
    var req = JSON.parse(e.postData.contents);
    if (req.k !== AUTH_KEY) return _json({ e: "unauthorized" });
    if (Array.isArray(req.q)) return _doBatch(req.q);
    return _doSingle(req);
  } catch (err) {
    return _json({ e: String(err) });
  }
}

function _doSingle(req) {
  if (!req.u || typeof req.u !== "string" || !req.u.match(/^https?:\/\//i)) {
    return _json({ e: "bad url" });
  }
  if (req.en && req.en.relay_url && req.en.psk) {
    var viaExit = _fetchViaExitNode(req);
    if (viaExit) {
      return _json({
        s: viaExit.s,
        h: viaExit.h,
        b: viaExit.b,
      });
    }
  }
  var opts = _buildOpts(req);
  var resp = UrlFetchApp.fetch(req.u, opts);
  return _json({
    s: resp.getResponseCode(),
    h: _respHeaders(resp),
    b: Utilities.base64Encode(resp.getContent()),
  });
}

function _doBatch(items) {
  var results = new Array(items.length);
  var fetchArgs = [];
  var fetchIndex = [];
  var fetchMethods = [];
  var i;
  var j;
  for (i = 0; i < items.length; i++) {
    var item = items[i];
    if (!item || typeof item !== "object") {
      results[i] = { e: "bad item" };
      continue;
    }
    if (!item.u || typeof item.u !== "string" || !item.u.match(/^https?:\/\//i)) {
      results[i] = { e: "bad url" };
      continue;
    }
    if (item.en && item.en.relay_url && item.en.psk) {
      var viaExit = _fetchViaExitNode(item);
      if (viaExit) {
        results[i] = {
          s: viaExit.s,
          h: viaExit.h,
          b: viaExit.b,
        };
        continue;
      }
    }
    try {
      var opts = _buildOpts(item);
      opts.url = item.u;
      fetchArgs.push(opts);
      fetchIndex.push(i);
      fetchMethods.push(String(item.m || "GET").toUpperCase());
      results[i] = null;
    } catch (err) {
      results[i] = { e: String(err) };
    }
  }
  var responses = [];
  if (fetchArgs.length > 0) {
    try {
      responses = UrlFetchApp.fetchAll(fetchArgs);
    } catch (err) {
      responses = [];
      for (j = 0; j < fetchArgs.length; j++) {
        try {
          if (!SAFE_REPLAY_METHODS[fetchMethods[j]]) {
            results[fetchIndex[j]] = {
              e: "batch fetchAll failed; unsafe method not replayed",
            };
            responses[j] = null;
            continue;
          }
          var args = fetchArgs[j];
          var url = args.url;
          var fetchOpts = {};
          for (var key in args) {
            if (Object.prototype.hasOwnProperty.call(args, key) && key !== "url") {
              fetchOpts[key] = args[key];
            }
          }
          responses[j] = UrlFetchApp.fetch(url, fetchOpts);
        } catch (singleErr) {
          results[fetchIndex[j]] = { e: String(singleErr) };
          responses[j] = null;
        }
      }
    }
  }
  var rIdx = 0;
  for (i = 0; i < items.length; i++) {
    if (results[i] !== null) continue;
    var resp = responses[rIdx++];
    if (!resp) {
      if (!results[i]) results[i] = { e: "fetch failed" };
    } else {
      results[i] = {
        s: resp.getResponseCode(),
        h: _respHeaders(resp),
        b: Utilities.base64Encode(resp.getContent()),
      };
    }
  }
  return _json({ q: results });
}

function _buildOpts(req) {
  var opts = {
    method: (req.m || "GET").toLowerCase(),
    muteHttpExceptions: true,
    followRedirects: req.r !== false,
    validateHttpsCertificates: true,
  };
  if (req.h && typeof req.h === "object") {
    var headers = {};
    for (var k in req.h) {
      if (req.h.hasOwnProperty(k) && !SKIP_HEADERS[k.toLowerCase()]) {
        headers[k] = req.h[k];
      }
    }
    opts.headers = headers;
  }
  if (req.b) {
    opts.payload = Utilities.base64Decode(req.b);
    if (req.ct) opts.contentType = req.ct;
  }
  return opts;
}

function _respHeaders(resp) {
  try {
    if (typeof resp.getAllHeaders === "function") return resp.getAllHeaders();
  } catch (err) {}
  return resp.getHeaders();
}

function doGet(e) {
  return HtmlService.createHtmlOutput("<h1>Welcome</h1><p>Shade relay is running.</p>");
}

function _json(obj) {
  var out = {};
  if (obj && typeof obj === "object" && !Array.isArray(obj)) {
    for (var k in obj) {
      if (Object.prototype.hasOwnProperty.call(obj, k)) {
        out[k] = obj[k];
      }
    }
  }
  out.cap = 2;
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(ContentService.MimeType.JSON);
}
"""#

/// Full tunnel capable CodeFull.gs — keeps normal relay compatibility and adds tunnel ops.
private let codeGS_Full: String = #"""
/**
 * Shade / MasterHttpRelay — Full mode Apps Script
 *
 * Supports:
 *  - Single HTTP relay: {k,m,u,h,b,ct,r}
 *  - Batch HTTP relay:  {k,q:[...]}
 *  - Tunnel single op:  {k,t,...}
 *  - Tunnel batch ops:  {k,t:"batch",ops:[...]}
 *
 * Required edits before deploy:
 *  - AUTH_KEY must match Shade config auth_key
 *  - TUNNEL_SERVER_URL must point to your tunnel-node
 *  - TUNNEL_AUTH_KEY must match tunnel-node shared key
 */

const AUTH_KEY = "CHANGE_ME_TO_A_STRONG_SECRET";
const TUNNEL_SERVER_URL = "https://YOUR_TUNNEL_NODE_URL";
const TUNNEL_AUTH_KEY = "YOUR_TUNNEL_AUTH_KEY";

const SKIP_HEADERS = {
  host: 1, connection: 1, "content-length": 1,
  "transfer-encoding": 1, "proxy-connection": 1, "proxy-authorization": 1,
  "x-forwarded-for": 1, "x-forwarded-host": 1, "x-forwarded-proto": 1,
  "x-forwarded-port": 1, "x-real-ip": 1, "forwarded": 1, "via": 1,
};

const SAFE_REPLAY_METHODS = { GET: 1, HEAD: 1, OPTIONS: 1 };

function _fetchViaExitNode(req) {
  try {
    var en = req.en;
    if (!en || typeof en !== "object") return null;
    var relayUrl = en.relay_url;
    var exitPsk = en.psk;
    if (
      !relayUrl ||
      typeof relayUrl !== "string" ||
      !relayUrl.match(/^https?:\/\//i) ||
      !exitPsk ||
      typeof exitPsk !== "string"
    ) {
      return null;
    }
    var inner = {
      k: exitPsk,
      u: req.u,
      m: (req.m || "GET").toUpperCase(),
    };
    if (req.h && typeof req.h === "object") inner.h = req.h;
    if (req.b) inner.b = req.b;
    var resp = UrlFetchApp.fetch(relayUrl, {
      method: "post",
      contentType: "application/json",
      payload: JSON.stringify(inner),
      muteHttpExceptions: true,
      followRedirects: true,
    });
    var text = resp.getContentText();
    var data = JSON.parse(text);
    if (data.e) return null;
    if (typeof data.s !== "number") return null;
    if (!data.h || typeof data.h !== "object") return null;
    if (typeof data.b !== "string") return null;
    return data;
  } catch (err) {
    return null;
  }
}

function doPost(e) {
  try {
    var req = JSON.parse(e.postData.contents);
    if (req.k !== AUTH_KEY) return _json({ e: "unauthorized" });
    if (req.t) return _doTunnel(req);
    if (Array.isArray(req.q)) return _doBatch(req.q);
    return _doSingle(req);
  } catch (err) {
    return _json({ e: String(err) });
  }
}

function doGet(e) {
  return ContentService.createTextOutput("ok")
    .setMimeType(ContentService.MimeType.TEXT);
}

function _doTunnel(req) {
  if (req.t === "batch") {
    return _doTunnelBatch(req);
  }
  var payload = { k: TUNNEL_AUTH_KEY };
  switch (req.t) {
    case "connect":
      payload.op = "connect";
      payload.host = req.h;
      payload.port = req.p;
      break;
    case "connect_data":
      payload.op = "connect_data";
      payload.host = req.h;
      payload.port = req.p;
      if (req.d) payload.data = req.d;
      break;
    case "data":
      payload.op = "data";
      payload.sid = req.sid;
      if (req.d) payload.data = req.d;
      break;
    case "close":
      payload.op = "close";
      payload.sid = req.sid;
      break;
    default:
      return _json({ e: "unknown tunnel op: " + req.t, code: "UNSUPPORTED_OP" });
  }
  return _forwardTunnelJson("/tunnel", payload, "tunnel node");
}

function _doTunnelBatch(req) {
  var ops = req.ops;
  if (!Array.isArray(ops)) return _json({ e: "bad tunnel batch ops" });
  var payload = { k: TUNNEL_AUTH_KEY, ops: ops };
  return _forwardTunnelJson("/tunnel/batch", payload, "tunnel batch");
}

function _forwardTunnelJson(path, payload, label) {
  var resp = UrlFetchApp.fetch(TUNNEL_SERVER_URL + path, {
    method: "post",
    contentType: "application/json",
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
    followRedirects: true,
  });
  if (resp.getResponseCode() !== 200) {
    return _json({ e: label + " HTTP " + resp.getResponseCode() });
  }
  return ContentService.createTextOutput(resp.getContentText())
    .setMimeType(ContentService.MimeType.JSON);
}

function _doSingle(req) {
  if (!req.u || typeof req.u !== "string" || !req.u.match(/^https?:\/\//i)) {
    return _json({ e: "bad url" });
  }
  if (req.en && req.en.relay_url && req.en.psk) {
    var viaExit = _fetchViaExitNode(req);
    if (viaExit) {
      return _json({
        s: viaExit.s,
        h: viaExit.h,
        b: viaExit.b,
      });
    }
  }
  var opts = _buildOpts(req);
  var resp = UrlFetchApp.fetch(req.u, opts);
  return _json({
    s: resp.getResponseCode(),
    h: _respHeaders(resp),
    b: Utilities.base64Encode(resp.getContent()),
  });
}

function _doBatch(items) {
  var results = new Array(items.length);
  var fetchArgs = [];
  var fetchIndex = [];
  var fetchMethods = [];
  var i;
  var j;

  for (i = 0; i < items.length; i++) {
    var item = items[i];
    if (!item || typeof item !== "object") {
      results[i] = { e: "bad item" };
      continue;
    }
    if (!item.u || typeof item.u !== "string" || !item.u.match(/^https?:\/\//i)) {
      results[i] = { e: "bad url" };
      continue;
    }
    if (item.en && item.en.relay_url && item.en.psk) {
      var viaExit = _fetchViaExitNode(item);
      if (viaExit) {
        results[i] = {
          s: viaExit.s,
          h: viaExit.h,
          b: viaExit.b,
        };
        continue;
      }
    }
    try {
      var opts = _buildOpts(item);
      opts.url = item.u;
      fetchArgs.push(opts);
      fetchIndex.push(i);
      fetchMethods.push(String(item.m || "GET").toUpperCase());
      results[i] = null;
    } catch (err) {
      results[i] = { e: String(err) };
    }
  }

  var responses = [];
  if (fetchArgs.length > 0) {
    try {
      responses = UrlFetchApp.fetchAll(fetchArgs);
    } catch (err) {
      responses = [];
      for (j = 0; j < fetchArgs.length; j++) {
        try {
          if (!SAFE_REPLAY_METHODS[fetchMethods[j]]) {
            results[fetchIndex[j]] = { e: "batch fetchAll failed; unsafe method not replayed" };
            responses[j] = null;
            continue;
          }
          var fallbackReq = fetchArgs[j];
          var fallbackUrl = fallbackReq.url;
          var fallbackOpts = {};
          for (var key in fallbackReq) {
            if (Object.prototype.hasOwnProperty.call(fallbackReq, key) && key !== "url") {
              fallbackOpts[key] = fallbackReq[key];
            }
          }
          responses[j] = UrlFetchApp.fetch(fallbackUrl, fallbackOpts);
        } catch (singleErr) {
          results[fetchIndex[j]] = { e: String(singleErr) };
          responses[j] = null;
        }
      }
    }
  }

  var rIdx = 0;
  for (i = 0; i < items.length; i++) {
    if (results[i] !== null) continue;
    var resp = responses[rIdx++];
    if (!resp) {
      if (!results[i]) results[i] = { e: "fetch failed" };
    } else {
      results[i] = {
        s: resp.getResponseCode(),
        h: _respHeaders(resp),
        b: Utilities.base64Encode(resp.getContent()),
      };
    }
  }
  return _json({ q: results });
}

function _buildOpts(req) {
  var opts = {
    method: (req.m || "GET").toLowerCase(),
    muteHttpExceptions: true,
    followRedirects: req.r !== false,
    validateHttpsCertificates: true,
    escaping: false,
  };
  if (req.h && typeof req.h === "object") {
    var headers = {};
    for (var k in req.h) {
      if (req.h.hasOwnProperty(k) && !SKIP_HEADERS[k.toLowerCase()]) {
        headers[k] = req.h[k];
      }
    }
    opts.headers = headers;
  }
  if (req.b) {
    opts.payload = Utilities.base64Decode(req.b);
    if (req.ct) opts.contentType = req.ct;
  }
  return opts;
}

function _respHeaders(resp) {
  try {
    if (typeof resp.getAllHeaders === "function") {
      return resp.getAllHeaders();
    }
  } catch (err) {}
  return resp.getHeaders();
}

function _json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
"""#

/// Cloudflare-routing Code.gs — forwards every request to the Worker.
private let codeGS_Cloudflare: String = #"""
/**
 * DomainFront Relay — Google Apps Script With Cloudflare Worker Exit
 *
 * FLOW:
 *   Client → GAS (Google Apps Script) → CFW (Cloudflare Worker) → Internet
 *
 * MODES:
 *   1. Single:  POST { k, m, u, h, b, ct, r }       → { s, h, b }
 *   2. Batch:   POST { k, q: [{m,u,h,b,ct,r}, ...] } → { q: [{s,h,b}, ...] }
 */

const AUTH_KEY = "STRONG_SECRET_KEY";
const WORKER_URL = "https://example.workers.dev";

const SKIP_HEADERS = {
  host: 1, connection: 1, "content-length": 1,
  "transfer-encoding": 1, "proxy-connection": 1, "proxy-authorization": 1,
  "priority": 1, te: 1,
  "x-forwarded-for": 1, "x-forwarded-host": 1, "x-forwarded-proto": 1,
  "x-forwarded-port": 1, "x-real-ip": 1, "forwarded": 1, "via": 1,
};

const SAFE_REPLAY_METHODS = { GET: 1, HEAD: 1, OPTIONS: 1 };

function _fetchViaExitNode(req) {
  try {
    var en = req.en;
    if (!en || typeof en !== "object") return null;
    var relayUrl = en.relay_url;
    var exitPsk = en.psk;
    if (
      !relayUrl ||
      typeof relayUrl !== "string" ||
      !relayUrl.match(/^https?:\/\//i) ||
      !exitPsk ||
      typeof exitPsk !== "string"
    ) {
      return null;
    }
    var inner = {
      k: exitPsk,
      u: req.u,
      m: (req.m || "GET").toUpperCase(),
    };
    if (req.h && typeof req.h === "object") inner.h = req.h;
    if (req.b) inner.b = req.b;
    var resp = UrlFetchApp.fetch(relayUrl, {
      method: "post",
      contentType: "application/json",
      payload: JSON.stringify(inner),
      muteHttpExceptions: true,
      followRedirects: true,
    });
    var text = resp.getContentText();
    var data = JSON.parse(text);
    if (data.e) return null;
    if (typeof data.s !== "number") return null;
    if (!data.h || typeof data.h !== "object") return null;
    if (typeof data.b !== "string") return null;
    return data;
  } catch (err) {
    return null;
  }
}

function doPost(e) {
  try {
    var req = JSON.parse(e.postData.contents);
    if (req.k !== AUTH_KEY) return _json({ e: "unauthorized" });

    if (Array.isArray(req.q)) return _doBatch(req.q);
    return _doSingle(req);

  } catch (err) {
    return _json({ e: String(err) });
  }
}

function _doSingle(req) {
  if (!req.u || typeof req.u !== "string" || !req.u.match(/^https?:\/\//i)) {
    return _json({ e: "bad url" });
  }

  if (req.en && req.en.relay_url && req.en.psk) {
    var viaExit = _fetchViaExitNode(req);
    if (viaExit) {
      return _json({
        s: viaExit.s,
        h: viaExit.h,
        b: viaExit.b,
      });
    }
  }

  var payload = _buildWorkerPayload(req);

  var resp = UrlFetchApp.fetch(WORKER_URL, {
    method: "post",
    contentType: "application/json",
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
    followRedirects: true
  });

  try {
    return _json(JSON.parse(resp.getContentText()));
  } catch (e) {
    return _json({ e: "invalid worker response", raw: resp.getContentText() });
  }
}

function _doBatch(items) {
  var results = new Array(items.length);
  var fetchArgs = [];
  var fetchIndex = [];
  var fetchMethods = [];
  var i;
  var j;

  for (i = 0; i < items.length; i++) {
    var item = items[i];

    if (!item || typeof item !== "object") {
      results[i] = { e: "bad item" };
      continue;
    }
    if (!item.u || typeof item.u !== "string" || !item.u.match(/^https?:\/\//i)) {
      results[i] = { e: "bad url" };
      continue;
    }

    if (item.en && item.en.relay_url && item.en.psk) {
      var viaExit = _fetchViaExitNode(item);
      if (viaExit) {
        results[i] = {
          s: viaExit.s,
          h: viaExit.h,
          b: viaExit.b,
        };
        continue;
      }
    }

    try {
      var payload = _buildWorkerPayload(item);

      fetchArgs.push({
        url: WORKER_URL,
        method: "post",
        contentType: "application/json",
        payload: JSON.stringify(payload),
        muteHttpExceptions: true,
        followRedirects: true
      });
      fetchIndex.push(i);
      fetchMethods.push("POST");
      results[i] = null;
    } catch (err) {
      results[i] = { e: String(err) };
    }
  }

  var responses = [];
  if (fetchArgs.length > 0) {
    try {
      responses = UrlFetchApp.fetchAll(fetchArgs);
    } catch (err) {
      responses = [];
      for (j = 0; j < fetchArgs.length; j++) {
        try {
          if (!SAFE_REPLAY_METHODS[fetchMethods[j]]) {
            results[fetchIndex[j]] = {
              e: "batch fetchAll failed; unsafe method not replayed",
            };
            responses[j] = null;
            continue;
          }
          var args = fetchArgs[j];
          var url = args.url;
          var fetchOpts = {};
          for (var key in args) {
            if (Object.prototype.hasOwnProperty.call(args, key) && key !== "url") {
              fetchOpts[key] = args[key];
            }
          }
          responses[j] = UrlFetchApp.fetch(url, fetchOpts);
        } catch (singleErr) {
          results[fetchIndex[j]] = { e: String(singleErr) };
          responses[j] = null;
        }
      }
    }
  }

  var rIdx = 0;
  for (i = 0; i < items.length; i++) {
    if (results[i] !== null) continue;
    var resp = responses[rIdx++];
    if (!resp) {
      if (!results[i]) results[i] = { e: "fetch failed" };
    } else {
      try {
        results[i] = JSON.parse(resp.getContentText());
      } catch (e) {
        results[i] = { e: "invalid worker response", raw: resp.getContentText() };
      }
    }
  }

  return _json({ q: results });
}

function _buildWorkerPayload(req) {
  var headers = {};

  if (req.h && typeof req.h === "object") {
    for (var k in req.h) {
      if (req.h.hasOwnProperty(k) && !SKIP_HEADERS[k.toLowerCase()]) {
        headers[k] = req.h[k];
      }
    }
  }

  return {
    u: req.u,
    m: (req.m || "GET").toUpperCase(),
    h: headers,
    b: req.b || null,
    ct: req.ct || null,
    r: req.r !== false
  };
}

function doGet(e) {
  return HtmlService.createHtmlOutput(
    "<!DOCTYPE html><html><head><title>My App</title></head>" +
      '<body style="font-family:sans-serif;max-width:600px;margin:40px auto">' +
      "<h1>Relay Active</h1><p>Cloudflare Worker routing enabled.</p>" +
      "</body></html>"
  );
}

function _json(obj) {
  var out = {};
  if (obj && typeof obj === "object" && !Array.isArray(obj)) {
    for (var k in obj) {
      if (Object.prototype.hasOwnProperty.call(obj, k)) {
        out[k] = obj[k];
      }
    }
  }
  out.cap = 2;
  return ContentService
    .createTextOutput(JSON.stringify(out))
    .setMimeType(ContentService.MimeType.JSON);
}
"""#

/// Cloudflare Worker — fetches the target URL on behalf of the Apps Script.
private let workerJS: String = #"""
const WORKER_URL = "myworker.workers.dev";

export default {
  async fetch(request) {
    try {
      if (request.headers.get("x-relay-hop") === "1") {
        return json({ e: "loop detected" }, 508);
      }

      const req = await request.json();

      if (!req.u) {
        return json({ e: "missing url" }, 400);
      }

      const targetUrl = new URL(req.u);

      const BLOCKED_HOSTS = [
        WORKER_URL,
      ];

      if (BLOCKED_HOSTS.some(h => targetUrl.hostname.endsWith(h))) {
        return json({ e: "self-fetch blocked" }, 400);
      }

      const headers = new Headers();
      if (req.h && typeof req.h === "object") {
        for (const [k, v] of Object.entries(req.h)) {
          headers.set(k, v);
        }
      }

      headers.set("x-relay-hop", "1");

      const fetchOptions = {
        method: (req.m || "GET").toUpperCase(),
        headers,
        redirect: req.r === false ? "manual" : "follow"
      };

      if (req.b) {
        const binary = Uint8Array.from(atob(req.b), c => c.charCodeAt(0));
        fetchOptions.body = binary;
      }

      const resp = await fetch(targetUrl.toString(), fetchOptions);

      // Read response safely (no stack overflow)
      const buffer = await resp.arrayBuffer();
      const uint8 = new Uint8Array(buffer);

      let binary = "";
      const chunkSize = 0x8000; // prevent call stack overflow

      for (let i = 0; i < uint8.length; i += chunkSize) {
        binary += String.fromCharCode.apply(
          null,
          uint8.subarray(i, i + chunkSize)
        );
      }

      const base64 = btoa(binary);

      const responseHeaders = {};
      resp.headers.forEach((v, k) => {
        responseHeaders[k] = v;
      });

      return json({
        s: resp.status,
        h: responseHeaders,
        b: base64
      });

    } catch (err) {
      return json({ e: String(err) }, 500);
    }
  }
};

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      "content-type": "application/json"
    }
  });
}
"""#
