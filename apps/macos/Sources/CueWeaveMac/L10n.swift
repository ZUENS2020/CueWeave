import Foundation

final class L10n: ObservableObject {
    static let shared = L10n()

    @Published private(set) var preference = "system"
    @Published private(set) var language = L10n.resolve("system")

    private let catalog: [String: [String: String]]

    private init() {
        catalog = Self.loadCatalog()
    }

    var englishKeys: Set<String> { Set((catalog["en"] ?? [:]).keys) }
    var chineseKeys: Set<String> { Set((catalog["zh"] ?? [:]).keys) }

    func setPreference(_ value: String) {
        let next = ["system", "en", "zh"].contains(value) ? value : "system"
        let resolved = Self.resolve(next)
        guard next != preference || resolved != language else { return }
        preference = next
        language = resolved
    }

    func t(_ key: String, _ args: String...) -> String {
        var value = catalog[language]?[key] ?? catalog["en"]?[key] ?? key
        for (index, arg) in args.enumerated() {
            value = value.replacingOccurrences(of: "{\(index)}", with: arg)
        }
        return value
    }

    static func resolve(_ preference: String) -> String {
        if preference == "en" || preference == "zh" { return preference }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code.hasPrefix("zh") ? "zh" : "en"
    }

    private static func loadCatalog() -> [String: [String: String]] {
        for url in catalogURLs() {
            guard let data = try? Data(contentsOf: url),
                  let parsed = try? JSONDecoder().decode([String: [String: String]].self, from: data),
                  parsed["en"] != nil, parsed["zh"] != nil
            else { continue }
            return parsed
        }
        return [:]
    }

    private static func catalogURLs() -> [URL] {
        var urls: [URL] = []
        if let exe = Bundle.main.executableURL {
            urls.append(exe.deletingLastPathComponent().appendingPathComponent("l10n.json"))
        }
        urls.append(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("shared/l10n.json")
        )
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0 ..< 8 {
            urls.append(directory.appendingPathComponent("apps/shared/l10n.json"))
            directory.deleteLastPathComponent()
        }
        return urls
    }
}
