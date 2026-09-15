import SwiftUI

/// A standalone sheet, own entry point (EntryListView's toolbar, shown only when there's
/// something to show) — not a card bolted onto WriteView/InsightView. No new SwiftData/CloudKit
/// schema: entries are matched live off the existing `createdAt` field via `OnThisDayService`.
struct OnThisDayView: View {
    let entries: [Entry]
    var onSelectEntry: (Entry) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(entries) { entry in
                        Button {
                            dismiss()
                            onSelectEntry(entry)
                        } label: {
                            OnThisDayCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle(displayMode == .sentinel ? "TEMPORAL ECHO" : "On This Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct OnThisDayCard: View {
    let entry: Entry
    @Environment(\.appDisplayMode) private var displayMode

    private var yearsAgo: Int {
        max(1, Calendar.current.dateComponents([.year], from: entry.createdAt, to: Date()).year ?? 1)
    }

    // Text(_:) only auto-extracts a string LITERAL at the call site — a plain interpolated
    // String built here and handed to Text() would silently skip localization/extraction, so
    // this wraps each branch in String(localized:) explicitly instead.
    private var yearsAgoLabel: String {
        yearsAgo == 1
            ? String(localized: "1 year ago")
            : String(localized: "\(yearsAgo) years ago")
    }

    private var moodColor: Color {
        entry.mood.map { MirrorTheme.moodColor(for: $0) } ?? MirrorTheme.primary
    }

    private var snippet: String {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Group {
                    if displayMode == .sentinel {
                        Text(yearsAgoLabel.uppercased())
                            .font(MirrorTheme.mono(11, weight: .bold))
                            .tracking(0.6)
                    } else {
                        Text(yearsAgoLabel)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(moodColor)

                Circle().fill(moodColor.opacity(0.5)).frame(width: 3, height: 3)

                Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(MirrorTheme.textTertiary)

                Spacer()

                if let mood = entry.mood, !mood.isEmpty {
                    Text(MirrorTheme.localizedMoodName(for: mood))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(moodColor)
                }
            }

            Text(snippet)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(MirrorTheme.textPrimary.opacity(0.9))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: 16)
    }
}
