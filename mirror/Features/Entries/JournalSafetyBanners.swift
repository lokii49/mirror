import SwiftUI

/// "Your latest changes aren't in iCloud yet." iOS gives no warning before the user turns
/// iCloud off for the app — which erases this device's copy — so this standing notice is
/// the warning. The host decides when to show it (`JournalSafety.showsNotBackedUp`).
struct NotBackedUpBanner: View {
    let uploadFailing: Bool

    var body: some View {
        NoticeBanner(
            systemImage: "icloud.slash",
            title: Text(uploadFailing ? "iCloud upload is failing" : "Not backed up to iCloud yet"),
            sentinelTitle: Text(uploadFailing ? "UPLINK FAILING" : "UPLINK PENDING"),
            message: Text(message)
        )
    }

    private var message: LocalizedStringKey {
        #if os(macOS)
        "Your latest changes are only on this Mac. Keep mirror open while online until this clears, and don't turn off iCloud for mirror or sign out of iCloud before then: that erases this Mac's copy."
        #else
        "Your latest changes are only on this device. Keep mirror open on Wi-Fi until this clears, and don't turn off iCloud for mirror or sign out of iCloud before then: that erases this device's copy."
        #endif
    }
}

/// Offers to put back entries the on-device backup has and the journal doesn't, after the
/// store collapsed (iCloud turned off/on, sign-out). See `JournalSafety.refreshRestoreOffer`.
/// The host shows it only while `JournalSafety.shared.restoreOffer` is non-nil.
struct RestoreFromDeviceBanner: View {
    var safety = JournalSafety.shared
    @State private var confirmRestore = false
    @State private var confirmDiscard = false

    var body: some View {
        if let offer = safety.restoreOffer {
            NoticeBanner(
                systemImage: "clock.arrow.circlepath",
                title: offer.entries > 0
                    ? Text("^[\(offer.entries) entry](inflect: true) can be restored from this device")
                    : Text("^[\(offer.checkIns) mood check-in](inflect: true) can be restored from this device"),
                sentinelTitle: offer.entries > 0
                    ? Text("^[\(offer.entries) LOG ENTRY](inflect: true) RECOVERABLE")
                    : Text("^[\(offer.checkIns) CHECK-IN](inflect: true) RECOVERABLE"),
                message: Text("This device kept a copy of entries that are no longer in your journal, likely because iCloud was turned off or signed out. Restoring adds them back; nothing is removed.")
            ) {
                HStack(spacing: 16) {
                    Button("Restore") { confirmRestore = true }
                        .font(.system(size: 14, weight: .semibold))
                        .disabled(safety.isRestoring)
                    Button("Not now", role: .destructive) { confirmDiscard = true }
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
            }
            .alert("Restore entries?", isPresented: $confirmRestore) {
                Button("Restore") { safety.restore() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(restoreMessage(offer))
            }
            .alert("Discard the device copy?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) { safety.discardRestoreOffer() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("These entries can't be restored afterwards. If you deleted them on purpose, discard.")
            }
        }
    }

    private func restoreMessage(_ offer: JournalSafety.RestoreOffer) -> LocalizedStringKey {
        if offer.entries == 0 {
            return "Adds back ^[\(offer.checkIns) mood check-in](inflect: true). If any of them were deleted on purpose, they'll come back too."
        }
        return offer.checkIns > 0
            ? "Adds back ^[\(offer.entries) entry](inflect: true) and ^[\(offer.checkIns) mood check-in](inflect: true). If any of them were deleted on purpose, they'll come back too."
            : "Adds back ^[\(offer.entries) entry](inflect: true). If any of them were deleted on purpose, they'll come back too."
    }
}
