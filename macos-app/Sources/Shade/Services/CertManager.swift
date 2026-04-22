import Foundation
import AppKit

/// Checks whether the MITM root CA is trusted by macOS and, when it is not,
/// installs it into the System keychain via a native admin password dialog.
///
/// shade-core writes the CA to Application Support/Shade/ca/ca.crt on first
/// start. Swift handles the trust install so there's no sudo/TTY problem.
enum CertManager {

    static var caPath: String {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return base.appendingPathComponent("Shade/ca/ca.crt").path
    }

    // MARK: - Trust check

    /// Returns true if the CA cert file exists AND macOS considers it trusted.
    static func isTrusted() -> Bool {
        guard FileManager.default.fileExists(atPath: caPath) else { return false }

        // Primary: security verify-cert returns 0 when the cert is in the trust store.
        if runSecurity(["verify-cert", "-c", caPath]) == 0 { return true }

        // Fallback: check system keychain presence (cert added via add-trusted-cert).
        if runSecurity(["find-certificate", "-a", "-c", "MasterHttpRelayVPN",
                        "/Library/Keychains/System.keychain"]) == 0 { return true }

        return false
    }

    // MARK: - Install

    enum InstallResult {
        case alreadyTrusted
        case installedOK
        case cancelled
        case failed(String)
    }

    /// Installs the CA cert into the System keychain with an admin prompt.
    /// Safe to call from any async context; blocks until the user responds.
    static func installIfNeeded() async -> InstallResult {
        guard FileManager.default.fileExists(atPath: caPath) else {
            return .failed("CA cert not yet written by core")
        }
        if isTrusted() { return .alreadyTrusted }

        // Shell command — single-quote the path to handle spaces
        let escapedPath = caPath.replacingOccurrences(of: "'", with: "'\\''")
        let shellCmd = "/usr/bin/security add-trusted-cert -d -r trustRoot "
            + "-k /Library/Keychains/System.keychain '\(escapedPath)'"
        let appleScriptSource = """
        do shell script "\(escape(shellCmd))" \
            with administrator privileges \
            with prompt "Shade needs to install its MITM root certificate so HTTPS traffic can be proxied correctly. This is a one-time step."
        """

        return await Task.detached(priority: .userInitiated) {
            var errDict: NSDictionary?
            guard let script = NSAppleScript(source: appleScriptSource) else {
                return InstallResult.failed("AppleScript init failed")
            }
            _ = script.executeAndReturnError(&errDict)
            if let e = errDict {
                let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
                if code == -128 { return InstallResult.cancelled }
                let msg = (e[NSAppleScript.errorMessage] as? String) ?? "unknown error"
                return InstallResult.failed(msg)
            }
            return InstallResult.installedOK
        }.value
    }

    // MARK: - Helpers

    private static func runSecurity(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let sink = Pipe()
        p.standardOutput = sink
        p.standardError = sink
        do { try p.run(); p.waitUntilExit() } catch { return -1 }
        return p.terminationStatus
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
