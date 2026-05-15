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
        URL(string: "https://mirror.app/privacy") // replace before App Store submission
    }
}
