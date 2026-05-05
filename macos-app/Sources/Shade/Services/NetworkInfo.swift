import Foundation
import Darwin

/// Small helpers around the local machine's network interfaces.
enum NetworkInfo {

    /// Best-effort primary LAN IPv4 address (e.g. 192.168.x.x / 10.x.x.x).
    /// Returns the first non-loopback IPv4 found on `en*` interfaces, ignoring
    /// link-local 169.254/16 unless nothing else is available.
    static func primaryLANAddress() -> String? {
        var fallback: String?
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }

            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0 else { continue }

            guard let sa = cur.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: cur.pointee.ifa_name)
            // Wi-Fi and Ethernet are en*; ignore VPN/tap-style interfaces.
            guard name.hasPrefix("en") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let res = getnameinfo(sa,
                                  socklen_t(sa.pointee.sa_len),
                                  &host, socklen_t(host.count),
                                  nil, 0, NI_NUMERICHOST)
            guard res == 0 else { continue }

            let ip = String(cString: host)
            if ip.hasPrefix("169.254.") {
                if fallback == nil { fallback = ip }
                continue
            }
            return ip
        }
        return fallback
    }
}
