import Foundation

enum AppConstants {
    // MARK: - App Store
    // Set appStoreID once the app is live in App Store Connect.
    static let appStoreID: String? = "6769007201" // e.g. "6738461506"

    static var appStoreReviewURL: URL? {
        guard let id = appStoreID else { return nil }
        return URL(string: "itms-apps://itunes.apple.com/app/id\(id)?action=write-review")
    }

    // MARK: - Legal
    // Host a simple privacy policy page (GitHub Pages, Notion, or any static site).
    static var privacyPolicyURL: URL? {
        URL(string: "https://mirrornotes.org/privacy.html")
    }

    static var termsOfUseURL: URL? {
        URL(string: "https://mirrornotes.org/terms.html")
    }

    // MARK: - Support
    static var feedbackURL: URL? {
        URL(string: "mailto:hello@mirrornotes.org?subject=MirrorNotes%20Feedback")
    }
}
