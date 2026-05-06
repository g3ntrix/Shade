import SwiftUI
import AppKit

/// Top-level setup wizard: Apps Script, Cloudflare Worker, and tunnel-node on a VPS (Docker; install script clears legacy systemd + prior tunnel containers).
struct SetupView: View {
    enum Mode { case chooser, appsScript, cloudflare, exitRelay }
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
        case .exitRelay:
            VPSExitNodeSetupView(onBack: {
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
                    Text("Setup Wizard")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Pick your main relay path. Full tunnel uses tunnel-node on your VPS (one install script) with CodeFull.gs.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 14) {
                    ChooserCard(
                        title: "Apps Script only",
                        subtitle: "Simplest, 4 steps",
                        details: "Standard relay on Google Apps Script. Traffic exits from Google IPs.",
                        icon: "doc.text.fill",
                        accent: .purple
                    ) {
                        onPick(.appsScript)
                    }

                    ChooserCard(
                        title: "Cloudflare Worker",
                        subtitle: "Apps Script + Worker, 6 steps",
                        details: "Apps Script forwards to a Worker. Traffic exits from Cloudflare IPs.",
                        icon: "cloud.fill",
                        accent: .orange
                    ) {
                        onPick(.cloudflare)
                    }

                    ChooserCard(
                        title: "Tunnel node (VPS)",
                        subtitle: "Full tunnel — Docker",
                        details: "Docker installs tunnel-node on the first free port in a safe range, then you deploy Apps Script and paste your Deployment ID.",
                        icon: "server.rack",
                        accent: .teal
                    ) {
                        onPick(.exitRelay)
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
                    Text("Start wizard")
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
    @State private var authKeyDraft: String = SetupRandom.hexKey()
    @State private var authKeyConfirmed: Bool = true
    @State private var deploymentIDDraft: String = ""
    @State private var profileNameDraft: String = ""
    @State private var profileSaved: Bool = false

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
                Select everything in the default Code.gs, delete it, then paste \
                the code below. Shade has already generated a strong random \
                Auth Key for you and embedded it in the code — no manual edit \
                needed. Save with ⌘S.
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
            title: "Paste your Deployment ID",
            body:
                """
                After deploying, Google shows a "Deployment ID" (starts with AKfycb…) \
                and a "Web app URL". Copy the Deployment ID and paste it below — \
                Shade saves the profile (Script ID + Auth Key) automatically. \
                Then head to the Dashboard and hit Start.
                """,
            showProfileSave: true
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WizardHeader(
                    title: "Apps Script Setup",
                    subtitle: "Get your Google Apps Script deployment running in four short steps.",
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

                if s.showAuthKey {
                    if authKeyConfirmed {
                        VStack(alignment: .leading, spacing: 8) {
                            GeneratedKeyDisplay(
                                value: authKeyDraft,
                                accent: accent,
                                onRegenerate: { authKeyDraft = SetupRandom.hexKey() },
                                onChange: { authKeyConfirmed = false }
                            )
                            CodeSnippet(
                                filename: "Code.gs",
                                code: codeGS_AppsScriptOnly
                                    .replacingOccurrences(
                                        of: "CHANGE_ME_TO_A_STRONG_SECRET",
                                        with: authKeyDraft
                                            .replacingOccurrences(of: "\"", with: "\\\"")
                                    ),
                                accent: accent
                            )
                        }
                    } else {
                        AuthKeyPrompt(authKey: $authKeyDraft, accent: accent) {
                            authKeyConfirmed = true
                        }
                    }
                }

                if s.showProfileSave {
                    ProfileSavePanel(
                        accent: accent,
                        profileName: $profileNameDraft,
                        deploymentID: $deploymentIDDraft,
                        authKey: authKeyDraft,
                        saved: $profileSaved,
                        usesCloudflare: false,
                        onSave: saveProfile
                    )
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
    }

    private func saveProfile() {
        let sid = deploymentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty, !authKeyDraft.isEmpty else { return }
        let name = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Apps Script \(app.settings.credentials.count + 1)"
            : profileNameDraft
        let cred = Credential(
            name: name,
            scriptID: sid,
            authKey: authKeyDraft,
            usesCloudflare: false
        )
        app.settings.credentials.append(cred)
        app.settings.activeCredentialID = cred.id
        app.saveSettings()
        withAnimation { profileSaved = true }
    }
}

// MARK: - Cloudflare branch

private struct CloudflareSetupView: View {
    @EnvironmentObject var app: AppState
    let onBack: () -> Void

    @State private var step: Int = 0
    @State private var workerURLDraft: String = ""
    @State private var workerURLConfirmed: Bool = false
    @State private var authKeyDraft: String = SetupRandom.hexKey()
    @State private var authKeyConfirmed: Bool = true
    @State private var deploymentIDDraft: String = ""
    @State private var profileNameDraft: String = ""
    @State private var profileSaved: Bool = false

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
                Shade has already generated a strong random Auth Key and baked \
                it (and your Worker URL) into the code below — no manual edit \
                needed. Copy the result, paste it into the Apps Script editor, \
                and save with ⌘S.
                """,
            showAuthKey: true,
            codeKind: .codeGS_CF
        ),
        .init(
            title: "Deploy Apps Script & paste Deployment ID",
            body:
                """
                Click Deploy → New deployment. For "Select type" click the gear \
                icon and pick Web app. Configure:

                  • Description: anything you want
                  • Execute as: Me
                  • Who has access: Anyone

                Authorize the script if Google asks. Copy the Deployment ID and \
                paste it below — Shade saves the profile (with the Cloudflare \
                tag) automatically. Then head to the Dashboard and hit Start.
                """,
            showProfileSave: true
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WizardHeader(
                    title: "Cloudflare Worker Setup",
                    subtitle: "Deploy a Cloudflare Worker plus a Google Apps Script that forwards to it. 6 steps.",
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
                        GeneratedKeyDisplay(
                            value: authKeyDraft,
                            accent: accent,
                            onRegenerate: { authKeyDraft = SetupRandom.hexKey() },
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

                if s.showProfileSave {
                    ProfileSavePanel(
                        accent: accent,
                        profileName: $profileNameDraft,
                        deploymentID: $deploymentIDDraft,
                        authKey: authKeyDraft,
                        saved: $profileSaved,
                        usesCloudflare: true,
                        onSave: saveProfile
                    )
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

    private func saveProfile() {
        let sid = deploymentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty, !authKeyDraft.isEmpty else { return }
        let name = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Cloudflare \(app.settings.credentials.count + 1)"
            : profileNameDraft
        let cred = Credential(
            name: name,
            scriptID: sid,
            authKey: authKeyDraft,
            usesCloudflare: true
        )
        app.settings.credentials.append(cred)
        app.settings.activeCredentialID = cred.id
        app.saveSettings()
        withAnimation { profileSaved = true }
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

// MARK: - Tunnel node on VPS (Docker, dynamic port)

private struct VPSExitNodeSetupView: View {
    private enum TunnelPorts {
        static let scanStart = 18_080
        static let scanEnd = 18_199
    }

    @EnvironmentObject var app: AppState
    let onBack: () -> Void
    @State private var step: Int = 0
    @State private var serverIP: String = ""
    @State private var tunnelListenPortDraft: String = ""
    @State private var relayAuthKeyDraft: String = SetupRandom.hexKey()
    @State private var tunnelAuthKeyDraft: String = SetupRandom.hexKey()
    @State private var deploymentIDDraft: String = ""
    @State private var profileNameDraft: String = ""
    @State private var profileSaved: Bool = false

    private let accent: Color = .teal

    private let steps: [WizardStep] = [
        .init(
            title: "What this does",
            body:
                """
                How it works:

                  Your apps → Shade → Google Apps Script → your VPS tunnel node → internet

                You will do three things:

                  1) Run one install script on the VPS
                  2) Deploy one Google Apps Script (we generate it for you)
                  3) Paste the Deployment ID back into Shade
                """
        ),
        .init(
            title: "Install the tunnel node on your VPS",
            body:
                """
                1) Enter your VPS public IP or hostname below.

                2) Paste the install script on the VPS (Docker required).
                   It will pick a free port in \(TunnelPorts.scanStart) to \(TunnelPorts.scanEnd) and print TUNNEL_PORT.

                3) Save the printed TUNNEL_PORT value.

                4) Open that TCP port in your cloud firewall.
                """
        ),
        .init(
            title: "Set tunnel port and deploy Apps Script",
            body:
                """
                1) Enter the TUNNEL_PORT value from the VPS output in the Tunnel port field.

                2) Open script.google.com and create a New project.

                3) Delete everything in Code.gs and paste the generated script below.

                4) Save.

                5) Deploy as a Web app:
                   - Execute as: Me
                   - Who has access: Anyone
                """,
            link: URL(string: "https://script.google.com/home/projects/create")
        ),
        .init(
            title: "Save the Deployment ID",
            body:
                """
                Copy the Deployment ID (it starts with AKfycb) and paste it below.

                Shade will add the profile and activate Full tunnel for that profile.
                """,
            showProfileSave: true
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WizardHeader(
                    title: "Full tunnel (VPS)",
                    subtitle: "Run one VPS install script, deploy one Apps Script, paste the Deployment ID.",
                    onBack: onBack,
                    accent: accent
                )
                StepperBar(count: steps.count, current: step, accent: accent)
                stepCard
            }
        }
    }

    private var trimmedVPSInput: String {
        serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var targetHost: String {
        let t = trimmedVPSInput
        return t.isEmpty ? "YOUR_VPS_IP" : t
    }

    /// Host part for display (no scheme, no path); strips optional :port for labeling.
    private var targetHostLabel: String {
        var h = trimmedVPSInput
        if h.isEmpty { return "VPS" }
        if let r = h.range(of: "://") { h = String(h[r.upperBound...]) }
        if let idx = h.firstIndex(of: "/") { h = String(h[..<idx]) }
        h = h.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let colon = h.lastIndex(of: ":"),
           h[h.index(after: colon)...].allSatisfy(\.isNumber) {
            return String(h[..<colon])
        }
        return h
    }

    /// Port for TUNNEL_SERVER_URL when the user does not type host:port in the IP field.
    private var effectiveTunnelPortForURL: String {
        let t = tunnelListenPortDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = Int(t), (1024...65_535).contains(p) { return "\(p)" }
        return "\(TunnelPorts.scanStart)"
    }

    private var normalizedTunnelBaseURL: String {
        var h = trimmedVPSInput
        if h.isEmpty { return "http://YOUR_VPS_IP:\(effectiveTunnelPortForURL)" }
        if let r = h.range(of: "://") { h = String(h[r.upperBound...]) }
        if let idx = h.firstIndex(of: "/") { h = String(h[..<idx]) }
        h = h.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hostPart: String
        let portPart: String
        if let colon = h.lastIndex(of: ":"),
           h[h.index(after: colon)...].allSatisfy(\.isNumber) {
            hostPart = String(h[..<colon])
            portPart = String(h[h.index(after: colon)...])
        } else {
            hostPart = h
            portPart = effectiveTunnelPortForURL
        }
        return "http://\(hostPart):\(portPart)"
    }

    private var isTunnelPortFieldValid: Bool {
        guard let p = Int(tunnelListenPortDraft.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (1024...65_535).contains(p)
    }

    private var canProceedFromInstallStep: Bool {
        !trimmedVPSInput.isEmpty
            && !relayAuthKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !tunnelAuthKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var publicHostForEmbeddedScript: String {
        if trimmedVPSInput.isEmpty { return "YOUR_PUBLIC_IP" }
        return targetHostLabel
    }

    /// Docker + host network; first free port in scan range (avoids Xray etc. on 8080/18080).
    private var vpsBootstrapScript: String {
        let key = tunnelAuthKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedKey = key.replacingOccurrences(of: "'", with: "'\\''")
        let escapedHost = publicHostForEmbeddedScript.replacingOccurrences(of: "'", with: "'\\''")
        return """
        set -euo pipefail
        TUNNEL_AUTH_KEY='\(escapedKey)'
        PUBLIC_HOST='\(escapedHost)'
        IMAGE='ghcr.io/therealaleph/mhrv-tunnel-node:latest'
        if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO=sudo; fi
        if ! command -v docker >/dev/null 2>&1; then
          echo "docker missing: installing docker.io..."
          $SUDO apt-get update -y
          $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
        fi
        $SUDO systemctl enable --now containerd 2>/dev/null || true
        $SUDO systemctl enable --now docker 2>/dev/null || true
        READY=""
        for i in $(seq 1 30); do
          if $SUDO docker info >/dev/null 2>&1; then
            READY=1
            break
          fi
          if [ "$i" -eq 10 ] || [ "$i" -eq 20 ]; then
            $SUDO systemctl restart containerd 2>/dev/null || true
            $SUDO systemctl restart docker 2>/dev/null || true
          fi
          sleep 2
        done
        if [ -z "${READY:-}" ]; then
          echo "error: docker is installed but not ready after waiting." >&2
          echo "check: sudo systemctl status containerd docker" >&2
          echo "logs: sudo journalctl -u containerd -u docker --no-pager | tail -n 120" >&2
          exit 1
        fi
        # Legacy native install (older wizard): stop, untrack, drop unit file.
        $SUDO systemctl stop mhrv-tunnel-node 2>/dev/null || true
        $SUDO systemctl disable mhrv-tunnel-node 2>/dev/null || true
        $SUDO rm -f /etc/systemd/system/mhrv-tunnel-node.service 2>/dev/null || true
        $SUDO rm -f /lib/systemd/system/mhrv-tunnel-node.service 2>/dev/null || true
        $SUDO rm -f /usr/lib/systemd/system/mhrv-tunnel-node.service 2>/dev/null || true
        $SUDO systemctl daemon-reload 2>/dev/null || true
        # Prior Docker tunnel-node(s): standard name and any container from this image.
        $SUDO docker rm -f mhrv-tunnel 2>/dev/null || true
        _IDS=$($SUDO docker ps -aq --filter ancestor="$IMAGE" 2>/dev/null) || true
        for _id in $_IDS; do
          $SUDO docker rm -f "$_id" 2>/dev/null || true
        done
        CHOSEN=""
        for p in $(seq \(TunnelPorts.scanStart) \(TunnelPorts.scanEnd)); do
          if ! ss -lntp 2>/dev/null | grep -qE ":${p}\\b"; then
            CHOSEN=$p
            break
          fi
        done
        if [ -z "${CHOSEN:-}" ]; then
          echo "error: no free TCP port in \(TunnelPorts.scanStart)-\(TunnelPorts.scanEnd) (ss -lntp)." >&2
          exit 1
        fi
        PULLED=""
        for i in $(seq 1 6); do
          if $SUDO docker pull "$IMAGE"; then
            PULLED=1
            break
          fi
          echo "warn: docker pull failed (attempt $i/6). retrying in 5s..."
          sleep 5
        done
        if [ -z "${PULLED:-}" ]; then
          echo "error: failed to pull $IMAGE after retries (network/TLS issue)." >&2
          exit 1
        fi
        $SUDO docker run -d --name mhrv-tunnel --restart unless-stopped \\
          --network host \\
          -e "PORT=${CHOSEN}" \\
          -e "TUNNEL_AUTH_KEY=${TUNNEL_AUTH_KEY}" \\
          "$IMAGE"
        sleep 2
        set +e
        HC=$(curl -fsS "http://127.0.0.1:${CHOSEN}/health" 2>/dev/null)
        set -eu
        if printf '%s' "$HC" | grep -q ok; then
          echo "ok: tunnel-node is up on port ${CHOSEN}."
        else
          echo "warn: curl http://127.0.0.1:${CHOSEN}/health failed — docker logs mhrv-tunnel"
        fi
        echo ""
        echo "========================================"
        echo "  COPY THIS PORT NUMBER INTO SHADE"
        echo "            ${CHOSEN}"
        echo "========================================"
        echo "TUNNEL_SERVER_URL=http://${PUBLIC_HOST}:${CHOSEN}"
        echo "Open TCP ${CHOSEN} in your cloud firewall."
        """
    }

    /// Cleanup snippet users can run later to fully remove the deployed tunnel node.
    private var vpsRemovalScript: String {
        let escapedImage = "ghcr.io/therealaleph/mhrv-tunnel-node:latest"
            .replacingOccurrences(of: "'", with: "'\\''")
        return """
        set -euo pipefail
        IMAGE='\(escapedImage)'
        if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO=sudo; fi
        $SUDO docker rm -f mhrv-tunnel 2>/dev/null || true
        _IDS=$($SUDO docker ps -aq --filter ancestor="$IMAGE" 2>/dev/null) || true
        for _id in $_IDS; do
          $SUDO docker rm -f "$_id" 2>/dev/null || true
        done
        $SUDO systemctl stop mhrv-tunnel-node 2>/dev/null || true
        $SUDO systemctl disable mhrv-tunnel-node 2>/dev/null || true
        $SUDO rm -f /etc/systemd/system/mhrv-tunnel-node.service 2>/dev/null || true
        $SUDO rm -f /lib/systemd/system/mhrv-tunnel-node.service 2>/dev/null || true
        $SUDO rm -f /usr/lib/systemd/system/mhrv-tunnel-node.service 2>/dev/null || true
        $SUDO systemctl daemon-reload 2>/dev/null || true
        echo "done: tunnel-node deployment cleanup finished."
        """
    }

    private var renderedFullTunnelScript: String {
        let auth = Self.jsStringLiteral(relayAuthKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        let tunnel = Self.jsStringLiteral(tunnelAuthKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        let url = Self.jsStringLiteral(normalizedTunnelBaseURL)
        return codeGS_FullTunnelTemplate
            .replacingOccurrences(of: "<<SHADE_AUTH_KEY>>", with: auth)
            .replacingOccurrences(of: "<<TUNNEL_SERVER_URL>>", with: url)
            .replacingOccurrences(of: "<<TUNNEL_PSK>>", with: tunnel)
    }

    private static func jsStringLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func saveTunnelProfile() {
        let sid = deploymentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let auth = relayAuthKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tunnelKey = tunnelAuthKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sid.count >= 8, !auth.isEmpty, !tunnelKey.isEmpty else { return }
        let baseURL = normalizedTunnelBaseURL
        let tunnelProf = ExitNodeProfile(
            name: "Tunnel \(targetHostLabel)",
            relayURL: baseURL,
            psk: tunnelKey
        )
        let name = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Full tunnel \(app.settings.credentials.count + 1)"
            : profileNameDraft
        let cred = Credential(
            name: name,
            scriptID: sid,
            authKey: auth,
            usesCloudflare: false,
            usesFullTunnel: true,
            usesExitTag: true,
            linkedExitNodeProfileID: tunnelProf.id
        )
        app.settings.credentials.append(cred)
        app.settings.activeCredentialID = cred.id
        app.settings.exitNodeProfiles.append(tunnelProf)
        app.settings.activeExitNodeProfileID = tunnelProf.id
        app.settings.exitRoutingAllowed = true
        app.settings.exitRelayActive = true
        app.saveSettings()
        withAnimation { profileSaved = true }
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

                if step == 1 {
                    TextField("VPS public IP or hostname (e.g. 203.0.113.50)", text: $serverIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    VStack(alignment: .leading, spacing: 12) {
                        keyBlock(
                            title: "AUTH_KEY (Shade + Apps Script)",
                            binding: $relayAuthKeyDraft,
                            regenerate: { relayAuthKeyDraft = SetupRandom.hexKey() }
                        )
                        keyBlock(
                            title: "TUNNEL_AUTH_KEY (server + Apps Script)",
                            binding: $tunnelAuthKeyDraft,
                            regenerate: { tunnelAuthKeyDraft = SetupRandom.hexKey() }
                        )
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.04))
                    )

                    Text("Tunnel base URL used in script: \(normalizedTunnelBaseURL)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    CodeSnippet(
                        filename: "install-tunnel-node.sh — paste once on the VPS",
                        code: vpsBootstrapScript,
                        accent: accent
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Remove from VPS (optional)", systemImage: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("If you want to uninstall this deployment later, run this cleanup snippet on the VPS.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CodeSnippet(
                        filename: "remove-tunnel-node.sh — cleanup command",
                        code: vpsRemovalScript,
                        accent: .red
                    )
                }

                if step == 2 {
                    HStack(spacing: 8) {
                        Text("1) Enter TUNNEL_PORT:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. 18080", text: $tunnelListenPortDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 110)
                    }

                    if isTunnelPortFieldValid {
                        CodeSnippet(
                            filename: "Code.gs (full tunnel)",
                            code: renderedFullTunnelScript,
                            accent: accent
                        )
                    } else {
                        Text("Paste the VPS script first, copy TUNNEL_PORT from its output, then enter it here to generate Code.gs.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if s.showProfileSave {
                    ProfileSavePanel(
                        accent: accent,
                        profileName: $profileNameDraft,
                        deploymentID: $deploymentIDDraft,
                        authKey: relayAuthKeyDraft,
                        saved: $profileSaved,
                        usesCloudflare: false,
                        onSave: saveTunnelProfile
                    )
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
                    nextDisabled: (step == 1 && !canProceedFromInstallStep) || (step == 2 && !isTunnelPortFieldValid)
                )
            }
        }
    }

    private func keyBlock(title: String, binding: Binding<String>, regenerate: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button("Regenerate", action: regenerate)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent)
            }
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }
}

// MARK: - Shared wizard chrome

private struct WizardStep {
    let title: String
    let body:  String
    var link:  URL?    = nil
    var showAuthKey:    Bool = false
    var showWorkerURL:  Bool = false
    var showProfileSave: Bool = false
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


// CodeFull.gs — keep in sync with apps_script/CodeFull.gs
let codeGS_FullTunnelTemplate: String = #"""
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

const AUTH_KEY = "<<SHADE_AUTH_KEY>>";
const TUNNEL_SERVER_URL = "<<TUNNEL_SERVER_URL>>";
const TUNNEL_AUTH_KEY = "<<TUNNEL_PSK>>";

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
  var base = String(TUNNEL_SERVER_URL || "").replace(/\/+$/, "");
  var url = base + path;
  var resp = UrlFetchApp.fetch(url, {
    method: "post",
    contentType: "application/json",
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
    followRedirects: true,
  });
  var status = resp.getResponseCode();
  if (status !== 200) {
    var body = "";
    try { body = resp.getContentText(); } catch (err) {}
    if (body && body.length > 240) body = body.substring(0, 240);
    return _json({
      e: label + " HTTP " + status,
      u: url,
      b: body
    });
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

// MARK: - Setup helpers (auto-generated key + profile save panel)

enum SetupRandom {
    /// 32 hex chars (128 bits of entropy) — strong enough as AUTH_KEY.
    static func hexKey(byteCount: Int = 16) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<byteCount { bytes[i] = UInt8(truncatingIfNeeded: rng.next()) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private struct GeneratedKeyDisplay: View {
    let value: String
    let accent: Color
    let onRegenerate: () -> Void
    let onChange: () -> Void
    @State private var copied = false
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Auth Key generated")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button("Regenerate", action: onRegenerate)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent)
                Button("Set manually", action: onChange)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(revealed ? value : String(repeating: "•", count: min(value.count, 32)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copied ? .green : accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )

            Text("Auto-embedded into the snippet below — no manual edit. Shade will save this same key with your profile in the final step.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

private struct ProfileSavePanel: View {
    let accent: Color
    @Binding var profileName: String
    @Binding var deploymentID: String
    let authKey: String
    @Binding var saved: Bool
    let usesCloudflare: Bool
    let onSave: () -> Void

    private var sidTrim: String {
        deploymentID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !sidTrim.isEmpty && sidTrim.count >= 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundStyle(accent)
                Text(saved ? "Profile saved" : "Save profile to Shade")
                    .font(.system(size: 12, weight: .semibold))
                if usesCloudflare { CloudflareBadge() }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PROFILE NAME (OPTIONAL)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. Home, School", text: $profileName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .disabled(saved)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("DEPLOYMENT ID")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("AKfycb…", text: $deploymentID)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .disabled(saved)
            }

            HStack {
                Spacer()
                if saved {
                    Label("Saved & set as active", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Button(action: onSave) {
                        Text("Save profile")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(!canSave)
                    .opacity(canSave ? 1.0 : 0.5)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }
}
