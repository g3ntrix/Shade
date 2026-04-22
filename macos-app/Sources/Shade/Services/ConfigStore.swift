import Foundation

/// Reads/writes `AppSettings` to Application Support, plus produces the
/// `config.json` the bundled Python core consumes.
final class ConfigStore {
    private let fm = FileManager.default

    var appSupportDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Shade", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var settingsFile: URL { appSupportDir.appendingPathComponent("settings.json") }
    private var coreConfigFile: URL { appSupportDir.appendingPathComponent("config.json") }

    // MARK: - Settings

    func loadSettings() -> AppSettings? {
        guard let data = try? Data(contentsOf: settingsFile) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    func saveSettings(_ s: AppSettings) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(s) {
            try? data.write(to: settingsFile, options: .atomic)
        }
    }

    // MARK: - Core config.json

    /// Serializes `AppSettings.makeCoreConfig()` to a JSON file the core reads
    /// with `shade-core -c <path>`. Returns the path.
    @discardableResult
    func writeCoreConfig(_ settings: AppSettings) throws -> URL {
        let dict = settings.makeCoreConfig()
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: coreConfigFile, options: .atomic)
        return coreConfigFile
    }
}
