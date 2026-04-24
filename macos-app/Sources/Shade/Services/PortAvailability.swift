import Foundation
import Darwin

/// Quick check whether a TCP port is free on a given bind host.
enum PortAvailability {
    static func isAvailable(port: Int, host: String) -> Bool {
        guard port > 0, port < 65536 else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        // Intentionally NOT setting SO_REUSEADDR here: we want "can I
        // exclusively bind this port?", not "can I share it?". On macOS
        // SO_REUSEADDR lets our probe succeed even when another process
        // holds the port with SO_REUSEADDR — which gave false positives
        // that let the core spawn then fail its real bind inside Python,
        // producing the misleading "listener didn't come up in time"
        // timeout on the Swift side.

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian

        let bindIP: String
        switch host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "0.0.0.0", "*":
            bindIP = "0.0.0.0"
        case "localhost", "127.0.0.1":
            bindIP = "127.0.0.1"
        default:
            bindIP = "0.0.0.0"
        }
        bindIP.withCString { cstr in
            _ = inet_pton(AF_INET, cstr, &addr.sin_addr)
        }

        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }

    /// Starting at `preferred`, scan upward until a free port is found.
    /// Returns the first available port, or `preferred + 100` as a last-resort guess.
    static func findAvailable(preferred: Int, host: String) -> Int {
        for offset in 0..<100 {
            let candidate = preferred + offset
            if candidate > 65535 { break }
            if isAvailable(port: candidate, host: host) {
                return candidate
            }
        }
        return preferred  // give up, let the core report the error
    }

    /// Finds a pair of free ports (http, socks) that don't collide.
    /// Tries to keep desired values; if busy, scans upward from each.
    static func findAvailablePair(httpPort: Int, socksPort: Int, host: String) -> (http: Int, socks: Int) {
        let http = findAvailable(preferred: httpPort, host: host)
        var socks = findAvailable(preferred: socksPort, host: host)
        // Make sure they don't collide
        if socks == http {
            socks = findAvailable(preferred: socks + 1, host: host)
        }
        return (http, socks)
    }

    /// Find a free utun interface name by checking which ones currently exist.
    static func findFreeUtun() -> String {
        let existing = existingUtunNames()
        // Try utun10 through utun99 (avoid low numbers used by system VPNs)
        for n in 10..<100 {
            let name = "utun\(n)"
            if !existing.contains(name) {
                return name
            }
        }
        // Fallback
        return "utun99"
    }

    private static func existingUtunNames() -> Set<String> {
        var names = Set<String>()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return names }
        defer { freeifaddrs(ifaddr) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = current {
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("utun") {
                names.insert(name)
            }
            current = ifa.pointee.ifa_next
        }
        return names
    }
}
