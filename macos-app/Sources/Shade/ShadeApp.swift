import SwiftUI
import Combine

@main
struct ShadeApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 820)
                .preferredColorScheme(.dark)
                .onAppear {
                    delegate.setup(appState)
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
    private var eventMonitor: Any?
    private var statusCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }
    
    func setup(_ appState: AppState) {
        self.appState = appState
        updatePopoverContent()
        updateIcon()

        // Keep the icon in sync with the live status — fires immediately on
        // every state transition rather than only when the popover opens.
        statusCancellable = appState.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.image = NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "Shade")
        }

        popover.behavior = .transient
        updatePopoverContent()
    }
    
    private func updatePopoverContent() {
        guard let appState = appState else { return }
        let rootView = MenuBarView(onClose: { [weak self] in
            self?.closePopover()
        }).environmentObject(appState)
        
        if let hostingController = popover.contentViewController as? NSHostingController<AnyView> {
            hostingController.rootView = AnyView(rootView)
        } else {
            popover.contentViewController = NSHostingController(rootView: AnyView(rootView))
        }
    }

    func updateIcon() {
        guard let button = statusItem?.button else { return }
        let isRunning = appState?.status.isRunning ?? false
        button.image = NSImage(systemSymbolName: isRunning ? "bolt.shield.fill" : "bolt.shield", accessibilityDescription: "Shade")
    }

    @objc func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    private func showPopover() {
        guard let button = statusItem?.button else { return }

        updatePopoverContent()
        // Icon is always up-to-date via the Combine stream; no need to duplicate here.

        // Ensure the popover size is recalculated
        if let contentVC = popover.contentViewController {
            let size = contentVC.view.fittingSize
            popover.contentSize = NSSize(width: 270, height: size.height)
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        // Event monitor to catch clicks outside the popover if .transient fails
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if self?.popover.isShown == true {
                self?.closePopover()
            }
        }
    }
    
    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
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
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "shade-core"]
        try? p.run()
        p.waitUntilExit()
    }
}

