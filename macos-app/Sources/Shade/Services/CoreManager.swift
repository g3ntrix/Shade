import Foundation

/// Spawns and supervises the bundled `shade-core` binary (PyInstaller-frozen
/// `main.py`). The core reads its config from the path we pass via `-c`.
/// No admin/sudo is required for this process — only the optional TUN layer
/// escalates.
final class CoreManager {
    var onLog: ((LogLine) -> Void)?
    var onStatus: ((AppState.Status) -> Void)?

    private var process: Process?
    private var scanProcess: Process?
    private var pipe: Pipe?
    private var userInitiatedStop = false
    private let store = ConfigStore()

    /// Waits for `host:socksPort` to accept TCP. Returns true when the core
    /// is ready to receive SOCKS5 traffic (means the listener fully started).
    /// Times out after ~30 s — older Intel Macs need this much to unpack
    /// the PyInstaller onefile archive and import cryptography/h2 on a
    /// cold filesystem cache. The same core comes up in ~400 ms from a
    /// warm Terminal session, so the long ceiling only costs us on failure.
    private func waitForListener(host: String, port: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if canConnect(host: host, port: port) { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func canConnect(host: String, port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        let ip = host == "0.0.0.0" ? "127.0.0.1" : host
        ip.withCString { _ = inet_pton(AF_INET, $0, &addr.sin_addr) }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }

    func start(settings: AppSettings) async throws {
        await stop()

        // Pick the per-arch core binary (shade-core-arm64 or
        // shade-core-x86_64). We ship two separate executables — NOT a
        // lipo'd universal — because PyInstaller's onefile payload lives
        // in appended bytes that lipo silently drops, causing Intel
        // Macs to try to dlopen the arm64 Python framework.
        let hostArch = currentMachineArch()
        guard let coreURL = resolveCoreBinary(hostArch: hostArch) else {
            // Show which binaries ARE bundled so the error is actionable.
            let candidates: [String] = ["shade-core-arm64", "shade-core-x86_64"]
            let present: [String] = candidates.filter { name in
                Bundle.main.url(forResource: name, withExtension: nil) != nil
            }
            let detail = present.isEmpty
                ? "no shade-core-* binary is bundled"
                : "bundled: \(present.joined(separator: ", "))"
            throw NSError(
                domain: "Shade", code: 12,
                userInfo: [NSLocalizedDescriptionKey:
                    "shade-core is incompatible with this Mac (host arch: \(hostArch); \(detail)). Reinstall a build that includes this architecture."]
            )
        }

        let configURL = try store.writeCoreConfig(settings)

        // Strip com.apple.quarantine from the nested core binary. When users
        // AirDrop / download Shade.app, macOS tags every file inside with
        // quarantine. With hardened runtime + ad-hoc signature, Gatekeeper
        // on some OS versions silently refuses to exec quarantined nested
        // Mach-Os — the parent opens fine (user approved once) but children
        // don't inherit. This call is idempotent and cheap.
        stripQuarantine(at: coreURL)

        let msg = "[CoreManager] Launching \(coreURL.lastPathComponent) (arch: \(hostArch))"
        self.onLog?(LogLine(timestamp: Date(), stream: .system, text: msg + "\n"))

        let p = Process()
        p.executableURL = coreURL
        p.arguments = ["-c", configURL.path, "--no-cert-check"]
        // Isolate env so Python doesn't inherit a broken user PYTHONPATH etc.
        p.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONUNBUFFERED": "1", // Ensure logs aren't swallowed if it crashes
            // main.py also respects these — useful as a second channel.
            "DFT_SCRIPT_ID": settings.scriptID,
            "DFT_AUTH_KEY": settings.authKey
        ]

        let out = Pipe()
        p.standardOutput = out
        p.standardError = out

        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            
            // Read remaining data before closing the handler
            if let data = try? out.fileHandleForReading.readToEnd(), !data.isEmpty {
                let text = String(data: data, encoding: .utf8) ?? ""
                self.onLog?(LogLine(timestamp: Date(), stream: .stdout, text: text))
            }
            out.fileHandleForReading.readabilityHandler = nil
            
            self.process = nil
            self.pipe = nil

            // Any stop we initiated — or any SIGTERM/SIGKILL — is a clean
            // shutdown, not an error. This prevents the "Core exited (15)"
            // banner after the user clicks Stop (SIGTERM = 15).
            let initiated = self.userInitiatedStop
            self.userInitiatedStop = false
            
            let status = proc.terminationStatus
            let isCleanSignal = proc.terminationReason == .uncaughtSignal
                && (status == SIGTERM || status == SIGKILL)
            
            if initiated || status == 0 || isCleanSignal {
                // Only reset status if it's currently starting/running/stopping.
                // If it's already .error, we want to keep that error.
                self.onStatus?(.stopped)
                return
            }

            let msg = "[shade-core exited with status \(status)]"
            self.onLog?(LogLine(timestamp: Date(), stream: .stderr, text: msg + "\n"))
            self.onStatus?(.error("Core exited (\(status))"))
        }

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            let text = String(data: chunk, encoding: .utf8) ?? ""
            self?.onLog?(LogLine(timestamp: Date(), stream: .stdout, text: text))
        }

        do {
            try p.run()
        } catch {
            self.onLog?(LogLine(timestamp: Date(), stream: .system, text: "[CoreManager] p.run() failed: \(error.localizedDescription)\n"))
            throw error
        }
        
        process = p
        pipe = out

        let probeHost = settings.listenHost == "0.0.0.0" ? "127.0.0.1" : settings.listenHost
        let ready = await waitForListener(host: settings.listenHost, port: settings.socksPort)
        
        if !ready {
            self.onLog?(LogLine(timestamp: Date(), stream: .system, text: "[CoreManager] waitForListener timed out.\n"))
            if process == nil { return }

            // Include the probe target so the user can cross-check against
            // core's own "Listening SOCKS5 on …" log line. If the ports
            // don't match, the user has a config mismatch; if they match
            // but we still can't connect, another process is holding the
            // port (now surfaces as an explicit error from the core too).
            throw NSError(
                domain: "Shade", code: 11,
                userInfo: [NSLocalizedDescriptionKey:
                    "Core started but SOCKS5 listener on \(probeHost):\(settings.socksPort) didn't come up in time. Check Logs: another process may be holding that port."]
            )
        }
        self.onLog?(LogLine(timestamp: Date(), stream: .system, text: "[CoreManager] Listener ready.\n"))
        onStatus?(.running)
    }

    func stop() async {
        if let p = process, p.isRunning {
            userInitiatedStop = true
            p.terminate()
            for _ in 0 ..< 20 {
                if process == nil { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if let p = process, p.isRunning {
                // Core ignored SIGTERM — force kill.
                kill(p.processIdentifier, SIGKILL)
            }
        }
        pipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        pipe = nil
    }

    /// Run the core binary with `--scan` to probe Google IPs.
    /// Streams each output line back via `onLog`, returns the recommended IP
    /// (from the "Recommended: Set \"google_ip\": \"x.x.x.x\"" line), or nil
    /// if none was found / scan failed.
    func runScan(
        settings: AppSettings,
        onLog: @escaping (String) -> Void
    ) async -> String? {
        // Cancel any previous scan that's still running.
        if let p = scanProcess, p.isRunning { p.terminate() }
        scanProcess = nil

        let hostArch = currentMachineArch()
        guard let coreURL = resolveCoreBinary(hostArch: hostArch) else {
            onLog("[Scanner] shade-core binary not found for arch \(hostArch).\n")
            return nil
        }
        stripQuarantine(at: coreURL)

        let configURL: URL
        do { configURL = try store.writeCoreConfig(settings) } catch {
            onLog("[Scanner] Could not write config: \(error.localizedDescription)\n")
            return nil
        }

        let p = Process()
        p.executableURL = coreURL
        p.arguments = ["-c", configURL.path, "--scan"]
        p.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONUNBUFFERED": "1",
            "DFT_SCRIPT_ID": settings.scriptID,
            "DFT_AUTH_KEY":  settings.authKey
        ]

        let out = Pipe()
        p.standardOutput = out
        p.standardError  = out
        scanProcess = p

        // Thread-safe accumulator so the readabilityHandler closure (which
        // runs on a background thread) doesn't trigger Swift 6 concurrency
        // warnings when we later read fullOutput on the main actor.
        final class OutputStore: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var value = ""
            func append(_ s: String) { lock.lock(); value += s; lock.unlock() }
        }
        let store = OutputStore()

        // Stream each available chunk to the UI in real time.
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            store.append(text)
            onLog(text)
        }

        do { try p.run() } catch {
            onLog("[Scanner] Launch failed: \(error.localizedDescription)\n")
            scanProcess = nil
            return nil
        }

        // Wait for the scan to finish (it runs to completion on its own).
        await withCheckedContinuation { cont in
            p.terminationHandler = { _ in cont.resume() }
        }
        out.fileHandleForReading.readabilityHandler = nil

        // Drain any remaining bytes.
        if let data = try? out.fileHandleForReading.readToEnd(), !data.isEmpty {
            let text = String(data: data, encoding: .utf8) ?? ""
            store.append(text)
            onLog(text)
        }

        scanProcess = nil

        // Parse: Recommended: Set "google_ip": "1.2.3.4"
        for line in store.value.components(separatedBy: .newlines) {
            if line.contains("Recommended:"), let q1 = line.lastIndex(of: "\"") {
                let before = line[line.startIndex ..< q1]
                if let q0 = before.lastIndex(of: "\"") {
                    let ip = String(line[line.index(after: q0) ..< q1])
                    if !ip.isEmpty { return ip }
                }
            }
        }
        return nil
    }

    private func currentMachineArch() -> String {
        // sysctlbyname("hw.machine") returns the process's reported arch.
        // Under Rosetta on Apple Silicon it returns "x86_64" — which is
        // exactly what we want, since we're then an x86_64 process and
        // need the x86_64 core binary. On native arm64 it returns "arm64".
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buf, &size, nil, 0)
        let machine = String(cString: buf)
        if machine.hasPrefix("arm") { return "arm64" }
        if machine.hasPrefix("x86") { return "x86_64" }
        return machine
    }

    /// Return the bundled shade-core binary for this host, or nil if the
    /// matching per-arch slice isn't present.
    private func resolveCoreBinary(hostArch: String) -> URL? {
        let primary = "shade-core-\(hostArch)"
        if let url = Bundle.main.url(forResource: primary, withExtension: nil),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        return nil
    }

    /// Remove com.apple.quarantine (and provenance) from a bundled binary
    /// using setxattr/removexattr. We use the syscalls directly instead of
    /// shelling out to /usr/bin/xattr because /usr/bin/xattr itself may be
    /// gated behind command-line-tools on stripped-down systems.
    private func stripQuarantine(at url: URL) {
        let path = (url.path as NSString).fileSystemRepresentation
        // XATTR_NOFOLLOW = 0x0001. Errors are ignored — if the attr isn't
        // there, removexattr returns ENOATTR and that's fine.
        _ = removexattr(path, "com.apple.quarantine", 0x0001)
        _ = removexattr(path, "com.apple.provenance", 0x0001)
    }
}
