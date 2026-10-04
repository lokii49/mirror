#if DEBUG
import Foundation
import SwiftData
import CryptoKit

/// DEBUG-only synthetic journal for performance baselines: `--perfSeed=<N>` opens an on-disk scratch
/// store (never the real one, no CloudKit) and fills it once with N synthetic entries, one per day,
/// every 10th with a photo-sized blob. Synthetic text only. Encryption uses a fixed key derived from a
/// constant, so seeded runs never read or write the Keychain (a content key written to the synced
/// Keychain here would reach the owner's other devices) and the store stays readable across launches.
enum PerfSeed {
    static var requestedCount: Int? {
        CommandLine.arguments.lazy.compactMap { arg -> Int? in
            guard arg.hasPrefix("--perfSeed=") else { return nil }
            return Int(arg.dropFirst("--perfSeed=".count))
        }.first
    }

    static var isRequested: Bool { requestedCount != nil }

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PerfSeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("perf-\(requestedCount ?? 0).store")
    }

    static let key = SymmetricKey(data: SHA256.hash(data: Data("mirror-perf-seed-v1".utf8)))

    private static let sentences = [
        "Woke up early and made coffee before the meeting.", "The standup ran long again.",
        "Lunch was noodles at the desk.", "Called Sam after work and talked about the trip.",
        "Felt tired by the afternoon but finished the report.", "Went for a run by the river.",
        "Read two chapters before bed.", "The client changed the scope again.",
        "Cooked dal and rice for dinner.", "Not sure about the plan for the weekend.",
        "Spent the evening fixing the bike.", "Grateful for a quiet morning.",
    ]

    @MainActor
    static func seedIfNeeded(into context: ModelContext) {
        guard let count = requestedCount, count > 0 else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard existing < count else { return }
        let moods = MirrorTheme.moodOptions
        let photo = Data((0..<180_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let now = Date()
        for i in existing..<count {
            let text = (0..<8).map { sentences[(i + $0 * 5) % sentences.count] }.joined(separator: " ")
            let entry = Entry(text: text, mood: moods[i % moods.count])
            entry.createdAt = now.addingTimeInterval(-Double(i) * 86_400 - 3_600)
            if i % 10 == 0 { entry.photoData = photo }
            context.insert(entry)
            if i % 200 == 199 { try? context.save() }
        }
        try? context.save()
    }
}
#endif
