import CloudKit
import CryptoKit
import Foundation
import RevenueCat

/// Gives RevenueCat one app user ID per iCloud account instead of an anonymous ID per install,
/// so a promotional entitlement the owner grants in the RevenueCat dashboard survives a reinstall
/// and reaches the user's other devices (iPhone and Mac share the `iCloud.com.lokesh.mirror`
/// container). Grants live on the RevenueCat customer, not on an App Store receipt, so Restore
/// can't bring them back to a new anonymous ID (owner, 2026-10-16).
///
/// The ID is a SHA-256 of the CloudKit user record name, which is stable per iCloud account per
/// container; RevenueCat never sees Apple's identifier itself. Offline or CloudKit failing: nothing
/// changes and RevenueCat keeps whatever ID it has. Signed out of iCloud: see below.
enum RevenueCatIdentity {
    static let idPrefix = "icloud_"

    /// `$RCAnonymousID:…` → identified: RevenueCat aliases the anonymous customer into the new
    /// one, so purchases made before this shipped stay with the user. Signed in to a different
    /// iCloud account than last time: switches to that account's customer.
    ///
    /// Signed out of iCloud (`.noAccount`, never a status that only couldn't be read): a device
    /// still on an `icloud_` ID logs out, so it stops acting as the previous account's customer
    /// and becomes anonymous. That network call happens once, on the first launch after sign-out.
    static func logInWithICloudAccount() async {
        guard canUseCloudKit else { return }
        let container = CKContainer.default()
        let status = try? await container.accountStatus()
        if status == .noAccount {
            if Purchases.shared.appUserID.hasPrefix(idPrefix) {
                _ = try? await Purchases.shared.logOut()
            }
            return
        }
        guard status == .available,
              let recordName = try? await container.userRecordID().recordName else { return }
        let appUserID = appUserID(forRecordName: recordName)
        guard Purchases.shared.appUserID != appUserID else { return }
        // The returned customer info also reaches `SubscriptionService` via `customerInfoStream`.
        _ = try? await Purchases.shared.logIn(appUserID)
    }

    static func appUserID(forRecordName recordName: String) -> String {
        let digest = SHA256.hash(data: Data(recordName.utf8))
        return idPrefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static var canUseCloudKit: Bool {
        #if DEBUG
        // Same guard as JournalSafety: unsigned screenshot builds, entitlement-free UI-test and
        // device-test copies have no iCloud container, and CKContainer.default() raises an
        // Objective-C exception there. Unit tests must not log the simulator's account in either.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--macSnapshot") || args.contains("--uitesting") || PerfSeed.isRequested { return false }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #endif
        return true
    }
}
