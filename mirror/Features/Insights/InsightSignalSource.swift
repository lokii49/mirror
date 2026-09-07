import SwiftUI
import SwiftData

/// Reconstruction helpers for `InsightSignalSource`. A non-generic namespace
/// because `InsightSignalSource` is generic over its background view, and Swift
/// forbids stored `static` properties (the `DateFormatter`s) on generic types.
enum SignalSourceReconstruct {
    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy · HH:mm"
        return f
    }()

    /// "3 entries · 5 Sep – 6 Sep" (or a single day).
    static func spanLabel(_ list: [Entry]) -> String {
        guard let newest = list.first?.createdAt, let oldest = list.last?.createdAt else {
            return "no entries"
        }
        let n = list.count
        let range = Calendar.current.isDate(newest, inSameDayAs: oldest)
            ? dayMonth.string(from: newest)
            : "\(dayMonth.string(from: oldest)) – \(dayMonth.string(from: newest))"
        return "\(n) \(n == 1 ? "entry" : "entries") · \(range)"
    }

    static func moodLabel(_ list: [Entry]) -> String {
        var seen: [String] = []
        for m in list.compactMap(\.mood) where !seen.contains(m) { seen.append(m) }
        return seen.isEmpty
            ? "—"
            : seen.prefix(5).map { MirrorTheme.localizedMoodName(for: $0).uppercased() }.joined(separator: ", ")
    }

    static func readingList(_ list: [Entry]) -> [(day: String, snippet: String)] {
        list.prefix(3).map { (day: dayMonth.string(from: $0.createdAt), snippet: snippet(for: $0)) }
    }

    /// One-line gist of an entry for the READING list — text collapsed to a
    /// single line (inline photo tokens stripped), else the voice transcript,
    /// else a type label. Mirrors `EntryListView.makePreview`'s handling of the
    /// decryption-failure and photo-token cases — this panel's whole claim is
    /// "here is exactly what the model read", so an undecryptable entry has to
    /// say so, not silently render as "Untitled".
    static func snippet(for entry: Entry) -> String {
        if entry.textDecryptionFailed { return "Encrypted entry unavailable" }
        var raw = entry.text.isEmpty ? (entry.voiceNoteTranscript ?? "") : entry.text
        for (range, _) in allPhotoTokens(in: raw).reversed() { raw.removeSubrange(range) }
        let oneLine = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !oneLine.isEmpty { return oneLine }
        if entry.hasVoiceNotes { return "Voice note" }
        if entry.hasPhoto { return "Photo entry" }
        return "Untitled"
    }
}

/// The "behind the glass" panel shown while an insight card is held in Sentinel
/// mode (see `PeekReveal`). It makes mirror's core promise inspectable: this
/// text was written by a model on *this* device, from *these* entries, and
/// nothing was sent anywhere.
///
/// The `Insight` doesn't record which entries fed it, so the "read" / "context"
/// rows are RECONSTRUCTED here by re-running the same selection the matching
/// `InsightService` generator uses, as of the insight's `generatedAt`.
/// Approximate by design — entries added or deleted since can shift it — but
/// honest about the shape. One panel, four reconstructions (daily / weekly /
/// monthly / ask), keyed off `insight.type`.
///
/// `background` must match the front card's own background exactly, so a wipe
/// reveals different text on the same surface rather than a differently-
/// coloured box. Each call site passes its front's fill.
struct InsightSignalSource<Background: View>: View {
    let insight: Insight
    let entries: [Entry]
    @ViewBuilder var background: Background

    // MARK: Reconstructed context

    /// Everything the panel renders, built ONCE per render (`body` computes a
    /// single `let`). `rows` is label/value pairs in display order; `reading` is
    /// the (up to 3) entries the model read closely — empty when the generator
    /// worked from aggregates (monthly) rather than entry text.
    private struct Resolved {
        var rows: [(label: String, value: String)]
        var reading: [(day: String, snippet: String)]
        var note: String?
    }

    private func engineLabel() -> String {
        switch insight.generatedByEngine {
        case "foundationModels": return "APPLE FOUNDATION MODELS · ON-DEVICE"
        case "gemma":            return "GEMMA 3 1B · ON-DEVICE"
        default:                 return "ON-DEVICE MODEL"
        }
    }

    private func resolve() -> Resolved {
        let asOf = insight.generatedAt
        let prior = entries
            .filter { $0.createdAt <= asOf }
            .sorted { $0.createdAt > $1.createdAt }

        var rows: [(label: String, value: String)] = [
            ("ENGINE", engineLabel()),
            ("GENERATED", SignalSourceReconstruct.stamp.string(from: asOf)),
        ]

        switch insight.type {
        case .weeklyDigest:
            // InsightService.generateWeeklyDigest: thisWeek.prefix(12) close,
            // priorWeeks.prefix(14) background.
            let wk = DateHelpers.weekIdentifier(for: asOf)
            let thisWeek = Array(prior.filter { DateHelpers.weekIdentifier(for: $0.createdAt) == wk }.prefix(12))
            let earlier = prior.filter { DateHelpers.weekIdentifier(for: $0.createdAt) != wk }.prefix(14).count
            rows.append(("THIS WEEK", SignalSourceReconstruct.spanLabel(thisWeek)))
            if earlier > 0 { rows.append(("EARLIER", "\(earlier) \(earlier == 1 ? "entry" : "entries") carried in")) }
            rows.append(("MOOD READ", SignalSourceReconstruct.moodLabel(thisWeek)))
            return Resolved(rows: rows, reading: SignalSourceReconstruct.readingList(thisWeek), note: nil)

        case .monthlyReport:
            // InsightService.buildMonthlyReportMessage: the model reads the
            // month as AGGREGATES (word counts, mood arc, week groups) plus a
            // 20-entry memory brief — not entry-by-entry. No READING list.
            let mo = DateHelpers.monthIdentifier(for: asOf)
            let monthE = Array(prior.filter { DateHelpers.monthIdentifier(for: $0.createdAt) == mo })
            let earlier = prior.filter { DateHelpers.monthIdentifier(for: $0.createdAt) != mo }.prefix(20).count
            rows.append(("THIS MONTH", SignalSourceReconstruct.spanLabel(monthE)))
            if earlier > 0 { rows.append(("EARLIER", "\(earlier) \(earlier == 1 ? "entry" : "entries") carried in")) }
            rows.append(("MOOD ARC", SignalSourceReconstruct.moodLabel(monthE)))
            return Resolved(rows: rows, reading: [], note: "Read as monthly aggregates, not entry-by-entry.")

        case .askResponse:
            // InsightService.ask: SearchService.search(question, limit: 10) is
            // the close read; background.prefix(8) is scanned context.
            let q = (insight.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let matched = SearchService.search(query: q, in: prior, limit: 10)
            let matchedIDs = Set(matched.map(\.id))
            let scanned = prior.filter { !matchedIDs.contains($0.id) }.prefix(8).count
            if !q.isEmpty { rows.append(("QUESTION", q)) }
            rows.append(("MATCHED", matched.isEmpty ? "no entries matched" : "\(matched.count) \(matched.count == 1 ? "entry" : "entries")"))
            if scanned > 0 { rows.append(("SCANNED", "\(scanned) more \(scanned == 1 ? "entry" : "entries")")) }
            rows.append(("MOOD READ", SignalSourceReconstruct.moodLabel(matched)))
            return Resolved(rows: rows, reading: SignalSourceReconstruct.readingList(matched), note: nil)

        case .dailyNudge:
            fallthrough
        @unknown default:
            // InsightService.generateNudge: 14-day window → 3 recent close,
            // up to 20 background.
            let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: asOf) ?? asOf
            let within = prior.filter { $0.createdAt >= cutoff }
            let recent = within.isEmpty ? Array(prior.prefix(1)) : Array(within.prefix(3))
            let recentIDs = Set(recent.map(\.id))
            let background = prior.filter { !recentIDs.contains($0.id) }.prefix(20).count
            rows.append(("READ CLOSELY", SignalSourceReconstruct.spanLabel(recent)))
            if background > 0 { rows.append(("CONTEXT", "\(background) earlier \(background == 1 ? "entry" : "entries")")) }
            rows.append(("MOOD READ", SignalSourceReconstruct.moodLabel(recent)))
            return Resolved(rows: rows, reading: SignalSourceReconstruct.readingList(recent), note: nil)
        }
    }

    // MARK: Body

    var body: some View {
        let r = resolve()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .bold))
                Text("SIGNAL SOURCE")
                    .font(MirrorTheme.mono(11, weight: .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(MirrorTheme.ember)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(r.rows.enumerated()), id: \.offset) { _, item in
                    row(item.label, item.value)
                }
            }

            if let note = r.note {
                Text(note)
                    .font(MirrorTheme.mono(9.5, weight: .regular))
                    .foregroundStyle(MirrorTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !r.reading.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("READING")
                        .font(MirrorTheme.mono(10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(MirrorTheme.textSecondary)
                    ForEach(Array(r.reading.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(item.day)
                                .font(MirrorTheme.mono(10, weight: .medium))
                                .foregroundStyle(MirrorTheme.textTertiary)
                                .frame(width: 44, alignment: .leading)
                            Text(item.snippet)
                                .font(MirrorTheme.mono(10.5, weight: .regular))
                                .foregroundStyle(MirrorTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }

            Rectangle()
                .fill(MirrorTheme.ember.opacity(0.3))
                .frame(height: 1)
                .padding(.top, 2)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("NO NETWORK · NEVER LEFT THIS DEVICE")
                    .font(MirrorTheme.mono(10, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundStyle(MirrorTheme.violetLight)
        }
        // Fills the front card's frame exactly (PeekReveal renders this behind
        // the front). The background is passed by the call site so it matches
        // that front's own fill — a wipe reveals different text on the same
        // surface, not a differently-coloured box.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .background { background }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(MirrorTheme.mono(10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(MirrorTheme.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(MirrorTheme.mono(11, weight: .medium))
                .foregroundStyle(MirrorTheme.textPrimary)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The daily reflection card's background (`InsightTextView`): `inkMid` plus the
/// top-right accent radial it carries as an overlay. Reused by the weekly digest
/// and monthly report, whose hero cards are plain `inkMid` — they pass just the
/// colour.
struct SignalSourceInkBackground: View {
    var accentRadial: Bool = false
    var body: some View {
        ZStack {
            MirrorTheme.inkMid
            if accentRadial {
                RadialGradient(
                    colors: [MirrorTheme.primary.opacity(0.16), .clear],
                    center: .init(x: 0.90, y: 0.10),
                    startRadius: 0,
                    endRadius: 200
                )
            }
        }
    }
}

#if DEBUG
#Preview("Signal source") {
    // SwiftData @Model instances need a container — creating them detached throws
    // "invalid reuse after initialization failure" in the canvas.
    let container = try! ModelContainer(
        for: Insight.self, Entry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext

    let insight = Insight(
        type: .dailyNudge,
        content: "You keep circling back to the same unfinished conversation.",
        periodIdentifier: "2026-09-07",
        generatedByEngine: .gemma
    )
    ctx.insert(insight)

    let samples: [(String, String?, Double)] = [
        ("Long day. The review went fine but I couldn't shake it.", "Drained", 20),
        ("Walked instead of scrolling. Small win.", "Hopeful", 44),
        ("Couldn't focus. Kept re-reading the same email.", "Anxious", 70),
        ("Quiet weekend.", nil, 24 * 6),
    ]
    let entries: [Entry] = samples.map { text, mood, hrs in
        let e = Entry(text: text, mood: mood)
        e.createdAt = .now.addingTimeInterval(-3600 * hrs)
        ctx.insert(e)
        return e
    }

    return InsightSignalSource(insight: insight, entries: entries) {
        SignalSourceInkBackground(accentRadial: true)
    }
        .environment(\.appDisplayMode, .sentinel)
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(MirrorTheme.ember.opacity(0.55), lineWidth: 1) }
        .padding()
        .background(MirrorTheme.inkBase)
        .modelContainer(container)
}
#endif
