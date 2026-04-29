import SwiftUI
import SwiftData

private let moodLabels: [String] = ["Rough", "Low", "Okay", "Good", "Alive"]

struct EntriesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var searchText = ""
    @State private var showSearch = false

    private var filteredEntries: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.text.localizedCaseInsensitiveContains(query)
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
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.createdAt, format: .dateTime.weekday(.wide).day())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let label = moodLabel {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                if entry.voiceNoteData != nil {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text("\(entry.wordCount)w")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(preview)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var preview: String {
        let lines = entry.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let textPreview = lines.joined(separator: " ")
        if !textPreview.isEmpty { return textPreview }
        if entry.voiceNoteData != nil { return "Voice note \(formatDuration(entry.voiceNoteDuration))" }
        return ""
    }
}
