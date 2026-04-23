import Foundation

// MARK: - Credential

struct Credential: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var scriptID: String
    var authKey: String
    var isEnabledForLB: Bool = true

    init(id: UUID = UUID(), name: String = "Default",
         scriptID: String = "", authKey: String = "", isEnabledForLB: Bool = true) {
        self.id = id
        self.name = name
        self.scriptID = scriptID
        self.authKey = authKey
        self.isEnabledForLB = isEnabledForLB
    }
}

// MARK: - AppSettings

struct AppSettings: Codable, Equatable {

    // ── Credentials ───────────────────────────────────────────────────────
    var credentials: [Credential] = []
    var activeCredentialID: UUID? = nil
    var enableLoadBalancing: Bool = false

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
        case credentials, activeCredentialID, enableLoadBalancing
        case listenHost, listenPort, socksPort
        case frontDomain, googleIP, verifySSL, logLevel
        case useSystemProxy
        // Legacy keys — only read for migration, never written
        case legacyScriptID = "scriptID"
        case legacyAuthKey  = "authKey"
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

        listenHost      = (try? c.decode(String.self,   forKey: .listenHost))      ?? "127.0.0.1"
        listenPort      = (try? c.decode(Int.self,       forKey: .listenPort))      ?? 1080
        socksPort       = (try? c.decode(Int.self,       forKey: .socksPort))       ?? 8080
        frontDomain     = (try? c.decode(String.self,   forKey: .frontDomain))     ?? "www.google.com"
        googleIP        = (try? c.decode(String.self,   forKey: .googleIP))        ?? "216.239.38.120"
        verifySSL       = (try? c.decode(Bool.self,      forKey: .verifySSL))       ?? true
        logLevel        = (try? c.decode(LogLevel.self,  forKey: .logLevel))        ?? .info
        useSystemProxy     = (try? c.decode(Bool.self,      forKey: .useSystemProxy))  ?? false
        enableLoadBalancing = (try? c.decode(Bool.self,      forKey: .enableLoadBalancing)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(credentials,        forKey: .credentials)
        try c.encode(activeCredentialID, forKey: .activeCredentialID)
        try c.encode(listenHost,         forKey: .listenHost)
        try c.encode(listenPort,         forKey: .listenPort)
        try c.encode(socksPort,          forKey: .socksPort)
        try c.encode(frontDomain,        forKey: .frontDomain)
        try c.encode(googleIP,           forKey: .googleIP)
        try c.encode(verifySSL,          forKey: .verifySSL)
        try c.encode(logLevel,           forKey: .logLevel)
        try c.encode(useSystemProxy,     forKey: .useSystemProxy)
        try c.encode(enableLoadBalancing, forKey: .enableLoadBalancing)
    }

    // MARK: - Core config

    func makeCoreConfig() -> [String: Any] {
        let cred = activeCredential
        
        // Determine which scripts to pass to the core
        let scriptsToUse: [Credential]
        if enableLoadBalancing {
            scriptsToUse = credentials.filter { $0.isEnabledForLB }
        } else {
            scriptsToUse = cred != nil ? [cred!] : []
        }

        let scriptConfigs = scriptsToUse.map { c in
            ["id": c.scriptID, "key": c.authKey]
        }.filter { !($0["id"]?.isEmpty ?? true) }

        var dict: [String: Any] = [
            "mode":           "apps_script",
            "google_ip":      googleIP,
            "front_domain":   frontDomain,
            "script_id":      cred?.scriptID ?? "",
            "auth_key":       cred?.authKey  ?? "",
            "script_configs": scriptConfigs,
            "parallel_relay": enableLoadBalancing ? 2 : 1,
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
