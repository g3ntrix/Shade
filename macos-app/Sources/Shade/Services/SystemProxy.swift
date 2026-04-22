import Foundation
import AppKit

/// Sets / clears the macOS system-wide SOCKS proxy using `networksetup`.
/// Changes are applied to every active network service so Wi-Fi, Ethernet,
/// and USB adapters all route through the proxy automatically.
enum SystemProxy {

    enum Result { case ok, cancelled, failed(String) }

    // MARK: - Enable

    /// Sets the SOCKS proxy to `host:port` on all network services and turns it on.
    static func enable(host: String, port: Int) async -> Result {
        let h = host == "0.0.0.0" ? "127.0.0.1" : host
        // [*] matches a literal '*' in both BRE and ERE without needing a backslash.
        let shell = "networksetup -listallnetworkservices | grep -v '^[*]' | tail -n +2 | while IFS= read -r svc; do networksetup -setsocksfirewallproxy \"$svc\" \(h) \(port) off 2>/dev/null; networksetup -setsocksfirewallproxystate \"$svc\" on 2>/dev/null; done"
        return await run(shell, prompt: "Shade needs permission to set the system SOCKS5 proxy so all apps route through it automatically.")
    }

    // MARK: - Disable

    /// Turns the SOCKS proxy off on all network services.
    static func disable() async -> Result {
        let shell = "networksetup -listallnetworkservices | grep -v '^[*]' | tail -n +2 | while IFS= read -r svc; do networksetup -setsocksfirewallproxystate \"$svc\" off 2>/dev/null; done"
        return await run(shell, prompt: "Shade needs permission to clear the system SOCKS5 proxy.")
    }

    /// Best-effort synchronous disable — used during app termination where async is unavailable.
    static func disableSync() {
        let shell = "networksetup -listallnetworkservices | grep -v '^[*]' | tail -n +2 | while IFS= read -r svc; do networksetup -setsocksfirewallproxystate \"$svc\" off 2>/dev/null; done"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", shell]
        p.standardOutput = Pipe()
        p.standardError  = Pipe()
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: - Status check (no admin needed)

    /// Returns true if the system SOCKS proxy is currently enabled on any service.
    static func isEnabled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        p.arguments = ["--proxy"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return false }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.contains("SOCKSEnable : 1")
    }

    // MARK: - Private

    private static func run(_ shell: String, prompt: String) async -> Result {
        let src = "do shell script \"\(escape(shell))\" with administrator privileges with prompt \"\(escape(prompt))\""
        return await Task.detached(priority: .userInitiated) {
            var errDict: NSDictionary?
            guard let script = NSAppleScript(source: src) else {
                return Result.failed("AppleScript init failed")
            }
            _ = script.executeAndReturnError(&errDict)
            if let e = errDict {
                let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
                if code == -128 { return Result.cancelled }
                let msg = (e[NSAppleScript.errorMessage] as? String) ?? "unknown"
                return Result.failed(msg)
            }
            return Result.ok
        }.value
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            default:   out.append(ch)
            }
        }
        return out
    }
}
