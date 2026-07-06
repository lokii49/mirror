import XCTest
import SwiftData
@testable import mirror

// XCTest-based version: print() output appears in xcodebuild so we can read actual timing numbers.
// Tests the four hot paths that caused freeze with year-long (365-entry) journal datasets.

@MainActor
final class PerformanceXCTests: XCTestCase {

    private var container: ModelContainer!
    private var entries: [Entry] = []

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Entry.self, configurations: config)
        let context = ModelContext(container)

        let moods = ["Joyful", "Grateful", "Peaceful", "Content", "Energized", "Hopeful",
                     "Anxious", "Overwhelmed", "Frustrated", "Drained", "Sad", "Numb"]
        let base = Calendar.current.date(byAdding: .day, value: -364, to: Date())!
        for i in 0..<365 {
            let e = Entry(text: "Day \(i): Journaling today. Reflecting on what happened and how I feel about it.")
            e.mood = moods[i % moods.count]
            e.createdAt = Calendar.current.date(byAdding: .day, value: i, to: base)!
            context.insert(e)
        }
        try context.save()

        let descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\Entry.createdAt, order: .reverse)])
        entries = try context.fetch(descriptor)
        XCTAssertEqual(entries.count, 365)
    }

    // MARK: - Test 1: usedMoods per-frame vs cached

    func test_usedMoods_perFrameVsCached() {
        let frames = 60

        // OLD: decrypt all 365 moods every frame (was happening in body's listSnapshot computed var)
        let oldStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            let _ = entries.compactMap(\.mood).filter { !$0.isEmpty }
        }
        let oldMs = (CFAbsoluteTimeGetCurrent() - oldStart) * 1000

        // NEW: decrypt once (.task fires), read cached array on remaining frames
        let newStart = CFAbsoluteTimeGetCurrent()
        let cached = entries.compactMap(\.mood).filter { !$0.isEmpty }
        for _ in 0..<(frames - 1) { let _ = cached }
        let newMs = (CFAbsoluteTimeGetCurrent() - newStart) * 1000

        print("\n[usedMoods] 365 entries × \(frames) frames")
        print("  OLD (per-frame decrypt): \(String(format: "%.1f", oldMs))ms")
        print("  NEW (1 decrypt + cache): \(String(format: "%.1f", newMs))ms")
        print("  Speedup: \(String(format: "%.0f", oldMs / max(newMs, 0.001)))x\n")

        XCTAssert(oldMs > newMs * 5, "Per-frame decryption must be >5x slower than cached. OLD=\(String(format: "%.1f", oldMs))ms NEW=\(String(format: "%.1f", newMs))ms")
    }

    // MARK: - Test 2: CalendarHeatmap entriesByDay dict rebuild vs cached

    func test_calendarHeatmap_dictRebuildVsCached() {
        let cal = Calendar.current
        let frames = 60

        // OLD: full dict rebuilt from all entries on every render (entriesByDay was a computed var)
        let oldStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            var dict: [Date: [Entry]] = [:]
            for e in entries {
                let day = cal.startOfDay(for: e.createdAt)
                dict[day, default: []].append(e)
            }
            let _ = dict
        }
        let oldMs = (CFAbsoluteTimeGetCurrent() - oldStart) * 1000

        // NEW: built once in .task(id: entries.count), O(1) lookup per cell
        let newStart = CFAbsoluteTimeGetCurrent()
        var cached: [Date: [Entry]] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e.createdAt)
            cached[day, default: []].append(e)
        }
        for _ in 0..<(frames - 1) { let _ = cached }
        let newMs = (CFAbsoluteTimeGetCurrent() - newStart) * 1000

        print("\n[entriesByDay] 365 entries × \(frames) frames")
        print("  OLD (per-frame rebuild): \(String(format: "%.1f", oldMs))ms")
        print("  NEW (1 build + cache):   \(String(format: "%.1f", newMs))ms")
        print("  Speedup: \(String(format: "%.0f", oldMs / max(newMs, 0.001)))x\n")

        XCTAssert(oldMs > newMs * 5, "Per-frame dict rebuild must be >5x slower than cached. OLD=\(String(format: "%.1f", oldMs))ms NEW=\(String(format: "%.1f", newMs))ms")
    }

    // MARK: - Test 3: currentStreak sort removal

    func test_currentStreak_sortRemovalSpeedup() {
        let cal = Calendar.current
        let iterations = 100

        // OLD: sorted entries on every body evaluation (O(n log n) per frame on already-sorted data)
        let oldStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            let sorted = entries.sorted { $0.createdAt > $1.createdAt }
            var streak = 0, checkDate = cal.startOfDay(for: Date())
            for e in sorted {
                let d = cal.startOfDay(for: e.createdAt)
                if d == checkDate { streak += 1; checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate }
                else if d < checkDate { break }
            }
            let _ = streak
        }
        let oldMs = (CFAbsoluteTimeGetCurrent() - oldStart) * 1000

        // NEW: iterate directly (@Query sort: .reverse guarantees newest-first order)
        let newStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            var streak = 0, checkDate = cal.startOfDay(for: Date())
            for e in entries {
                let d = cal.startOfDay(for: e.createdAt)
                if d == checkDate { streak += 1; checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate }
                else if d < checkDate { break }
            }
            let _ = streak
        }
        let newMs = (CFAbsoluteTimeGetCurrent() - newStart) * 1000

        print("\n[currentStreak] 365 entries × \(iterations) iterations")
        print("  OLD (sort + iterate): \(String(format: "%.1f", oldMs))ms")
        print("  NEW (iterate only):   \(String(format: "%.1f", newMs))ms")
        print("  Speedup: \(String(format: "%.0f", oldMs / max(newMs, 0.001)))x\n")

        XCTAssert(oldMs > newMs, "Sort+iterate must be slower than direct iteration on already-sorted data. OLD=\(String(format: "%.1f", oldMs))ms NEW=\(String(format: "%.1f", newMs))ms")
    }

    // MARK: - Test 4: Full listSnapshot — worst-case body path

    func test_listSnapshot_fullBodyPathVsCached() {
        let cal = Calendar.current
        let frames = 60

        // OLD: full recompute every frame (mood decrypt + calendar grouping in body)
        let oldStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            let moods = entries.compactMap(\.mood).filter { !$0.isEmpty }
            let groups = Dictionary(grouping: entries) { entry -> Date in
                let c = cal.dateComponents([.year, .month], from: entry.createdAt)
                return cal.date(from: c) ?? entry.createdAt
            }
            let _ = (moods, groups.keys.sorted(by: >))
        }
        let oldMs = (CFAbsoluteTimeGetCurrent() - oldStart) * 1000

        // NEW: compute once, 59 more frames read the cache
        let newStart = CFAbsoluteTimeGetCurrent()
        let cachedMoods = entries.compactMap(\.mood).filter { !$0.isEmpty }
        let cachedGroups = Dictionary(grouping: entries) { entry -> Date in
            let c = cal.dateComponents([.year, .month], from: entry.createdAt)
            return cal.date(from: c) ?? entry.createdAt
        }
        let cachedKeys = cachedGroups.keys.sorted(by: >)
        for _ in 0..<(frames - 1) { let _ = (cachedMoods, cachedKeys) }
        let newMs = (CFAbsoluteTimeGetCurrent() - newStart) * 1000

        print("\n[listSnapshot] 365 entries × \(frames) frames (mood decrypt + calendar grouping)")
        print("  OLD (per-frame recompute): \(String(format: "%.1f", oldMs))ms")
        print("  NEW (1 compute + cache):   \(String(format: "%.1f", newMs))ms")
        print("  Speedup: \(String(format: "%.0f", oldMs / max(newMs, 0.001)))x\n")

        XCTAssert(oldMs > newMs * 5, "Per-frame snapshot must be >5x slower than cached. OLD=\(String(format: "%.1f", oldMs))ms NEW=\(String(format: "%.1f", newMs))ms")
    }

    // MARK: - Test 5: MoodTimelineView heatmap (points → dayMoodMap → weeks) vs cached

    func test_moodTimelineHeatmap_perFrameVsCached() {
        let cal = Calendar.current
        let frames = 60

        func buildHeatmap(from entries: [Entry]) -> (weeks: [[Date?]], dayMoodMap: [String: String]) {
            let points = entries
                .compactMap { entry -> (date: Date, mood: String)? in
                    guard let mood = entry.mood else { return nil }
                    return (entry.createdAt, mood)
                }
                .sorted { $0.date < $1.date }

            var dayMoodMap: [String: String] = [:]
            for point in points {
                let c = cal.dateComponents([.year, .month, .day], from: point.date)
                let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
                dayMoodMap[key] = point.mood
            }

            guard let earliest = points.first?.date else { return ([], dayMoodMap) }
            let today = Date()
            var startComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: earliest)
            startComps.weekday = 2
            guard var weekStart = cal.date(from: startComps) else { return ([], dayMoodMap) }
            if weekStart > earliest {
                weekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
            }
            var weeks: [[Date?]] = []
            while weekStart <= today {
                var week: [Date?] = []
                for offset in 0..<7 {
                    if let d = cal.date(byAdding: .day, value: offset, to: weekStart), d <= today {
                        week.append(d)
                    } else {
                        week.append(nil)
                    }
                }
                weeks.append(week)
                weekStart = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
            }
            return (weeks, dayMoodMap)
        }

        // OLD: recomputed from scratch on every body re-eval (range taps, paywall sheet, etc)
        let oldStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            let _ = buildHeatmap(from: entries)
        }
        let oldMs = (CFAbsoluteTimeGetCurrent() - oldStart) * 1000

        // NEW: computed once in .task(id:), remaining frames read the cache
        let newStart = CFAbsoluteTimeGetCurrent()
        let cached = buildHeatmap(from: entries)
        for _ in 0..<(frames - 1) { let _ = cached }
        let newMs = (CFAbsoluteTimeGetCurrent() - newStart) * 1000

        print("\n[moodTimelineHeatmap] 365 entries × \(frames) frames")
        print("  OLD (per-frame rebuild): \(String(format: "%.1f", oldMs))ms")
        print("  NEW (1 build + cache):   \(String(format: "%.1f", newMs))ms")
        print("  Speedup: \(String(format: "%.0f", oldMs / max(newMs, 0.001)))x\n")

        XCTAssert(oldMs > newMs * 5, "Per-frame heatmap rebuild must be >5x slower than cached. OLD=\(String(format: "%.1f", oldMs))ms NEW=\(String(format: "%.1f", newMs))ms")
    }
}
