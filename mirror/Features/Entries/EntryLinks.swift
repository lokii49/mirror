import SwiftUI
import SwiftData

/// Links between entries (3.1.8, item 5). A link is an ordinary inline link whose URL is
/// `mirror://entry/<id>`, so it round-trips through the editors, sync, export and older app
/// versions (which already open that URL). Only links the person made count: nothing is inferred.
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

    /// Entries whose own links point at `target`, newest first. Only entries that carry inline
    /// styles are decrypted.
    @MainActor
    static func backlinks(to target: UUID, in context: ModelContext) -> [Backlink] {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.encryptedInlineStyleData != nil },
                                                sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.propertiesToFetch = [\.id, \.createdAt, \.encryptedInlineStyleData]
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.compactMap { entry in
            guard entry.id != target,
                  let ranges = NoteEditorCodec.decodeInlineStyleDocument(entry.inlineStyleData)?.ranges,
                  ranges.contains(where: { entryID(from: $0.linkURL) == target }) else { return nil }
            return Backlink(id: entry.id, createdAt: entry.createdAt, title: title(of: entry))
        }
    }

    /// An entry's first non-empty line, without photo tokens, for lists of links.
    static func title(of entry: Entry) -> String {
        let line = entry.text
            .replacingOccurrences(of: #"\[\[mirror-photo[^\]]*\]\]"#, with: "", options: .regularExpression)
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

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard let id = EntryLinks.entryID(from: url) else { return .systemAction }
                var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0 {
                    EntryLinks.open(id)
                } else {
                    missing = true
                }
                return .handled
            })
            .alert("Entry not found", isPresented: $missing) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The linked entry was deleted, or hasn't synced to this device yet.")
            }
    }
}

/// "Linked from": entries that link here, in the reader.
struct LinkedFromSection: View {
    let entryID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @State private var links: [EntryLinks.Backlink] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always present, so the task runs even while there's nothing to show (a task on an
            // empty Group never fires).
            Color.clear
                .frame(height: 0)
                .task(id: TaskKey(entryID: entryID, revision: JournalRevision.shared.value)) {
                    links = EntryLinks.backlinks(to: entryID, in: modelContext)
                }
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(displayMode == .sentinel ? "LINKED FROM" : "Linked from", systemImage: "arrow.turn.up.left")
                        .scaledFont(12, weight: .bold, design: displayMode == .sentinel ? .monospaced : .default)
                        .foregroundStyle(MirrorTheme.textTertiary)
                        .tracking(0.6)
                    ForEach(links) { link in
                        Button { EntryLinks.open(link.id) } label: {
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
                    ContentUnavailableView.search(text: query)
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
            .task(id: query) {
                // A short pause so typing doesn't search on every key.
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                guard !Task.isCancelled else { return }
                let pool = entries.filter { $0.id != excluding && !$0.textDecryptionFailed }
                let found = query.trimmingCharacters(in: .whitespaces).isEmpty
                    ? Array(pool.prefix(50))
                    : Array(SearchService.filter(query: query, in: pool).prefix(50))
                shown = found.map { .init(id: $0.id, createdAt: $0.createdAt, title: EntryLinks.title(of: $0)) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }
}
