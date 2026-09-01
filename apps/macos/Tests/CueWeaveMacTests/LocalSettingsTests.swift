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
            openRouterModel: "google/gemini-3.7-flash",
            aiStudioModel: "gemini-3.7-flash",
            uiLanguage: "zh"
        )

        try LocalSettingsStore.save(expected, to: url)

        #expect(LocalSettingsStore.load(from: url) == expected)
        #expect(permissions(url) == 0o600)
        #expect(permissions(directory) == 0o700)
    }

    private func permissions(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.posixPermissions] as? Int ?? 0
    }
}
