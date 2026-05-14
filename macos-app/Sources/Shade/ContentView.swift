import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: Tab = .dashboard
    // Explicit visibility binding lets us animate the sidebar reveal
    // ourselves on the first show; the system-default toggle animation
    // is what produces the visible stutter on cold-start re-opens.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard, setup, settings, logs, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .setup:    return "Setup Wizard"
            case .settings: return "Settings"
            case .logs:     return "Logs"
            case .about:    return "About"
            }
        }
        var symbol: String {
            switch self {
            case .dashboard: return "bolt.shield"
            case .setup:    return "wand.and.stars"
            case .settings: return "slider.horizontal.3"
            case .logs:     return "text.alignleft"
            case .about:    return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(tab: $tab)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ZStack {
                BackgroundGradient()
                Group {
                    switch tab {
                    case .dashboard: DashboardView()
                    case .setup:    SetupView()
                    case .settings: SettingsView()
                    case .logs:     LogsView()
                    case .about:    AboutView()
                    }
                }
                .padding(24)
            }
            .navigationTitle(tab.title)
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowAccessor())
    }
}

/// Quiet animated background — deep near-black base with two slow, very
/// subtle blue/teal gradient drifts. Tuned to stay dark enough that card
/// surfaces, dividers, and small text remain legible everywhere on screen.
/// 10 fps + heavily desaturated low-alpha blobs keep this nearly free on
/// the CPU/GPU so it doesn't compete with the sidebar's open animation.
struct BackgroundGradient: View {
    private let base = LinearGradient(
        colors: [
            Color(.sRGB, red: 0.05, green: 0.06, blue: 0.09, opacity: 1),
            Color(.sRGB, red: 0.07, green: 0.08, blue: 0.12, opacity: 1)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        // Base layer is static — rendered once, never invalidated. Only the
        // tiny moving-blobs layer above sits inside the TimelineView, so a
        // sidebar transition doesn't have to re-rasterize the whole window.
        ZStack {
            base
            AuroraBlobs()
            Color.black.opacity(0.45) // wash for legibility
        }
        .ignoresSafeArea()
    }

}

/// Drift layer extracted so its repaint loop is isolated from the rest of
/// the window. Only this small subview invalidates each frame.
private struct AuroraBlobs: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    blob(
                        color: Color(.sRGB, red: 0.18, green: 0.28, blue: 0.45, opacity: 1),
                        center: CGPoint(
                            x: w * (0.30 + 0.14 * CGFloat(sin(t * 0.035))),
                            y: h * (0.25 + 0.12 * CGFloat(cos(t * 0.030)))
                        ),
                        radius: max(w, h) * 0.55
                    )
                    blob(
                        color: Color(.sRGB, red: 0.14, green: 0.30, blue: 0.40, opacity: 1),
                        center: CGPoint(
                            x: w * (0.78 + 0.14 * CGFloat(cos(t * 0.028))),
                            y: h * (0.75 + 0.14 * CGFloat(sin(t * 0.032)))
                        ),
                        radius: max(w, h) * 0.50
                    )
                }
                .compositingGroup()
                .blur(radius: 90)
            }
        }
    }

    private func blob(color: Color, center: CGPoint, radius: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.30), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
    }
}

/// Makes the window transparent-titlebar + draggable by background.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window {
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.isMovableByWindowBackground = true
                w.styleMask.insert(.fullSizeContentView)
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
