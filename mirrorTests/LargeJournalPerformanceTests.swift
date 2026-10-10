import Foundation
import SwiftData
import Testing
@testable import mirror

/// End-to-end timings at large journal sizes (roadmap §1, "End-to-end performance numbers"):
/// decrypting entries into search documents, filtering, Ask's keyword search, archive export
/// (staging the package) and archive open (planning an import of that package). Synthetic text
/// only. Timings are attached to the result; the assertions are generous ceilings, not targets.
@MainActor
@Suite(.disabled(if: ProcessInfo.processInfo.environment["MIRROR_CI_SIMULATOR"] == "1", "Timing ceilings are for local machines; Xcode Cloud's are slower (mirror CI scheme)"))
struct LargeJournalPerformanceTests {
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Entry.self, configurations: config)
        containers.all.append(container)
        return container.mainContext
    }

    private static let moods = ["Content", "Anxious", "Joyful", "Drained", "Hopeful"]

    private func journal(_ count: Int, in context: ModelContext) throws -> [Entry] {
        var entries: [Entry] = []
        for index in 0..<count {
            let body = String(repeating: "A synthetic afternoon by the river, notes about work and sleep. ", count: 8)
                + (index % 5 == 0 ? "Coffee at the library with a friend." : "Tea at home before bed.")
            let entry = Entry(text: body, mood: Self.moods[index % Self.moods.count])
            entry.createdAt = Date(timeIntervalSinceReferenceDate: 700_000_000 + Double(index) * 86_400 / 2)
            entry.tags = index % 3 == 0 ? ["work"] : ["home", "sleep"]
            context.insert(entry)
            entries.append(entry)
        }
        try context.save()
        return entries
    }

    private func ms(_ block: () throws -> Void) rethrows -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        try block()
        return (CFAbsoluteTimeGetCurrent() - start) * 1_000
    }

    @Test func journalOperationsAtLargeSizes() async throws {
        var report: [String] = []
        for count in [500, 2_000, 5_000] {
            let ctx = try context()
            let entries = try journal(count, in: ctx)

            // Decrypt every entry into a search document, as the Entries list snapshot does.
            var documents: [EntrySearchDocument] = []
            let decrypt = ms {
                documents = entries.map { entry in
                    EntrySearchDocument(
                        passages: [.init(entry.text, source: .body)],
                        tags: entry.tags.map(EntrySearch.fold),
                        moods: entry.mood.map { [EntrySearch.fold($0)] } ?? [],
                        createdAt: entry.createdAt, hasPhoto: false, hasAudio: false,
                        isPinned: entry.isPinned, isReadable: true
                    )
                }
            }
            let query = EntrySearchQuery.parse("coffee river -meeting tag:work")
            var matched = 0
            let filter = ms { matched = documents.filter { EntrySearch.matches($0, query: query) }.count }
            #expect(matched > 0)

            var askHits = 0
            let ask = ms { askHits = SearchService.search(query: "When did I have coffee at the library?", in: entries).count }
            #expect(askHits > 0)

            let exportStart = CFAbsoluteTimeGetCurrent()
            let staged = try await ArchiveTransfer.stageArchive(entries: entries, collections: []) { _ in }
            let export = (CFAbsoluteTimeGetCurrent() - exportStart) * 1_000
            defer { try? FileManager.default.removeItem(at: staged.root.deletingLastPathComponent()) }
            #expect(staged.exported == count)

            let openStart = CFAbsoluteTimeGetCurrent()
            let plan = try await ArchiveTransfer.planImport(folder: staged.root, existing: entries)
            let open = (CFAbsoluteTimeGetCurrent() - openStart) * 1_000
            #expect(plan.identical == count)

            let line = String(format: "count=%d decrypt+documents %.0f ms, filter %.1f ms, ask keyword %.0f ms, export (stage) %.0f ms, open (plan import) %.0f ms",
                              count, decrypt, filter, ask, export, open)
            print("LARGE_JOURNAL " + line)
            report.append(line)
            #expect(filter < 2_000 && ask < 10_000 && export < 120_000 && open < 120_000)
        }
        Attachment.record(report.joined(separator: "\n"), named: "large-journal.txt")
    }
}
