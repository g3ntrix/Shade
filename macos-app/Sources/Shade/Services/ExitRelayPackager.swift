import Foundation
import AppKit

enum ExitRelayPackager {
    enum PackageError: LocalizedError {
        case sourceMissing(String)
        case packagingFailed(String)

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let path):
                return "Required file missing: \(path)"
            case .packagingFailed(let message):
                return "Packaging failed: \(message)"
            }
        }
    }

    static func buildPackage(exportInstructions: Bool = true) throws -> (bundleURL: URL, instructionsURL: URL?) {
        let fm = FileManager.default
        let timestamp = Self.timestamp()
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]

        let bundleName = "shade-exit-relay-\(timestamp).tgz"
        let bundleURL = desktop.appendingPathComponent(bundleName)
        let instructionsURL = exportInstructions
            ? desktop.appendingPathComponent("shade-exit-relay-\(timestamp)-setup.txt")
            : nil

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shade-exit-relay-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let root = tmp.appendingPathComponent("shade-exit-relay", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceDir = repoRoot()
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("vps-exit-worker", isDirectory: true)

        let files = [
            "server.js",
            "package.json",
            "README.md",
            "ecosystem.config.example.cjs",
            "install.sh",
        ]
        for file in files {
            let src = sourceDir.appendingPathComponent(file)
            guard fm.fileExists(atPath: src.path) else {
                throw PackageError.sourceMissing(src.path)
            }
            try fm.copyItem(at: src, to: root.appendingPathComponent(file))
        }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("install.sh").path)

        if fm.fileExists(atPath: bundleURL.path) { try fm.removeItem(at: bundleURL) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        task.arguments = ["-czf", bundleURL.path, "-C", tmp.path, "shade-exit-relay"]
        let errPipe = Pipe()
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PackageError.packagingFailed(msg)
        }

        if let instructionsURL {
            try serverInstructions(bundleName: bundleURL.lastPathComponent)
                .write(to: instructionsURL, atomically: true, encoding: .utf8)
        }

        return (bundleURL, instructionsURL)
    }

    static func deploymentCommands(bundleURL: URL, serverIP: String) -> [(label: String, code: String)] {
        let target = serverIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "YOUR_VPS_IP"
            : serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = bundleURL.lastPathComponent

        return [
            (
                label: "1. Upload Bundle To VPS",
                code: "scp \"$HOME/Desktop/\(name)\" root@\(target):/root/"
            ),
            (
                label: "2. One Command Install + Start",
                code: "ssh root@\(target) 'cd /root && tar -xzf \(name) && bash /root/shade-exit-relay/install.sh'"
            ),
            (
                label: "3. Use Printed Relay URL + PSK",
                code: "Copy the Relay URL and Exit PSK printed by the installer into Shade -> Settings -> Exit node."
            ),
        ]
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func serverInstructions(bundleName: String) -> String {
        """
        # Shade Exit Relay VPS Setup
        # 1) Upload the generated bundle to /root on the VPS:
        #    scp \(bundleName) root@YOUR_VPS_IP:/root/
        #
        # 2) Run exactly one install command on the VPS:
        #    ssh root@YOUR_VPS_IP 'cd /root && tar -xzf \(bundleName) && bash /root/shade-exit-relay/install.sh'
        #
        # The script automatically:
        # - installs Node.js/PM2 if missing
        # - picks a free relay port (starting from 18081)
        # - generates a strong EXIT PSK
        # - starts and saves pm2 process
        #
        # It prints:
        # - Relay URL
        # - Exit PSK
        #
        # Paste those values into Shade -> Settings -> Exit node.
        """
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private static func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        // .../macos-app/Sources/Shade/Services/ExitRelayPackager.swift -> repo root
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
