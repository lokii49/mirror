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

    private var reconstruction: (recent: [Entry], backgroundCount: Int) {
        let asOf = insight.generatedAt
        let prior = entries
            .filter { $0.createdAt <= asOf }
            .sorted { $0.createdAt > $1.createdAt }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: asOf) ?? asOf
        let within = prior.filter { $0.createdAt >= cutoff }
        let recent = within.isEmpty ? Array(prior.prefix(1)) : Array(within.prefix(3))
        let recentIDs = Set(recent.map(\.id))
        let background = prior.filter { !recentIDs.contains($0.id) }.prefix(20)
        return (recent, background.count)
    }

    private var engineLabel: String {
        switch insight.generatedByEngine {
        case "foundationModels": return "APPLE FOUNDATION MODELS · ON-DEVICE"
        case "gemma":            return "GEMMA 3 1B · ON-DEVICE"
        default:                 return "ON-DEVICE MODEL"
        }
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

    private var readCloselyValue: String {
        let recent = reconstruction.recent
        guard let newest = recent.first?.createdAt, let oldest = recent.last?.createdAt else {
            return "no earlier entries"
        }
        let n = recent.count
        let range = Calendar.current.isDate(newest, inSameDayAs: oldest)
            ? Self.dayMonth.string(from: newest)
            : "\(Self.dayMonth.string(from: oldest)) – \(Self.dayMonth.string(from: newest))"
        return "\(n) \(n == 1 ? "entry" : "entries") · \(range)"
    }

    private var moodValue: String {
        let moods = reconstruction.recent
            .compactMap(\.mood)
            .reduce(into: [String]()) { acc, m in if !acc.contains(m) { acc.append(m) } }
            .map { MirrorTheme.localizedMoodName(for: $0).uppercased() }
        return moods.isEmpty ? "—" : moods.joined(separator: ", ")
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .bold))
                Text("SIGNAL SOURCE")
                    .font(MirrorTheme.mono(11, weight: .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(MirrorTheme.ember)

            VStack(alignment: .leading, spacing: 9) {
                row("ENGINE", engineLabel)
                row("GENERATED", Self.stamp.string(from: insight.generatedAt))
                row("READ CLOSELY", readCloselyValue)
                if reconstruction.backgroundCount > 0 {
                    row("CONTEXT", "\(reconstruction.backgroundCount) earlier entries")
                }
                row("MOOD READ", moodValue)
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
