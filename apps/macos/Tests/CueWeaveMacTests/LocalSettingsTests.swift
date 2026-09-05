import Foundation
import Testing
@testable import CueWeaveMac

@Suite("Local settings")
struct LocalSettingsTests {
    @Test("API keys use only an owner-readable local file")
    func roundTripAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cueweave-settings-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = LocalSettings(
            alignmentProvider: "ai_studio",
            openRouterAPIKey: "openrouter-secret",
            aiStudioAPIKey: "aistudio-secret",
            openRouterModel: ModelDefaults.openRouter,
            aiStudioModel: ModelDefaults.aiStudio,
            uiLanguage: "zh"
        )

        try LocalSettingsStore.save(expected, to: url)

        #expect(LocalSettingsStore.load(from: url) == expected)
        #expect(permissions(url) == 0o600)
        #expect(permissions(directory) == 0o700)
    }

    @Test("Legacy defaults migrate without replacing custom models")
    func migrateLegacyDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cueweave-settings-migration-\(UUID().uuidString)")
        let legacyURL = directory.appendingPathComponent("legacy.json")
        let customURL = directory.appendingPathComponent("custom.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try LocalSettingsStore.save(LocalSettings(
            openRouterModel: "google/gemini-3.7-flash",
            aiStudioModel: "gemini-3.7-flash"
        ), to: legacyURL)
        try LocalSettingsStore.save(LocalSettings(
            openRouterModel: "custom/openrouter-model",
            aiStudioModel: "custom-aistudio-model"
        ), to: customURL)

        let migrated = LocalSettingsStore.load(from: legacyURL)
        #expect(migrated.openRouterModel == ModelDefaults.openRouter)
        #expect(migrated.aiStudioModel == ModelDefaults.aiStudio)
        let custom = LocalSettingsStore.load(from: customURL)
        #expect(custom.openRouterModel == "custom/openrouter-model")
        #expect(custom.aiStudioModel == "custom-aistudio-model")
    }

    private func permissions(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.posixPermissions] as? Int ?? 0
    }
}
