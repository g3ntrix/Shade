import SwiftUI
import AppKit

/// Top-level setup wizard: Apps Script only, Cloudflare Worker, or val.town exit relay.
struct SetupView: View {
    enum Mode { case chooser, appsScript, cloudflare, exitNode }
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
        case .exitNode:
            ExitNodeSetupView(onBack: {
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
                    Text("Pick your main relay path. You can add val.town exit tunnels anytime under Settings → Exit node.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 14) {
                    ChooserCard(
                        title: "Apps Script only",
                        subtitle: "Simplest, 5 steps",
                        details: "Relay on Google Apps Script only. Traffic exits from Google IPs.",
                        icon: "doc.text.fill",
                        accent: .accentColor
                    ) {
                        onPick(.appsScript)
                    }

                    ChooserCard(
                        title: "Cloudflare Worker",
                        subtitle: "Apps Script + Worker, 7 steps",
                        details: "Apps Script forwards to a Worker. Traffic exits from Cloudflare IPs.",
                        icon: "cloud.fill",
                        accent: .orange,
                        recommended: true
                    ) {
                        onPick(.cloudflare)
                    }

                    ChooserCard(
                        title: "Exit node (val.town)",
                        subtitle: "Optional, 6 steps",
                        details: "Extra HTTP hop (e.g. val.town) for sites that block Google IPs. Add tunnels under Settings → Exit node.",
                        icon: "arrow.turn.up.right",
                        accent: .mint
                    ) {
                        onPick(.exitNode)
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
    var recommended: Bool = false
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
                    if recommended {
                        Text("RECOMMENDED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(
                                Capsule().fill(accent.opacity(0.15))
                                    .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 0.5))
                            )
                    }
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
    let onBack: () -> Void
    @State private var step: Int = 0
    @State private var authKeyDraft: String = ""
    @State private var authKeyConfirmed: Bool = false

    private let accent: Color = .accentColor

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

                This version can optionally send some requests through an exit relay \
                (val.town, etc.): add tunnels under Settings → Exit node; host list \
                and mode live in Settings → Exit node. The exit PSK and AUTH_KEY are \
                two different secrets.
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

                You now have everything:
                  • Script ID → the Deployment ID you just copied
                  • Auth Key  → the AUTH_KEY string you set in step 2
                """
        ),
        .init(
            title: "Add the profile to Shade",
            body:
                """
                Head back to the Dashboard, click + Add next to Profile, paste your \
                Script ID and Auth Key, and save. Hit Start and you're connected.

                If you use an exit node: deploy it (Setup Guide → Exit node), add the \
                URL and PSK under Settings → Exit node, tune host list under \
                Settings → Exit node, then Stop → Start. Redeploy Apps Script when \
                you replace Code.gs from this guide.
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

                If you use an exit node: deploy it (Setup Guide → Exit node), add \
                tunnels under Settings → Exit node, tune routing under \
                Settings → Exit node, then Stop → Start. This Code.gs tries the exit \
                hop when Shade marks a request. Redeploy Apps Script after updating \
                the snippet from this guide.
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

// MARK: - Exit node (val.town) branch

private struct ExitNodeSetupView: View {
    let onBack: () -> Void
    @State private var step: Int = 0
    @State private var pskDraft: String = ""
    @State private var pskConfirmed: Bool = false

    private let accent: Color = .mint

    private let steps: [WizardStep] = [
        .init(
            title: "What this does",
            body:
                """
                Some sites dislike Google’s outbound IP. Shade can send matching \
                requests through a small relay on val.town so the site sees val’s IP.

                You still need an Apps Script or Cloudflare profile. This guide \
                only deploys the val relay; paste URL + PSK under Settings → Exit node.
                """
        ),
        .init(
            title: "Create a val.town account",
            body:
                """
                Sign up at val.town (free tier is fine). Next step creates an HTTP val.
                """,
            link: URL(string: "https://www.val.town")
        ),
        .init(
            title: "New HTTP val (TypeScript)",
            body:
                """
                In val.town: New → HTTP → TypeScript. Leave the editor open; you will \
                paste the script in the next step.
                """
        ),
        .init(
            title: "Set PSK and paste the script",
            body:
                """
                Pick a secret (≥ 8 chars). It is only for the val endpoint, not your \
                Apps Script AUTH_KEY. Use This Key, paste the script into val.town, Save.
                """,
            showAuthKey: true
        ),
        .init(
            title: "Copy your val’s public URL",
            body:
                """
                After save, copy the public URL (often ends in .web.val.run). That is \
                the Relay URL in Shade. A browser GET may show method_not_allowed; POST is normal.
                """
        ),
        .init(
            title: "Wire it into Shade",
            body:
                """
                1. Redeploy Code.gs from the Apps Script or Cloudflare guide here if you have not already.

                2. Settings → Exit node → + : paste Relay URL and the same PSK.

                3. Turn on Allow val tunnel and Route through val. Stop → Start Shade.

                With two or more tunnels, use LB on the card to round-robin.
                """
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WizardHeader(
                    title: "Exit node (val.town)",
                    subtitle: "Deploy a val.town HTTP relay, then add it under Settings → Exit node.",
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

                if s.showAuthKey {
                    if pskConfirmed {
                        VStack(alignment: .leading, spacing: 8) {
                            ConfirmedHint(
                                text: "PSK embedded: copy the script below into val.town.",
                                accent: accent,
                                onChange: { pskConfirmed = false }
                            )
                            CodeSnippet(
                                filename: "val HTTP val (TypeScript)",
                                code: ValtownTemplate.withPSKEmbedded(pskDraft),
                                accent: accent
                            )
                        }
                    } else {
                        AuthKeyPrompt(
                            authKey: $pskDraft,
                            accent: accent,
                            title: "Choose exit PSK",
                            detail:
                                "Protects the val endpoint only. Same value as const PSK in the script "
                                + "and in Shade (Settings → Exit node). Not your Apps Script AUTH_KEY.",
                            onConfirm: { pskConfirmed = true }
                        )
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
                    nextDisabled: step == 3 && !pskConfirmed
                )
            }
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
