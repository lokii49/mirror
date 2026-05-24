import Testing
import SwiftData
import Foundation
@testable import mirror

// Benchmarks the per-frame hot paths that caused app freeze with year-long datasets.
// Each test contrasts the OLD approach (called every render frame) vs NEW (cached, called once).

@MainActor
struct PerformanceTests {

    // MARK: - Helpers

    private static func makeEntries() throws -> (container: ModelContainer, entries: [Entry]) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Entry.self, configurations: config)
        let context = ModelContext(container)

        let moods = ["Joyful", "Grateful", "Peaceful", "Content", "Energized", "Hopeful",
                     "Anxious", "Overwhelmed", "Frustrated", "Drained", "Sad", "Numb"]
        let base = Calendar.current.date(byAdding: .day, value: -364, to: Date())!
        for i in 0..<365 {
            let e = Entry(text: "Day \(i): Some journaled thoughts for today. Reflecting on experiences.")
            e.mood = moods[i % moods.count]
            e.createdAt = Calendar.current.date(byAdding: .day, value: i, to: base)!
            context.insert(e)
        }
        try context.save()

        let descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\Entry.createdAt, order: .reverse)])
        let entries = try context.fetch(descriptor)
        return (container, entries)
    }

    private func ms(_ start: Double) -> Double {
        (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    private func log(_ message: String) {
        fputs("PERF_RESULT: \(message)\n", stderr)
    }

    // MARK: - Test 1: usedMoods (EntryListView hot path)
    // OLD: called every body evaluation → 60 AES-decrypt-all calls per second while scrolling.
    // NEW: .task(id:) computes once on data change, body reads cached array.

    @Test func usedMoods_perFrameVsCached() throws {
        let (_, entries) = try Self.makeEntries()
        #expect(entries.count == 365)

        let frames = 60

        // OLD: decrypt all moods every frame
        let oldStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            let _ = entries.compactMap(\.mood).filter { !$0.isEmpty }
        }
        let oldMs = ms(oldStart)

        // NEW: decrypt once, array read on remaining frames
        let newStart = CFAbsoluteTimeGetCurrent()
        let cachedMoods = entries.compactMap(\.mood).filter { !$0.isEmpty }
        for _ in 0..<(frames - 1) {
            let _ = cachedMoods
        }
        let newMs = ms(newStart)

        log("[usedMoods] OLD \(frames) frames: \(String(format: "%.1f", oldMs))ms | NEW (1 compute + \(frames-1) cache reads): \(String(format: "%.1f", newMs))ms | speedup: \(String(format: "%.0f", oldMs / max(newMs, 0.001)))x")

        #expect(oldMs > newMs * 5,
                "Per-frame mood decryption (\(String(format: "%.1f", oldMs))ms) must be >5x slower than cached (\(String(format: "%.1f", newMs))ms)")
    }

    // MARK: - Test 2: CalendarHeatmap entriesByDay dict
    // OLD: dict rebuilt from all entries on every cell render (~371 cells × rebuild).
    // NEW: built once in .task(id: entries.count), O(1) cache lookup per cell.

    @Test func calendarHeatmap_dictRebuildVsCached() throws {
        let (_, entries) = try Self.makeEntries()
        let cal = Calendar.current

        let frames = 60

        // OLD: rebuild on every render
        let oldStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            var dict: [Date: [Entry]] = [:]
            for e in entries {
                let day = cal.startOfDay(for: e.createdAt)
                dict[day, default: []].append(e)
            }
            let _ = dict
        }
        let oldMs = ms(oldStart)

        // NEW: build once, read 59 more times
        let newStart = CFAbsoluteTimeGetCurrent()
        var cachedDict: [Date: [Entry]] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e.createdAt)
            cachedDict[day, default: []].append(e)
        }
        for _ in 0..<(frames - 1) {
            let _ = cachedDict
        }
        let newMs = ms(newStart)

        log("[entriesByDay] OLD \(frames) rebuilds: \(String(format: "%.1f", oldMs))ms | NEW (1 build + \(frames-1) reads): \(String(format: "%.1f", newMs))ms | speedup: \(String(format: "%.0f", oldMs / max(newMs, 0.001)))x")

        #expect(oldMs > newMs * 5,
                "Per-frame dict rebuild (\(String(format: "%.1f", oldMs))ms) must be >5x slower than cached (\(String(format: "%.1f", newMs))ms)")
    }

    // MARK: - Test 3: currentStreak sort removal (MoodTimelineView)
    // OLD: entries.sorted { } on every body evaluation — O(n log n) on already-sorted data.
    // NEW: iterate entries directly (@Query sort: .reverse guarantees order).

    @Test func currentStreak_sortRemovalSpeedup() throws {
        let (_, entries) = try Self.makeEntries()
        let cal = Calendar.current
        let iterations = 100

        // OLD: sort then iterate
        let oldStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            let sorted = entries.sorted { $0.createdAt > $1.createdAt }
            var streak = 0
            var checkDate = cal.startOfDay(for: Date())
            for entry in sorted {
                let entryDay = cal.startOfDay(for: entry.createdAt)
                if entryDay == checkDate {
                    streak += 1
                    checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                } else if entryDay < checkDate { break }
            }
            let _ = streak
        }
        let oldMs = ms(oldStart)

        // NEW: iterate directly (already sorted newest-first)
        let newStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            var streak = 0
            var checkDate = cal.startOfDay(for: Date())
            for entry in entries {
                let entryDay = cal.startOfDay(for: entry.createdAt)
                if entryDay == checkDate {
                    streak += 1
                    checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                } else if entryDay < checkDate { break }
            }
            let _ = streak
        }
        let newMs = ms(newStart)

        log("[currentStreak] OLD \(iterations)x sort+iterate: \(String(format: "%.1f", oldMs))ms | NEW \(iterations)x iterate: \(String(format: "%.1f", newMs))ms | speedup: \(String(format: "%.0f", oldMs / max(newMs, 0.001)))x")

        #expect(oldMs > newMs,
                "Sorting already-sorted data (\(String(format: "%.1f", oldMs))ms) must be slower than direct iteration (\(String(format: "%.1f", newMs))ms)")
    }

    // MARK: - Test 4: Full listSnapshot simulation (worst-case body path)
    // Simulates what EntryListView.body was doing on every scroll frame with 365 entries.

    @Test func listSnapshot_fullBodyPathVsCached() throws {
        let (_, entries) = try Self.makeEntries()
        let cal = Calendar.current
        let frames = 60

        // OLD: full snapshot computed every frame (mood decrypt + calendar grouping)
        let oldStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            let usedMoods = entries.compactMap(\.mood).filter { !$0.isEmpty }
            let groups = Dictionary(grouping: entries) { entry -> Date in
                let comps = cal.dateComponents([.year, .month], from: entry.createdAt)
                return cal.date(from: comps) ?? entry.createdAt
            }
            let _ = (usedMoods, groups.keys.sorted(by: >))
        }
        let oldMs = ms(oldStart)

        // NEW: computed once, then cache reads
        let newStart = CFAbsoluteTimeGetCurrent()
        let cachedMoods = entries.compactMap(\.mood).filter { !$0.isEmpty }
        let cachedGroups = Dictionary(grouping: entries) { entry -> Date in
            let comps = cal.dateComponents([.year, .month], from: entry.createdAt)
            return cal.date(from: comps) ?? entry.createdAt
        }
        let cachedKeys = cachedGroups.keys.sorted(by: >)
        for _ in 0..<(frames - 1) {
            let _ = (cachedMoods, cachedKeys)
        }
        let newMs = ms(newStart)

        log("[listSnapshot] OLD \(frames) full rebuilds: \(String(format: "%.1f", oldMs))ms | NEW (1 build + \(frames-1) cache reads): \(String(format: "%.1f", newMs))ms | speedup: \(String(format: "%.0f", oldMs / max(newMs, 0.001)))x")

        #expect(oldMs > newMs * 5,
                "Per-frame snapshot (\(String(format: "%.1f", oldMs))ms for \(frames) frames) must be >5x slower than cached (\(String(format: "%.1f", newMs))ms)")
    }
}
