import Foundation
import AppKit

/// One-time admin install that drops a tiny wrapper + scoped NOPASSWD sudoers
/// rule for `/usr/local/bin/shade-proxy`. After install, the app can enable
/// or disable the system SOCKS proxy without showing the admin prompt — so
/// toggling the "System proxy" switch off no longer asks for a password.
///
/// The sudoers rule is narrowly scoped to this one wrapper script. The
/// wrapper only runs `networksetup` with whitelisted subcommands
/// (`-listallnetworkservices`, `-setsocksfirewallproxy`,
/// `-setsocksfirewallproxystate`) so there's no arbitrary-command path.
enum ProxyHelper {
    static let sudoersPath = "/etc/sudoers.d/shade-proxy"
    static let helperPath  = "/usr/local/bin/shade-proxy"
    static let helperVersion = "1.1.0"

    enum HelperError: LocalizedError {
        case promptCancelled
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .promptCancelled:
                return "Admin permission was cancelled."
            case .installFailed(let msg):
                return "System-proxy helper install failed: \(msg)"
            }
        }
    }

    /// True when the wrapper exists and passwordless sudo works against it.
    static func isInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: helperPath),
              fm.fileExists(atPath: sudoersPath)
        else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", helperPath, "--self-check"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError  = out
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return false }
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text == helperVersion
        } catch {
            return false
        }
    }

    /// Run the helper passwordless. Returns exit status (0 = success).
    @discardableResult
    static func run(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", helperPath] + args
        p.standardOutput = Pipe()
        p.standardError  = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return -1 }
        return p.terminationStatus
    }

    static func install() throws {
        let user = NSUserName()

        let helperScript = #"""
        #!/bin/bash
        # shade-proxy: scoped wrapper for system SOCKS proxy toggles.
        set -euo pipefail
        if [ "${1:-}" = "--self-check" ]; then echo "__VERSION__"; exit 0; fi
        ACTION="${1:-}"
        HOST="${2:-}"
        PORT="${3:-}"
        case "$ACTION" in
          enable)
            if [ -z "$HOST" ] || [ -z "$PORT" ]; then
              echo "usage: $0 enable <host> <port>" >&2; exit 1
            fi
            /usr/sbin/networksetup -listallnetworkservices \
              | /usr/bin/grep -v '^[*]' | /usr/bin/tail -n +2 \
              | while IFS= read -r svc; do
                  /usr/sbin/networksetup -setsocksfirewallproxy "$svc" "$HOST" "$PORT" off 2>/dev/null || true
                  /usr/sbin/networksetup -setsocksfirewallproxystate "$svc" on 2>/dev/null || true
                done
            ;;
          disable)
            /usr/sbin/networksetup -listallnetworkservices \
              | /usr/bin/grep -v '^[*]' | /usr/bin/tail -n +2 \
              | while IFS= read -r svc; do
                  /usr/sbin/networksetup -setsocksfirewallproxystate "$svc" off 2>/dev/null || true
                done
            ;;
          *)
            echo "usage: $0 enable <host> <port> | disable" >&2; exit 1
            ;;
        esac
        """#.replacingOccurrences(of: "__VERSION__", with: helperVersion)

        let helperB64 = Data(helperScript.utf8).base64EncodedString()

        let sudoersContent = "\(user) ALL=(ALL) NOPASSWD: \(helperPath)\n"
        let sudoersB64 = Data(sudoersContent.utf8).base64EncodedString()

        let shell = """
        set -e
        mkdir -p /usr/local/bin
        echo '\(helperB64)' | /usr/bin/base64 -D > '\(helperPath)'
        chown root:wheel '\(helperPath)'
        chmod 755 '\(helperPath)'
        echo '\(sudoersB64)' | /usr/bin/base64 -D > '\(sudoersPath)'
        chown root:wheel '\(sudoersPath)'
        chmod 440 '\(sudoersPath)'
        /usr/sbin/visudo -cf '\(sudoersPath)' >/dev/null
        """

        let source = """
        do shell script "\(escape(shell))" with administrator privileges with prompt "Shade needs one-time admin permission so enabling or disabling the system proxy never asks for your password again."
        """

        var err: NSDictionary?
        if let script = NSAppleScript(source: source) {
            _ = script.executeAndReturnError(&err)
        }
        if let e = err {
            let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -128 { throw HelperError.promptCancelled }
            let msg = (e[NSAppleScript.errorMessage] as? String) ?? "unknown"
            throw HelperError.installFailed(msg)
        }
        guard isInstalled() else {
            throw HelperError.installFailed("Sudoers rule did not activate — try again.")
        }
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
