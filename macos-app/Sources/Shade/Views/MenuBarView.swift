import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    var onClose: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Section: Identity & Primary Toggle
            HStack(spacing: 12) {
                ShadeBrandImage(size: 34, cornerRadius: 8)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Shade")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(app.status.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Rectangular Power Button
                Button {
                    Task {
                        if app.status.isRunning { await app.stop() }
                        else { await app.start() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if app.status.isTransitioning {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: app.status.isRunning ? "stop.fill" : "play.fill")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(app.status.isRunning ? "STOP" : "START")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(app.status.isRunning 
                                  ? LinearGradient(colors: [.red, .pink], startPoint: .top, endPoint: .bottom)
                                  : LinearGradient(colors: [.accentColor, .purple], startPoint: .top, endPoint: .bottom))
                            .shadow(color: (app.status.isRunning ? Color.red : Color.accentColor).opacity(0.2), radius: 4, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(app.status.isTransitioning)
            }
            .padding(16)
            
            Divider().opacity(0.1).padding(.horizontal, 16)
            
            // Settings & Profile Section (Modern & Efficient)
            VStack(spacing: 12) {
                // Profile & Uptime
                HStack {
                    Label {
                        Text(app.settings.activeCredential?.name ?? "No Profile")
                            .font(.system(size: 11, weight: .semibold))
                    } icon: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.purple)
                    }
                    Spacer()
                    if app.status.isRunning, let started = app.startedAt {
                         Text(format(interval: Date().timeIntervalSince(started)))
                             .font(.system(size: 10, design: .monospaced))
                             .foregroundStyle(.secondary)
                    }
                }
                
                // System Proxy Toggle
                HStack {
                    Label {
                        Text("System Proxy")
                            .font(.system(size: 11))
                    } icon: {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { app.settings.useSystemProxy },
                        set: { newValue in Task { await app.setSystemProxy(newValue) } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
            }
            .padding(16)
            
            // Network Stats (Compact)
            if app.status.isRunning {
                Divider().opacity(0.1).padding(.horizontal, 16)
                HStack {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                    Text(verbatim: "SOCKS5 \(listenerLine)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            
            Divider().opacity(0.1)
            
            // Bottom Actions: Side-by-Side Grid
            HStack(spacing: 0) {
                ActionButtonSmall(title: "Dashboard", icon: "square.grid.2x2", action: {
                    showWindow()
                    onClose?()
                })
                
                Divider().frame(height: 18).opacity(0.15)
                
                ActionButtonSmall(title: "Quit", icon: "power", isDestructive: true, action: {
                    NSApp.terminate(nil)
                })
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
        }
        .frame(width: 260)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow).ignoresSafeArea())
    }
    
    private var listenerLine: String {
        let port = app.activeSOCKSPort > 0 ? app.activeSOCKSPort : app.settings.socksPort
        return "127.0.0.1:\(port)"
    }
    
    private func showWindow() {
        if let window = NSApp.windows.first(where: { 
            $0.isVisible == false || ($0.canBecomeKey && $0.title != "" && $0.title != "ItemPopover")
        }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(#selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: nil, from: nil)
        }
    }
    
    private func format(interval: TimeInterval) -> String {
        let t = Int(interval)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }
}

struct ActionButtonSmall: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
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
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}


