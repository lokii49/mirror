import SwiftUI
import SwiftData

private let moodLabels = MirrorTheme.moodOptions

struct EntriesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var showSearch = false
    @State private var selectedMoodFilter: String? = nil
    @State private var selectedEntry: Entry?
    @State private var showEntryDetail = false

    private struct EntryMonthGroup {
        let date: Date
        let entries: [Entry]
    }

    private struct EntryListSnapshot {
        let filteredEntries: [Entry]
        let usedMoods: [String]
        let groupedByMonth: [EntryMonthGroup]
    }

    private var listSnapshot: EntryListSnapshot {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = entries
        let usedMoods = usedMoods(in: entries)

        if let mood = selectedMoodFilter {
            result = result.filter { $0.mood == mood }
        }
        if !query.isEmpty {
            result = result.filter { $0.insightContext.localizedCaseInsensitiveContains(query) }
        }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: result) { entry -> Date in
            let comps = calendar.dateComponents([.year, .month], from: entry.createdAt)
            return calendar.date(from: comps) ?? entry.createdAt
        }
        let groupedByMonth = groups.keys.sorted(by: >).map { month in
            EntryMonthGroup(date: month, entries: groups[month, default: []].sorted { $0.createdAt > $1.createdAt })
        }

        return EntryListSnapshot(filteredEntries: result, usedMoods: usedMoods, groupedByMonth: groupedByMonth)
    }

    var body: some View {
        let snapshot = listSnapshot
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else if snapshot.filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: debouncedSearchText)
                } else {
                    entryList(snapshot)
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
                VStack(spacing: 0) {
                    if showSearch { searchBar }
                    if !snapshot.usedMoods.isEmpty { moodFilterBar(snapshot.usedMoods) }
                }
            }
            .onChange(of: searchText) { _, newValue in
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    if newValue == searchText {
                        debouncedSearchText = newValue
                    }
                }
            }
            .navigationDestination(isPresented: $showEntryDetail) {
                if let selectedEntry {
                    EntryDetailView(entry: selectedEntry) {
                        showEntryDetail = false
                        self.selectedEntry = nil
                    }
                }
            }
        }
    }

    private func usedMoods(in entries: [Entry]) -> [String] {
        let all = entries.compactMap(\.mood).filter { !$0.isEmpty }
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    private func moodFilterBar(_ usedMoods: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(usedMoods, id: \.self) { mood in
                    let isSelected = selectedMoodFilter == mood
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMoodFilter = isSelected ? nil : mood
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(MirrorTheme.moodColor(for: mood))
                                .frame(width: 7, height: 7)
                            Text(mood)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected
                                ? MirrorTheme.moodColor(for: mood).opacity(0.18)
                                : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? MirrorTheme.moodColor(for: mood) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(MirrorTheme.bgBase)
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

    private func entryList(_ snapshot: EntryListSnapshot) -> some View {
        List {
            Text("\(snapshot.filteredEntries.count) \(snapshot.filteredEntries.count == 1 ? "entry" : "entries")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ForEach(snapshot.groupedByMonth, id: \.date) { group in
                Section {
                    ForEach(group.entries) { entry in
                        EntryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEntry = entry
                                showEntryDetail = true
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    modelContext.delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                } header: {
                    Text(monthTitle(for: group.date))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .padding(.horizontal, 4)
                        .padding(.top, 0)
                        .padding(.bottom, 2)
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 96, for: .scrollContent)
        .listSectionSpacing(8)
        .environment(\.defaultMinListHeaderHeight, 0)
        .environment(\.defaultMinListRowHeight, 1)
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
    private let moodLabel: String?
    private let preview: String
    private let displayWordCount: Int
    private let hasReadablePreview: Bool
    private let hasVoiceNotes: Bool

    init(entry: Entry) {
        self.entry = entry
        self.moodLabel = entry.mood.flatMap { $0.isEmpty ? nil : $0 }
        let snapshot = Self.makePreview(for: entry)
        self.preview = snapshot.preview
        self.displayWordCount = snapshot.wordCount
        self.hasReadablePreview = snapshot.hasReadablePreview
        self.hasVoiceNotes = snapshot.hasVoiceNotes
    }

    private var previewTextColor: Color {
        hasReadablePreview && !entry.textDecryptionFailed ? .primary : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(preview)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(previewTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasVoiceNotes {
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
                if displayWordCount > 0 {
                    Text("\(displayWordCount)w")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                if let label = moodLabel {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(MirrorTheme.moodColor(for: label))
                            .frame(width: 7, height: 7)
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    private static let stylePrefixes = ["### ", "## ", "# ", "    "]

    private static func strippedLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in Self.stylePrefixes where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        if trimmed.hasPrefix("○ ") || trimmed.hasPrefix("✓ ") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    private static func makePreview(for entry: Entry) -> (preview: String, wordCount: Int, hasReadablePreview: Bool, hasVoiceNotes: Bool) {
        guard !entry.textDecryptionFailed else {
            return ("Encrypted entry unavailable", 0, false, entry.hasVoiceNotes)
        }
        let textPreview = entry.text
            .replacingOccurrences(of: inlinePhotoToken, with: "")
            .components(separatedBy: .newlines)
            .map { strippedLine($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let voicePreview = entry.voiceNotePreview
        let voiceTranscriptPreview = voicePreview.transcript
        let hasReadablePreview = !textPreview.isEmpty || voiceTranscriptPreview != nil || voicePreview.count > 0 || entry.hasPhoto
        let textSource = textPreview.isEmpty ? (voiceTranscriptPreview ?? "") : textPreview
        let wordCount = textSource
            .split { $0.isWhitespace || $0.isNewline }
            .filter { !$0.isEmpty }
            .count

        if !textPreview.isEmpty {
            return (textPreview, wordCount, hasReadablePreview, voicePreview.count > 0)
        }
        if let voiceTranscriptPreview {
            return (voiceTranscriptPreview, wordCount, hasReadablePreview, voicePreview.count > 0)
        }
        if voicePreview.count > 0 {
            if voicePreview.count == 1 {
                return ("Voice note \(formatDuration(voicePreview.duration))", wordCount, hasReadablePreview, true)
            }
            return ("\(voicePreview.count) voice notes", wordCount, hasReadablePreview, true)
        }
        if entry.hasPhoto {
            return ("Photo entry", wordCount, hasReadablePreview, false)
        }
        return ("Untitled entry", wordCount, hasReadablePreview, false)
    }
}
