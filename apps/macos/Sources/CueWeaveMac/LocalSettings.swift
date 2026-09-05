import Foundation

enum ModelDefaults {
    static let openRouter = "google/gemini-3.8-flash"
    static let aiStudio = "gemini-3.8-flash"

    fileprivate static let legacyOpenRouter = "google/gemini-3.7-flash"
    fileprivate static let legacyAIStudio = "gemini-3.7-flash"
}

struct LocalSettings: Codable, Equatable {
    var alignmentProvider: String?
    var openRouterAPIKey: String?
    var aiStudioAPIKey: String?
    var openRouterModel: String?
    var aiStudioModel: String?
    var uiLanguage: String?

    mutating func migrateLegacyModelDefaults() {
        if openRouterModel == ModelDefaults.legacyOpenRouter {
            openRouterModel = ModelDefaults.openRouter
        }
        if aiStudioModel == ModelDefaults.legacyAIStudio {
            aiStudioModel = ModelDefaults.aiStudio
        }
    }
}

enum LocalSettingsStore {
    static let configURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CueWeave", isDirectory: true)
        .appendingPathComponent("config.json")

    static func load(from url: URL = configURL) -> LocalSettings {
        guard let data = try? Data(contentsOf: url),
              var settings = try? JSONDecoder().decode(LocalSettings.self, from: data)
        else { return LocalSettings() }
        settings.migrateLegacyModelDefaults()
        return settings
    }

    static func save(_ settings: LocalSettings, to url: URL = configURL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
