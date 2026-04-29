import Foundation

// MARK: - Credential

struct Credential: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var scriptID: String
    var authKey: String
    var isEnabledForLB: Bool = true
    var usesCloudflare: Bool = false

    init(id: UUID = UUID(), name: String = "Default",
         scriptID: String = "", authKey: String = "",
         isEnabledForLB: Bool = true, usesCloudflare: Bool = false) {
        self.id = id
        self.name = name
        self.scriptID = scriptID
        self.authKey = authKey
        self.isEnabledForLB = isEnabledForLB
        self.usesCloudflare = usesCloudflare
    }

    enum CodingKeys: String, CodingKey {
        case id, name, scriptID, authKey, isEnabledForLB, usesCloudflare
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        name           = try c.decode(String.self, forKey: .name)
        scriptID       = try c.decode(String.self, forKey: .scriptID)
        authKey        = try c.decode(String.self, forKey: .authKey)
        isEnabledForLB = (try? c.decode(Bool.self, forKey: .isEnabledForLB)) ?? true
        usesCloudflare = (try? c.decode(Bool.self, forKey: .usesCloudflare)) ?? false
    }
}

// MARK: - LBStrategy

/// Determines which profiles get sent to the core when load balancing is on,
/// and how the app responds when an entire pool becomes unhealthy.
enum LBStrategy: String, Codable, CaseIterable, Identifiable {
    case balanced        = "balanced"
    case cfPreferred     = "cf_preferred"
    case normalPreferred = "normal_preferred"
    case cfOnly          = "cf_only"
    case normalOnly      = "normal_only"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced:        return "Balanced"
        case .cfPreferred:     return "Cloudflare First"
        case .normalPreferred: return "Apps Script First"
        case .cfOnly:          return "Cloudflare Only"
        case .normalOnly:      return "Apps Script Only"
        }
    }

    /// One-line explanation shown in the picker and tooltip.
    var detail: String {
        switch self {
        case .balanced:
            return "All selected profiles, spread evenly across requests."
        case .cfPreferred:
            return "Use Cloudflare profiles first; fall back to Apps Script if all Cloudflare fail."
        case .normalPreferred:
            return "Use Apps Script profiles first; fall back to Cloudflare if all Apps Script fail."
        case .cfOnly:
            return "Cloudflare profiles only."
        case .normalOnly:
            return "Apps Script profiles only."
        }
    }

    var icon: String {
        switch self {
        case .balanced:        return "arrow.triangle.2.circlepath"
        case .cfPreferred:     return "cloud.fill"
        case .normalPreferred: return "doc.text.fill"
        case .cfOnly:          return "lock.icloud.fill"
        case .normalOnly:      return "lock.doc.fill"
        }
    }

    /// True for strategies that can trigger an automatic fallback restart.
    var hasFallback: Bool {
        self == .cfPreferred || self == .normalPreferred
    }
}

// MARK: - AppSettings

struct AppSettings: Codable, Equatable {

    // ── Credentials ───────────────────────────────────────────────────────
    var credentials: [Credential] = []
    var activeCredentialID: UUID? = nil
    var enableLoadBalancing: Bool = false
    var lbStrategy: LBStrategy = .balanced

    // ── Transient LB state (NOT persisted) ────────────────────────────────
    /// True while the core is running on the fallback pool after the primary
    /// pool went fully unhealthy. Reset to false on every user-initiated stop.
    var lbFallbackActive: Bool = false

    // ── Listener ──────────────────────────────────────────────────────────
    var listenHost: String = "127.0.0.1"
    var listenPort: Int    = 1080
    var socksPort:  Int    = 8080

    // ── Fronting ──────────────────────────────────────────────────────────
    var frontDomain: String   = "www.google.com"
    var googleIP:    String   = "216.239.38.120"
    var verifySSL:   Bool     = true
    var logLevel:    LogLevel = .info

    // ── System proxy ──────────────────────────────────────────────────────
    var useSystemProxy: Bool = false

    // MARK: Enums

    enum LogLevel: String, Codable, CaseIterable, Identifiable {
        case debug   = "DEBUG"
        case info    = "INFO"
        case warning = "WARNING"
        case error   = "ERROR"
        var id: String { rawValue }
    }

    // MARK: Computed helpers

    var activeCredential: Credential? {
        guard let id = activeCredentialID else { return credentials.first }
        return credentials.first { $0.id == id } ?? credentials.first
    }

    var scriptID: String { activeCredential?.scriptID ?? "" }
    var authKey:  String { activeCredential?.authKey  ?? "" }

    static let `default` = AppSettings()
    init() {}

    // MARK: - Codable (custom for legacy migration)

    enum CodingKeys: String, CodingKey {
        case credentials, activeCredentialID, enableLoadBalancing, lbStrategy
        case listenHost, listenPort, socksPort
        case frontDomain, googleIP, verifySSL, logLevel
        case useSystemProxy
        // Legacy keys — only read for migration, never written
        case legacyScriptID = "scriptID"
        case legacyAuthKey  = "authKey"
        // lbFallbackActive is intentionally NOT listed — it is transient.
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        credentials        = (try? c.decode([Credential].self, forKey: .credentials)) ?? []
        activeCredentialID = try? c.decode(UUID.self, forKey: .activeCredentialID)

        // Migrate old single-credential JSON
        if credentials.isEmpty {
            let sid = (try? c.decode(String.self, forKey: .legacyScriptID)) ?? ""
            let ak  = (try? c.decode(String.self, forKey: .legacyAuthKey))  ?? ""
            if !sid.isEmpty || !ak.isEmpty {
                let cred = Credential(name: "Default", scriptID: sid, authKey: ak)
                credentials        = [cred]
                activeCredentialID = cred.id
            }
        }

        listenHost           = (try? c.decode(String.self,    forKey: .listenHost))           ?? "127.0.0.1"
        listenPort           = (try? c.decode(Int.self,        forKey: .listenPort))           ?? 1080
        socksPort            = (try? c.decode(Int.self,        forKey: .socksPort))            ?? 8080
        frontDomain          = (try? c.decode(String.self,    forKey: .frontDomain))          ?? "www.google.com"
        googleIP             = (try? c.decode(String.self,    forKey: .googleIP))             ?? "216.239.38.120"
        verifySSL            = (try? c.decode(Bool.self,       forKey: .verifySSL))            ?? true
        logLevel             = (try? c.decode(LogLevel.self,   forKey: .logLevel))             ?? .info
        useSystemProxy       = (try? c.decode(Bool.self,       forKey: .useSystemProxy))       ?? false
        enableLoadBalancing  = (try? c.decode(Bool.self,       forKey: .enableLoadBalancing))  ?? false
        lbStrategy           = (try? c.decode(LBStrategy.self, forKey: .lbStrategy))           ?? .balanced
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(credentials,         forKey: .credentials)
        try c.encode(activeCredentialID,  forKey: .activeCredentialID)
        try c.encode(listenHost,          forKey: .listenHost)
        try c.encode(listenPort,          forKey: .listenPort)
        try c.encode(socksPort,           forKey: .socksPort)
        try c.encode(frontDomain,         forKey: .frontDomain)
        try c.encode(googleIP,            forKey: .googleIP)
        try c.encode(verifySSL,           forKey: .verifySSL)
        try c.encode(logLevel,            forKey: .logLevel)
        try c.encode(useSystemProxy,      forKey: .useSystemProxy)
        try c.encode(enableLoadBalancing, forKey: .enableLoadBalancing)
        try c.encode(lbStrategy,          forKey: .lbStrategy)
        // lbFallbackActive is NOT encoded — it resets to false on every app launch.
    }

    // MARK: - Effective LB pool

    /// The set of credentials that will actually be sent to the core, given
    /// the current strategy and fallback state. This mirrors `makeCoreConfig()`'s
    /// script selection logic and is used by the UI (ClusterPulse, banners).
    var effectiveLBPool: [Credential] {
        guard enableLoadBalancing else {
            return activeCredential.map { [$0] } ?? []
        }
        let enabled    = credentials.filter { $0.isEnabledForLB }
        let cfPool     = enabled.filter  { $0.usesCloudflare }
        let normalPool = enabled.filter  { !$0.usesCloudflare }

        switch lbStrategy {
        case .balanced:
            return enabled
        case .cfOnly:
            return cfPool
        case .normalOnly:
            return normalPool
        case .cfPreferred:
            if lbFallbackActive { return enabled }          // fell back → use all
            return cfPool.isEmpty ? normalPool : cfPool     // primary pool
        case .normalPreferred:
            if lbFallbackActive { return enabled }
            return normalPool.isEmpty ? cfPool : normalPool
        }
    }

    // MARK: - Core config

    func makeCoreConfig() -> [String: Any] {
        let cred = activeCredential
        let scriptsToUse = enableLoadBalancing ? effectiveLBPool : (cred.map { [$0] } ?? [])

        let scriptConfigs: [[String: Any]] = scriptsToUse.map { c in
            ["id": c.scriptID, "key": c.authKey, "is_cf": c.usesCloudflare]
        }.filter { ($0["id"] as? String)?.isEmpty == false }

        var dict: [String: Any] = [
            "mode":           "apps_script",
            "google_ip":      googleIP,
            "front_domain":   frontDomain,
            "script_id":      cred?.scriptID ?? "",
            "auth_key":       cred?.authKey  ?? "",
            "script_configs": scriptConfigs,
            "parallel_relay": enableLoadBalancing ? max(1, scriptConfigs.count) : 1,
            "listen_host":    listenHost,
            "listen_port":    listenPort,
            "socks5_host":    listenHost,
            "socks5_port":    socksPort,
            "log_level":      logLevel.rawValue,
            "verify_ssl":     verifySSL
        ]
        dict = dict.compactMapValues { value -> Any? in
            if let s = value as? String { return s.isEmpty ? nil : s }
            return value
        }
        return dict
    }
}
