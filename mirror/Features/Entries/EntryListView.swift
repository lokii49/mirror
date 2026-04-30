import SwiftUI
import SwiftData

private let moodLabels = MirrorTheme.moodOptions

struct EntriesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var searchText = ""
    @State private var showSearch = false

    private var filteredEntries: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.insightContext.localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedByMonth: [(date: Date, entries: [Entry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { entry -> Date in
            let comps = calendar.dateComponents([.year, .month], from: entry.createdAt)
            return calendar.date(from: comps) ?? entry.createdAt
        }
        return groups.keys.sorted(by: >).map { month in
            (month, groups[month, default: []].sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    entryList
                }
            }
            .navigationTitle("Entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { showSearch.toggle() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showSearch {
                    searchBar
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search entries...", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .futureSurface(cornerRadius: 14)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MirrorTheme.bgBase)
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(groupedByMonth, id: \.date) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(monthTitle(for: group.date))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .padding(.horizontal, 4)

                        ForEach(group.entries) { entry in
                            NavigationLink {
                                EntryDetailView(entry: entry)
                            } label: {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MirrorTheme.bgBase)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No entries yet")
                .font(.system(size: 20, weight: .semibold))
            Text("Tap Write to start your first entry.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func monthTitle(for date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}

private struct EntryRow: View {
    let entry: Entry

    private var moodLabel: String? {
        guard let mood = entry.mood, !mood.isEmpty else { return nil }
        return mood
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(preview)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !entry.voiceNotes.isEmpty {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.createdAt, format: .dateTime.weekday(.wide).day())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let label = moodLabel {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                Text("\(entry.wordCount)w")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .futureSurface(cornerRadius: 16)
    }

    private var preview: String {
        let lines = entry.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let textPreview = lines.joined(separator: " ")
        if !textPreview.isEmpty { return textPreview }
        if !entry.voiceNotes.isEmpty {
            if let transcript = entry.voiceNotes
                .compactMap(\.transcript)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) {
                return transcript
            }
            if entry.voiceNotes.count == 1 {
                return "Voice note \(formatDuration(entry.voiceNotes[0].duration))"
            }
            return "\(entry.voiceNotes.count) voice notes"
        }
        return ""
    }
}
