import SwiftUI
import SwiftData

/// Drafts, Duplicates and Recently Deleted: opened from the Saved views menu and from Organize.
enum LibraryPage: String, Identifiable, CaseIterable {
    case drafts, duplicates, recentlyDeleted
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .drafts: return "Drafts"
        case .duplicates: return "Duplicates"
        case .recentlyDeleted: return "Recently Deleted"
        }
    }

    var icon: String {
        switch self {
        case .drafts: return "doc.text"
        case .duplicates: return "square.on.square"
        case .recentlyDeleted: return "trash"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .drafts: DraftsView()
        case .duplicates: DuplicatesView()
        case .recentlyDeleted: RecentlyDeletedView()
        }
    }
}

/// One library page in a sheet of its own (from the Saved views menu).
struct LibrarySheet: View {
    let page: LibraryPage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            page.destination
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 600)
        #endif
    }
}

/// The list rows' shared look: first line, then a secondary line.
private struct LibraryRowText: View {
    let title: String
    let detail: String
    var locked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .lineLimit(2)
                .foregroundStyle(locked ? .secondary : .primary)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Drafts

struct DraftsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [SavedDraftStore.Summary] = []
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            if drafts.isEmpty {
                ContentUnavailableView {
                    Label("No drafts", systemImage: "doc.text")
                } description: {
                    Text("In Write, Save to Drafts puts an entry aside so you can finish it later. Drafts stay on this device.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(drafts) { draft in
                Button {
                    resume(draft)
                } label: {
                    LibraryRowText(title: draft.preview ?? (draft.payload == nil
                                                            ? String(localized: "Can't be read on this device yet")
                                                            : String(localized: "Photo or voice note")),
                                   detail: detail(for: draft),
                                   locked: draft.payload == nil)
                }
                .buttonStyle(.plain)
                .disabled(draft.payload == nil)
                .accessibilityHint("Opens it in Write")
                .swipeActions {
                    Button("Delete", role: .destructive) { delete(draft) }
                }
                .contextMenu {
                    Button("Continue writing", systemImage: "square.and.pencil") { resume(draft) }
                        .disabled(draft.payload == nil)
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(draft) }
                }
            }
        }
        .navigationTitle("Drafts")
        .toolbar {
            if !drafts.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete All", role: .destructive) { confirmDeleteAll = true }
                }
            }
        }
        .confirmationDialog("Delete all drafts?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                SavedDraftStore.deleteAll()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Drafts aren't entries yet, so they don't go to Recently Deleted. This can't be undone.")
        }
        .task { reload() }
    }

    private func detail(for draft: SavedDraftStore.Summary) -> String {
        var parts: [String] = []
        if let savedAt = draft.savedAt { parts.append(savedAt.formatted(.relative(presentation: .named))) }
        if draft.wordCount > 0 { parts.append(String(localized: "\(draft.wordCount) words")) }
        return parts.joined(separator: " · ")
    }

    private func reload() {
        drafts = SavedDraftStore.summaries()
    }

    private func delete(_ draft: SavedDraftStore.Summary) {
        SavedDraftStore.delete(draft.id)
        reload()
    }

    /// The Write editor does the swap (its own draft goes to Drafts first).
    private func resume(_ draft: SavedDraftStore.Summary) {
        SavedDraftStore.pendingResume = draft.id
        dismiss()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mirrorResumeSavedDraft, object: nil)
        }
    }
}

// MARK: - Duplicates

struct DuplicatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [Entry]
    @State private var groups: [[EntryDuplicates.Candidate]] = []
    @State private var loaded = false
    @State private var errorMessage: String?


    var body: some View {
        List {
            if loaded && groups.isEmpty {
                ContentUnavailableView {
                    Label("No duplicates", systemImage: "checkmark.circle")
                } description: {
                    Text("Entries with exactly the same text show up here. Very short entries, like a single word, are left out.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.first?.id) { group in
                Section {
                    ForEach(Array(group.enumerated()), id: \.element.id) { index, candidate in
                        HStack(alignment: .firstTextBaseline) {
                            Text(candidate.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute()))
                            Spacer()
                            if index == 0 {
                                Text("Kept")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Merge into the oldest", systemImage: "arrow.triangle.merge") { merge(group) }
                } header: {
                    Text(preview(group.first?.text ?? ""))
                        .textCase(nil)
                        .lineLimit(2)
                } footer: {
                    Text(footer(for: group))
                }
            }
        }
        .navigationTitle("Duplicates")
        .task(id: entries.count) {
            // Keyed on the count, not the texts: a merge (the only change made here) changes it,
            // and a per-render scan of every entry would cost what the list caches avoid.
            groups = EntryDuplicates.groups(EntryDuplicates.candidates(in: modelContext))
            loaded = true
        }
        .alert("Couldn't merge", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func preview(_ text: String) -> String {
        NoteEditorCodec.splitTrailingPhotoTokens(text).body
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private func footer(for group: [EntryDuplicates.Candidate]) -> String {
        let base = String(localized: "Merging keeps the oldest and adds the others' tags and voice notes to it. The others move to Recently Deleted.")
        guard EntryDuplicates.spansSeveralDays(group) else { return base }
        return String(localized: "Written on different days.") + " " + base
    }

    private func merge(_ group: [EntryDuplicates.Candidate]) {
        do {
            try EntryDuplicates.merge(group.map(\.id), in: modelContext)
        } catch EntryDuplicates.MergeError.unreadable {
            errorMessage = String(localized: "One of these entries can't be read on this device yet.")
        } catch {
            errorMessage = String(localized: "This device can't encrypt right now. Try again once it's unlocked.")
        }
    }
}

// MARK: - Recently Deleted

struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrashedEntry.deletedAt, order: .reverse) private var rows: [TrashedEntry]
    @State private var previews: [UUID: String] = [:]
    @State private var confirmEmpty = false
    @State private var pendingDelete: TrashedEntry?
    @State private var errorMessage: String?

    private var items: [TrashedEntry] { EntryTrash.newestPerEntry(rows) }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing deleted", systemImage: "trash")
                } description: {
                    Text("Deleted entries stay here for \(EntryTrash.retentionDays) days, on all your devices, before they're removed for good.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(items) { row in
                        LibraryRowText(title: previews[row.id] ?? String(localized: "Can't be read on this device yet"),
                                       detail: detail(for: row),
                                       locked: previews[row.id] == nil)
                            .swipeActions(edge: .leading) {
                                Button("Restore") { restore([row]) }.tint(.accentColor)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) { pendingDelete = row }
                            }
                            .contextMenu {
                                Button("Restore", systemImage: "arrow.uturn.backward") { restore([row]) }
                                Button("Delete Now", systemImage: "trash", role: .destructive) { pendingDelete = row }
                            }
                    }
                } footer: {
                    Text("Entries here aren't used for reflections, Ask or widgets. They're removed for good after \(EntryTrash.retentionDays) days.")
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Restore All", systemImage: "arrow.uturn.backward") { restore(items) }
                        Button("Delete All", systemImage: "trash", role: .destructive) { confirmEmpty = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: rows.map(\.id)) {
            var next: [UUID: String] = [:]
            for row in rows {
                guard let text = row.decryptedText else { continue }
                let body = NoteEditorCodec.splitTrailingPhotoTokens(text).body
                let line = body.split(whereSeparator: \.isNewline).first.map(String.init)
                next[row.id] = line ?? (row.hasPhoto || row.hasVoiceNote ? String(localized: "Photo or voice note") : "")
            }
            previews = next
        }
        .confirmationDialog("Delete all \(items.count) entries for good?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                perform { try EntryTrash.empty(in: modelContext) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They're removed from all your devices. This can't be undone.")
        }
        .confirmationDialog("Delete this entry for good?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Now", role: .destructive) {
                if let pendingDelete { perform { try EntryTrash.deletePermanently([pendingDelete], in: modelContext) } }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from all your devices. This can't be undone.")
        }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func detail(for row: TrashedEntry) -> String {
        let written = row.createdAt.formatted(.dateTime.day().month(.abbreviated).year())
        let days = EntryTrash.daysRemaining(for: row)
        let left = days == 1 ? String(localized: "1 day left") : String(localized: "\(days) days left")
        return "\(written) · \(left)"
    }

    private func restore(_ rows: [TrashedEntry]) {
        perform { _ = try EntryTrash.restore(rows, in: modelContext) }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch {
            errorMessage = String(localized: "Your journal couldn't be saved right now. Try again.")
        }
    }
}
