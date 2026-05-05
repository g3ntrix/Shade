import Foundation

// MARK: - Credential

struct Credential: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var scriptID: String
    var authKey: String
    var isEnabledForLB: Bool = true
    var usesCloudflare: Bool = false
    /// When true, relay JSON may include exit-node (`en`) for this deployment.
    var usesValTunnel: Bool = false

    init(id: UUID = UUID(), name: String = "Default",
         scriptID: String = "", authKey: String = "",
         isEnabledForLB: Bool = true, usesCloudflare: Bool = false,
         usesValTunnel: Bool = false) {
        self.id = id
        self.name = name
        self.scriptID = scriptID
        self.authKey = authKey
        self.isEnabledForLB = isEnabledForLB
        self.usesCloudflare = usesCloudflare
        self.usesValTunnel = usesValTunnel
    }

    enum CodingKeys: String, CodingKey {
        case id, name, scriptID, authKey, isEnabledForLB, usesCloudflare, usesValTunnel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        name           = try c.decode(String.self, forKey: .name)
        scriptID       = try c.decode(String.self, forKey: .scriptID)
        authKey        = try c.decode(String.self, forKey: .authKey)
        isEnabledForLB = (try? c.decode(Bool.self, forKey: .isEnabledForLB)) ?? true
        usesCloudflare = (try? c.decode(Bool.self, forKey: .usesCloudflare)) ?? false
        usesValTunnel = (try? c.decode(Bool.self, forKey: .usesValTunnel)) ?? false
    }
}

// MARK: - ExitNodeProfile

/// One HTTP exit relay (hosted service or self-hosted tools/vps-exit-worker). Apps Script POSTs here for matching hosts.
struct ExitNodeProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var relayURL: String
    var psk: String
    /// When exit load balancing is on, only checked profiles participate in round-robin.
    var isEnabledForLB: Bool = true

    init(
        id: UUID = UUID(),
        name: String = "Exit relay",
        relayURL: String = "",
        psk: String = "",
        isEnabledForLB: Bool = true
    ) {
        self.id = id
        self.name = name
        self.relayURL = relayURL
        self.psk = psk
        self.isEnabledForLB = isEnabledForLB
    }

    enum CodingKeys: String, CodingKey {
        case id, name, relayURL, psk, isEnabledForLB
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self, forKey: .id)
        name           = try c.decode(String.self, forKey: .name)
        relayURL       = try c.decode(String.self, forKey: .relayURL)
        psk            = try c.decode(String.self, forKey: .psk)
        isEnabledForLB = (try? c.decode(Bool.self, forKey: .isEnabledForLB)) ?? true
    }
}

// MARK: - ExitNodeMode

/// Selective = only listed host suffixes use the exit relay; full = all relay URLs.
enum ExitNodeMode: String, Codable, CaseIterable, Identifiable {
    case selective = "selective"
    case full = "full"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selective: return "Selective"
        case .full:      return "Full"
        }
    }

    var detail: String {
        switch self {
        case .selective:
            return "Only host suffixes listed below use the exit node."
        case .full:
            return "Every relayed URL goes through the exit node (higher latency)."
        }
    }
}

// MARK: - LBStrategy

/// Determines which Apps Script profiles get sent to the core when load balancing is on.
enum LBStrategy: String, Codable, CaseIterable, Identifiable {
    case balanced        = "balanced"
    case cfPreferred     = "cf_preferred"
    case normalPreferred = "normal_preferred"
    case cfOnly          = "cf_only"
    case normalOnly      = "normal_only"
    case valPreferred    = "val_preferred"
    case valOnly         = "val_only"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced:        return "Balanced"
        case .cfPreferred:     return "Cloudflare First"
        case .normalPreferred: return "Apps Script First"
        case .cfOnly:          return "Cloudflare Only"
        case .normalOnly:      return "Apps Script Only"
        case .valPreferred:    return "Exit First"
        case .valOnly:         return "Exit Only"
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
        case .valPreferred:
            return "Use exit-enabled profiles first; fall back to others if all exit-enabled profiles fail."
        case .valOnly:
            return "Profiles tagged for exit relay only."
        }
    }

    var icon: String {
        switch self {
        case .balanced:        return "arrow.triangle.2.circlepath"
        case .cfPreferred:     return "cloud.fill"
        case .normalPreferred: return "doc.text.fill"
        case .cfOnly:          return "lock.icloud.fill"
        case .normalOnly:      return "lock.doc.fill"
        case .valPreferred:    return "arrow.turn.up.right"
        case .valOnly:         return "lock.shield.fill"
        }
    }

    /// True for strategies that can trigger an automatic fallback restart.
    var hasFallback: Bool {
        self == .cfPreferred
            || self == .normalPreferred
            || self == .valPreferred
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

    // ── Advanced ──────────────────────────────────────────────────────────
    var enableAppLogs: Bool = false
    var youtubeViaRelay: Bool = false
    var useFullTunnel: Bool = false

    // ── Exit node (Apps Script → exit relay → origin) ───────────────────────
    /// Settings: allow exit relays; when off the core omits exit_node and related controls are disabled.
    var exitRoutingAllowed: Bool = false
    /// Dashboard: actually route matching traffic through configured tunnels (default off).
    var valRelayEnabled: Bool = false
    /// Round-robin across `exitNodeProfiles` that have `isEnabledForLB`. When false, only `activeExitNodeProfileID` (or the first valid profile) is used.
    var enableExitNodeLB: Bool = false
    var exitNodeProfiles: [ExitNodeProfile] = []
    var activeExitNodeProfileID: UUID? = nil
    var exitNodeMode: ExitNodeMode = .full
    /// Space- or comma-separated host suffixes (e.g. chatgpt.com openai.com).
    var exitNodeHosts: String = "chatgpt.com openai.com claude.ai x.com grok.com"

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
        case useSystemProxy, enableAppLogs, youtubeViaRelay
        case useFullTunnel
        case exitRoutingAllowed, valRelayEnabled
        /// Legacy single toggle; read for migration only.
        case exitNodeEnabled
        case enableExitNodeLB, exitNodeProfiles, activeExitNodeProfileID
        case exitNodeMode, exitNodeHosts
        case legacyExitRelayURL = "exitNodeRelayURL"
        case legacyExitPSK = "exitNodePSK"
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
        enableAppLogs        = (try? c.decode(Bool.self,       forKey: .enableAppLogs))        ?? false
        youtubeViaRelay      = (try? c.decode(Bool.self,       forKey: .youtubeViaRelay))      ?? false
        useFullTunnel        = (try? c.decode(Bool.self,       forKey: .useFullTunnel))        ?? false
        let legacyExitOn = (try? c.decode(Bool.self, forKey: .exitNodeEnabled)) ?? false
        exitRoutingAllowed = (try? c.decode(Bool.self, forKey: .exitRoutingAllowed)) ?? legacyExitOn
        valRelayEnabled    = (try? c.decode(Bool.self, forKey: .valRelayEnabled))    ?? legacyExitOn
        enableExitNodeLB     = (try? c.decode(Bool.self,       forKey: .enableExitNodeLB))     ?? false
        exitNodeProfiles     = (try? c.decode([ExitNodeProfile].self, forKey: .exitNodeProfiles)) ?? []
        activeExitNodeProfileID = try? c.decode(UUID.self, forKey: .activeExitNodeProfileID)
        exitNodeMode         = (try? c.decode(ExitNodeMode.self, forKey: .exitNodeMode))       ?? .full
        exitNodeHosts        = (try? c.decode(String.self,     forKey: .exitNodeHosts))        ?? "chatgpt.com openai.com claude.ai x.com grok.com"

        if exitNodeProfiles.isEmpty {
            let legacyURL = (try? c.decode(String.self, forKey: .legacyExitRelayURL)) ?? ""
            let legacyPSK = (try? c.decode(String.self, forKey: .legacyExitPSK)) ?? ""
            if !legacyURL.isEmpty || !legacyPSK.isEmpty {
                let p = ExitNodeProfile(name: "Exit 1", relayURL: legacyURL, psk: legacyPSK)
                exitNodeProfiles = [p]
                if activeExitNodeProfileID == nil { activeExitNodeProfileID = p.id }
            }
        }
        enableLoadBalancing  = (try? c.decode(Bool.self,       forKey: .enableLoadBalancing))  ?? false
        let lbRaw = (try? c.decode(String.self, forKey: .lbStrategy)) ?? "balanced"
        lbStrategy = AppSettings.migrateLBStrategy(rawValue: lbRaw)
    }

    /// Maps stored raw strings; removes retired strategies without failing decode.
    private static func migrateLBStrategy(rawValue: String) -> LBStrategy {
        switch rawValue {
        case "non_val_preferred", "non_val_only":
            return .balanced
        default:
            return LBStrategy(rawValue: rawValue) ?? .balanced
        }
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
        try c.encode(enableAppLogs,       forKey: .enableAppLogs)
        try c.encode(youtubeViaRelay,     forKey: .youtubeViaRelay)
        try c.encode(useFullTunnel,       forKey: .useFullTunnel)
        try c.encode(exitRoutingAllowed, forKey: .exitRoutingAllowed)
        try c.encode(valRelayEnabled,    forKey: .valRelayEnabled)
        try c.encode(enableExitNodeLB,       forKey: .enableExitNodeLB)
        try c.encode(exitNodeProfiles,       forKey: .exitNodeProfiles)
        try c.encode(activeExitNodeProfileID, forKey: .activeExitNodeProfileID)
        try c.encode(exitNodeMode,           forKey: .exitNodeMode)
        try c.encode(exitNodeHosts,          forKey: .exitNodeHosts)
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
        let valPool    = enabled.filter  { $0.usesValTunnel }
        let nonValPool = enabled.filter  { !$0.usesValTunnel }

        switch lbStrategy {
        case .balanced:
            return enabled
        case .cfOnly:
            return cfPool
        case .normalOnly:
            return normalPool.filter { !$0.usesValTunnel }
        case .cfPreferred:
            if lbFallbackActive { return enabled }          // fell back → use all
            return cfPool.isEmpty ? normalPool : cfPool     // primary pool
        case .normalPreferred:
            if lbFallbackActive { return enabled }
            return normalPool.isEmpty ? cfPool : normalPool
        case .valOnly:
            return valPool
        case .valPreferred:
            if lbFallbackActive { return enabled }
            return valPool.isEmpty ? nonValPool : valPool
        }
    }

    /// LB cluster dots: full emphasis for the strategy’s preferred tier only (fallback tier matches dimmed out-of-pool styling).
    func isLBPulsePrimaryFocus(_ cred: Credential) -> Bool {
        guard enableLoadBalancing else { return true }
        let enabled = credentials.filter(\.isEnabledForLB)
        let cfPool = enabled.filter(\.usesCloudflare)
        let normalPool = enabled.filter { !$0.usesCloudflare }
        let valPool = enabled.filter(\.usesValTunnel)

        switch lbStrategy {
        case .balanced:
            return true
        case .cfOnly:
            return cred.usesCloudflare
        case .normalOnly:
            return !cred.usesCloudflare
        case .valOnly:
            return cred.usesValTunnel
        case .cfPreferred:
            if lbFallbackActive { return true }
            if cfPool.isEmpty { return !cred.usesCloudflare }
            return cred.usesCloudflare
        case .normalPreferred:
            if lbFallbackActive { return true }
            if normalPool.isEmpty { return cred.usesCloudflare }
            let plainAppsScript = normalPool.filter { !$0.usesValTunnel }
            if plainAppsScript.isEmpty { return !cred.usesCloudflare }
            return !cred.usesCloudflare && !cred.usesValTunnel
        case .valPreferred:
            if lbFallbackActive { return true }
            if valPool.isEmpty { return !cred.usesValTunnel }
            return cred.usesValTunnel
        }
    }

    /// Valid exit profiles: non-empty http(s) URL and PSK length ≥ 8.
    func validExitNodeProfiles() -> [ExitNodeProfile] {
        exitNodeProfiles.filter { p in
            let u = p.relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let low = u.lowercased()
            return (low.hasPrefix("https://") || low.hasPrefix("http://")) && p.psk.count >= 8
        }
    }

    /// Profiles passed to the core for exit round-robin or single-relay mode.
    var effectiveExitNodePool: [ExitNodeProfile] {
        let valid = validExitNodeProfiles()
        guard exitRoutingAllowed, valRelayEnabled, !valid.isEmpty else { return [] }
        if enableExitNodeLB {
            let pool = valid.filter(\.isEnabledForLB)
            return pool.isEmpty ? valid : pool
        }
        if let id = activeExitNodeProfileID, let one = valid.first(where: { $0.id == id }) {
            return [one]
        }
        return valid.first.map { [$0] } ?? []
    }

    // MARK: - Core config

    func makeCoreConfig() -> [String: Any] {
        let cred = activeCredential
        let scriptsToUse = enableLoadBalancing ? effectiveLBPool : (cred.map { [$0] } ?? [])

        let scriptConfigs: [[String: Any]] = scriptsToUse.map { c in
            [
                "id": c.scriptID,
                "key": c.authKey,
                "is_cf": c.usesCloudflare,
                "use_exit": c.usesValTunnel,
            ]
        }.filter { !($0["id"] as? String ?? "").isEmpty }

        var dict: [String: Any] = [
            "mode":           (useFullTunnel ? "full" : "apps_script"),
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
            "verify_ssl":     verifySSL,
            "youtube_via_relay": youtubeViaRelay
        ]
        let exitPool = effectiveExitNodePool
        if !exitPool.isEmpty {
            let tokens = exitNodeHosts.split { ch in
                ch.isWhitespace || ch == ","
            }.map { $0.lowercased() }.filter { !$0.isEmpty }
            let relayConfigs: [[String: String]] = exitPool.map { p in
                [
                    "relay_url": p.relayURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    "psk": p.psk,
                ]
            }
            var en: [String: Any] = [
                "enabled": true,
                "mode": exitNodeMode.rawValue,
                "relay_configs": relayConfigs,
            ]
            if exitNodeMode == .selective {
                en["hosts"] = tokens
            }
            dict["exit_node"] = en
        }
        dict = dict.compactMapValues { value -> Any? in
            if let s = value as? String { return s.isEmpty ? nil : s }
            return value
        }
        return dict
    }
}
