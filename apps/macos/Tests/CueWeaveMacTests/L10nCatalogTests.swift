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
        let l10n = L10n()
        l10n.setPreference("zh")
        #expect(l10n.language == "zh")
        #expect(l10n.t("action.save") == "保存")
        l10n.setPreference("en")
        #expect(l10n.t("action.save") == "Save")
    }
}
