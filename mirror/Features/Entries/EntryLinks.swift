import SwiftUI
import SwiftData

/// Links between entries (3.1.8, item 5). A link is an ordinary inline link whose URL is
/// `mirror://entry/<id>`, so it round-trips through 3.1.8's editors, sync and export. Versions
/// before 3.1.8 (iOS 3.1.7, Mac 1.1.7) accept only http(s) links: their reader shows the linked
/// words as plain text, and their editors drop the link from `inlineStyleData` on the first edit
/// of that entry, for every device once it syncs. Text and other styles are kept. Only links the
/// person made count: nothing is inferred.
enum EntryLinks {
    static func urlString(for id: UUID) -> String { "mirror://entry/\(id.uuidString)" }

    /// The entry a `mirror://entry/<id>` URL points at.
    static func entryID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "mirror", url.host?.lowercased() == "entry",
              let first = url.pathComponents.dropFirst().first else { return nil }
        return UUID(uuidString: first)
    }

    static func entryID(from urlString: String?) -> UUID? {
        urlString.flatMap(URL.init(string:)).flatMap(entryID(from:))
    }

    struct Backlink: Identifiable, Equatable {
        let id: UUID
        let createdAt: Date
        let title: String
    }

    /// Entries whose own links point at `target`, newest first, built for every target at once and
    /// kept per journal revision and container: the reader asks on every open and every save, and
    /// each build decrypts every entry that carries inline styles (code review, 2026-11-06).
    @MainActor private static var cache: (revision: Int, container: ObjectIdentifier, byTarget: [UUID: [Backlink]])?

    @MainActor
    static func cachedBacklinks(to target: UUID, in context: ModelContext) -> [Backlink] {
        let revision = JournalRevision.shared.value
        let container = ObjectIdentifier(context.container)
        if let cache, cache.revision == revision, cache.container == container {
            return cache.byTarget[target] ?? []
        }
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.encryptedInlineStyleData != nil },
                                                sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.propertiesToFetch = [\.id, \.createdAt, \.encryptedInlineStyleData]
        var byTarget: [UUID: [Backlink]] = [:]
        for entry in (try? context.fetch(descriptor)) ?? [] {
            guard let ranges = NoteEditorCodec.decodeInlineStyleDocument(entry.inlineStyleData)?.ranges else { continue }
            let targets = Set(ranges.compactMap { entryID(from: $0.linkURL) }).subtracting([entry.id])
            guard !targets.isEmpty else { continue }
            let link = Backlink(id: entry.id, createdAt: entry.createdAt, title: title(of: entry))
            for target in targets { byTarget[target, default: []].append(link) }
        }
        cache = (revision, container, byTarget)
        return byTarget[target] ?? []
    }

    /// An entry's first non-empty line, without photo tokens, for lists of links.
    static func title(of entry: Entry) -> String {
        let line = entry.text
            .replacingPhotoTokens()
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !line.isEmpty else { return String(localized: "Untitled entry") }
        guard line.count > 120 else { return line }
        // At a word boundary, so a title never ends mid-word.
        let cut = line.prefix(120)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }

    /// Opens an entry from a link: the Mac's reader pane, or the Entries tab on iPhone and iPad.
    @MainActor
    static func open(_ id: UUID) {
        #if os(macOS)
        NotificationCenter.default.post(name: .mirrorMacOpenEntry, object: nil, userInfo: ["id": id])
        #else
        NotificationCenter.default.post(name: .mirrorOpenEntryFromLibrary, object: id)
        #endif
    }
}

/// Entry links open inside the app (the system could hand `mirror://` to another installed copy);
/// a link to an entry that's gone says so instead of doing nothing.
struct EntryLinkRouting: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @State private var missing = false
    /// iPhone and iPad: the linked entry is pushed on top of this reader, so Back returns here
    /// (it used to replace the open entry; code review, 2026-11-06).
    @State private var pushed: UUID?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard let id = EntryLinks.entryID(from: url) else { return .systemAction }
                var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0 {
                    #if os(iOS)
                    pushed = id
                    #else
                    EntryLinks.open(id)
                    #endif
                } else {
                    missing = true
                }
                return .handled
            })
            #if os(iOS)
            .navigationDestination(item: $pushed) { id in LinkedEntryReader(entryID: id) }
            #endif
            .alert("Entry not found", isPresented: $missing) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The linked entry was deleted, or hasn't synced to this device yet.")
            }
    }
}

/// A linked entry's reader, pushed from a link (iPhone and iPad).
struct LinkedEntryReader: View {
    @Query private var matches: [Entry]

    init(entryID: UUID) {
        _matches = Query(filter: #Predicate<Entry> { $0.id == entryID })
    }

    var body: some View {
        if let entry = matches.first {
            EntryDetailView(entry: entry)
        } else {
            ContentUnavailableView("Entry not found", systemImage: "link",
                                   description: Text("The linked entry was deleted, or hasn't synced to this device yet."))
        }
    }
}

/// "Linked from": entries that link here, in the reader.
struct LinkedFromSection: View {
    let entryID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.appDisplayMode) private var displayMode
    @State private var links: [EntryLinks.Backlink] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always present, so the task runs even while there's nothing to show (a task on an
            // empty Group never fires).
            Color.clear
                .frame(height: 0)
                .task(id: TaskKey(entryID: entryID, revision: JournalRevision.shared.value)) {
                    links = EntryLinks.cachedBacklinks(to: entryID, in: modelContext)
                }
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(displayMode == .sentinel ? "LINKED FROM" : "Linked from", systemImage: "arrow.turn.up.left")
                        .scaledFont(12, weight: .bold, design: displayMode == .sentinel ? .monospaced : .default)
                        .foregroundStyle(MirrorTheme.textTertiary)
                        .tracking(0.6)
                    ForEach(links) { link in
                        // Through the reader's link routing: pushed on iPhone and iPad, the pane on Mac.
                        Button { if let url = URL(string: EntryLinks.urlString(for: link.id)) { openURL(url) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.title)
                                    .scaledFont(15, weight: .medium)
                                    .foregroundStyle(MirrorTheme.textPrimary)
                                    .lineLimit(2)
                                Text(link.createdAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                                    .scaledFont(12)
                                    .foregroundStyle(MirrorTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens that entry")
                    }
                }
            }
        }
    }

    private struct TaskKey: Hashable { var entryID: UUID; var revision: Int }
}

/// Picks the entry a link points at: the newest entries, or those matching a search.
struct EntryLinkPicker: View {
    /// The entry being written (not offered).
    var excluding: UUID?
    let onPick: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var query = ""
    @State private var shown: [EntryLinks.Backlink] = []
    /// Built once when the sheet opens (each entry decrypted once); typing filters these strings off
    /// the main actor (code review, 2026-11-06: it re-decrypted the whole journal per search).
    /// Entries are main-actor models, so the build runs there in short chunks that yield, and the
    /// newest entries show before it finishes (audit, 2026-11-06: one pass froze large journals).
    @State private var index: [(item: EntryLinks.Backlink, text: String)]?
    /// The first page, shown at once (titles only).
    @State private var newest: [EntryLinks.Backlink] = []

    var body: some View {
        NavigationStack {
            List(shown) { item in
                Button {
                    onPick(item.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).foregroundStyle(.primary).lineLimit(2)
                        Text(item.createdAt, format: .dateTime.day().month(.abbreviated).year())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if shown.isEmpty {
                    if index == nil {
                        ProgressView()
                    } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView("No entries to link", systemImage: "link")
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: Text("Search entries"))
            .navigationTitle("Link to an Entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                // The newest page first, then the whole index in chunks that let the sheet scroll
                // and take typing meanwhile. Runs once per open.
                var built: [(item: EntryLinks.Backlink, text: String)] = []
                built.reserveCapacity(entries.count)
                for (n, entry) in entries.enumerated() {
                    guard entry.id != excluding, !entry.textDecryptionFailed else { continue }
                    let item = EntryLinks.Backlink(id: entry.id, createdAt: entry.createdAt, title: EntryLinks.title(of: entry))
                    built.append((item, (entry.insightContext + " " + entry.tags.joined(separator: " ")).lowercased()))
                    if built.count == 50, newest.isEmpty {
                        newest = built.map(\.item)
                        if query.isEmpty { shown = newest }
                    }
                    if n % 100 == 99 {
                        await Task.yield()
                        if Task.isCancelled { return }
                    }
                }
                index = built
            }
            .task(id: TaskKey(query: query, ready: index != nil)) {
                let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
                guard !needle.isEmpty else {
                    shown = index.map { Array($0.prefix(50).map(\.item)) } ?? newest
                    return
                }
                // A short pause so typing doesn't search on every key.
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let all = index else { return }
                let tag = needle.hasPrefix("#") ? String(needle.dropFirst()) : needle
                let found = await Task.detached(priority: .userInitiated) {
                    Array(all.lazy.filter { $0.text.contains(needle) || (!tag.isEmpty && $0.text.contains(tag)) }.prefix(50).map(\.item))
                }.value
                guard !Task.isCancelled else { return }
                shown = found
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    private struct TaskKey: Hashable { var query: String; var ready: Bool }
}
