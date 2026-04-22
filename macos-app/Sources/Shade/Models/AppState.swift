import Foundation
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case error(String)

        var isRunning: Bool {
            if case .running = self { return true } else { return false }
        }
        var isTransitioning: Bool {
            switch self {
            case .starting, .stopping: return true
            default: return false
            }
        }
        var label: String {
            switch self {
            case .stopped:        return "Ready to connect"
            case .starting:       return "Starting…"
            case .running:        return "Running"
            case .stopping:       return "Stopping…"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    @Published var settings: AppSettings
    @Published var status: Status = .stopped
    @Published var logs: [LogLine] = []
    @Published var startedAt: Date?

    /// Ports actually in use (may differ from settings if auto-adjusted).
    @Published var activeHTTPPort:  Int = 0
    @Published var activeSOCKSPort: Int = 0

    /// YouTube connectivity test result.
    @Published var testResult: TestResult = .idle

    enum TestResult: Equatable {
        case idle
        case testing
        case success(ms: Int)
        case failure(String)

        var label: String {
            switch self {
            case .idle:             return ""
            case .testing:          return "Testing…"
            case .success(let ms):  return "\(ms) ms"
            case .failure(let msg): return msg
            }
        }
    }

    @AppStorage("hasShownCertRestartSucceeded") var hasShownCertRestartSucceeded = false

    private let store = ConfigStore()
    private let core  = CoreManager()

    init() {
        self.settings = ConfigStore().loadSettings() ?? .default

        core.onLog = { [weak self] line in
            Task { @MainActor in self?.append(line) }
        }
        core.onStatus = { [weak self] new in
            Task { @MainActor in self?.status = new }
        }
    }

    // MARK: - Persistence

    func saveSettings() { store.saveSettings(settings) }

    // MARK: - Start / stop

    func start() async {
        saveSettings()

        let trimmedScript = settings.scriptID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuth   = settings.authKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScript.isEmpty, !trimmedAuth.isEmpty else {
            status = .error("Add and select a profile on the Dashboard first.")
            return
        }

        // ── Auto-select available ports ──────────────────────────────────
        let ports = PortAvailability.findAvailablePair(
            httpPort:  settings.listenPort,
            socksPort: settings.socksPort,
            host:      settings.listenHost
        )
        var effective = settings
        effective.listenPort = ports.http
        effective.socksPort  = ports.socks
        activeHTTPPort  = ports.http
        activeSOCKSPort = ports.socks

        if ports.http != settings.listenPort || ports.socks != settings.socksPort {
            append(LogLine(
                timestamp: Date(), stream: .system,
                text: "⚠︎ Preferred ports busy — using HTTP:\(ports.http) SOCKS5:\(ports.socks)\n"
            ))
        }

        status = .starting
        startedAt = Date()
        do {
            try await core.start(settings: effective)

            // ── Certificate install (async, non-blocking) ────────────────
            Task {
                if !FileManager.default.fileExists(atPath: CertManager.caPath) {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
                let result = await CertManager.installIfNeeded()
                switch result {
                case .installedOK:
                    append(LogLine(timestamp: Date(), stream: .system,
                        text: "✓ Certificate installed — restart your browser to apply.\n"))
                    hasShownCertRestartSucceeded = false
                case .cancelled:
                    append(LogLine(timestamp: Date(), stream: .system,
                        text: "⚠ Certificate install cancelled — HTTPS pages may show SSL errors.\n"))
                case .failed(let msg) where !msg.contains("not yet written"):
                    append(LogLine(timestamp: Date(), stream: .system,
                        text: "⚠ Certificate install failed: \(msg)\n"))
                default:
                    break
                }
                if case .alreadyTrusted = result {
                    hasShownCertRestartSucceeded = true
                }
            }

            // ── System proxy ─────────────────────────────────────────────
            if settings.useSystemProxy {
                let host = effective.listenHost == "0.0.0.0" ? "127.0.0.1" : effective.listenHost
                let result = await SystemProxy.enable(host: host, port: effective.socksPort)
                switch result {
                case .ok:
                    append(LogLine(timestamp: Date(), stream: .system,
                        text: "✓ System SOCKS5 proxy set to \(host):\(effective.socksPort)\n"))
                case .cancelled:
                    append(LogLine(timestamp: Date(), stream: .system,
                        text: "⚠ System proxy permission cancelled — configure manually if needed.\n"))
                case .failed(let msg):
                    append(LogLine(timestamp: Date(), stream: .system,
                        text: "⚠ System proxy failed: \(msg)\n"))
                }
            }

            if !hasShownCertRestartSucceeded {
                Task {
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    hasShownCertRestartSucceeded = true
                }
            }
        } catch {
            status = .error(error.localizedDescription)
            startedAt = nil
            await core.stop()
        }
    }

    func stop() async {
        status = .stopping

        // Clear system proxy before stopping the core
        if settings.useSystemProxy {
            _ = await SystemProxy.disable()
        }

        await core.stop()
        startedAt = nil
        activeHTTPPort  = 0
        activeSOCKSPort = 0
    }

    // MARK: - System proxy toggle

    /// Called by the proxy toggle on the Dashboard. Applies immediately if running.
    func setSystemProxy(_ on: Bool) async {
        settings.useSystemProxy = on
        saveSettings()

        guard status.isRunning else { return }

        if on {
            let host = (activeHTTPPort > 0 ? settings.listenHost : settings.listenHost)
                .replacingOccurrences(of: "0.0.0.0", with: "127.0.0.1")
            let port = activeSOCKSPort > 0 ? activeSOCKSPort : settings.socksPort
            let result = await SystemProxy.enable(host: host, port: port)
            if case .failed(let msg) = result {
                append(LogLine(timestamp: Date(), stream: .system,
                    text: "⚠ System proxy: \(msg)\n"))
            }
        } else {
            _ = await SystemProxy.disable()
        }
    }

    // MARK: - Logs

    func append(_ line: LogLine) {
        if logs.count > 5000 { logs.removeFirst(1000) }
        logs.append(line)
    }

    func clearLogs() { logs.removeAll() }

    // MARK: - YouTube connectivity test

    func testYouTubeDelay() async {
        testResult = .testing

        let socksPort = activeSOCKSPort > 0 ? activeSOCKSPort : settings.socksPort
        let host = settings.listenHost == "0.0.0.0" ? "127.0.0.1" : settings.listenHost

        let result: TestResult = await Task.detached {
            let start = CFAbsoluteTimeGetCurrent()
            let url = URL(string: "https://www.youtube.com/generate_204")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 15)
            request.httpMethod = "HEAD"

            let config = URLSessionConfiguration.ephemeral
            config.connectionProxyDictionary = [
                "SOCKSEnable": true,
                "SOCKSProxy":  host,
                "SOCKSPort":   socksPort,
            ]
            config.timeoutIntervalForRequest = 15

            let session = URLSession(configuration: config)
            do {
                let (_, response) = try await session.data(for: request)
                let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                if let http = response as? HTTPURLResponse,
                   (200..<400).contains(http.statusCode) {
                    return .success(ms: ms)
                }
                return .success(ms: ms)
            } catch {
                let msg = error.localizedDescription
                return .failure(msg.count > 60 ? String(msg.prefix(60)) + "…" : msg)
            }
        }.value

        testResult = result
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if testResult == result { testResult = .idle }
        }
    }
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let stream: Stream
    let text: String
    enum Stream { case stdout, stderr, system }
}
