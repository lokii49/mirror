import SwiftUI

/// The "behind the glass" panel for the daily reflection card, shown while the
/// card is held in Sentinel mode (see `PeekReveal`). It makes mirror's core
/// promise inspectable: this reflection was written by a model on *this* device,
/// from *these* entries, and nothing was sent anywhere.
///
/// The `Insight` doesn't record which entries fed it, so "read closely" /
/// "context" are RECONSTRUCTED here by re-running the same selection
/// `InsightService.generateNudge` uses (14-day window → 3 recent + up to 20
/// background), as of the reflection's `generatedAt`. Approximate by design —
/// entries added or deleted since can shift it — but honest about the shape.
struct ReflectionSignalSource: View {
    let insight: Insight
    let entries: [Entry]

    // MARK: Reconstructed context

    /// Everything the panel needs, built ONCE per render (`body` computes a single
    /// `let`). The entry array is the full-history `@Query` from `InsightView` —
    /// filter/sort it once, not once per row.
    private struct Resolved {
        let engine: String
        let generated: String
        let readClosely: String
        let backgroundCount: Int
        let moods: String
        /// The (up to 3) entries the reflection read closely — day + one-line
        /// snippet. Same text the user sees in the entry list; it's their own
        /// journal on their own device, shown only on a deliberate press-hold.
        let reading: [(day: String, snippet: String)]
    }

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy · HH:mm"
        return f
    }()

    private func resolve() -> Resolved {
        let asOf = insight.generatedAt

        // Re-runs InsightService.generateNudge's selection as of `asOf`.
        let prior = entries
            .filter { $0.createdAt <= asOf }
            .sorted { $0.createdAt > $1.createdAt }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: asOf) ?? asOf
        let within = prior.filter { $0.createdAt >= cutoff }
        let recent = within.isEmpty ? Array(prior.prefix(1)) : Array(within.prefix(3))
        let recentIDs = Set(recent.map(\.id))
        let backgroundCount = prior.filter { !recentIDs.contains($0.id) }.prefix(20).count

        let engine: String
        switch insight.generatedByEngine {
        case "foundationModels": engine = "APPLE FOUNDATION MODELS · ON-DEVICE"
        case "gemma":            engine = "GEMMA 3 1B · ON-DEVICE"
        default:                 engine = "ON-DEVICE MODEL"
        }

        let readClosely: String
        if let newest = recent.first?.createdAt, let oldest = recent.last?.createdAt {
            let n = recent.count
            let range = Calendar.current.isDate(newest, inSameDayAs: oldest)
                ? Self.dayMonth.string(from: newest)
                : "\(Self.dayMonth.string(from: oldest)) – \(Self.dayMonth.string(from: newest))"
            readClosely = "\(n) \(n == 1 ? "entry" : "entries") · \(range)"
        } else {
            readClosely = "no earlier entries"
        }

        var seenMoods: [String] = []
        for m in recent.compactMap(\.mood) where !seenMoods.contains(m) { seenMoods.append(m) }
        let moods = seenMoods.isEmpty
            ? "—"
            : seenMoods.map { MirrorTheme.localizedMoodName(for: $0).uppercased() }.joined(separator: ", ")

        let reading = recent.prefix(3).map {
            (day: Self.dayMonth.string(from: $0.createdAt), snippet: Self.snippet(for: $0))
        }

        return Resolved(
            engine: engine,
            generated: Self.stamp.string(from: asOf),
            readClosely: readClosely,
            backgroundCount: backgroundCount,
            moods: moods,
            reading: Array(reading)
        )
    }

    /// One-line gist of an entry for the READING list — text collapsed to a
    /// single line, else the voice transcript, else a type label.
    private static func snippet(for entry: Entry) -> String {
        let raw = entry.text.isEmpty ? (entry.voiceNoteTranscript ?? "") : entry.text
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
                row("ENGINE", r.engine)
                row("GENERATED", r.generated)
                row("READ CLOSELY", r.readClosely)
                if r.backgroundCount > 0 {
                    row("CONTEXT", "\(r.backgroundCount) earlier \(r.backgroundCount == 1 ? "entry" : "entries")")
                }
                row("MOOD READ", r.moods)
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
        // Fills the front card's frame exactly (PeekReveal renders this as an
        // overlay of the front), so the X-ray panel never balloons past the card
        // it replaces. Content sits at the top; the grid fills whatever's left.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .background {
            MirrorTheme.inkMid
            SentinelGridBackground().opacity(0.7)
        }
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("Signal source") {
    let insight = Insight(
        type: .dailyNudge,
        content: "You keep circling back to the same unfinished conversation.",
        periodIdentifier: "2026-09-07",
        generatedByEngine: .gemma
    )
    let entries: [Entry] = [
        { let e = Entry(text: "Long day. The review went fine but I couldn't shake it.", mood: "Drained"); e.createdAt = .now.addingTimeInterval(-3600 * 20); return e }(),
        { let e = Entry(text: "Walked instead of scrolling. Small win.", mood: "Hopeful"); e.createdAt = .now.addingTimeInterval(-3600 * 44); return e }(),
        { let e = Entry(text: "Couldn't focus. Kept re-reading the same email.", mood: "Anxious"); e.createdAt = .now.addingTimeInterval(-3600 * 70); return e }(),
        { let e = Entry(text: "Quiet weekend.", mood: nil); e.createdAt = .now.addingTimeInterval(-3600 * 24 * 6); return e }(),
    ]
    return ReflectionSignalSource(insight: insight, entries: entries)
        .environment(\.appDisplayMode, .sentinel)
        .frame(height: 300)  // stands in for the front reflection card's height
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(MirrorTheme.ember.opacity(0.55), lineWidth: 1) }
        .padding()
        .background(MirrorTheme.inkBase)
}
#endif
