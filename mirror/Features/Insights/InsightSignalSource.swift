import SwiftUI
import SwiftData

/// "How this was generated" — opened from `InsightSourceButton` on an insight
/// card in Sentinel mode. Makes mirror's core promise inspectable: this text
/// came from a model on *this* device, from *these* entries, and nothing was
/// sent anywhere.
///
/// A `NavigationStack` sheet: the provenance HUD, then a link to the verbatim
/// system prompt. `entries` comes from a fresh `@Query` so no call site has to
/// thread it through.
struct InsightSourceSheet: View {
    let insight: Insight
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                InsightSignalSource(insight: insight, entries: entries)
                    .padding(20)
            }
            .background(MirrorTheme.inkBase)
            .navigationTitle("How this was generated")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: InsightType.self) { SystemPromptDetail(type: $0, content: insight.content) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The provenance HUD. Engine, what it read, mood, "never left this device",
/// and a link to the system prompt. The read/context rows are RECONSTRUCTED by
/// re-running the matching generator's selection as of `insight.generatedAt`
/// (approximate — entries added or deleted since shift it, but the shape is
/// honest).
struct InsightSignalSource: View {
    let insight: Insight
    let entries: [Entry]

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy · HH:mm"; return f
    }()
    private static let dayMonth: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    struct Resolved {
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

    private static func span(_ list: [Entry]) -> String {
        guard let newest = list.first?.createdAt, let oldest = list.last?.createdAt else { return "no entries" }
        let n = list.count
        let range = Calendar.current.isDate(newest, inSameDayAs: oldest)
            ? dayMonth.string(from: newest)
            : "\(dayMonth.string(from: oldest)) – \(dayMonth.string(from: newest))"
        return "\(n) \(n == 1 ? "entry" : "entries") · \(range)"
    }

    private static func moods(_ list: [Entry]) -> String {
        var seen: [String] = []
        for m in list.compactMap(\.mood) where !seen.contains(m) { seen.append(m) }
        return seen.isEmpty ? "—" : seen.prefix(4).map { MirrorTheme.localizedMoodName(for: $0).uppercased() }.joined(separator: ", ")
    }

    private static func snippet(for entry: Entry) -> String {
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

    private static func readingList(_ list: [Entry]) -> [(day: String, snippet: String)] {
        list.prefix(3).map { (day: dayMonth.string(from: $0.createdAt), snippet: snippet(for: $0)) }
    }

    private func resolve() -> Resolved {
        Self.resolve(insight: insight, entries: entries, engineLabel: engineLabel())
    }

    /// On the grammar-constrained Gemma paths (3.0.5+) the model gets much less than the
    /// free-prose prompt: the nudge only the newest day's entries, the digest only this week's,
    /// the monthly report only this month's, with no earlier entries or summary at all. Those
    /// insights are recognized by their shape (`isGrammarGrounded`), the same test the saved-
    /// insight repair passes use; Foundation Models output never takes that path.
    static func resolve(insight: Insight, entries: [Entry], engineLabel: String) -> Resolved {
        let asOf = insight.generatedAt
        // Readability (hasReadableContext, which the generators filter on) decrypts, so it's
        // checked lazily on each case's slice, never across the whole history per render.
        let prior = entries.filter { $0.createdAt <= asOf }.sorted { $0.createdAt > $1.createdAt }
        let readable = InsightService.hasReadableContext
        let grammarPath = InsightService.isGrammarGrounded(insight.content)
            && insight.generatedByEngine != LLMEngine.foundationModels.rawValue
        let quotedNote = "Every quote is copied word for word from these entries. Long entries are shortened to fit."
        var rows: [(String, String)] = [
            ("ENGINE", engineLabel),
            ("GENERATED", Self.stamp.string(from: asOf)),
        ]

        switch insight.type {
        case .weeklyDigest:
            let wk = DateHelpers.digestWeekIdentifier(for: asOf)
            let thisWeek = Array(prior.lazy.filter { DateHelpers.digestWeekIdentifier(for: $0.createdAt) == wk }.filter(readable).prefix(12))
            let earlier = prior.lazy.filter { DateHelpers.digestWeekIdentifier(for: $0.createdAt) != wk }.filter(readable).prefix(14).count
            rows.append(("THIS WEEK", Self.span(thisWeek)))
            if grammarPath {
                rows.append(("EARLIER", "none sent"))
            } else if earlier > 0 {
                rows.append(("EARLIER", "\(earlier) \(earlier == 1 ? "entry" : "entries") carried in"))
            }
            rows.append(("MOOD READ", Self.moods(thisWeek)))
            return Resolved(rows: rows, reading: Self.readingList(thisWeek), note: grammarPath ? quotedNote : nil)

        case .monthlyReport:
            let mo = DateHelpers.monthIdentifier(for: asOf)
            let monthE = prior.filter { DateHelpers.monthIdentifier(for: $0.createdAt) == mo }.filter(readable)
            let earlier = prior.lazy.filter { DateHelpers.monthIdentifier(for: $0.createdAt) != mo }.filter(readable).prefix(20).count
            rows.append(("THIS MONTH", Self.span(monthE)))
            if grammarPath {
                rows.append(("EARLIER", "none sent"))
            } else if earlier > 0 {
                rows.append(("EARLIER", "\(earlier) \(earlier == 1 ? "entry" : "entries") carried in"))
            }
            rows.append(("MOOD ARC", Self.moods(monthE)))
            return Resolved(rows: rows, reading: [], note: grammarPath ? quotedNote : "Read as monthly aggregates, not entry-by-entry.")

        case .askResponse:
            let q = (insight.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let pool = prior.filter(readable)   // Ask searches every readable entry, as ask() does
            let matched = SearchService.search(query: q, in: pool, limit: 10)
            let scanned = pool.filter { !Set(matched.map(\.id)).contains($0.id) }.prefix(8).count
            if !q.isEmpty { rows.append(("QUESTION", q)) }
            rows.append(("MATCHED", matched.isEmpty ? "no entries matched" : "\(matched.count) \(matched.count == 1 ? "entry" : "entries")"))
            if scanned > 0 { rows.append(("SCANNED", "\(scanned) more \(scanned == 1 ? "entry" : "entries")")) }
            rows.append(("MOOD READ", Self.moods(matched)))
            return Resolved(rows: rows, reading: Self.readingList(matched), note: nil)

        case .dailyNudge:
            // dailyNudgeContext keeps at most 3 recent + 20 background, all from the newest
            // readable entries, so the newest 23 give the same answer.
            let (recent, backgroundEntries) = InsightService.dailyNudgeContext(from: Array(prior.lazy.filter(readable).prefix(23)), asOf: asOf)
            if grammarPath {
                // groundedNudgePlan / localizedGroundedNudge: the newest entry and any others
                // from the same day, nothing else.
                let source = InsightService.groundedNudgeSourceEntries(recent)
                rows.append(("READ CLOSELY", Self.span(source)))
                rows.append(("CONTEXT", "none sent"))
                rows.append(("MOOD READ", Self.moods(source)))
                // The linked instructions say "Do not give advice"; a closing tip is the app's.
                let endsWithFixedTip = InsightService.groundedNudgeTips.values.joined().contains { insight.content.hasSuffix($0) }
                let note = endsWithFixedTip
                    ? quotedNote + " The last sentence is fixed text MirrorNotes adds on difficult days; the model didn't write it."
                    : quotedNote
                return Resolved(rows: rows, reading: Self.readingList(source), note: note)
            }
            let background = backgroundEntries.count
            rows.append(("READ CLOSELY", Self.span(recent)))
            if background > 0 {
                // Honest about what actually reaches the model: `background` entries
                // are never sent in full — only a handful of short excerpts plus
                // aggregate stats (see InsightService.buildMemoryBrief). Reporting just
                // "N earlier entries" read as "N entries fully read," which is what
                // prompted the question this label now answers directly.
                let quoted = min(background, InsightService.memoryBriefExcerptLimit)
                rows.append(("CONTEXT", "\(background) earlier \(background == 1 ? "entry" : "entries") summarized · \(quoted) quoted"))
            }
            rows.append(("MOOD READ", Self.moods(recent)))
            return Resolved(rows: rows, reading: Self.readingList(recent), note: nil)
        }
    }

    var body: some View {
        let r = resolve()
        let symbol = InsightService.systemPrompt(for: insight.type, content: insight.content).ref
            .split(separator: "·").last.map { $0.trimmingCharacters(in: .whitespaces) }
            ?? "system prompt"

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 11, weight: .bold))
                Text("SIGNAL SOURCE").font(MirrorTheme.mono(11, weight: .bold)).tracking(1.4)
            }
            .foregroundStyle(MirrorTheme.ember)

            VStack(alignment: .leading, spacing: 8) {
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
                VStack(alignment: .leading, spacing: 5) {
                    Text("READING")
                        .font(MirrorTheme.mono(10, weight: .bold)).tracking(0.6)
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
                                .lineLimit(2).truncationMode(.tail)
                        }
                    }
                }
            }

            Rectangle().fill(MirrorTheme.ember.opacity(0.3)).frame(height: 1)

            NavigationLink(value: insight.type) {
                HStack(spacing: 6) {
                    Image(systemName: "curlybraces").font(.system(size: 10, weight: .bold))
                    Text("SYSTEM PROMPT · \(symbol)")
                        .font(MirrorTheme.mono(10, weight: .bold)).tracking(0.4)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(MirrorTheme.ember)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                Text("NO NETWORK · NEVER LEFT THIS DEVICE")
                    .font(MirrorTheme.mono(10, weight: .bold)).tracking(0.8)
            }
            .foregroundStyle(MirrorTheme.violetLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(red: 0.043, green: 0.043, blue: 0.063),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MirrorTheme.ember.opacity(0.3), lineWidth: 1)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(MirrorTheme.mono(10, weight: .bold)).tracking(0.6)
                .foregroundStyle(MirrorTheme.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(MirrorTheme.mono(11, weight: .medium))
                .foregroundStyle(MirrorTheme.textPrimary)
                .lineLimit(3).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The verbatim system prompt — read live from `InsightService.systemPrompt(for:)`,
/// the same constant the generator sends. Pushed from `InsightSourceSheet`.
struct SystemPromptDetail: View {
    let type: InsightType
    var content: String? = nil

    var body: some View {
        let p = InsightService.systemPrompt(for: type, content: content)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(p.ref)
                    .font(MirrorTheme.mono(11, weight: .bold))
                    .foregroundStyle(MirrorTheme.ember)
                    .textSelection(.enabled)
                Text("The exact instruction sent to the on-device model. It doesn't change per entry — the same text every time an insight of this kind is generated.")
                    .font(.system(size: 13))
                    .foregroundStyle(MirrorTheme.textSecondary)
                Text(p.body)
                    .font(MirrorTheme.mono(12, weight: .regular))
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(red: 0.043, green: 0.043, blue: 0.063),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MirrorTheme.ember.opacity(0.25), lineWidth: 1)
                    }
            }
            .padding(20)
        }
        .background(MirrorTheme.inkBase)
        .navigationTitle("System prompt")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
private func sheetPreview(_ type: InsightType, question: String? = nil) -> some View {
    let container = try! ModelContainer(
        for: Insight.self, Entry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let insight = Insight(
        type: type, content: "placeholder",
        periodIdentifier: "2026-09-07", question: question, generatedByEngine: .gemma
    )
    ctx.insert(insight)
    for (text, mood, hrs) in [
        ("Long day. Review went fine, couldn't shake it.", "Drained", 20.0),
        ("Walked instead of scrolling. Small win.", "Hopeful", 44.0),
        ("Re-read the same email six times.", "Anxious", 70.0),
    ] {
        let e = Entry(text: text, mood: mood)
        e.createdAt = .now.addingTimeInterval(-3600 * hrs)
        ctx.insert(e)
    }
    return InsightSourceSheet(insight: insight)
        .environment(\.appDisplayMode, .sentinel)
        .modelContainer(container)
}

#Preview("Source — daily")   { sheetPreview(.dailyNudge) }
#Preview("Source — ask")     { sheetPreview(.askResponse, question: "how have I been sleeping?") }
#Preview("Source — monthly") { sheetPreview(.monthlyReport) }
#endif
