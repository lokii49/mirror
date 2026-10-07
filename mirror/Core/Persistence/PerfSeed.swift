#if DEBUG
import Foundation
import SwiftData
import CryptoKit
#if os(macOS)
import AppKit
#endif

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

    /// After launch: open Entries and run a few searches, so the entry-list signposts
    /// (entries.snapshot / entries.deps) measure the list without anyone clicking.
    @MainActor
    static func runEntriesScenario() async {
        #if os(macOS)
        try? await Task.sleep(for: .seconds(3))
        NotificationCenter.default.post(name: .mirrorMacNavigate, object: nil, userInfo: ["destination": "entries"])
        for query in ["", "coffee", "", "river", "", "run", ""] {
            try? await Task.sleep(for: .seconds(2))
            NotificationCenter.default.post(name: .mirrorMacDebugEntriesState, object: nil, userInfo: ["search": query])
        }
        #endif
    }

    /// `--draftRecoveryCheck=edit` edits the newest entry without saving and quits
    /// abruptly; `=restore` reopens it and captures the editor (expects the
    /// Restore prompt). Use with `--scratchDraftStorage` and `--macSnapshotDir=`.
    static var draftRecoveryPhase: String? {
        CommandLine.arguments.first { $0.hasPrefix("--draftRecoveryCheck=") }
            .map { String($0.dropFirst("--draftRecoveryCheck=".count)) }
    }

    @MainActor
    static func runDraftRecoveryCheck() async {
        #if os(macOS)
        try? await Task.sleep(for: .seconds(3))
        NotificationCenter.default.post(name: .mirrorMacNavigate, object: nil, userInfo: ["destination": "entries"])
        try? await Task.sleep(for: .seconds(1))
        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(1))
        NotificationCenter.default.post(name: .mirrorMacDebugOpenEditor, object: nil)
        try? await Task.sleep(for: .seconds(2))
        let window = NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
        if draftRecoveryPhase == "edit" {
            NotificationCenter.default.post(name: .mirrorMacDebugWrite, object: nil,
                                            userInfo: ["action": "appendText", "text": " Synthetic unsaved edit."])
            try? await Task.sleep(for: .seconds(2.5))   // past the debounced draft save
            MacSnapshot.capture(window, name: "draft-edit-before-quit")
            exit(0)   // no clean teardown, like a crash or force quit
        }
        MacSnapshot.capture(window?.sheets.first ?? window, name: "draft-\(draftRecoveryPhase ?? "")-prompt")
        let action = draftRecoveryPhase == "discard" ? "discardDraft" : "restoreDraft"
        NotificationCenter.default.post(name: .mirrorMacDebugWrite, object: nil, userInfo: ["action": action])
        try? await Task.sleep(for: .seconds(1.5))
        MacSnapshot.capture(window, name: "draft-\(draftRecoveryPhase ?? "")-after")
        NSApp.terminate(nil)
        #endif
    }

    @MainActor
    static func seedIfNeeded(into context: ModelContext) {
        guard let count = requestedCount, count > 0 else { return }
        defer {
            if CommandLine.arguments.contains("--entryFilterFixture") { seedFilterFixture(into: context) }
            // The draft recovery check drives the main window; onboarding would cover it.
            if draftRecoveryPhase != nil, ((try? context.fetchCount(FetchDescriptor<UserProfile>())) ?? 0) == 0 {
                let profile = UserProfile()
                profile.onboardingComplete = true
                context.insert(profile)
                try? context.save()
            }
        }
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

    /// Explicitly requested synthetic rows for archive filter UI checks only.
    @MainActor
    private static func seedFilterFixture(into context: ModelContext) {
        for index in 0..<3 {
            let id = UUID(uuidString: "F1700000-0000-0000-0000-00000000000\(index)")!
            let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
            guard (try? context.fetchCount(descriptor)) == 0 else { continue }
            let names = ["Alpha", "Beta", "Gamma"]
            let entry = Entry(text: "Filter fixture \(names[index]): coffee by the river.", mood: index == 0 ? "Content" : "Anxious")
            entry.id = id
            entry.tags = index == 0 ? ["work", "travel"] : (index == 1 ? ["work"] : ["travel"])
            entry.isPinned = index == 0
            if index == 0 { entry.photoData = Data([0]); entry.voiceNoteData = Data([0]) }
            context.insert(entry)
        }
        try? context.save()
    }
}
#endif
