import Foundation

/// Spawns and supervises the bundled `shade-core` binary (PyInstaller-frozen
/// `main.py`). The core reads its config from the path we pass via `-c`.
/// No admin/sudo is required for this process — only the optional TUN layer
/// escalates.
final class CoreManager {
    var onLog: ((LogLine) -> Void)?
    var onStatus: ((AppState.Status) -> Void)?

    private var process: Process?
    private var pipe: Pipe?
    private var userInitiatedStop = false
    private let store = ConfigStore()

    /// Waits for `host:socksPort` to accept TCP. Returns true when the core
    /// is ready to receive SOCKS5 traffic (means the listener fully started).
    /// Times out after ~8 s.
    private func waitForListener(host: String, port: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(8)
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

        guard let coreURL = Bundle.main.url(forResource: "shade-core", withExtension: nil),
              FileManager.default.isExecutableFile(atPath: coreURL.path)
        else {
            throw NSError(
                domain: "Shade", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "shade-core binary missing from app bundle — rebuild the app."]
            )
        }

        let hostArch = currentMachineArch()
        let coreArchs = binaryArchs(at: coreURL.path)
        if !coreArchs.isEmpty && !coreArchs.contains(hostArch) {
            let available = coreArchs.joined(separator: ",")
            throw NSError(
                domain: "Shade", code: 12,
                userInfo: [NSLocalizedDescriptionKey: "shade-core is incompatible with this Mac architecture (host: \(hostArch), core: \(available)). Reinstall a universal build."]
            )
        }

        let configURL = try store.writeCoreConfig(settings)

        let p = Process()
        p.executableURL = coreURL
        p.arguments = ["-c", configURL.path]
        // Isolate env so Python doesn't inherit a broken user PYTHONPATH etc.
        p.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            // main.py also respects these — useful as a second channel.
            "DFT_SCRIPT_ID": settings.scriptID,
            "DFT_AUTH_KEY": settings.authKey
        ]

        let out = Pipe()
        p.standardOutput = out
        p.standardError = out

        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
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
                self.onStatus?(.stopped)
                return
            }

            let msg = "[shade-core exited with status \(status)]"
            self.onLog?(LogLine(timestamp: Date(), stream: .stderr, text: msg + "\n"))
            self.onStatus?(.error("Core exited (\(status))"))
        }

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(data: chunk, encoding: .utf8) ?? ""
            self?.onLog?(LogLine(timestamp: Date(), stream: .stdout, text: text))
        }

        try p.run()
        process = p
        pipe = out

        let ready = await waitForListener(host: settings.listenHost, port: settings.socksPort)
        if !ready {
            // Core is still alive but the SOCKS listener never came up — surface
            // as an error but leave the process running so the user can see
            // whatever logs it's emitting.
            throw NSError(
                domain: "Shade", code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Core started but SOCKS5 listener didn't come up in time. Check Logs."]
            )
        }
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

    private func currentMachineArch() -> String {
        let (status, out) = runTool("/usr/bin/uname", ["-m"])
        if status == 0 {
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "unknown"
    }

    private func binaryArchs(at path: String) -> [String] {
        let (status, out) = runTool("/usr/bin/lipo", ["-archs", path])
        if status != 0 { return [] }
        return out
            .split { $0 == " " || $0 == "\n" || $0 == "\t" }
            .map(String.init)
    }

    private func runTool(_ executable: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return (-1, "")
        }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }
}
