import SwiftUI

@main
struct ShadeApp: App {
    @StateObject private var appState = AppState()

    /// Ensure shade-core and tun2socks are killed when the app quits,
    /// even if the user Force-Quits or Cmd-Q without clicking Stop.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(.dark)
                .onAppear {
                    delegate.appState = appState
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Handles graceful shutdown of child processes when the app is terminated.
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        if let app = appState, app.status.isRunning {
            // Clear system proxy synchronously so it doesn't stay set after quit
            if app.settings.useSystemProxy {
                SystemProxy.disableSync()
            }
            Task { await app.stop() }
            Thread.sleep(forTimeInterval: 0.5)
        }
        killLeftoverProcesses()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func killLeftoverProcesses() {
        for name in ["shade-core"] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            p.arguments = ["-f", name]
            try? p.run()
            p.waitUntilExit()
        }
    }
}
