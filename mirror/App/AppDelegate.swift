import UIKit

/// Only exists to receive the background URL session completion callback — SwiftUI's
/// App protocol has no hook for it. iOS calls this when it relaunches (or wakes) the
/// app because a background download finished while mirror was suspended, backgrounded,
/// or the device was locked; without acknowledging via the stored completion handler,
/// iOS won't let the app get background time for the next such event.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == ModelDownloadManager.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        // Referencing .shared here is what re-attaches to the still-running background
        // session if the system relaunched the app fresh to deliver this event.
        ModelDownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}
