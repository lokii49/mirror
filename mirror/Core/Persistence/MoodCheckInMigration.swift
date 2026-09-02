import Foundation
import SwiftData

/// One-time move of daily mood check-ins from the pre-2.0.9 encrypted
/// `UserDefaults` blob (`mirror.moodCheckIns`) into SwiftData, so they sync via
/// CloudKit like everything else.
///
/// One-directional and idempotent: reads the blob, inserts any check-in whose
/// `id` isn't already a `MoodCheckIn`, and **never deletes the blob** — a
/// downgrade, or a CloudKit schema deploy that hasn't landed yet, must not lose
/// the user's history. The flag is set only after a successful `save()`, so a
/// transient failure just retries on the next foreground.
enum MoodCheckInMigration {
    private static let flag = "mirror.didMigrateMoodCheckInsToSwiftData"
    private static let legacyKey = "mirror.moodCheckIns"

    private struct LegacyRecord: Codable {
        let id: UUID
        let mood: String
        let createdAt: Date
    }

    @MainActor
    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flag) else { return }

        let legacy = legacyRecords()
        guard !legacy.isEmpty else {
            // Nothing to migrate — mark done so we stop checking.
            UserDefaults.standard.set(true, forKey: flag)
            return
        }

        let existing = (try? context.fetch(FetchDescriptor<MoodCheckIn>())) ?? []
        let existingIDs = Set(existing.map(\.id))

        var inserted = 0
        for record in legacy where !existingIDs.contains(record.id) {
            context.insert(MoodCheckIn(id: record.id, mood: record.mood, createdAt: record.createdAt))
            inserted += 1
        }

        do {
            if inserted > 0 { try context.save() }
            UserDefaults.standard.set(true, forKey: flag)
        } catch {
            // Leave the flag unset — retry next foreground. The blob is intact.
        }
    }

    private static func legacyRecords() -> [LegacyRecord] {
        guard let encrypted = UserDefaults.standard.string(forKey: legacyKey),
              let json = MirrorEncryption.decryptOptionalStringValue(encrypted),
              let data = json.data(using: .utf8),
              let records = try? JSONDecoder().decode([LegacyRecord].self, from: data)
        else { return [] }
        return records
    }
}
