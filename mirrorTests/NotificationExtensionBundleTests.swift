import Testing
import Foundation
@testable import mirror

#if os(iOS)
// The expanded daily nudge (MirrorNotificationContentExtension) had no strings resources, so
// "Write now", "Open log" and the mood name were English everywhere, and it showed the body twice:
// once in its own card and again in the system's default content below it (backlog B).
@Suite("Notification content extension bundle")
struct NotificationExtensionBundleTests {
    private static var appex: Bundle? {
        Bundle.main.builtInPlugInsURL
            .map { $0.appendingPathComponent("MirrorNotificationContentExtension.appex") }
            .flatMap(Bundle.init(url:))
    }

    @Test func defaultContentIsHidden_soTheBodyShowsOnce() throws {
        let appex = try #require(Self.appex)
        let attributes = (appex.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any]
        #expect(attributes?["UNNotificationExtensionDefaultContentHidden"] as? Bool == true)
    }

    @Test(arguments: ["de", "ja", "ru"])
    func buttonsAndMoodsAreTranslated(_ language: String) throws {
        let appex = try #require(Self.appex)
        let lproj = try #require(appex.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)))
        for key in ["Write now", "Open log", "Content", "Anxious", "Numb"] {
            let text = lproj.localizedString(forKey: key, value: nil, table: nil)
            #expect(text != key, "\(language): \(key) is untranslated in the extension")
        }
    }
}
#endif
