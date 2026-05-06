import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: Tab = .dashboard

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
        NavigationSplitView {
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
        .background(WindowAccessor())
    }
}

struct BackgroundGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.sRGB, red: 0.07, green: 0.08, blue: 0.12, opacity: 1),
                Color(.sRGB, red: 0.10, green: 0.11, blue: 0.16, opacity: 1)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
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
