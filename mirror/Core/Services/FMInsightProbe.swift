#if DEBUG
import Foundation

/// DEBUG-only: `--fmInsightProbe` (with `--perfSeed=N`, so the app runs on the synthetic scratch store with the
/// fixed debug key, never the real journal or CloudKit) runs the weekly digest, the monthly report and Ask on
/// Foundation Models inside the real app, on synthetic entries held in memory, prints each result and quits.
/// Nothing is saved: no Insight rows, no notifications. For checking the FM insight paths on a Mac with Apple
/// Intelligence, where the Sunday / last-week gates would otherwise hide them (tools/llmrig/fm/RUBRIC_FM.md).
/// Synthetic text only, so printing the output is fine here (never do this with real entries).
enum FMInsightProbe {
    static var isRequested: Bool { CommandLine.arguments.contains("--fmInsightProbe") }

    private static func entries(_ items: [(String, String)], spacingDays: Double) -> [Entry] {
        items.enumerated().map { i, item in
            let e = Entry(text: item.0, mood: item.1)
            e.createdAt = Date().addingTimeInterval(-Double(i) * spacingDays * 86_400)
            return e
        }
    }

    private static let week: [(String, String)] = [
        ("Mom's knee surgery is booked for the 14th. Tara says she can take the first week but I'll need to cover the second.", "Anxious"),
        ("Long day at work, the audit team wants every invoice from March. Came home and Miso was asleep on my laptop bag, which made me laugh.", "Drained"),
        ("Called Mom tonight. She sounded calmer than me about the whole thing. We talked about her garden for almost an hour.", "Peaceful"),
        ("Asked my manager, Deepa, if I can work from Mom's place for a week. She said she'll think about it.", "Hopeful"),
        ("Skipped the gym again. Ate cereal for dinner. I keep making lists and not doing anything on them.", "Overwhelmed"),
    ]
    private static let germanWeek: [(String, String)] = [
        ("Ich habe die ganze Nacht nicht geschlafen, weil der Bericht morgen fällig ist.", "Anxious"),
        ("Lena hat mir nach der Arbeit Suppe gebracht und wir haben lange geredet.", "Grateful"),
        ("Der Bericht ist immer noch nicht fertig und Jonas will ihn am Montag sehen.", "Overwhelmed"),
        ("Heute bin ich zum ersten Mal seit Wochen wieder gelaufen.", "Energized"),
    ]
    private static let monthExtra: [(String, String)] = [
        ("Second pottery class tonight. My bowl actually came out round this time.", "Joyful"),
        ("Couldn't sleep again, up until 3 scrolling. Everything feels heavy and slow.", "Drained"),
        ("Missed the grant deadline by one day. Dr. Okafor was kind about it but I felt so stupid.", "Sad"),
        ("Ran 5k without stopping for the first time since spring.", "Energized"),
        ("Quiet Sunday. Glazed two mugs and read on the balcony.", "Content"),
        ("Jun left his dishes in the sink again and I finally said something.", "Frustrated"),
    ]

    @MainActor
    static func run() async {
        try? await Task.sleep(for: .seconds(3))
        print("[FMInsightProbe] Foundation Models preferred: \(LocalLLMService.prefersFoundationModels)")
        let weekEntries = entries(week, spacingDays: 0.05)
        await report("weekly (en)") { try await InsightService.generateWeeklyDigest(weekEntries: weekEntries, allEntries: weekEntries) }
        let german = entries(germanWeek, spacingDays: 0.05)
        await report("weekly (de)") { try await InsightService.generateWeeklyDigest(weekEntries: german, allEntries: german) }
        let month = entries(week + monthExtra, spacingDays: 0.9)
        await report("monthly (en)") { try await InsightService.generateMonthlyReport(monthEntries: month, allEntries: month) }
        for question in ["How is my mom doing?", "Have I been sleeping well?", "Did I go on any trips?"] {
            await report("ask: \(question)") { try await InsightService.ask(question: question, entries: month) }
        }
        print("[FMInsightProbe] done")
        exit(0)
    }

    @MainActor
    private static func report(_ label: String, _ run: () async throws -> (text: String, engine: LLMEngine)) async {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let result = try await run()
            print("[FMInsightProbe] == \(label) | engine=\(result.engine.rawValue) | \(clock.now - start)\n\(result.text)")
        } catch {
            print("[FMInsightProbe] == \(label) | error: \(error)")
        }
    }
}
#endif
