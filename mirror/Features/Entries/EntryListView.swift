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
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query private var collectionModels: [JournalCollection]
    @Query private var savedViewModels: [SavedEntryView]
    @State private var showOrganizer = false
    @State private var newCollectionFor: Entry?
    @State private var savingView = false
    /// Query a saved view just applied: its own sort wins over the Best Match switch.
    @State private var savedViewQuery: String?
    /// Decrypted collection names, rebuilt only when a collection record changes
    /// (no decryption while scrolling).
    @State private var collectionLookupCache = CollectionLookup([])
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var showSearch = false
    @State private var showSearchHelp = false
    @FocusState private var searchFocused: Bool
    @State private var filters = EntryFilterCriteria()
    @State private var showFilters = false
    @State private var filterNow = Date()
    @State private var selectedEntry: Entry?
    @State private var showEntryDetail = false
    @State private var showOnThisDay = false
    @State private var snapshotCache: EntryListSnapshot? = nil
    /// Decrypted mood / tags / search text / row preview per entry, so a snapshot rebuild only
    /// decrypts what changed (memory only; see EntryDecryptCache).
    @State private var decryptCache = EntryDecryptCache()
    @State private var sortOrder: EntrySortOrder = .newestFirst
    // Set right before a pin/unpin toggle so the snapshot recompute (which lands
    // in .task, a separate transaction from the toggle site) animates only that
    // interaction — not every search keystroke, sort change, or tag edit.
    @State private var animatePinChange = false
    // Bumped (only while some entries are unreadable) so the snapshot re-decrypts: a content
    // key can arrive via iCloud Keychain — on a fresh install, or after the user turns it on
    // in Settings — without any entry changing, and the cached row previews would otherwise
    // stay "unavailable". Gated on unreadableCount so a healthy journal is never re-decrypted.
    @State private var foregroundRefresh = 0
    @AppStorage(UnreadableEntriesBanner.dismissedCountKey) private var unreadableBannerDismissedCount = 0
    // Ticks every 30s only while iCloud has pending changes, so the "not backed up" banner
    // appears once a normal upload would have finished (JournalSafety.showsNotBackedUp).
    @State private var backupStatusNow = Date()
    private var journalSafety: JournalSafety { JournalSafety.shared }
    #if os(macOS)
    @State private var macShowCalendar = false
    @FocusState private var macSearchFocused: Bool
    @FocusState private var macListFocused: Bool
    @State private var macPendingDelete: Entry?
    @Environment(\.openWindow) private var openWindow
    #endif

    private enum EntrySortOrder: String, CaseIterable {
        case bestMatch   = "Best Match"
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case mostWords   = "Most Words"
        case byMood      = "By Mood"

        var icon: String {
            switch self {
            case .bestMatch:   return "text.magnifyingglass"
            case .newestFirst: return "arrow.down.circle"
            case .oldestFirst: return "arrow.up.circle"
            case .mostWords:   return "text.word.spacing"
            case .byMood:      return "face.smiling"
            }
        }

        var displayName: LocalizedStringKey {
            switch self {
            case .bestMatch:   return "Best Match"
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
        var isSearchMatch = false
    }

    private struct EntryListSnapshot {
        let filteredEntries: [Entry]
        let usedMoods: [String]
        let usedTags: [String]
        let pinnedEntries: [Entry]
        let groupedByMonth: [EntryMonthGroup]
        let rowPreviews: [UUID: EntryRowPreview]
        let unreadableCount: Int
        /// Results are one ranked list (Best Match), not month sections.
        var isRanked = false
        var matchesWithoutFilters: Int?
    }

    private struct SnapshotDeps: Equatable {
        let search: String
        let filters: EntryFilterCriteria
        let day: Date
        let entryCount: Int
        let contentHash: Int
        let sort: String
        let foregroundRefresh: Int
        let collections: Int
    }

    private var snapshotDeps: SnapshotDeps {
        PerfSignpost.interval("entries.deps") { snapshotDepsValue }
    }

    private var snapshotDepsValue: SnapshotDeps {
        SnapshotDeps(
            search: debouncedSearchText,
            filters: filters,
            day: Calendar.current.startOfDay(for: filterNow),
            entryCount: entries.count,
            contentHash: EntryDecryptCache.contentSignature(for: entries),
            sort: sortOrder.rawValue,
            foregroundRefresh: foregroundRefresh,
            collections: collectionSignature
        )
    }

    private var listSnapshot: EntryListSnapshot { makeListSnapshot() }

    private func makeListSnapshot(searchResults: EntrySearch.Results? = nil) -> EntryListSnapshot {
        let query = EntrySearchQuery.parse(debouncedSearchText)
        var result = entries
        let cache = decryptCache
        cache.prune(keeping: entries)
        let usedMoods = usedMoods(in: entries)
        let usedTags = usedTags(in: entries)

        if let searchResults {
            result = result.filter { searchResults.ids.contains($0.id) }
        } else {
            if filters.isActive {
                let known = Set(collectionModels.map(\.id))
                result = result.filter { filters.matches(cache.item(for: $0).document.resolvingCollection(known), now: filterNow) }
            }
            if !query.isEmpty {
                result = result.filter { EntrySearch.matches(cache.item(for: $0).document, query: query) }
            }
        }

        let ranked = effectiveSortOrder(for: query) == .bestMatch
        switch effectiveSortOrder(for: query) {
        case .bestMatch:
            var scores = searchResults?.scores ?? [:]
            if searchResults == nil {
                for entry in result { scores[entry.id] = EntrySearch.relevance(cache.item(for: entry).document, query: query) }
            }
            // Stable: @Query order is newest first, so equal scores stay newest first.
            result = result.enumerated().sorted { lhs, rhs in
                let l = scores[lhs.element.id] ?? 0, r = scores[rhs.element.id] ?? 0
                return l != r ? l > r : lhs.offset < rhs.offset
            }.map(\.element)
        case .newestFirst: break  // already sorted by @Query
        case .oldestFirst: result = result.sorted { $0.createdAt < $1.createdAt }
        case .mostWords:   result = result.sorted { $0.wordCount > $1.wordCount }
        case .byMood:      result = result.sorted { (cache.item(for: $0).mood ?? "") < (cache.item(for: $1).mood ?? "") }
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
        let groupedByMonth = ranked ? [EntryMonthGroup(date: .distantPast, entries: result.filter { !$0.isPinned })].filter { !$0.entries.isEmpty } : groups.keys.sorted(by: monthSortAscending ? (<) : (>)).map { month in
            let monthEntries = groups[month, default: []]
            let sortedMonthEntries: [Entry]
            switch sortOrder {
            case .bestMatch, .newestFirst: sortedMonthEntries = monthEntries.sorted { $0.createdAt > $1.createdAt }
            case .oldestFirst: sortedMonthEntries = monthEntries.sorted { $0.createdAt < $1.createdAt }
            case .mostWords:   sortedMonthEntries = monthEntries.sorted { $0.wordCount > $1.wordCount }
            case .byMood:      sortedMonthEntries = monthEntries.sorted { (cache.item(for: $0).mood ?? "") < (cache.item(for: $1).mood ?? "") }
            }
            return EntryMonthGroup(date: month, entries: sortedMonthEntries)
        }

        // Precompute all row display data (mood + text decrypts) so EntryRow.init does zero decrypts
        var rowPreviews: [UUID: EntryRowPreview] = [:]
        for entry in entries {
            rowPreviews[entry.id] = cache.item(for: entry).preview
        }
        for entry in result where !query.isEmpty {
            let item = cache.item(for: entry)
            let match = searchResults.map { $0.excerpts[entry.id] }
                ?? EntrySearch.excerpt(item.document, query: query)
            guard let excerpt = match else { continue }
            var attributed = AttributedString(excerpt.text)
            for range in excerpt.highlights {
                guard let stringRange = Range(range, in: excerpt.text),
                      let start = AttributedString.Index(stringRange.lowerBound, within: attributed),
                      let end = AttributedString.Index(stringRange.upperBound, within: attributed) else { continue }
                attributed[start..<end].inlinePresentationIntent = .stronglyEmphasized
                attributed[start..<end].foregroundColor = displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet
            }
            let label: Text
            switch excerpt.source {
            case .body: label = Text("")
            case .transcript(let index): label = Text("Voice note \(index): ")
            case .translation(let index): label = Text("Voice note \(index), English translation: ")
            }
            let preview = item.preview
            rowPreviews[entry.id] = EntryRowPreview(
                moodLabel: preview.moodLabel, preview: label + Text(attributed),
                wordCount: preview.wordCount, hasReadablePreview: true,
                hasVoiceNotes: preview.hasVoiceNotes, textDecryptionFailed: preview.textDecryptionFailed,
                isSearchMatch: true
            )
        }

        // A transcript or tag can arrive before its encryption key even when body
        // text is already readable. Keep the existing key-arrival retry active.
        let unreadableCount = entries.filter { !cache.item(for: $0).document.isReadable }.count
        return EntryListSnapshot(filteredEntries: result, usedMoods: usedMoods, usedTags: usedTags, pinnedEntries: pinnedEntries, groupedByMonth: groupedByMonth, rowPreviews: rowPreviews, unreadableCount: unreadableCount, isRanked: ranked && !result.isEmpty, matchesWithoutFilters: searchResults?.matchesWithoutFilters)
    }

    private var collectionLookup: CollectionLookup { collectionLookupCache }

    private var collectionSignature: Int {
        var hasher = Hasher()
        for collection in collectionModels {
            hasher.combine(collection.id)
            hasher.combine(collection.sortIndex)
            hasher.combine(collection.encryptedPayload)
        }
        return hasher.finalize()
    }

    private var canSaveCurrentView: Bool { filters.isActive || !debouncedSearchText.isEmpty }

    /// Opens a saved view: its search, filters (relative dates recomputed now) and sort.
    private func applySavedView(_ payload: SavedEntryView.Payload) {
        withAnimation(.easeInOut(duration: 0.2)) {
            savedViewQuery = payload.query == debouncedSearchText ? nil : payload.query
            filters = payload.criteria.criteria()
            filterNow = Date()
            searchText = payload.query
            debouncedSearchText = payload.query
            if !payload.query.isEmpty { showSearch = true }
            sortOrder = EntrySortOrder(rawValue: payload.sort) ?? .newestFirst
        }
    }

    private func saveCurrentView(named name: String) {
        let payload = SavedEntryView.Payload(name: name, query: debouncedSearchText,
                                             criteria: SavedCriteria(filters), sort: sortOrder.rawValue)
        try? JournalOrganizationStore.saveView(payload, in: modelContext)
    }

    /// Best Match applies only while the search has words in it; otherwise the
    /// list falls back to newest first.
    private func effectiveSortOrder(for query: EntrySearchQuery) -> EntrySortOrder {
        sortOrder == .bestMatch && !query.hasTextTerms ? .newestFirst : sortOrder
    }

    private var availableSortOrders: [EntrySortOrder] {
        EntrySearchQuery.parse(debouncedSearchText).hasTextTerms
            ? EntrySortOrder.allCases
            : EntrySortOrder.allCases.filter { $0 != .bestMatch }
    }

    /// Starting a word search switches the default order to Best Match; clearing it
    /// switches back. A sort the user picked themselves is left alone.
    private func updateSortForSearch(from old: String, to new: String) {
        let had = EntrySearchQuery.parse(old).hasTextTerms
        let has = EntrySearchQuery.parse(new).hasTextTerms
        if !had, has, sortOrder == .newestFirst { sortOrder = .bestMatch }
        if had, !has, sortOrder == .bestMatch { sortOrder = .newestFirst }
    }

    private func sectionTitle(for group: EntryMonthGroup, ranked: Bool) -> String {
        ranked ? String(localized: "Best matches") : monthTitle(for: group.date)
    }

    // Computed on every render off the existing @Query — cheap (date-component comparison only,
    // no decryption) even for a large journal, and typically yields 0-2 entries.
    private var onThisDayMatches: [Entry] {
        OnThisDayService.matches(in: entries)
    }

    private var trailingToolbar: some View {
        HStack(spacing: 16) {
            filtersButton
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
            SavedViewsMenu(views: savedViewModels, canSaveCurrent: canSaveCurrentView,
                           open: applySavedView, saveCurrent: { savingView = true }, manage: { showOrganizer = true }) {
                Image(systemName: "bookmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
            .accessibilityLabel("Saved views")
            Menu {
                ForEach(availableSortOrders, id: \.self) { order in
                    Button {
                        withAnimation { sortOrder = order }
                    } label: {
                        Label(order.displayName, systemImage: sortOrder == order ? "checkmark" : order.icon)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(displayMode == .sentinel && sortOrder != .newestFirst ? MirrorTheme.ember : Color.primary)
            }
            .accessibilityLabel("Sort by")
            Button {
                withAnimation { showSearch.toggle() }
            } label: {
                Image(systemName: displayMode == .sentinel ? "scope" : "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(displayMode == .sentinel && showSearch ? MirrorTheme.ember : Color.primary)
            }
            .accessibilityLabel("Search entries")
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
                    if !collectionModels.isEmpty {
                        CollectionsBar(lookup: collectionLookup, scope: $filters.collection) { showOrganizer = true }
                    }
                    if !snapshot.usedMoods.isEmpty { moodFilterBar(snapshot.usedMoods) }
                    if !snapshot.usedTags.isEmpty { tagFilterBar(snapshot.usedTags) }
                }
            }
            #endif
            .task(id: searchText) {
                let value = searchText
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard !Task.isCancelled else { return }
                debouncedSearchText = value
            }
            .onChange(of: debouncedSearchText) { old, new in
                if let applied = savedViewQuery, applied == new {
                    savedViewQuery = nil
                    return
                }
                updateSortForSearch(from: old, to: new)
            }
            .task(id: collectionSignature) { collectionLookupCache = CollectionLookup(collectionModels) }
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
            .sheet(isPresented: $showOrganizer) { OrganizationManagerSheet() }
            .modifier(OrganizationPrompts(newCollectionFor: $newCollectionFor, savingView: $savingView, saveView: saveCurrentView))
            .sheet(isPresented: $showFilters) {
                EntryFiltersView(criteria: filters, moods: snapshot.usedMoods, tags: snapshot.usedTags) {
                    filters = $0
                    filterNow = Date()
                }
            }
            .task(id: filters.dateScope) {
                guard filters.isRelativeDate else { return }
                while !Task.isCancelled {
                    let now = Date()
                    filterNow = now
                    guard let tomorrow = Calendar.current.dateInterval(of: .day, for: now)?.end else { return }
                    do { try await Task.sleep(for: .seconds(max(1, tomorrow.timeIntervalSince(now)))) }
                    catch { return }
                }
            }
            .task(id: snapshotDeps) {
                let query = EntrySearchQuery.parse(debouncedSearchText)
                let readerTerms = query.problem == nil ? ReaderSearchHighlight.terms(for: query) : []
                if ReaderSearchHighlight.shared.terms != readerTerms { ReaderSearchHighlight.shared.terms = readerTerms }
                var searchResults: EntrySearch.Results?
                if !query.isEmpty || filters.isActive {
                    decryptCache.prune(keeping: entries)
                    let documents = entries.map { ($0.id, decryptCache.item(for: $0).document) }
                    let criteria = filters
                    let now = filterNow
                    let calendar = Calendar.current
                    let known = Set(collectionModels.map(\.id))
                    let worker = Task.detached(priority: .userInitiated) {
                        EntrySearch.evaluate(documents, query: query, filters: criteria, now: now, calendar: calendar,
                                             knownCollections: known)
                    }
                    searchResults = await PerfSignpost.interval("entries.search") {
                        await withTaskCancellationHandler {
                            await worker.value
                        } onCancel: { worker.cancel() }
                    }
                }
                guard !Task.isCancelled else { return }
                let newSnapshot = PerfSignpost.interval("entries.snapshot") { makeListSnapshot(searchResults: searchResults) }
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
                if let open = note.userInfo?["filters"] as? Bool { showFilters = open }
                if let moods = note.userInfo?["filterMoods"] as? [String] { filters.moods = Set(moods) }
                if let id = note.userInfo?["collection"] as? UUID { filters.collection = .collection(id) }
                if let open = note.userInfo?["organizer"] as? Bool { showOrganizer = open }
                if let name = note.userInfo?["applySavedViewNamed"] as? String,
                   let payload = savedViewModels.compactMap(\.payload).first(where: { $0.name == name }) {
                    applySavedView(payload)
                }
                if note.userInfo?["selectFirstResult"] as? Bool == true, let snapshotCache {
                    macSelection?.wrappedValue = macOrderedEntries(snapshotCache).first
                }
            }
            #endif
            #endif
            .task(id: journalSafety.hasPendingChanges) {
                backupStatusNow = Date()
                while journalSafety.hasPendingChanges, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    backupStatusNow = Date()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { filterNow = Date() }
                if phase == .active, (snapshotCache?.unreadableCount ?? 0) > 0 { foregroundRefresh &+= 1 }
            }
            // On a fresh install CloudKit often delivers entries before iCloud Keychain delivers
            // the key. Re-check for a couple of minutes so the rows (and the banner) clear on
            // their own instead of waiting for the next foreground.
            .task(id: (snapshotCache?.unreadableCount ?? 0) > 0) {
                guard (snapshotCache?.unreadableCount ?? 0) > 0 else { return }
                for _ in 0..<12 {
                    try? await Task.sleep(for: .seconds(10))
                    if Task.isCancelled { return }
                    foregroundRefresh &+= 1
                }
            }
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

    private func unreadableBanner(_ snapshot: EntryListSnapshot) -> some View {
        UnreadableEntriesBanner(unreadableCount: snapshot.unreadableCount) {
            unreadableBannerDismissedCount = snapshot.unreadableCount
        }
    }

    @ViewBuilder
    private var activeFiltersRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                activeFilterChips
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    clearFiltersAndSearch()
                }
            } label: {
                Group {
                    if displayMode == .sentinel {
                        Text("Clear All").textCase(.uppercase).font(MirrorTheme.mono(11, weight: .medium))
                    } else {
                        Text("Clear All").font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filter.clearAll")
        }
    }

    private var activeFilterChips: some View {
        HStack(spacing: 8) {
            if filters.collection != .all {
                filterChip(label: collectionLookup.label(for: filters.collection), systemImage: "folder") { filters.collection = .all }
            }
            if filters.dateScope != .allTime {
                filterChip(label: dateFilterLabel, systemImage: "calendar") { filters.selectDay(nil) }
            }
            ForEach(filters.moods.sorted(), id: \.self) { mood in
                filterChip(
                    label: MirrorTheme.localizedMoodName(for: mood),
                    systemImage: "circle.fill",
                    color: MirrorTheme.moodColor(for: mood)
                ) { filters.moods.remove(mood) }
            }
            if !filters.tags.isEmpty {
                let names = filters.tags.sorted().map { "#\(MirrorTheme.localizedTagName(for: $0))" }.joined(separator: ", ")
                let mode = filters.tagMatch == .any ? String(localized: "Any selected tag") : String(localized: "All selected tags")
                filterChip(label: "\(mode): \(names)", systemImage: "tag") { filters.tags = [] }
            }
            if filters.photosOnly {
                filterChip(label: String(localized: "With photos"), systemImage: "photo") { filters.photosOnly = false }
            }
            if filters.audioOnly {
                filterChip(label: String(localized: "With voice notes"), systemImage: "waveform") { filters.audioOnly = false }
            }
            if filters.pinnedOnly {
                filterChip(label: String(localized: "Pinned only"), systemImage: "pin") { filters.pinnedOnly = false }
            }
            if !searchText.isEmpty {
                filterChip(label: searchText, systemImage: "magnifyingglass") { searchText = ""; debouncedSearchText = "" }
            }
        }
    }

    private func clearFiltersAndSearch() {
        filters = EntryFilterCriteria()
        searchText = ""
        debouncedSearchText = ""
        searchFocused = false
    }

    private var dateFilterLabel: String {
        switch filters.dateScope {
        case .allTime: return String(localized: "All time")
        case .today: return String(localized: "Today")
        case .thisWeek: return String(localized: "This week")
        case .thisMonth: return String(localized: "This month")
        case .range:
            let start = filters.startDate?.formatted(.dateTime.month(.abbreviated).day().year())
            let end = filters.endDate?.formatted(.dateTime.month(.abbreviated).day().year())
            if let start, let end { return "\(start) – \(end)" }
            if let start { return String(localized: "From \(start)") }
            if let end { return String(localized: "Through \(end)") }
            return String(localized: "Date range")
        }
    }

    private var filtersButton: some View {
        Button {
            searchFocused = false
            #if os(macOS)
            macSearchFocused = false
            #endif
            showFilters = true
        } label: {
            Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundStyle(filters.isActive ? (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet) : Color.primary)
        }
        .accessibilityLabel("Filter entries")
        .accessibilityIdentifier("filter.open")
        .help("Filter entries")
    }

    private func filterChip(
        label: String,
        systemImage: String,
        color: Color? = nil,
        onRemove: @escaping () -> Void
    ) -> some View {
        let color = color ?? (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet)
        return Button(action: onRemove) {
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
        let all = entries.compactMap { decryptCache.item(for: $0).mood }.filter { !$0.isEmpty }
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    private func usedTags(in entries: [Entry]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            for tag in decryptCache.item(for: entry).tags where seen.insert(tag).inserted {
                result.append(tag)
            }
        }
        return result
    }

    private func tagFilterBar(_ usedTags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(usedTags, id: \.self) { tag in
                    let isSelected = filters.tags.contains(tag)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSelected { filters.tags.remove(tag) } else { filters.tags.insert(tag) }
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
                    let isSelected = filters.moods.contains(mood)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSelected { filters.moods.remove(mood) } else { filters.moods.insert(mood) }
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
            .focused($searchFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            searchHelpButton
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
        .onAppear { searchFocused = true }
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
            .contextMenu {
                MoveToCollectionMenu(entry: entry, lookup: collectionLookup) { newCollectionFor = entry }
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(macSelection?.wrappedValue?.id == entry.id ? MirrorTheme.violet.opacity(0.16) : Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    WriteDraftStore.clearIncludingPreserved(slot: .entry(entry.id))
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
                    selectedDate: filters.selectedDay,
                    onDaySelected: { date in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filters.selectDay(date)
                        }
                    }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if journalSafety.restoreOffer != nil {
                Section {
                    RestoreFromDeviceBanner()
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            if journalSafety.showsNotBackedUp(now: backupStatusNow) {
                Section {
                    NotBackedUpBanner(uploadFailing: journalSafety.lastExportFailed)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            if UnreadableEntriesBanner.shouldShow(unreadableCount: snapshot.unreadableCount, dismissedCount: unreadableBannerDismissedCount) {
                Section {
                    unreadableBanner(snapshot)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            // Active filters row
            if filters.isActive || !searchText.isEmpty {
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
                if let count = snapshot.matchesWithoutFilters, count > 0 {
                    relaxFiltersButton(count)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
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
                                Text(sectionTitle(for: group, ranked: snapshot.isRanked)).font(MirrorTheme.mono(13, weight: .bold)).tracking(1.5)
                            } else {
                                Text(sectionTitle(for: group, ranked: snapshot.isRanked)).font(.system(size: 13, weight: .black, design: .rounded)).tracking(1.5)
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

    /// The search matches entries the filters hide: offer to keep the search and
    /// drop the filters, instead of leaving the user to guess which one to remove.
    private func relaxFiltersButton(_ count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { filters = EntryFilterCriteria() }
        } label: {
            Group {
                if displayMode == .sentinel {
                    Text("Search without filters (\(count))").font(MirrorTheme.mono(12, weight: .semibold)).textCase(.uppercase)
                } else {
                    Text("Search without filters (\(count))").font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.relaxFilters")
    }

    private var emptyFilteredMessage: LocalizedStringKey {
        if let problem = EntrySearchQuery.parse(debouncedSearchText).problem {
            switch problem {
            case .unfinishedQuote: return "Close the quotation marks to search."
            case .missingValue: return "Add a value after the search filter."
            case .unknownFilter: return "Unknown search filter. Open Search help for supported filters."
            case .invalidDate: return "Use a valid date in YYYY-MM-DD format."
            case .invalidValue: return "Unsupported filter value. Open Search help for examples."
            }
        }
        if !debouncedSearchText.isEmpty && filters.isActive { return "No entries match your search with these filters." }
        if !debouncedSearchText.isEmpty { return "No entries match your search" }
        if filters.isActive { return "No entries match these filters. Remove a filter or clear all to see more entries." }
        return "No entries match your search"
    }

    private var searchHelpButton: some View {
        Button { showSearchHelp = true } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search help")
        .popover(isPresented: $showSearchHelp) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Search help").font(.headline)
                Text("All words must match. Use quotes for a phrase and a minus sign to exclude a word.")
                Text(verbatim: "coffee river\n\"work trip\" -meeting\ntag:work mood:Content\nhas:photo has:audio is:pinned\nafter:2026-09-01 before:2026-10-01")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("Date filters exclude the named day. Tags and moods must match the full name. You can also use mood names in your language.")
                Button("Done") { showSearchHelp = false }
            }
            .padding(20)
            .frame(idealWidth: 320, maxWidth: 360)
        }
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
            if !collectionModels.isEmpty {
                CollectionsBar(lookup: collectionLookup, scope: $filters.collection) { showOrganizer = true }
            }
            macCalendarDisclosure
            if macShowCalendar {
                VStack(spacing: 8) {
                    CalendarHeatmap(
                        entries: entries,
                        selectedDate: filters.selectedDay,
                        onDaySelected: { date in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                filters.selectDay(date)
                            }
                        }
                    )
                }
                .padding(.bottom, 8)
            }

            if filters.isActive || !searchText.isEmpty {
                activeFiltersRow.padding(.horizontal, 12).padding(.vertical, 8)
            }

            Group {
                if journalSafety.restoreOffer != nil {
                    RestoreFromDeviceBanner()
                }
                if journalSafety.showsNotBackedUp(now: backupStatusNow) {
                    NotBackedUpBanner(uploadFailing: journalSafety.lastExportFailed)
                }
                if UnreadableEntriesBanner.shouldShow(unreadableCount: snapshot.unreadableCount, dismissedCount: unreadableBannerDismissedCount) {
                    unreadableBanner(snapshot)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
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
                        if let count = snapshot.matchesWithoutFilters, count > 0 {
                            relaxFiltersButton(count).frame(maxWidth: .infinity).padding(.top, 8)
                        }
                    }
                    ForEach(snapshot.groupedByMonth, id: \.date) { group in
                        macSectionLabel(sectionTitle(for: group, ranked: snapshot.isRanked).uppercased(), icon: nil, topPadding: 14)
                        ForEach(group.entries) { entry in
                            macRow(entry, snapshot: snapshot)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .modifier(MacNoScrollEdgeEffect())
            // Keyboard: arrows move through the list, Return edits, Delete asks first.
            .focusable()
            .focusEffectDisabled()
            .focused($macListFocused)
            .onKeyPress(.upArrow) { macMoveSelection(-1, snapshot); return .handled }
            .onKeyPress(.downArrow) { macMoveSelection(1, snapshot); return .handled }
            .onKeyPress(.return) {
                #if DEBUG
                NSLog("EntryList return key")
                #endif
                guard macSelection?.wrappedValue != nil else { return .ignored }
                NotificationCenter.default.post(name: .mirrorMacEditEntry, object: nil)
                return .handled
            }
            .onDeleteCommand { _ = macAskToDeleteSelection() }
            .onChange(of: macSelection?.wrappedValue?.id) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            }
            .confirmationDialog("Delete this entry?", isPresented: Binding(get: { macPendingDelete != nil }, set: { if !$0 { macPendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { macDeletePending(snapshot) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will be removed from this Mac and your other devices.")
            }
        }
        .background(MirrorTheme.inkMid)
        .overlay(alignment: .trailing) { Rectangle().fill(MacTokens.divider).frame(width: 1) }
        // Arrow keys work as soon as the list is on screen.
        .onAppear { macListFocused = true }
    }

    /// The rows in the order they are drawn: pinned first, then each month.
    private func macOrderedEntries(_ snapshot: EntryListSnapshot) -> [Entry] {
        var seen = Set<UUID>()
        return (snapshot.pinnedEntries + snapshot.groupedByMonth.flatMap(\.entries)).filter { seen.insert($0.id).inserted }
    }

    private func macMoveSelection(_ step: Int, _ snapshot: EntryListSnapshot) {
        let ordered = macOrderedEntries(snapshot)
        guard !ordered.isEmpty else { return }
        let current = macSelection?.wrappedValue.flatMap { selected in ordered.firstIndex { $0.id == selected.id } }
        let next = current.map { min(max($0 + step, 0), ordered.count - 1) } ?? (step > 0 ? 0 : ordered.count - 1)
        #if DEBUG
        NSLog("EntryList key move: %@ -> %d of %d", current.map(String.init) ?? "none", next, ordered.count)
        #endif
        macSelection?.wrappedValue = ordered[next]
    }

    private func macAskToDeleteSelection() -> KeyPress.Result {
        #if DEBUG
        NSLog("EntryList delete key: selection %@", macSelection?.wrappedValue == nil ? "none" : "set")
        #endif
        guard let selected = macSelection?.wrappedValue else { return .ignored }
        macPendingDelete = selected
        return .handled
    }

    /// Deletes, then selects the neighbouring entry, the way Notes does.
    private func macDeletePending(_ snapshot: EntryListSnapshot) {
        guard let entry = macPendingDelete else { return }
        let ordered = macOrderedEntries(snapshot)
        let index = ordered.firstIndex { $0.id == entry.id }
        let neighbour = index.flatMap { i in ordered.indices.contains(i + 1) ? ordered[i + 1] : (i > 0 ? ordered[i - 1] : nil) }
        macSelection?.wrappedValue = neighbour
        WriteDraftStore.clearIncludingPreserved(slot: .entry(entry.id))
        modelContext.delete(entry)
        try? modelContext.save()
        macPendingDelete = nil
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
            SavedViewsMenu(views: savedViewModels, canSaveCurrent: canSaveCurrentView,
                           open: applySavedView, saveCurrent: { savingView = true }, manage: { showOrganizer = true }) {
                Image(systemName: "bookmark")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(MacTokens.controlInk)
            .help("Saved views")
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
                ForEach(availableSortOrders, id: \.self) { order in
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
                        Button(MirrorTheme.localizedMoodName(for: mood)) { filters.moods = [mood] }
                    }
                }
            }
            let tags = usedTags(in: entries)
            if !tags.isEmpty {
                Menu("Show only tag") {
                    ForEach(tags, id: \.self) { tag in
                        Button("#\(MirrorTheme.localizedTagName(for: tag))") { filters.tags = [tag] }
                    }
                }
            }
            if filters.isActive || !searchText.isEmpty {
                Button("Clear filters") {
                    clearFiltersAndSearch()
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
                .onKeyPress(.escape) {
                    searchText = ""
                    macListFocused = true
                    return .handled
                }
            filtersButton.buttonStyle(.plain)
            if searchText.isEmpty {
                Text("⌘F").font(.system(size: 11))
            } else {
                Button {
                    searchText = ""
                    macSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 20, height: 22)
                }
                .buttonStyle(MacHoverButtonStyle())
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
            searchHelpButton
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
            .onTapGesture { open(entry); macListFocused = true }
            .contextMenu {
                Button("Edit") {
                    open(entry)
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .mirrorMacEditEntry, object: nil) }
                }
                Button("Open in New Window") { openWindow(id: "entry", value: entry.id) }
                Divider()
                Button(entry.isPinned ? "Unpin" : "Pin") {
                    animatePinChange = true
                    entry.isPinned.toggle()
                    try? modelContext.save()
                }
                if let mood = entry.mood, !mood.isEmpty {
                    Button("Show only \(MirrorTheme.localizedMoodName(for: mood))") { filters.moods = [mood] }
                }
                MoveToCollectionMenu(entry: entry, lookup: collectionLookup) { newCollectionFor = entry }
                Divider()
                Button("Share as text") {
                    let day = entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
                    presentShareSheet(items: ["\(day)\n\n\(entry.text)"])
                }
                Divider()
                Button("Delete", role: .destructive) {
                    // Clear the selection first so the reader never renders a deleted entry.
                    if isSelected { macSelection?.wrappedValue = nil }
                    WriteDraftStore.clearIncludingPreserved(slot: .entry(entry.id))
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
    @State private var hovered = false

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
                .lineLimit(preview?.isSearchMatch == true ? 2 : 1)
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
        .background(isSelected ? MacTokens.selectedRowFill : hovered ? MacTokens.controlInk.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(MacTokens.selectedRowBorder, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
#endif

/// Per-entry decrypted values for the entry list (mood, tags, the text search matches against, and the
/// row preview), so rebuilding the list after a search keystroke or filter change decrypts only entries
/// that are new or changed. Memory only: never written to disk or logged (decrypted journal text).
/// A failed text decrypt is never cached, so an entry whose key arrives later (iCloud Keychain) is
/// decrypted again on the next rebuild and the unreadable-entries banner can clear.
final class EntryDecryptCache {
    struct Item {
        let signature: Int
        let mood: String?
        let tags: [String]
        let searchText: String
        let document: EntrySearchDocument
        let preview: EntriesTabView.EntryRowPreview
    }

    private var items: [UUID: Item] = [:]

    /// Changes to any encrypted field the list reads change the signature.
    static func signature(of entry: Entry) -> Int {
        var h = Hasher()
        h.combine(entry.encryptedText)
        h.combine(entry.encryptedMood)
        h.combine(entry.encryptedTagsStorage)
        h.combine(entry.encryptedVoiceNoteTranscript)
        h.combine(entry.encryptedAdditionalVoiceNoteTranscriptsStorage)
        h.combine(entry.encryptedVoiceNoteEnglishTranslation)
        h.combine(entry.encryptedAdditionalVoiceNoteEnglishTranslationsStorage)
        h.combine(entry.encryptedVoiceNoteLanguageName)
        h.combine(entry.encryptedAdditionalVoiceNoteLanguageNamesStorage)
        h.combine(entry.encryptedTextStyleData)
        h.combine(entry.encryptedInlineStyleData)
        h.combine(entry.fontChoice)
        h.combine(entry.wordCount)
        h.combine(entry.createdAt)
        h.combine(entry.isPinned)
        h.combine(entry.collectionID)
        h.combine(entry.voiceNoteDuration)
        h.combine(entry.additionalVoiceNoteDurationsStorage)
        h.combine(entry.encryptedVoiceNoteData != nil)
        h.combine(entry.encryptedAdditionalVoiceNoteDataStorage?.count)
        h.combine(entry.encryptedPhotoData?.count)
        h.combine(entry.encryptedAdditionalPhotoDataStorage?.count)
        return h.finalize()
    }

    static func contentSignature(for entries: [Entry]) -> Int {
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.id)
            hasher.combine(signature(of: entry))
        }
        return hasher.finalize()
    }

    func item(for entry: Entry) -> Item {
        let sig = Self.signature(of: entry)
        if let cached = items[entry.id], cached.signature == sig { return cached }
        let preview = EntryRow.makePreview(for: entry)
        let failed = entry.textDecryptionFailed
        let mood = entry.mood
        let tags = entry.tags
        var passages: [EntrySearchDocument.Passage] = []
        let text = textWithPhotoTokensReplaced(entry.text)
        if !text.isEmpty { passages.append(.init(text, source: .body)) }
        let transcripts = [entry.voiceNoteTranscript ?? ""] + entry.additionalVoiceNoteTranscripts
        let translations = [entry.voiceNoteEnglishTranslation ?? ""] + entry.additionalVoiceNoteEnglishTranslations
        for (index, transcript) in transcripts.enumerated() where !transcript.isEmpty {
            passages.append(.init(transcript, source: .transcript(index + 1)))
        }
        for (index, translation) in translations.enumerated() where !translation.isEmpty {
            passages.append(.init(translation, source: .translation(index + 1)))
        }
        let encryptedSearchStrings = [entry.encryptedText, entry.encryptedMood,
            entry.encryptedVoiceNoteTranscript, entry.encryptedVoiceNoteEnglishTranslation].compactMap { $0 }
            + [entry.encryptedTagsStorage, entry.encryptedAdditionalVoiceNoteTranscriptsStorage,
               entry.encryptedAdditionalVoiceNoteEnglishTranslationsStorage].compactMap { data -> [String]? in
                guard let data else { return nil }
                return try? JSONDecoder().decode([String].self, from: data)
            }.flatMap { $0 }
        let searchReadable = !encryptedSearchStrings.contains { MirrorEncryption.encryptedStringNeedsUnavailableKey($0) }
        let additionalPhotos = entry.encryptedAdditionalPhotoDataStorage.flatMap {
            try? JSONDecoder().decode([Data].self, from: $0)
        } ?? []
        let document = EntrySearchDocument(
            passages: passages,
            tags: tags.map(EntrySearch.fold),
            moods: mood.map { [EntrySearch.fold($0), EntrySearch.fold(MirrorTheme.localizedMoodName(for: $0))] } ?? [],
            createdAt: entry.createdAt,
            hasPhoto: entry.hasPhoto || !additionalPhotos.isEmpty,
            hasAudio: entry.hasVoiceNotes, isPinned: entry.isPinned, isReadable: searchReadable,
            collectionID: entry.collectionID
        )
        let item = Item(
            signature: sig,
            mood: mood,
            tags: tags,
            searchText: passages.map(\.text).joined(separator: "\n\n"),
            document: document,
            preview: EntriesTabView.EntryRowPreview(
                moodLabel: entry.mood.flatMap { $0.isEmpty ? nil : $0 },
                preview: preview.preview,
                wordCount: preview.wordCount,
                hasReadablePreview: preview.hasReadablePreview,
                hasVoiceNotes: preview.hasVoiceNotes,
                textDecryptionFailed: failed
            )
        )
        if !failed && searchReadable { items[entry.id] = item } else { items[entry.id] = nil }
        return item
    }

    /// How many entries are cached (tests).
    var cachedCount: Int { items.count }

    /// Drops deleted entries.
    func prune(keeping entries: [Entry]) {
        let live = Set(entries.map(\.id))
        items = items.filter { live.contains($0.key) }
    }
}
