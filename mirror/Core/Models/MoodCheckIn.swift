import Foundation

/// A standalone daily mood signal, captured with one tap from a reminder —
/// no writing required.
///
/// Stored as an encrypted JSON blob in `UserDefaults`, NOT as a SwiftData
/// `@Model`. A new `@Model` type would add a new CKRecord type to the
/// CloudKit schema (`cloudKitDatabase: .automatic`), which needs a manual
/// production-schema deploy before it can ship — every prior release only
/// added fields to existing models, so that path is unproven here. A local
/// blob sidesteps it entirely. The tradeoff: check-ins don't sync across a
/// user's devices. For an ephemeral daily signal that's acceptable for v1;
/// promoting it to a synced model is a deliberate later step.
///
/// Deliberately kept out of every `entries.count`-based eligibility gate
/// (Daily Nudge / Ask / Weekly Digest / Brain View / the App Store review
/// milestone): a mood tap isn't "writing an entry."
struct MoodCheckIn: Identifiable, Codable, Equatable {
    let id: UUID
    let mood: String
    let createdAt: Date
}

enum MoodCheckInStore {
    private static let key = "mirror.moodCheckIns"
    private static let maxRetained = 400

    static func all() -> [MoodCheckIn] {
        guard let encrypted = UserDefaults.standard.string(forKey: key),
              let json = MirrorEncryption.decryptOptionalStringValue(encrypted),
              let data = json.data(using: .utf8),
              let records = try? JSONDecoder().decode([MoodCheckIn].self, from: data)
        else { return [] }
        return records
    }

    /// Appends and returns the new full list, so a caller holding an in-memory
    /// copy can update without re-reading and re-decrypting.
    @discardableResult
    static func add(mood: String, createdAt: Date = Date()) -> [MoodCheckIn] {
        var records = all()
        records.append(MoodCheckIn(id: UUID(), mood: mood, createdAt: createdAt))
        if records.count > maxRetained {
            records.removeFirst(records.count - maxRetained)
        }
        save(records)
        return records
    }

    private static func save(_ records: [MoodCheckIn]) {
        guard let data = try? JSONEncoder().encode(records),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(MirrorEncryption.encryptString(json), forKey: key)
    }
}
