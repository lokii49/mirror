import Testing
import Foundation
@testable import mirror

/// A fallback saved in one language is recognised in every other (backlog A6).
@Suite("Fallback detection across languages")
struct FallbackLocalizationTests {
    private static let keys = [
        InsightService.fallbackCatalogKeys.nudge,
        InsightService.fallbackCatalogKeys.unsupportedLanguage,
        InsightService.fallbackCatalogKeys.digest,
        InsightService.fallbackCatalogKeys.monthly,
    ]

    private static var languages: [String] { Bundle.main.localizations.filter { $0 != "Base" } }

    private static func text(_ key: String, in language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    @Test func bundleCarriesTheShippedLanguages() {
        // en + de/es/fr/it/pt-BR/ru/ja/ko/zh-Hans; fewer means the checks below prove little.
        #expect(Self.languages.count >= 10)
    }

    @Test func everyLanguagesFallbackIsDetected() {
        for language in Self.languages {
            for key in Self.keys {
                guard let text = Self.text(key, in: language) else {
                    Issue.record("no \(language).lproj"); continue
                }
                #expect(InsightService.isUngroundedFallback(text), "\(language): \(key.prefix(30))")
                if language != "en" {
                    #expect(text != key, "\(language) has no translation for \(key.prefix(30)); the check would be vacuous")
                }
            }
        }
    }

    @Test func unsupportedLanguageNoticeIsRecognisedInEveryLanguage() {
        for language in Self.languages {
            let text = Self.text(InsightService.fallbackCatalogKeys.unsupportedLanguage, in: language) ?? ""
            #expect(InsightService.isUnsupportedLanguageNotice(text), "\(language)")
        }
        #expect(!InsightService.isUnsupportedLanguageNotice(InsightService.fallbackCatalogKeys.nudge))
    }

    @Test func keysMatchTheConstantsTheAppSaves() {
        // If a String(localized:) literal changes without its key here, detection would miss it.
        #expect(InsightService.isUngroundedFallback(InsightService.dailyNudgeUngroundedFallback))
        #expect(InsightService.isUngroundedFallback(InsightService.weeklyDigestUngroundedFallback))
        #expect(InsightService.isUngroundedFallback(InsightService.monthlyReportUngroundedFallback))
        #expect(InsightService.isUnsupportedLanguageNotice(InsightService.dailyNudgeUnsupportedLanguageNotice))
        for key in Self.keys {
            #expect(Self.text(key, in: "en") == key)
        }
    }

    @Test func legacyEnglishWordingsStillMatch() {
        #expect(InsightService.isUngroundedFallback("Mirror couldn't find a reflection clearly grounded in today's entries. Check back tomorrow, or add a bit more to what you've written today."))
        #expect(InsightService.isUngroundedFallback("Mirror couldn't find a digest clearly grounded in this week's entries. Check back tomorrow, or write a bit more this week."))
    }

    @Test func ordinaryReflectionIsNotAFallback() {
        #expect(!InsightService.isUngroundedFallback(#"You wrote, "Walked by the lake after work." That sounds calm."#))
        #expect(!InsightService.isUngroundedFallback(""))
    }
}
