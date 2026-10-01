import SwiftUI
import SwiftData

private let moodLabels = MirrorTheme.moodOptions

struct EntriesTabView: View {
    var navResetID: UUID = UUID()
    var deepLinkEntryID: Binding<UUID?> = .constant(nil)
    /// macOS shows the reader beside the list instead of pushing it. When set, opening an
    /// entry writes it here and the list never navigates.
    var macSelection: Binding<Entry?>? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var showSearch = false
    @State private var selectedMoodFilter: String? = nil
    @State private var selectedTagFilter: String? = nil
    @State private var selectedDateFilter: Date? = nil
    @State private var selectedEntry: Entry?
    @State private var showEntryDetail = false
    @State private var showOnThisDay = false
    @State private var snapshotCache: EntryListSnapshot? = nil
    @State private var sortOrder: EntrySortOrder = .newestFirst
    // Set right before a pin/unpin toggle so the snapshot recompute (which lands
    // in .task, a separate transaction from the toggle site) animates only that
    // interaction — not every search keystroke, sort change, or tag edit.
    @State private var animatePinChange = false
    #if os(macOS)
    @State private var macShowCalendar = false
    @FocusState private var macSearchFocused: Bool
    #endif

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
        let pinnedEntries: [Entry]
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
        let pinnedHash: Int
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
            pinnedHash: entries.map(\.isPinned).hashValue,
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
            #if os(macOS)
            // The Mac search box also matches #tags and mood names.
            let bare = query.hasPrefix("#") ? String(query.dropFirst()) : query
            result = result.filter {
                $0.insightContext.localizedCaseInsensitiveContains(query)
                    || $0.tags.contains { $0.localizedCaseInsensitiveContains(bare) }
                    || ($0.mood.map { MirrorTheme.localizedMoodName(for: $0).localizedCaseInsensitiveContains(query) } ?? false)
            }
            #else
            result = result.filter { $0.insightContext.localizedCaseInsensitiveContains(query) }
            #endif
        }

        switch sortOrder {
        case .newestFirst: break  // already sorted by @Query
        case .oldestFirst: result = result.sorted { $0.createdAt < $1.createdAt }
        case .mostWords:   result = result.sorted { $0.wordCount > $1.wordCount }
        case .byMood:      result = result.sorted { ($0.mood ?? "") < ($1.mood ?? "") }
        }

        // Pinned entries surface in their own section above the month groups
        // (see entryList(_:)) — excluded here so they don't also render twice.
        // Deliberate: a month's "N entries" header counts only what's rendered
        // in that section, not the pinned ones that moved up top.
        let pinnedEntries = result.filter(\.isPinned)
        let calendar = Calendar.current
        let groups = Dictionary(grouping: result.filter { !$0.isPinned }) { entry -> Date in
            let comps = calendar.dateComponents([.year, .month], from: entry.createdAt)
            return calendar.date(from: comps) ?? entry.createdAt
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

        return EntryListSnapshot(filteredEntries: result, usedMoods: usedMoods, usedTags: usedTags, pinnedEntries: pinnedEntries, groupedByMonth: groupedByMonth, rowPreviews: rowPreviews)
    }

    // Computed on every render off the existing @Query — cheap (date-component comparison only,
    // no decryption) even for a large journal, and typically yields 0-2 entries.
    private var onThisDayMatches: [Entry] {
        OnThisDayService.matches(in: entries)
    }

    private var trailingToolbar: some View {
        HStack(spacing: 16) {
            if !onThisDayMatches.isEmpty {
                Button {
                    showOnThisDay = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : Color.primary)
                }
                .accessibilityLabel("On This Day")
            }
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
                    .foregroundStyle(displayMode == .sentinel && sortOrder != .newestFirst ? MirrorTheme.ember : Color.primary)
            }
            Button {
                withAnimation { showSearch.toggle() }
            } label: {
                Image(systemName: displayMode == .sentinel ? "scope" : "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(displayMode == .sentinel && showSearch ? MirrorTheme.ember : Color.primary)
            }
        }
    }

    var body: some View {
        let snapshot = snapshotCache ?? listSnapshot
        PlatformNavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    // Always show the list (heatmap stays visible even when filters produce 0 results)
                    #if os(macOS)
                    macColumn(snapshot)
                    #else
                    entryList(snapshot)
                    #endif
                }
            }
            .navigationTitle(displayMode == .sentinel ? "Log" : "Entries")
            .navigationBarTitleDisplayMode(.inline)
            #if os(iOS)
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
            #endif
            .onChange(of: searchText) { _, newValue in
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    if newValue == searchText {
                        debouncedSearchText = newValue
                    }
                }
            }
            #if os(iOS)
            // On Mac the reader sits beside the list (macSelection), so nothing is pushed.
            .navigationDestination(isPresented: $showEntryDetail) {
                if let selectedEntry {
                    EntryDetailView(entry: selectedEntry) {
                        showEntryDetail = false
                        self.selectedEntry = nil
                    }
                }
            }
            #endif
            .sheet(isPresented: $showOnThisDay) {
                OnThisDayView(entries: onThisDayMatches) { entry in
                    open(entry)
                }
            }
            .task(id: snapshotDeps) {
                let newSnapshot = listSnapshot
                if animatePinChange && !reduceMotion {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        snapshotCache = newSnapshot
                    }
                } else {
                    snapshotCache = newSnapshot
                }
                animatePinChange = false
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .mirrorMacFocusSearch)) { _ in macSearchFocused = true }
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .mirrorMacDebugEntriesState)) { note in
                if let open = note.userInfo?["calendar"] as? Bool { macShowCalendar = open }
                if let query = note.userInfo?["search"] as? String { searchText = query; debouncedSearchText = query }
            }
            #endif
            #endif
            .onChange(of: navResetID) { _, _ in
                showEntryDetail = false
                selectedEntry = nil
                macSelection?.wrappedValue = nil
            }
            .onChange(of: deepLinkEntryID.wrappedValue) { _, newID in
                guard let id = newID,
                      let match = entries.first(where: { $0.id == id }) else { return }
                open(match)
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
                Group {
                    if displayMode == .sentinel {
                        Text("CLEAR").font(MirrorTheme.mono(11, weight: .medium))
                    } else {
                        Text("Clear").font(.system(size: 12, weight: .medium))
                    }
                }
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
                Group {
                    if displayMode == .sentinel {
                        Text(label.uppercased()).font(MirrorTheme.mono(11, weight: .medium))
                    } else {
                        Text(label).font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundStyle(.primary)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                color.opacity(0.10),
                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous)) : AnyShape(Capsule())
            )
            .overlay {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(color.opacity(0.35), lineWidth: 1)
                }
            }
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
                        Group {
                            if displayMode == .sentinel {
                                Text("#\(MirrorTheme.localizedTagName(for: tag))".uppercased())
                                    .font(MirrorTheme.mono(11, weight: .medium))
                            } else {
                                Text("#\(MirrorTheme.localizedTagName(for: tag))")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? (displayMode == .sentinel ? MirrorTheme.ember.opacity(0.14) : MirrorTheme.violetDim) : MirrorTheme.inkRaised,
                            in: displayMode == .sentinel
                                ? AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                : AnyShape(Capsule())
                        )
                        .overlay {
                            if displayMode == .sentinel {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke((isSelected ? MirrorTheme.ember : MirrorTheme.textTertiary).opacity(isSelected ? 0.4 : 0.2), lineWidth: 1)
                            }
                        }
                        .foregroundStyle(isSelected ? (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violetLight) : MirrorTheme.textSecondary)
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
                                .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .semibold) : .system(size: 12, weight: .medium))
                                .textCase(displayMode == .sentinel ? .uppercase : nil)
                                .kerning(displayMode == .sentinel ? 0.3 : 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected
                                ? MirrorTheme.moodColor(for: mood).opacity(0.20)
                                : MirrorTheme.inkRaised,
                            in: displayMode == .sentinel
                                ? AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                : AnyShape(Capsule())
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
            Image(systemName: displayMode == .sentinel ? "scope" : "magnifyingglass")
                .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : .secondary)
            Group {
                if displayMode == .sentinel {
                    TextField("scan entries…", text: $searchText)
                        .font(MirrorTheme.mono(14, weight: .medium))
                } else {
                    TextField("Search entries...", text: $searchText)
                }
            }
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
        .themedCard(cornerRadius: 14)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MirrorTheme.bgBase)
    }

    private func open(_ entry: Entry) {
        if let macSelection {
            macSelection.wrappedValue = entry
        } else {
            selectedEntry = entry
            showEntryDetail = true
        }
    }

    @ViewBuilder
    private func entryRowView(_ entry: Entry, preview: EntryRowPreview?) -> some View {
        EntryRow(entry: entry, rowPreview: preview)
            .contentShape(Rectangle())
            .onTapGesture {
                open(entry)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(macSelection?.wrappedValue?.id == entry.id ? MirrorTheme.violet.opacity(0.16) : Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    modelContext.delete(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    animatePinChange = true
                    entry.isPinned.toggle()
                    try? modelContext.save()
                } label: {
                    Label(entry.isPinned ? "Unpin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
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

            if !snapshot.pinnedEntries.isEmpty {
                Section {
                    ForEach(snapshot.pinnedEntries) { entry in
                        entryRowView(entry, preview: snapshot.rowPreviews[entry.id])
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill").font(.system(size: 11, weight: .bold))
                        Group {
                            if displayMode == .sentinel {
                                Text("Pinned").font(MirrorTheme.mono(13, weight: .bold)).tracking(1.5)
                            } else {
                                Text("Pinned").font(.system(size: 13, weight: .black, design: .rounded)).tracking(1.5)
                            }
                        }
                    }
                    .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.75) : MirrorTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                }
            }

            if snapshot.filteredEntries.isEmpty {
                Group {
                    if displayMode == .sentinel {
                        Text(emptyFilteredMessage).font(MirrorTheme.mono(13, weight: .medium)).textCase(.uppercase)
                    } else {
                        Text(emptyFilteredMessage).font(.system(size: 14))
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
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
                        entryRowView(entry, preview: snapshot.rowPreviews[entry.id])
                    }
                } header: {
                    HStack {
                        Group {
                            if displayMode == .sentinel {
                                Text(monthTitle(for: group.date)).font(MirrorTheme.mono(13, weight: .bold)).tracking(1.5)
                            } else {
                                Text(monthTitle(for: group.date)).font(.system(size: 13, weight: .black, design: .rounded)).tracking(1.5)
                            }
                        }
                        Spacer()
                        Text(group.entries.count == 1 ? "1 entry" : "\(group.entries.count) entries")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .textCase(nil)
                    }
                    .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.75) : MirrorTheme.textTertiary)
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
        #if os(iOS)
        .listSectionSpacing(4)
        #endif
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
            Image(systemName: displayMode == .sentinel ? "viewfinder" : "book.closed")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.quaternary)
            Group {
                if displayMode == .sentinel {
                    Text("NO SIGNALS YET").font(MirrorTheme.mono(18, weight: .semibold)).tracking(1)
                } else {
                    Text("No entries yet").font(.system(size: 20, weight: .semibold))
                }
            }
            Group {
                if displayMode == .sentinel {
                    Text("OPEN TRANSMISSION TO LOG YOUR FIRST SIGNAL.").font(MirrorTheme.mono(12, weight: .medium))
                } else {
                    Text("Tap Write to start your first entry.").font(.system(size: 15))
                }
            }
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
    @Environment(\.appDisplayMode) private var displayMode
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
                    .font(displayMode == .sentinel ? MirrorTheme.mono(17, weight: .bold) : .system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(entry.createdAt, format: .dateTime.weekday(.abbreviated))
                    .font(displayMode == .sentinel ? MirrorTheme.mono(9.5, weight: .bold) : .system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .frame(width: 42)
            .padding(.vertical, 10)
            .background(
                moodColor.opacity(0.10),
                in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 14, style: .continuous)
            )
            .overlay {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(moodColor.opacity(0.35), lineWidth: 1)
                }
            }

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
                        .font(displayMode == .sentinel ? MirrorTheme.mono(11.5, weight: .medium) : .system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    if displayWordCount > 0 {
                        Text("\(displayWordCount)w")
                            .font(displayMode == .sentinel ? MirrorTheme.mono(11.5, weight: .medium) : .system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    if let label = moodLabel {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(MirrorTheme.moodColor(for: label))
                                .frame(width: 7, height: 7)
                            Text(displayMode == .sentinel
                                 ? MirrorTheme.localizedMoodName(for: label).uppercased()
                                 : MirrorTheme.localizedMoodName(for: label))
                                .font(displayMode == .sentinel ? MirrorTheme.mono(10.5, weight: .semibold) : .system(size: 12, weight: .semibold))
                                .kerning(displayMode == .sentinel ? 0.3 : 0)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            MirrorTheme.moodColor(for: label).opacity(0.10),
                            in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                        )
                        .overlay {
                            if displayMode == .sentinel {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(MirrorTheme.moodColor(for: label).opacity(0.3), lineWidth: 1)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MirrorTheme.inkMid,
            in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 10 : 20, style: .continuous)
        )
        .overlay(alignment: .leading) {
            // Vertical inset must clear the card's own corner radius below —
            // the bar isn't clipped to the card shape, so anything less lets
            // its square corners poke past the card's rounded silhouette
            // instead of sitting inside the flat wall of the curve.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(moodColor.opacity(moodLabel == nil ? 0.20 : 0.65))
                .frame(width: 4)
                .padding(.vertical, displayMode == .sentinel ? 10 : 20)
        }
        .overlay {
            RoundedRectangle(cornerRadius: displayMode == .sentinel ? 10 : 20, style: .continuous)
                .stroke(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.22) : MirrorTheme.inkBorder, lineWidth: 1)
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
        let wordCount = segmentedWordCount(textSource)

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

#if os(macOS)
// MARK: - Mac list (the design's Entries column)

extension Notification.Name {
    /// Snapshot mode only: userInfo "calendar" (Bool) and "search" (String).
    static let mirrorMacDebugEntriesState = Notification.Name("mirror.mac.debug.entriesState")
    /// Go > Find in Entries: show Entries and focus the search field.
    static let mirrorMacFocusSearch = Notification.Name("mirror.mac.focusSearch")
}

extension EntriesTabView {
    private func macColumn(_ snapshot: EntryListSnapshot) -> some View {
        VStack(spacing: 0) {
            macHeader
            macSearchField
            macCalendarDisclosure
            if macShowCalendar {
                VStack(spacing: 8) {
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
                    if selectedDateFilter != nil || selectedMoodFilter != nil || selectedTagFilter != nil {
                        activeFiltersRow.padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !snapshot.pinnedEntries.isEmpty {
                        macSectionLabel("PINNED", icon: "pin", topPadding: 6)
                        ForEach(snapshot.pinnedEntries) { entry in
                            macRow(entry, snapshot: snapshot)
                        }
                    }
                    if snapshot.filteredEntries.isEmpty {
                        Text(emptyFilteredMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(MacTokens.secondaryInk)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    }
                    ForEach(snapshot.groupedByMonth, id: \.date) { group in
                        macSectionLabel(monthTitle(for: group.date).uppercased(), icon: nil, topPadding: 14)
                        ForEach(group.entries) { entry in
                            macRow(entry, snapshot: snapshot)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .modifier(MacNoScrollEdgeEffect())
        }
        .background(MirrorTheme.inkMid)
        .overlay(alignment: .trailing) { Rectangle().fill(MacTokens.divider).frame(width: 1) }
    }

    fileprivate var macHeader: some View {
        HStack(spacing: 8) {
            Text("Entries")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MacTokens.ink)
            Text("\(entries.count)")
                .font(.system(size: 12))
                .foregroundStyle(MacTokens.secondaryInk)
            Spacer(minLength: 0)
            Button {
                NotificationCenter.default.post(name: .mirrorMacNewEntry, object: nil)
            } label: {
                MacIcon(name: "pen", size: 17)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(MacTokens.controlInk)
            .accessibilityLabel("New entry")
            .help("New entry")
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(height: MacTokens.chromeHeight)
        // The board has only the pen here; sort, filters and On This Day live in this menu.
        .contextMenu {
            Menu("Sort by") {
                ForEach(EntrySortOrder.allCases, id: \.self) { order in
                    Button {
                        withAnimation { sortOrder = order }
                    } label: {
                        Label(order.displayName, systemImage: sortOrder == order ? "checkmark" : order.icon)
                    }
                }
            }
            if !onThisDayMatches.isEmpty {
                Button("On This Day") { showOnThisDay = true }
            }
            let moods = usedMoods(in: entries)
            if !moods.isEmpty {
                Menu("Show only mood") {
                    ForEach(moods, id: \.self) { mood in
                        Button(MirrorTheme.localizedMoodName(for: mood)) { selectedMoodFilter = mood; selectedTagFilter = nil }
                    }
                }
            }
            let tags = usedTags(in: entries)
            if !tags.isEmpty {
                Menu("Show only tag") {
                    ForEach(tags, id: \.self) { tag in
                        Button("#\(MirrorTheme.localizedTagName(for: tag))") { selectedTagFilter = tag; selectedMoodFilter = nil }
                    }
                }
            }
            if selectedDateFilter != nil || selectedMoodFilter != nil || selectedTagFilter != nil {
                Button("Clear filters") {
                    selectedDateFilter = nil; selectedMoodFilter = nil; selectedTagFilter = nil
                }
            }
        }
    }

    fileprivate var macSearchField: some View {
        HStack(spacing: 8) {
            MacIcon(name: "search", size: 14)
            TextField("Search entries", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(MacTokens.ink)
                .focused($macSearchFocused)
                .accessibilityLabel("Search entries")
            Text("⌘F").font(.system(size: 11))
        }
        .foregroundStyle(MacTokens.secondaryInk)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(MirrorTheme.inkRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1) }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    fileprivate var macCalendarDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { macShowCalendar.toggle() }
        } label: {
            HStack(spacing: 6) {
                MacIcon(name: "chevron", size: 11)
                    .rotationEffect(.degrees(macShowCalendar ? 90 : 0))
                Text("Calendar").font(.system(size: 12))
            }
            .foregroundStyle(MacTokens.secondaryInk)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Calendar")
        .accessibilityValue(macShowCalendar ? "Expanded" : "Collapsed")
    }

    fileprivate func macSectionLabel(_ title: String, icon: String?, topPadding: CGFloat) -> some View {
        HStack(spacing: 6) {
            if let icon { MacIcon(name: icon, size: 11) }
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.66)
        .foregroundStyle(MacTokens.secondaryInk)
        .padding(.horizontal, 16)
        .padding(.top, topPadding)
        .padding(.bottom, 6)
    }

    private func macRow(_ entry: Entry, snapshot: EntryListSnapshot) -> some View {
        let isSelected = macSelection?.wrappedValue?.id == entry.id
        return MacEntryRow(entry: entry, preview: snapshot.rowPreviews[entry.id], isSelected: isSelected)
            .padding(.horizontal, 8)
            .onTapGesture { open(entry) }
            .contextMenu {
                Button(entry.isPinned ? "Unpin" : "Pin") {
                    animatePinChange = true
                    entry.isPinned.toggle()
                    try? modelContext.save()
                }
                if let mood = entry.mood, !mood.isEmpty {
                    Button("Show only \(MirrorTheme.localizedMoodName(for: mood))") { selectedMoodFilter = mood; selectedTagFilter = nil }
                }
                Divider()
                Button("Share as text") {
                    let day = entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
                    presentShareSheet(items: ["\(day)\n\n\(entry.text)"])
                }
                Divider()
                Button("Delete", role: .destructive) {
                    // Clear the selection first so the reader never renders a deleted entry.
                    if isSelected { macSelection?.wrappedValue = nil }
                    modelContext.delete(entry)
                    try? modelContext.save()
                }
            }
    }
}

/// One row of the Mac list: date and word count, the first line, then mood and tags.
private struct MacEntryRow: View {
    let entry: Entry
    let preview: EntriesTabView.EntryRowPreview?
    let isSelected: Bool

    private var mood: String? { preview?.moodLabel ?? entry.mood.flatMap { $0.isEmpty ? nil : $0 } }
    private var secondary: Color { isSelected ? MacTokens.selectedRowInk : MacTokens.secondaryInk }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                Spacer(minLength: 8)
                if let count = preview?.wordCount, count > 0 {
                    Text(count == 1 ? "1 word" : "\(count) words")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(secondary)

            (preview?.preview ?? Text("Untitled entry"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(MacTokens.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            if mood != nil || !entry.tags.isEmpty {
                HStack(spacing: 6) {
                    if let mood {
                        Circle().fill(MirrorTheme.moodColor(for: mood)).frame(width: 7, height: 7)
                        Text(MirrorTheme.localizedMoodName(for: mood))
                    }
                    if let firstTag = entry.tags.first {
                        Text("· #\(MirrorTheme.localizedTagName(for: firstTag))")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? MacTokens.selectedRowFill : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(MacTokens.selectedRowBorder, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
