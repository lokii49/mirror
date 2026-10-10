import Testing
import Foundation
@testable import mirror

// The Siri phrases in MirrorAppShortcuts had no AppShortcuts.xcstrings, so "Hey Siri, add a
// journal entry in MirrorNotes" only worked in English (backlog B). The catalog compiles to an
// AppShortcuts table in each .lproj; every phrase must keep ${applicationName} (Apple's rule).
@Suite("Siri phrase catalog")
struct AppShortcutsCatalogTests {
    private static let phrases = [
        "Add a journal entry in ${applicationName}",
        "Write in ${applicationName}",
        "Journal in ${applicationName}",
    ]

    private static var languages: [String] { Bundle.main.localizations.filter { $0 != "Base" && $0 != "en" } }

    @Test func everyLanguageHasEveryPhrase_withTheAppName() {
        #expect(Self.languages.count >= 9)
        for language in Self.languages {
            guard let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) else {
                Issue.record("no \(language).lproj"); continue
            }
            for phrase in Self.phrases {
                let text = bundle.localizedString(forKey: phrase, value: nil, table: "AppShortcuts")
                #expect(text != phrase, "\(language) has no translation for \(phrase)")
                #expect(text.contains("${applicationName}"), "\(language): \(text)")
            }
        }
    }
}
