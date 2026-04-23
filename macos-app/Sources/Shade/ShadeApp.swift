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

/// Handles graceful shutdown and manages the menubar status item.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var statusItem: NSStatusItem?
    var popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "Shade")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Setup Popover
        popover.contentSize = NSSize(width: 280, height: 320)
        popover.behavior = .transient
        // We will host our SwiftUI MenuBarView inside the popover
        if let appState = appState {
            popover.contentViewController = NSHostingController(rootView: MenuBarView(onClose: { [weak self] in
                self?.popover.performClose(nil)
            }).environmentObject(appState))
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Update appState in case it wasn't ready during setup
            if let appState = appState, popover.contentViewController == nil {
                popover.contentViewController = NSHostingController(rootView: MenuBarView(onClose: { [weak self] in
                    self?.popover.performClose(nil)
                }).environmentObject(appState))
            }
            
            // Refresh icon state
            if let appState = appState {
                button.image = NSImage(systemSymbolName: appState.status.isRunning ? "bolt.shield.fill" : "bolt.shield", accessibilityDescription: "Shade")
            }
            
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Fix: ensure the popover window becomes key so buttons work
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let app = appState, app.status.isRunning {
            if app.settings.useSystemProxy {
                SystemProxy.disableSync()
            }
            Task { await app.stop() }
            Thread.sleep(forTimeInterval: 0.5)
        }
        killLeftoverProcesses()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
