import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {

            // ── Header: brand + status + power button ────────────────────────
            HStack(spacing: 12) {
                ShadeBrandImage(size: 34, cornerRadius: 8)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Shade")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(headerSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                }

                Spacer()

                // Power button
                Button {
                    Task {
                        if app.status.isRunning { await app.stop() }
                        else { await app.start() }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if app.status.isTransitioning {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .scaleEffect(0.65)
                        } else {
                            Image(systemName: app.status.isRunning ? "stop.fill" : "play.fill")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text(app.status.isRunning ? "STOP" : "START")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(app.status.isRunning
                                ? LinearGradient(
                                    colors: [Color(hue: 0.0, saturation: 0.85, brightness: 0.85),
                                             Color(hue: 0.95, saturation: 0.8, brightness: 0.80)],
                                    startPoint: .top, endPoint: .bottom)
                                : LinearGradient(
                                    colors: [Color(hue: 0.72, saturation: 0.85, brightness: 0.95),
                                             Color(hue: 0.79, saturation: 0.90, brightness: 0.90)],
                                    startPoint: .top, endPoint: .bottom))
                            .shadow(color: (app.status.isRunning
                                ? Color(hue: 0.0, saturation: 0.85, brightness: 0.85)
                                : Color(hue: 0.72, saturation: 0.85, brightness: 0.95))
                                .opacity(0.35), radius: 5, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(app.status.isTransitioning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // ── Connection meter (only when running) ─────────────────────────
            if app.status.isRunning {
                Divider().opacity(0.08).padding(.horizontal, 12)

                MiniConnectionMeter()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }

            Divider().opacity(0.08).padding(.horizontal, 12)

            // ── Profile + uptime + system proxy ──────────────────────────────
            VStack(spacing: 10) {
                // Profile row
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                    Text(app.settings.activeCredential?.name ?? "No Profile")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if app.status.isRunning, let started = app.startedAt {
                        Text(format(interval: Date().timeIntervalSince(started)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                // System proxy toggle
                HStack(spacing: 8) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("System Proxy")
                        .font(.system(size: 11))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { app.settings.useSystemProxy },
                        set: { v in Task { await app.setSystemProxy(v) } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }

                // Listener address (compact)
                if app.status.isRunning {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.cyan)
                        Text(verbatim: "SOCKS5 \(listenerLine)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.08)

            // ── Bottom actions ────────────────────────────────────────────────
            HStack(spacing: 0) {
                ActionButtonSmall(title: "Dashboard", icon: "square.grid.2x2") {
                    showWindow()
                    onClose?()
                }
                Divider().frame(height: 18).opacity(0.15)
                ActionButtonSmall(title: "Quit", icon: "power", isDestructive: true) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .frame(width: 270)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow).ignoresSafeArea())
    }

    // MARK: - Helpers

    private var headerSubtitle: String {
        switch app.status {
        case .running:              return "Connected"
        case .starting:             return "Connecting…"
        case .stopping:             return "Disconnecting…"
        case .stopped:              return "Disconnected"
        case .error(let m):         return m.prefix(28) + (m.count > 28 ? "…" : "")
        }
    }

    private var subtitleColor: Color {
        switch app.status {
        case .running:              return .green
        case .starting, .stopping:  return .yellow
        case .error:                return .red
        case .stopped:              return .secondary
        }
    }

    private var listenerLine: String {
        let port = app.activeSOCKSPort > 0 ? app.activeSOCKSPort : app.settings.socksPort
        return "127.0.0.1:\(port)"
    }

    private func showWindow() {
        if let w = NSApp.windows.first(where: {
            $0.canBecomeKey && $0.title != "" && $0.title != "ItemPopover"
        }) {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func format(interval: TimeInterval) -> String {
        let t = Int(interval)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }
}

// MARK: - Mini connection meter (for the popover)

private struct MiniConnectionMeter: View {
    @EnvironmentObject var app: AppState
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {

            // ── Speed bars ──────────────────────────────────────────
            VStack(spacing: 5) {
                MiniSpeedBar(
                    label: "↓",
                    color: Color(hue: 0.60, saturation: 0.8, brightness: 0.9),
                    speedText: app.traffic.formattedSpeedDown,
                    bps: app.traffic.speedDown
                )
                MiniSpeedBar(
                    label: "↑",
                    color: Color(hue: 0.78, saturation: 0.75, brightness: 0.95),
                    speedText: app.traffic.formattedSpeedUp,
                    bps: app.traffic.speedUp
                )
            }

            // ── Usage totals row ────────────────────────────────────
            HStack(spacing: 0) {
                MiniStatCell(
                    label: "↓ Total",
                    value: app.traffic.formattedDown,
                    color: Color(hue: 0.60, saturation: 0.8, brightness: 0.9)
                )
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1, height: 24)
                MiniStatCell(
                    label: "↑ Total",
                    value: app.traffic.formattedUp,
                    color: Color(hue: 0.78, saturation: 0.75, brightness: 0.95)
                )
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1, height: 24)
                MiniStatCell(
                    label: "Session",
                    value: app.traffic.formattedTotal,
                    color: .cyan
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.07), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Mini speed bar

private struct MiniSpeedBar: View {
    let label:     String
    let color:     Color
    let speedText: String
    let bps:       Int64

    private let maxBps: Double = 2 * 1024 * 1024
    private var fill: Double { bps <= 0 ? 0 : min(Double(bps) / maxBps, 1.0) }

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 10)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.5), color],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * fill, fill > 0 ? 6 : 0))
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: fill)
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(bps > 0 ? speedText : "0 KB/s")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(bps > 0 ? color : .secondary)
                .frame(width: 60, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Mini stat cell

private struct MiniStatCell: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - Shared helpers

struct ActionButtonSmall: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .foregroundStyle(isDestructive ? .red : .primary.opacity(0.8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
