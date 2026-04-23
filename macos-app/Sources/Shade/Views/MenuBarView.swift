import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    var onClose: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Status & Toggle
            HStack(spacing: 12) {
                StatusOrbSmall(status: app.status)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Shade")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(app.status.label)
                        .font(.system(size: 13, weight: .semibold))
                }
                
                Spacer()
                
                Button {
                    Task {
                        if app.status.isRunning { await app.stop() }
                        else { await app.start() }
                    }
                } label: {
                    Text(app.status.isRunning ? "Stop" : "Start")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(app.status.isRunning 
                                      ? LinearGradient(colors: [.red, .pink], startPoint: .top, endPoint: .bottom)
                                      : LinearGradient(colors: [.accentColor, .purple], startPoint: .top, endPoint: .bottom))
                        )
                }
                .buttonStyle(.plain)
                .disabled(app.status.isTransitioning)
            }
            .padding(16)
            
            Divider().opacity(0.1)
            
            // Stats Section (if running)
            if app.status.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "network")
                            .font(.system(size: 10))
                        Text(listenerLine)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    
                    if let started = app.startedAt {
                        HStack {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text("Connected for \(format(interval: Date().timeIntervalSince(started)))")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider().opacity(0.1)
            }
            
            // Footer: Actions
            VStack(spacing: 0) {
                MenuActionButton(title: "Open Dashboard", icon: "macwindow") {
                    showWindow()
                    onClose?()
                }
                
                MenuActionButton(title: "Quit Shade", icon: "power", isDestructive: true) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var listenerLine: String {
        let port = app.activeSOCKSPort > 0 ? app.activeSOCKSPort : app.settings.socksPort
        return "SOCKS5 127.0.0.1:\(port)"
    }
    
    private func showWindow() {
        // Broad search for the main WindowGroup window
        if let window = NSApp.windows.first(where: { 
            $0.isVisible == false || ($0.canBecomeKey && $0.title != "")
        }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            // Fallback for SwiftUI window lifecycle which sometimes "hides" the window reference
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(#selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: nil, from: nil)
            // Note: Standard SwiftUI WindowGroup doesn't have a public "open" API yet, 
            // but bringing the app to front usually reveals the last known window if not terminated.
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

struct StatusOrbSmall: View {
    let status: AppState.Status
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 24, height: 24)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.5), radius: 3)
        }
    }
    var color: Color {
        switch status {
        case .running: return .green
        case .starting, .stopping: return .yellow
        case .error: return .red
        case .stopped: return .gray
        }
    }
}

struct MenuActionButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .foregroundStyle(isDestructive ? .red : .primary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
