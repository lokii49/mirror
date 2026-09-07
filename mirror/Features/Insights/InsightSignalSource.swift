import SwiftUI
import SwiftData

/// The "behind the glass" panel shown while an insight card is held in Sentinel
/// mode (see `PeekReveal`). Press-hold-and-wipe the card and this is what's
/// underneath: the **actual code that generated it** — the verbatim system
/// prompt (read live from `InsightService`, never a paraphrase) and the real
/// entry-selection excerpt, with `file:line` refs. Then a few facts resolved on
/// this device, and the promise: nothing left it.
///
/// One panel, four insight types (`insight.type`) — each shows its own prompt
/// and its own selection code.
struct InsightSignalSource: View {
    let insight: Insight
    let entries: [Entry]

    // MARK: Cache — `resolvedFacts()` filters + sorts the full-history `entries`
    // passed in from the call site (InsightView/AskView/MonthlyReportView's raw
    // `@Query`, no date/range predicate). This view is only mounted as
    // `PeekReveal`'s `back` while the card is held (see PeekReveal's own
    // comment), but for the *whole* press-hold-and-wipe gesture `PeekReveal`
    // appends a new `Smudge` per drag sample, re-evaluating `back`'s body —
    // and with it `resolvedFacts()` — at touch-sample frequency, even though
    // neither `insight` nor `entries` changes during the drag. Same bug shape
    // as the fixes in CalendarHeatmap/MoodTimelineView/WriteView/AskView/
    // InsightView (see PerformanceXCTests.swift), just triggered by a drag
    // instead of a keystroke or toggle.
    @State private var cachedFacts: [String] = []

    private var factsCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(insight.id)
        hasher.combine(insight.generatedAt)
        hasher.combine(insight.type)
        hasher.combine(insight.question)
        hasher.combine(entries.count)
        for entry in entries {
            hasher.combine(entry.encryptedMood)
            hasher.combine(entry.createdAt)
        }
        return hasher.finalize()
    }

    // MARK: Line model — a syntax-lightly-tinted code listing

    private enum Line: Identifiable {
        case comment(String)      // // …            → tertiary
        case rule                 // ────────────────
        case ref(String)          // file · SYMBOL   → ember
        case code(String)         // Swift-ish       → primary
        case prompt(String)       // prompt body     → secondary, wraps
        var id: String {
            switch self {
            case .comment(let s): return "c\(s)"
            case .rule:           return "rule\(UUID())"
            case .ref(let s):     return "r\(s)"
            case .code(let s):    return "k\(s)"
            case .prompt(let s):  return "p\(s)"
            }
        }
    }

    // MARK: Real selection-code excerpts (hand-transcribed; refs are exact)

    private static func selection(for type: InsightType) -> (ref: String, code: [String]) {
        switch type {
        case .dailyNudge:
            return ("InsightService.swift:171 · generateNudge(entries:)", [
                "let cutoff = Calendar.current.date(",
                "    byAdding: .day, value: -14, to: Date())",
                "let recent = withinWindow.isEmpty",
                "    ? Array(sorted.prefix(1))",
                "    : Array(withinWindow.prefix(3))",
                "let background = sorted",
                "    .filter { !recentIDs.contains($0.id) }",
                "    .prefix(20)",
            ])
        case .weeklyDigest:
            return ("InsightService.swift:224 · generateWeeklyDigest", [
                "let thisWeek = weekEntries.sorted {",
                "    $0.createdAt > $1.createdAt }",
                "let priorWeeks = allEntries.filter {",
                "    !weekIDs.contains($0.id) }",
                "recentEntries:     thisWeek.prefix(12)",
                "backgroundEntries: priorWeeks.prefix(14)",
            ])
        case .monthlyReport:
            return ("InsightService.swift:829 · buildMonthlyReportMessage", [
                "// the model reads AGGREGATES, not entry text:",
                "totalWords / avgWords / voiceCount",
                "moodCounts.prefix(5)   moodArc.prefix(12)",
                "weekGroups (entries grouped by week)",
                "+ memory brief over allEntries",
                "    .filter { !monthIDs.contains($0.id) }",
                "    .prefix(20)",
            ])
        case .askResponse:
            return ("InsightService.swift:255 · ask(question:entries:)", [
                "let relevant = SearchService.search(",
                "    query: question, in: sorted, limit: 10)",
                "let background = sorted",
                "    .filter { !relevantIDs.contains($0.id) }",
                "    .prefix(8)",
            ])
        }
    }

    // MARK: Facts resolved at display

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy · HH:mm"
        return f
    }()
    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private func engineLine() -> String {
        switch insight.generatedByEngine {
        case "foundationModels": return "engine    apple foundation models · on-device"
        case "gemma":            return "engine    gemma 3 1B · on-device"
        default:                 return "engine    on-device model"
        }
    }

    /// Re-runs the generator's own selection as of `insight.generatedAt` so the
    /// "read" / "context" lines are honest about which entries fed this one.
    private func resolvedFacts() -> [String] {
        let asOf = insight.generatedAt
        let prior = entries
            .filter { $0.createdAt <= asOf }
            .sorted { $0.createdAt > $1.createdAt }

        func span(_ list: [Entry]) -> String {
            guard let newest = list.first?.createdAt, let oldest = list.last?.createdAt else { return "0 entries" }
            let n = list.count
            let range = Calendar.current.isDate(newest, inSameDayAs: oldest)
                ? Self.dayMonth.string(from: newest)
                : "\(Self.dayMonth.string(from: oldest))–\(Self.dayMonth.string(from: newest))"
            return "\(n) \(n == 1 ? "entry" : "entries") · \(range)"
        }
        func moods(_ list: [Entry]) -> String {
            var seen: [String] = []
            for m in list.compactMap(\.mood) where !seen.contains(m) { seen.append(m) }
            return seen.isEmpty ? "—" : seen.prefix(4).map { MirrorTheme.localizedMoodName(for: $0).lowercased() }.joined(separator: ", ")
        }

        var lines = [engineLine()]
        switch insight.type {
        case .weeklyDigest:
            let wk = DateHelpers.weekIdentifier(for: asOf)
            let thisWeek = Array(prior.filter { DateHelpers.weekIdentifier(for: $0.createdAt) == wk }.prefix(12))
            let earlier = prior.filter { DateHelpers.weekIdentifier(for: $0.createdAt) != wk }.prefix(14).count
            lines.append("read      this week · \(span(thisWeek))")
            if earlier > 0 { lines.append("context   \(earlier) earlier \(earlier == 1 ? "entry" : "entries")") }
            lines.append("mood      \(moods(thisWeek))")
        case .monthlyReport:
            let mo = DateHelpers.monthIdentifier(for: asOf)
            let monthE = Array(prior.filter { DateHelpers.monthIdentifier(for: $0.createdAt) == mo })
            let earlier = prior.filter { DateHelpers.monthIdentifier(for: $0.createdAt) != mo }.prefix(20).count
            lines.append("read      this month · \(span(monthE)) (as aggregates)")
            if earlier > 0 { lines.append("context   \(earlier) earlier \(earlier == 1 ? "entry" : "entries")") }
            lines.append("mood      \(moods(monthE))")
        case .askResponse:
            let q = (insight.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let matched = SearchService.search(query: q, in: prior, limit: 10)
            let scanned = prior.filter { !Set(matched.map(\.id)).contains($0.id) }.prefix(8).count
            lines.append("query     \(q.isEmpty ? "—" : q)")
            lines.append("matched   \(matched.isEmpty ? "no entries" : span(matched))")
            if scanned > 0 { lines.append("context   \(scanned) more scanned") }
        default:
            let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: asOf) ?? asOf
            let within = prior.filter { $0.createdAt >= cutoff }
            let recent = within.isEmpty ? Array(prior.prefix(1)) : Array(within.prefix(3))
            let bg = prior.filter { !Set(recent.map(\.id)).contains($0.id) }.prefix(20).count
            lines.append("read      \(span(recent))")
            if bg > 0 { lines.append("context   \(bg) earlier \(bg == 1 ? "entry" : "entries")") }
            lines.append("mood      \(moods(recent))")
        }
        return lines
    }

    // MARK: Assembled listing

    /// The concise mechanism first — selection code + what it resolved to — so
    /// it lands inside the wipe. The verbatim prompt follows (truncated, with an
    /// exact `file:line` ref to the rest): full, it's 15–25 lines and buries
    /// everything else below the fold.
    private func lines() -> [Line] {
        let prompt = InsightService.systemPrompt(for: insight.type)
        let sel = Self.selection(for: insight.type)
        var out: [Line] = []

        out.append(.ref(sel.ref))
        out.append(.rule)
        for c in sel.code { out.append(.code(c)) }

        out.append(.rule)
        out.append(.comment("// resolved on this device · \(Self.stamp.string(from: insight.generatedAt))"))
        for f in cachedFacts { out.append(.code(f)) }
        out.append(.comment("// no network call · nothing left this device"))

        out.append(.rule)
        out.append(.ref(prompt.ref))
        let promptLines = prompt.body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let shown = 8
        for raw in promptLines.prefix(shown) { out.append(.prompt(raw)) }
        if promptLines.count > shown {
            out.append(.comment("// … \(promptLines.count - shown) more lines — open InsightService.swift to read the rest"))
        }
        return out
    }

    // MARK: Body — a code pane

    var body: some View {
        // No inner ScrollView: while the finger is down driving the wipe, a
        // nested scroll can't get touches (the gesture is on the PeekReveal
        // container). So the listing renders at full height and the card grows
        // to fit it while held — see the Ask call site.
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines()) { line in
                switch line {
                case .rule:
                    Rectangle().fill(MirrorTheme.inkBorder).frame(height: 1)
                        .padding(.vertical, 4)
                case .ref(let s):
                    Text(s)
                        .font(MirrorTheme.mono(10.5, weight: .bold))
                        .foregroundStyle(MirrorTheme.ember)
                        .textSelection(.enabled)
                case .comment(let s):
                    Text(s)
                        .font(MirrorTheme.mono(10, weight: .regular))
                        .foregroundStyle(MirrorTheme.textTertiary)
                case .code(let s):
                    Text(s)
                        .font(MirrorTheme.mono(10.5, weight: .regular))
                        .foregroundStyle(MirrorTheme.textPrimary)
                        .textSelection(.enabled)
                case .prompt(let s):
                    Text(s.isEmpty ? " " : s)
                        .font(MirrorTheme.mono(10.5, weight: .regular))
                        .foregroundStyle(MirrorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        // A flat editor ground — deliberately NOT the front card's colour. The
        // wipe is revealing source, not the same surface with other text.
        .background(Color(red: 0.043, green: 0.043, blue: 0.063))
        .task(id: factsCacheKey) {
            cachedFacts = resolvedFacts()
        }
        .overlay(alignment: .top) {
            Rectangle().fill(MirrorTheme.ember.opacity(0.55)).frame(height: 2)
        }
    }
}

#if DEBUG
private func signalSourcePreview(_ type: InsightType, question: String? = nil) -> some View {
    let container = try! ModelContainer(
        for: Insight.self, Entry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let insight = Insight(
        type: type,
        content: "placeholder",
        periodIdentifier: "2026-09-07",
        question: question,
        generatedByEngine: .gemma
    )
    ctx.insert(insight)
    let entries: [Entry] = [
        ("Long day. Review went fine, couldn't shake it.", "Drained", 20.0),
        ("Walked instead of scrolling. Small win.", "Hopeful", 44.0),
        ("Re-read the same email six times.", "Anxious", 70.0),
    ].map { text, mood, hrs in
        let e = Entry(text: text, mood: mood)
        e.createdAt = .now.addingTimeInterval(-3600 * hrs)
        ctx.insert(e)
        return e
    }
    return ScrollView {
        InsightSignalSource(insight: insight, entries: entries)
            .environment(\.appDisplayMode, .sentinel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(MirrorTheme.ember.opacity(0.5), lineWidth: 1) }
            .padding()
    }
        .background(MirrorTheme.inkBase)
        .modelContainer(container)
}

#Preview("Source — daily")   { signalSourcePreview(.dailyNudge) }
#Preview("Source — ask")     { signalSourcePreview(.askResponse, question: "how have I been sleeping?") }
#Preview("Source — monthly") { signalSourcePreview(.monthlyReport) }
#endif
