import Foundation
import Testing
@testable import CueWeaveMac

@Suite("Localization catalog")
struct L10nCatalogTests {
    @Test("English and Chinese catalogs share the same keys")
    func matchingKeys() {
        #expect(!L10n.shared.englishKeys.isEmpty)
        #expect(L10n.shared.englishKeys == L10n.shared.chineseKeys)
        #expect(L10n.shared.englishKeys.contains("action.save"))
        #expect(L10n.shared.t("action.save") == L10n.shared.t("action.save"))
    }

    @Test("Preference switches resolved language")
    func preferenceSwitch() {
        let previous = L10n.shared.preference
        defer { L10n.shared.setPreference(previous) }
        L10n.shared.setPreference("zh")
        #expect(L10n.shared.language == "zh")
        #expect(L10n.shared.t("action.save") == "保存")
        L10n.shared.setPreference("en")
        #expect(L10n.shared.t("action.save") == "Save")
    }
}
