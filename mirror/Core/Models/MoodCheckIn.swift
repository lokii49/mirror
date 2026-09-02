import Foundation
import SwiftData

/// A standalone daily mood signal — one tap from a reminder, no writing.
///
/// A SwiftData `@Model` synced via CloudKit (`cloudKitDatabase: .automatic`),
/// same as `Entry` / `Insight`. The mood label is encrypted at rest with the
/// shared content key, so CloudKit only ever sees ciphertext.
///
/// Deliberately kept out of every `entries.count`-based eligibility gate
/// (Daily Nudge / Ask / Weekly Digest / Brain View / the App Store review
/// milestone): a mood tap isn't "writing an entry".
///
/// CloudKit constraints honored: every stored property has a default value,
/// and there is no `@Attribute(.unique)` (CloudKit forbids it) — callers
/// de-duplicate on `id` instead (see `MoodCheckInMigration`).
@Model final class MoodCheckIn {
    var id: UUID = UUID()
    var encryptedMood: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), mood: String, createdAt: Date = Date()) {
        self.id = id
        self.encryptedMood = MirrorEncryption.encryptString(mood)
        self.createdAt = createdAt
    }

    /// Decrypted mood label; nil if this device can't read it yet (content key
    /// still propagating via iCloud Keychain).
    var decryptedMood: String? {
        MirrorEncryption.decryptOptionalStringValue(encryptedMood)
    }
}
