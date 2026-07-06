import SwiftUI
import SwiftData

private let moodLabels = MirrorTheme.moodOptions

struct EntriesTabView: View {
    var navResetID: UUID = UUID()
    var deepLinkEntryID: Binding<UUID?> = .constant(nil)

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var showSearch = false
    @State private var selectedMoodFilter: String? = nil
    @State private var selectedTagFilter: String? = nil
    @State private var selectedDateFilter: Date? = nil
    @State private var selectedEntry: Entry?
    @State private var showEntryDetail = false
    @State private var snapshotCache: EntryListSnapshot? = nil
    @State private var sortOrder: EntrySortOrder = .newestFirst

    private enum EntrySortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case mostWords   = "Most Words"
        case byMood      = "By Mood"

        var icon: String {
            switch self {
            case .newestFirst: return "arrow.down.circle"
            case .oldestFirst: return "arrow.up.circle"
            case .mostWords:   return "text.word.spacing"
            case .byMood:      return "face.smiling"
            }
        }

        var displayName: LocalizedStringKey {
            switch self {
            case .newestFirst: return "Newest First"
            case .oldestFirst: return "Oldest First"
            case .mostWords:   return "Most Words"
            case .byMood:      return "By Mood"
            }
        }
    }

    private struct EntryMonthGroup {
        let date: Date
        let entries: [Entry]
    }

    // Precomputed at task time — zero AES decrypts during scroll
    struct EntryRowPreview {
        let moodLabel: String?
        let preview: Text
        let wordCount: Int
        let hasReadablePreview: Bool
        let hasVoiceNotes: Bool
        let textDecryptionFailed: Bool
    }

    private struct EntryListSnapshot {
        let filteredEntries: [Entry]
        let usedMoods: [String]
        let usedTags: [String]
        let groupedByMonth: [EntryMonthGroup]
        let rowPreviews: [UUID: EntryRowPreview]
    }

    private struct SnapshotDeps: Equatable {
        let search: String
        let mood: String?
        let tag: String?
        let date: Date?
        let entryCount: Int
        let moodHash: Int
        let tagsHash: Int
        let sort: String
    }

    private var snapshotDeps: SnapshotDeps {
        SnapshotDeps(
            search: debouncedSearchText,
            mood: selectedMoodFilter,
            tag: selectedTagFilter,
            date: selectedDateFilter,
            entryCount: entries.count,
            moodHash: entries.map(\.encryptedMood).hashValue,
            tagsHash: entries.map(\.encryptedTagsStorage).hashValue,
            sort: sortOrder.rawValue
        )
    }

    private var listSnapshot: EntryListSnapshot {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = entries
        let usedMoods = usedMoods(in: entries)
        let usedTags = usedTags(in: entries)

        if let date = selectedDateFilter {
            result = result.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: date) }
        }
        if let mood = selectedMoodFilter {
            result = result.filter { $0.mood == mood }
        }
        if let tag = selectedTagFilter {
            result = result.filter { $0.tags.contains(tag) }
        }
        if !query.isEmpty {
            result = result.filter { $0.insightContext.localizedCaseInsensitiveContains(query) }
        }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: result) { entry -> Date in
            let comps = calendar.dateComponents([.year, .month], from: entry.createdAt)
            return calendar.date(from: comps) ?? entry.createdAt
        }
        switch sortOrder {
        case .newestFirst: break  // already sorted by @Query
        case .oldestFirst: result = result.sorted { $0.createdAt < $1.createdAt }
        case .mostWords:   result = result.sorted { $0.wordCount > $1.wordCount }
        case .byMood:      result = result.sorted { ($0.mood ?? "") < ($1.mood ?? "") }
        }

        let monthSortAscending = sortOrder == .oldestFirst
        let groupedByMonth = groups.keys.sorted(by: monthSortAscending ? (<) : (>)).map { month in
            let monthEntries = groups[month, default: []]
            let sortedMonthEntries: [Entry]
            switch sortOrder {
            case .newestFirst: sortedMonthEntries = monthEntries.sorted { $0.createdAt > $1.createdAt }
            case .oldestFirst: sortedMonthEntries = monthEntries.sorted { $0.createdAt < $1.createdAt }
            case .mostWords:   sortedMonthEntries = monthEntries.sorted { $0.wordCount > $1.wordCount }
            case .byMood:      sortedMonthEntries = monthEntries.sorted { ($0.mood ?? "") < ($1.mood ?? "") }
            }
            return EntryMonthGroup(date: month, entries: sortedMonthEntries)
        }

        // Precompute all row display data (mood + text decrypts) so EntryRow.init does zero decrypts
        var rowPreviews: [UUID: EntryRowPreview] = [:]
        for entry in entries {
            let p = EntryRow.makePreview(for: entry)
            rowPreviews[entry.id] = EntryRowPreview(
                moodLabel: entry.mood.flatMap { $0.isEmpty ? nil : $0 },
                preview: p.preview,
                wordCount: p.wordCount,
                hasReadablePreview: p.hasReadablePreview,
                hasVoiceNotes: p.hasVoiceNotes,
                textDecryptionFailed: entry.textDecryptionFailed
            )
        }

        return EntryListSnapshot(filteredEntries: result, usedMoods: usedMoods, usedTags: usedTags, groupedByMonth: groupedByMonth, rowPreviews: rowPreviews)
    }

    private var trailingToolbar: some View {
        HStack(spacing: 16) {
            Menu {
                ForEach(EntrySortOrder.allCases, id: \.self) { order in
                    Button {
                        withAnimation { sortOrder = order }
                    } label: {
                        Label(order.displayName, systemImage: sortOrder == order ? "checkmark" : order.icon)
                    }
                }
            } label: {
                Image(systemName: sortOrder == .newestFirst ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
            }
            Button {
                withAnimation { showSearch.toggle() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
    }

    var body: some View {
        let snapshot = snapshotCache ?? listSnapshot
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    // Always show the list (heatmap stays visible even when filters produce 0 results)
                    entryList(snapshot)
                }
            }
            .navigationTitle("Entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    trailingToolbar
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if showSearch { searchBar }
                    if !snapshot.usedMoods.isEmpty { moodFilterBar(snapshot.usedMoods) }
                    if !snapshot.usedTags.isEmpty { tagFilterBar(snapshot.usedTags) }
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
            .task(id: snapshotDeps) {
                snapshotCache = listSnapshot
            }
            .onChange(of: navResetID) { _, _ in
                showEntryDetail = false
                selectedEntry = nil
            }
            .onChange(of: deepLinkEntryID.wrappedValue) { _, newID in
                guard let id = newID,
                      let match = entries.first(where: { $0.id == id }) else { return }
                selectedEntry = match
                showEntryDetail = true
                deepLinkEntryID.wrappedValue = nil
            }
        }
    }

    @ViewBuilder
    private var activeFiltersRow: some View {
        HStack(spacing: 8) {
            if let date = selectedDateFilter {
                filterChip(
                    label: date.formatted(.dateTime.month(.abbreviated).day().year()),
                    systemImage: "calendar"
                ) { selectedDateFilter = nil }
            }
            if let mood = selectedMoodFilter {
                filterChip(
                    label: MirrorTheme.localizedMoodName(for: mood),
                    systemImage: "circle.fill",
                    color: MirrorTheme.moodColor(for: mood)
                ) { selectedMoodFilter = nil }
            }
            if let tag = selectedTagFilter {
                filterChip(label: "#\(MirrorTheme.localizedTagName(for: tag))", systemImage: "tag") { selectedTagFilter = nil }
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedDateFilter = nil
                    selectedMoodFilter = nil
                    selectedTagFilter = nil
                }
            } label: {
                Text("Clear")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func filterChip(
        label: String,
        systemImage: String,
        color: Color = MirrorTheme.primary,
        onRemove: @escaping () -> Void
    ) -> some View {
        Button(action: onRemove) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func usedMoods(in entries: [Entry]) -> [String] {
        let all = entries.compactMap(\.mood).filter { !$0.isEmpty }
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    private func usedTags(in entries: [Entry]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            for tag in entry.tags where seen.insert(tag).inserted {
                result.append(tag)
            }
        }
        return result
    }

    private func tagFilterBar(_ usedTags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(usedTags, id: \.self) { tag in
                    let isSelected = selectedTagFilter == tag
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTagFilter = isSelected ? nil : tag
                            if !isSelected { selectedMoodFilter = nil; selectedDateFilter = nil }
                        }
                    } label: {
                        Text("#\(MirrorTheme.localizedTagName(for: tag))")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? MirrorTheme.violetDim : MirrorTheme.inkRaised,
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? MirrorTheme.violetLight : MirrorTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(MirrorTheme.bgBase)
    }

    private func moodFilterBar(_ usedMoods: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(usedMoods, id: \.self) { mood in
                    let isSelected = selectedMoodFilter == mood
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMoodFilter = isSelected ? nil : mood
                            if !isSelected { selectedTagFilter = nil }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(MirrorTheme.moodColor(for: mood))
                                .frame(width: 7, height: 7)
                            Text(MirrorTheme.localizedMoodName(for: mood))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected
                                ? MirrorTheme.moodColor(for: mood).opacity(0.20)
                                : MirrorTheme.inkRaised,
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? MirrorTheme.moodColor(for: mood) : MirrorTheme.textSecondary)
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
            // Activity heatmap
            Section {
                CalendarHeatmap(
                    entries: entries,
                    selectedDate: selectedDateFilter,
                    onDaySelected: { date in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDateFilter = date
                            if date != nil { selectedMoodFilter = nil; selectedTagFilter = nil }
                        }
                    }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Active filters row
            if selectedDateFilter != nil || selectedMoodFilter != nil || selectedTagFilter != nil {
                Section {
                    activeFiltersRow
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            if snapshot.filteredEntries.isEmpty {
                Text(emptyFilteredMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 32)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                EmptyView()
            }

            ForEach(snapshot.groupedByMonth, id: \.date) { group in
                Section {
                    ForEach(group.entries) { entry in
                        EntryRow(entry: entry, rowPreview: snapshot.rowPreviews[entry.id])
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
                    HStack {
                        Text(monthTitle(for: group.date))
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .tracking(1.5)
                        Spacer()
                        Text(group.entries.count == 1 ? "1 entry" : "\(group.entries.count) entries")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .textCase(nil)
                    }
                    .foregroundStyle(MirrorTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 96, for: .scrollContent)
        .listSectionSpacing(4)
        .environment(\.defaultMinListHeaderHeight, 0)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollDismissesKeyboard(.interactively)
        .background(MirrorTheme.bgBase)
    }

    private var emptyFilteredMessage: LocalizedStringKey {
        if let date = selectedDateFilter {
            return "No entries on \(date.formatted(.dateTime.month(.wide).day()))"
        }
        if let mood = selectedMoodFilter {
            return "No \(MirrorTheme.localizedMoodName(for: mood).lowercased()) entries"
        }
        if let tag = selectedTagFilter {
            return "No entries tagged #\(MirrorTheme.localizedTagName(for: tag))"
        }
        return "No entries match your search"
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
    private let preview: Text
    private let displayWordCount: Int
    private let hasReadablePreview: Bool
    private let hasVoiceNotes: Bool
    private let decryptFailed: Bool
    // The preview joins multiple paragraphs into one line, so per-paragraph fonts
    // can't all render — use the entry's first paragraph's font, since that's what
    // the preview visually represents (its opening line).
    private var writingFontDesign: Font.Design {
        let firstOverride = entry.textStyleData
            .flatMap { try? JSONDecoder().decode(NoteTextStyleDocument.self, from: $0) }
            .flatMap { $0.fontChoices?.first }
        return WritingFontChoice.resolved(entryDefault: entry.fontChoice, override: firstOverride).swiftUIDesign
    }

    // rowPreview is precomputed in .task — zero decrypts during scroll.
    // Falls back to inline decryption only on first render before cache is ready.
    init(entry: Entry, rowPreview: EntriesTabView.EntryRowPreview? = nil) {
        self.entry = entry
        if let rp = rowPreview {
            self.moodLabel = rp.moodLabel
            self.preview = rp.preview
            self.displayWordCount = rp.wordCount
            self.hasReadablePreview = rp.hasReadablePreview
            self.hasVoiceNotes = rp.hasVoiceNotes
            self.decryptFailed = rp.textDecryptionFailed
        } else {
            self.decryptFailed = entry.textDecryptionFailed
            self.moodLabel = entry.mood.flatMap { $0.isEmpty ? nil : $0 }
            let snapshot = Self.makePreview(for: entry)
            self.preview = snapshot.preview
            self.displayWordCount = snapshot.wordCount
            self.hasReadablePreview = snapshot.hasReadablePreview
            self.hasVoiceNotes = snapshot.hasVoiceNotes
        }
    }

    private var previewTextColor: Color {
        hasReadablePreview && !decryptFailed ? MirrorTheme.textPrimary : MirrorTheme.textSecondary
    }

    private var moodColor: Color {
        moodLabel.map { MirrorTheme.moodColor(for: $0) } ?? MirrorTheme.primary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text(entry.createdAt, format: .dateTime.day())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(entry.createdAt, format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .frame(width: 42)
            .padding(.vertical, 10)
            .background(moodColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    preview
                        .font(.system(size: 16, weight: .medium, design: writingFontDesign))
                        .foregroundStyle(previewTextColor)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        if entry.hasPhoto {
                            Image(systemName: "photo")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        if hasVoiceNotes {
                            Image(systemName: "waveform")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.createdAt, format: .dateTime.hour().minute())
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
                            Text(MirrorTheme.localizedMoodName(for: label))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MirrorTheme.moodColor(for: label).opacity(0.10), in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(moodColor.opacity(moodLabel == nil ? 0.20 : 0.65))
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MirrorTheme.inkBorder, lineWidth: 1)
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

    fileprivate static func makePreview(for entry: Entry) -> (preview: Text, wordCount: Int, hasReadablePreview: Bool, hasVoiceNotes: Bool) {
        guard !entry.textDecryptionFailed else {
            return (Text("Encrypted entry unavailable"), 0, false, entry.hasVoiceNotes)
        }
        var entryTextStripped = entry.text
        for (r, _) in allPhotoTokens(in: entryTextStripped).reversed() { entryTextStripped.removeSubrange(r) }
        let textPreview = entryTextStripped
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
            return (Text(verbatim: textPreview), wordCount, hasReadablePreview, voicePreview.count > 0)
        }
        if let voiceTranscriptPreview {
            return (Text(verbatim: voiceTranscriptPreview), wordCount, hasReadablePreview, voicePreview.count > 0)
        }
        if voicePreview.count > 0 {
            if voicePreview.count == 1 {
                return (Text("Voice note \(formatDuration(voicePreview.duration))"), wordCount, hasReadablePreview, true)
            }
            return (Text("\(voicePreview.count) voice notes"), wordCount, hasReadablePreview, true)
        }
        if entry.hasPhoto {
            return (Text("Photo entry"), wordCount, hasReadablePreview, false)
        }
        return (Text("Untitled entry"), wordCount, hasReadablePreview, false)
    }
}
