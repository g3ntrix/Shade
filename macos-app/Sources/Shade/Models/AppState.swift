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

    /// Real-time tracking of which scripts are processing requests.
    @Published var activeSIDs: Set<String> = []
    private var lastHitAt: [String: Date] = [:]

    /// Scripts that failed the startup health probe. Cleared on every start.
    @Published var unhealthySIDs: Set<String> = []

    /// Scripts whose relay JSON included `cap` ≥ 2 (exit-aware Code.gs), from startup health logs.
    @Published var exitCapableSIDs: Set<String> = []

    /// Populated by the health monitor when a "preferred" strategy triggers
    /// an automatic restart on the fallback pool.
    @Published var lbFallbackMessage: String? = nil

    private var healthMonitorTask: Task<Void, Never>? = nil

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

    @Published var proxyEgressIP: ProxyIPState = .idle
    @Published var isCheckingProxyEgressIP: Bool = false

    enum ProxyIPState: Equatable {
        case idle
        case success(String)
        case failure(String)
        case unavailable(String)
    }

    // MARK: - Traffic stats

    struct TrafficStats {
        var totalDown:   Int64 = 0   // bytes
        var totalUp:     Int64 = 0   // bytes
        var speedDown:   Int64 = 0   // bytes/s
        var speedUp:     Int64 = 0   // bytes/s
        // Rolling buckets for speed calc (per-second bucket, last N seconds)
        fileprivate var lastDownBucket: Int64 = 0
        fileprivate var lastUpBucket:   Int64 = 0

        var formattedDown:  String { formatBytes(totalDown) }
        var formattedUp:    String { formatBytes(totalUp) }
        var formattedTotal: String { formatBytes(totalDown + totalUp) }
        var formattedSpeedDown: String { formatSpeed(speedDown) }
        var formattedSpeedUp:   String { formatSpeed(speedUp) }

        private func formatBytes(_ b: Int64) -> String {
            let kb = Double(b) / 1024
            let mb = kb / 1024
            let gb = mb / 1024
            if gb >= 1   { return String(format: "%.2f GB", gb) }
            if mb >= 0.1 { return String(format: "%.1f MB", mb) }
            if kb >= 0.1 { return String(format: "%.1f KB", kb) }
            return "\(b) B"
        }

        private func formatSpeed(_ bps: Int64) -> String {
            let kbps = Double(bps) / 1024
            let mbps = kbps / 1024
            if mbps >= 1   { return String(format: "%.1f MB/s", mbps) }
            if kbps >= 0.1 { return String(format: "%.0f KB/s", kbps) }
            return "0 KB/s"
        }
    }

    @Published var traffic = TrafficStats()
    // Running accumulators for the current second's bucket
    private var currentSecDownBytes: Int64 = 0
    private var currentSecUpBytes:   Int64 = 0
    private var speedTimer: Timer?

    @AppStorage("hasShownCertRestartSucceeded") var hasShownCertRestartSucceeded = false

    // MARK: - IP Scanner state

    enum ScanState: Equatable {
        case idle
        case scanning
        case done(recommendedIP: String?)
        case failed
    }
    @Published var scanState: ScanState = .idle
    @Published var scanLog: [String]    = []

    private let store = ConfigStore()
    private let core  = CoreManager()

    init() {
        self.settings = ConfigStore().loadSettings() ?? .default

        core.onLog = { [weak self] line in
            Task { @MainActor in 
                self?.append(line)
                self?.trackHits(in: line.text)
            }
        }
        core.onStatus = { [weak self] new in
            Task { @MainActor in self?.status = new }
        }

        // Speed-meter tick: every second, snapshot bucket → speed, reset.
        speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.traffic.speedDown = self.currentSecDownBytes
                self.traffic.speedUp   = self.currentSecUpBytes
                self.currentSecDownBytes = 0
                self.currentSecUpBytes   = 0
            }
        }
        
        // Decay timer to turn off "glowing" dots after inactivity
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.decayHits() }
        }
    }

    private func trackHits(in text: String) {
        // Clean text of ANSI escape sequences (like \u{1b}[32m)
        let cleanText = text.replacingOccurrences(of: "\\e\\[[0-9;]*[mK]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1b}\\[[0-9;]*[mK]", with: "", options: .regularExpression)

        // Health probe: [HEALTH] sid=<id> ok=true cap=<n> | ok=false reason=...
        if cleanText.contains("[HEALTH] sid=") {
            let tailFromSid: String = {
                guard let r = cleanText.range(of: "[HEALTH] sid=") else { return "" }
                return String(cleanText[r.upperBound...])
            }()
            let sid = String(tailFromSid.prefix(while: { !$0.isWhitespace && $0 != "\n" }))
            let ok = cleanText.contains("ok=true")
            var capLevel = 0
            if let capR = cleanText.range(of: "cap=") {
                let after = cleanText[capR.upperBound...]
                let digits = after.prefix(while: { $0.isNumber })
                capLevel = Int(digits) ?? 0
            }
            if !sid.isEmpty {
                for cred in settings.credentials
                where cred.scriptID.hasSuffix(sid) || sid.hasSuffix(cred.scriptID) {
                    if ok {
                        unhealthySIDs.remove(cred.scriptID)
                        if capLevel >= 2 {
                            exitCapableSIDs.insert(cred.scriptID)
                        } else {
                            exitCapableSIDs.remove(cred.scriptID)
                        }
                    } else {
                        unhealthySIDs.insert(cred.scriptID)
                        exitCapableSIDs.remove(cred.scriptID)
                    }
                }
            }
        }

        // Look for our machine-readable marker: [HIT] SID
        if let range = cleanText.range(of: "[HIT] ") {
            let hitSid = String(cleanText[range.upperBound...].prefix(while: { !$0.isWhitespace && $0 != "]" }))
            if !hitSid.isEmpty {
                for cred in settings.credentials {
                    if cred.scriptID.hasSuffix(hitSid) || hitSid.hasSuffix(cred.scriptID) {
                        activeSIDs.insert(cred.scriptID)
                        lastHitAt[cred.scriptID] = Date()
                    }
                }
            }
        }
        
        // Backward compatibility for Batch relay logs
        if let range = cleanText.range(of: "to script ") {
            let logSid = String(cleanText[range.upperBound...].prefix(while: { !$0.isWhitespace && $0 != "." && $0 != "," }))
            if !logSid.isEmpty {
                for cred in settings.credentials {
                    if cred.scriptID.hasSuffix(logSid) || logSid.hasSuffix(cred.scriptID) {
                        activeSIDs.insert(cred.scriptID)
                        lastHitAt[cred.scriptID] = Date()
                    }
                }
            }
        }
    }

    /// Accent: mint when this profile uses val exit, routing is on, and the deployment reported exit-aware relay JSON (`cap` ≥ 2).
    func pulseAccent(for credential: Credential) -> Color {
        if credential.usesValTunnel,
           !settings.effectiveExitNodePool.isEmpty,
           exitCapableSIDs.contains(credential.scriptID) {
            return .mint
        }
        if credential.usesCloudflare { return .orange }
        if credential.usesValTunnel { return .mint }
        return .purple
    }

    private func decayHits() {
        let now = Date()
        for (sid, date) in lastHitAt {
            if now.timeIntervalSince(date) > 2.0 {
                activeSIDs.remove(sid)
                lastHitAt.removeValue(forKey: sid)
            }
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
                text: "⚠︎ Preferred ports busy: using HTTP:\(ports.http) SOCKS5:\(ports.socks)\n"
            ))
        }

        status = .starting
        startedAt = Date()
        unhealthySIDs.removeAll()
        exitCapableSIDs.removeAll()
        do {
            // ── Certificate install (sync) ──────────────────────────────
            // We do this before starting the core so that:
            // 1. The CA cert is already trusted when the core starts.
            // 2. If generating the cert triggers a core launch, it happens here
            //    rather than inside the main core's startup window.
            let certResult = await CertManager.installIfNeeded()
            switch certResult {
            case .installedOK:
                append(LogLine(timestamp: Date(), stream: .system,
                    text: "✓ Certificate installed: restart your browser to apply.\n"))
                hasShownCertRestartSucceeded = false
            case .cancelled:
                append(LogLine(timestamp: Date(), stream: .system,
                    text: "⚠ Certificate install cancelled: HTTPS pages may show SSL errors.\n"))
            case .failed(let msg):
                append(LogLine(timestamp: Date(), stream: .system,
                    text: "⚠ Certificate install failed: \(msg)\n"))
            default:
                break
            }
            if case .alreadyTrusted = certResult {
                hasShownCertRestartSucceeded = true
            }

            try await core.start(settings: effective)

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
                        text: "⚠ System proxy permission cancelled: configure manually if needed.\n"))
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

            startHealthMonitor()

            Task { await self.checkProxyEgressIP() }
        } catch {
            status = .error(error.localizedDescription)
            startedAt = nil
            await core.stop()
        }
    }

    // MARK: - LB health monitor

    private func startHealthMonitor() {
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        guard settings.enableLoadBalancing, settings.lbStrategy.hasFallback else { return }

        healthMonitorTask = Task { @MainActor [weak self] in
            // Give the core time to run its startup health probes before we
            // start evaluating — 15 s is enough even on slow connections.
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            while !Task.isCancelled {
                guard let self, self.status.isRunning,
                      !self.settings.lbFallbackActive else { return }
                self.evaluateFallback()
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    private func evaluateFallback() {
        let enabled    = settings.credentials.filter { $0.isEnabledForLB }
        let cfPool     = enabled.filter { $0.usesCloudflare }
        let normalPool = enabled.filter { !$0.usesCloudflare }
        let valPool    = enabled.filter { $0.usesValTunnel }
        let nonValPool = enabled.filter { !$0.usesValTunnel }

        let shouldFallback: Bool
        let message: String

        switch settings.lbStrategy {
        case .cfPreferred:
            let allCFDead = !cfPool.isEmpty
                && cfPool.allSatisfy { unhealthySIDs.contains($0.scriptID) }
            shouldFallback = allCFDead && !normalPool.isEmpty
            message = "All Cloudflare profiles failed. Falling back to Apps Script profiles. Restart to try Cloudflare again."
        case .normalPreferred:
            let allNormalDead = !normalPool.isEmpty
                && normalPool.allSatisfy { unhealthySIDs.contains($0.scriptID) }
            shouldFallback = allNormalDead && !cfPool.isEmpty
            message = "All Apps Script profiles failed. Falling back to Cloudflare profiles. Restart to try Apps Script again."
        case .valPreferred:
            let allValDead = !valPool.isEmpty
                && valPool.allSatisfy { unhealthySIDs.contains($0.scriptID) }
            shouldFallback = allValDead && !nonValPool.isEmpty
            message = "All val-tagged profiles failed. Falling back to non-val profiles. Restart to try val profiles again."
        default:
            return
        }

        guard shouldFallback else { return }

        settings.lbFallbackActive = true
        lbFallbackMessage = message
        append(LogLine(timestamp: Date(), stream: .system,
            text: "⚠ \(message)\n"))
        append(LogLine(timestamp: Date(), stream: .system,
            text: "↻ Restarting core on fallback pool…\n"))

        // Stop then re-start — start() will read lbFallbackActive = true and
        // build the config with the full pool.
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.stop()
            await self.start()
        }
    }

    func stop() async {
        healthMonitorTask?.cancel()
        healthMonitorTask = nil

        status = .stopping

        // Clear system proxy before stopping the core
        if settings.useSystemProxy {
            _ = await SystemProxy.disable()
        }

        await core.stop()
        startedAt = nil
        activeHTTPPort  = 0
        activeSOCKSPort = 0
        traffic = TrafficStats()
        currentSecDownBytes = 0
        currentSecUpBytes   = 0

        // Reset fallback state so the next start() uses the primary pool again.
        settings.lbFallbackActive = false
        lbFallbackMessage = nil
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
        if settings.enableAppLogs {
            if logs.count > 5000 { logs.removeFirst(1000) }
            logs.append(line)
        }
        countTrafficBytes(in: line.text)
    }

    /// Scan a log chunk for the machine-readable traffic markers
    /// emitted by proxy_server.py:
    ///   "[TRAFFIC] rx=<N> tx=<N>"
    private func countTrafficBytes(in text: String) {
        // Fast-path: skip lines without the marker
        guard text.contains("[TRAFFIC]") else { return }

        for line in text.components(separatedBy: .newlines) {
            guard line.contains("[TRAFFIC]") else { continue }

            // Parse rx=N
            if let rxRange = line.range(of: "rx="),
               let spaceOrEnd = line[rxRange.upperBound...].firstIndex(where: { !$0.isNumber }) {
                if let rx = Int64(line[rxRange.upperBound ..< spaceOrEnd]) {
                    traffic.totalDown   += rx
                    currentSecDownBytes += rx
                }
            } else if let rxRange = line.range(of: "rx=") {
                if let rx = Int64(line[rxRange.upperBound...]) {
                    traffic.totalDown   += rx
                    currentSecDownBytes += rx
                }
            }

            // Parse tx=N
            if let txRange = line.range(of: "tx="),
               let spaceOrEnd = line[txRange.upperBound...].firstIndex(where: { !$0.isNumber }) {
                if let tx = Int64(line[txRange.upperBound ..< spaceOrEnd]) {
                    traffic.totalUp   += tx
                    currentSecUpBytes += tx
                }
            } else if let txRange = line.range(of: "tx=") {
                if let tx = Int64(line[txRange.upperBound...]) {
                    traffic.totalUp   += tx
                    currentSecUpBytes += tx
                }
            }
        }
    }

    func clearLogs() { logs.removeAll() }

    // MARK: - Manual certificate repair

    func repairCertificateNow() async -> String {
        append(LogLine(timestamp: Date(), stream: .system,
            text: "↻ Manual certificate repair requested.\n"))

        let result = await CertManager.reinstallFreshCertificate()
        switch result {
        case .installedOK:
            hasShownCertRestartSucceeded = false
            append(LogLine(timestamp: Date(), stream: .system,
                text: "✓ Certificate refreshed: restart your browser to apply.\n"))
            return "Certificate refreshed. Restart your browser and retry."
        case .alreadyTrusted:
            hasShownCertRestartSucceeded = true
            append(LogLine(timestamp: Date(), stream: .system,
                text: "✓ Certificate is already trusted.\n"))
            return "Certificate is already trusted."
        case .cancelled:
            append(LogLine(timestamp: Date(), stream: .system,
                text: "⚠ Certificate repair cancelled by user.\n"))
            return "Certificate repair cancelled."
        case .failed(let reason):
            append(LogLine(timestamp: Date(), stream: .system,
                text: "⚠ Certificate repair failed: \(reason)\n"))
            return Self.shorten("Certificate repair failed: \(reason)")
        }
    }

    // MARK: - YouTube connectivity test

    func testYouTubeDelay() async {
        testResult = .testing

        let socksPort = activeSOCKSPort > 0 ? activeSOCKSPort : settings.socksPort
        let host = settings.listenHost == "0.0.0.0" ? "127.0.0.1" : settings.listenHost

        var result = await runYouTubeProbe(host: host, socksPort: socksPort)
        if case .failure(let msg) = result, CertManager.looksLikeTLSIssue(msg) {
            append(LogLine(timestamp: Date(), stream: .system,
                text: "⚠ TLS/certificate error detected: refreshing certificate and retrying test.\n"))
            let refresh = await CertManager.reinstallFreshCertificate()
            switch refresh {
            case .installedOK:
                append(LogLine(timestamp: Date(), stream: .system,
                    text: "✓ Certificate refreshed: retrying YouTube test.\n"))
                result = await runYouTubeProbe(host: host, socksPort: socksPort)
            case .alreadyTrusted:
                result = await runYouTubeProbe(host: host, socksPort: socksPort)
            case .cancelled:
                result = .failure("TLS fix cancelled")
            case .failed(let reason):
                result = .failure(Self.shorten("TLS fix failed: \(reason)"))
            }
        }

        testResult = result
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if testResult == result { testResult = .idle }
        }
    }

    private func runYouTubeProbe(host: String, socksPort: Int) async -> TestResult {
        await Task.detached {
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
                let (_, _) = try await session.data(for: request)
                let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                return .success(ms: ms)
            } catch {
                return .failure(Self.shorten(error.localizedDescription))
            }
        }.value
    }

    func checkProxyEgressIP() async {
        guard !isCheckingProxyEgressIP else { return }
        guard status.isRunning else {
            proxyEgressIP = .unavailable("Start Shade first")
            return
        }
        isCheckingProxyEgressIP = true
        proxyEgressIP = .idle
        let host = settings.listenHost == "0.0.0.0" ? "127.0.0.1" : settings.listenHost
        let httpPort = activeHTTPPort > 0 ? activeHTTPPort : settings.listenPort
        let socksPort = activeSOCKSPort > 0 ? activeSOCKSPort : settings.socksPort

        do {
            let ip = try await fetchIPThroughProxy(host: host, httpPort: httpPort, socksPort: socksPort)
            proxyEgressIP = .success(ip)
        } catch {
            proxyEgressIP = .failure(Self.shorten(error.localizedDescription))
        }
        isCheckingProxyEgressIP = false
    }

    private func fetchIPThroughProxy(host: String, httpPort: Int, socksPort: Int) async throws -> String {
        let url = URL(string: "https://api.ipify.org?format=json")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            "HTTPEnable": true,
            "HTTPProxy": host,
            "HTTPPort": httpPort,
            "HTTPSEnable": true,
            "HTTPSProxy": host,
            "HTTPSPort": httpPort,
            "SOCKSEnable": true,
            "SOCKSProxy":  host,
            "SOCKSPort":   socksPort,
        ]
        config.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(for: request)

        if let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = json as? [String: Any],
           let ip = dict["ip"] as? String,
           !ip.isEmpty {
            return ip
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^(\d{1,3}\.){3}\d{1,3}$"#, options: .regularExpression) != nil
            || text.contains(":") {
            return text
        }
        throw NSError(domain: "Shade", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not parse IP"])
    }

    private nonisolated static func shorten(_ message: String) -> String {
        message.count > 60 ? String(message.prefix(60)) + "…" : message
    }

    // MARK: - IP Scanner

    func runIPScan() async {
        guard scanState != .scanning else { return }
        scanState = .scanning
        scanLog   = []

        let recommendedIP = await core.runScan(settings: settings) { [weak self] chunk in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Split chunks into lines so the UI can show them one-by-one.
                let lines = chunk.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { self.scanLog.append(trimmed) }
                }
            }
        }

        if recommendedIP != nil {
            scanState = .done(recommendedIP: recommendedIP)
        } else {
            // Check if we got any output at all (might just mean no IPs reachable).
            let gotOutput = scanLog.contains { $0.contains("/") || $0.contains("ms") || $0.contains("timeout") }
            scanState = gotOutput ? .done(recommendedIP: nil) : .failed
        }
    }

    func cancelScan() {
        // The process terminates itself when `runScan` is abandoned;
        // just reset the UI state.
        scanState = .idle
        scanLog   = []
    }

    func applyScanResult(_ ip: String) {
        settings.googleIP = ip
        saveSettings()
        append(LogLine(timestamp: Date(), stream: .system,
            text: "✓ google_ip updated to \(ip) from scanner: restart to apply.\n"))
        scanState = .idle
        scanLog   = []
    }

}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let stream: Stream
    let text: String
    enum Stream { case stdout, stderr, system }
}
