import SwiftUI
import SwiftData

/// Decrypted names for the list's chips and menus (memory only).
struct CollectionLookup {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let name: String
        let icon: String
    }
    let items: [Item]

    init(_ collections: [JournalCollection]) {
        items = collections
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            .map { Item(id: $0.id, name: $0.payload?.name ?? String(localized: "Locked collection"), icon: $0.payload?.icon ?? "folder") }
    }

    func name(for id: UUID) -> String? { items.first { $0.id == id }?.name }

    /// Chip label for a scope; a collection that no longer exists says so instead of
    /// silently showing everything.
    func label(for scope: EntryFilterCriteria.CollectionScope) -> String {
        switch scope {
        case .all: return String(localized: "All entries")
        case .unfiled: return String(localized: "Unfiled")
        case .collection(let id): return name(for: id) ?? String(localized: "Missing collection")
        }
    }
}

/// All · Unfiled · each collection, plus the manage button. Shown only once a
/// collection exists, so journals that don't use them look unchanged.
struct CollectionsBar: View {
    let lookup: CollectionLookup
    @Binding var scope: EntryFilterCriteria.CollectionScope
    let manage: () -> Void
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, title: String(localized: "All entries"), icon: "tray.full")
                chip(.unfiled, title: String(localized: "Unfiled"), icon: "tray")
                ForEach(lookup.items) { item in
                    chip(.collection(item.id), title: item.name, icon: item.icon)
                }
                Button(action: manage) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MirrorTheme.textSecondary)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage collections and saved views")
                .accessibilityIdentifier("collections.manage")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        #if os(iOS)
        .background(MirrorTheme.bgBase)
        #endif
    }

    private func chip(_ value: EntryFilterCriteria.CollectionScope, title: String, icon: String) -> some View {
        let selected = scope == value
        let accent = displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violetLight
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { scope = selected && value != .all ? .all : value }
        } label: {
            Label(title, systemImage: icon)
                .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .semibold) : .system(size: 12, weight: .medium))
                .textCase(displayMode == .sentinel ? .uppercase : nil)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selected ? (displayMode == .sentinel ? MirrorTheme.ember.opacity(0.14) : MirrorTheme.violetDim) : MirrorTheme.inkRaised,
                    in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) : AnyShape(Capsule())
                )
                .foregroundStyle(selected ? accent : MirrorTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Move to" for one entry: Unfiled, each collection, or a new one.
struct MoveToCollectionMenu: View {
    let entry: Entry
    let lookup: CollectionLookup
    let newCollection: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Menu {
            Button {
                try? JournalOrganizationStore.move([entry], to: nil, in: modelContext)
            } label: {
                Label("Unfiled", systemImage: entry.collectionID == nil ? "checkmark" : "tray")
            }
            ForEach(lookup.items) { item in
                Button {
                    try? JournalOrganizationStore.move([entry], to: item.id, in: modelContext)
                } label: {
                    Label(item.name, systemImage: entry.collectionID == item.id ? "checkmark" : item.icon)
                }
            }
            Divider()
            Button("New collection…", systemImage: "folder.badge.plus", action: newCollection)
        } label: {
            Label("Move to", systemImage: "folder")
        }
    }
}

/// Saved views: open one, save what is on screen, or manage them.
struct SavedViewsMenu<Label: View>: View {
    let views: [SavedEntryView]
    let canSaveCurrent: Bool
    let open: (SavedEntryView.Payload) -> Void
    let saveCurrent: () -> Void
    let manage: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            let sorted = views.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            ForEach(sorted) { view in
                if let payload = view.payload {
                    Button(payload.name, systemImage: "bookmark") { open(payload) }
                }
            }
            if !sorted.isEmpty { Divider() }
            Button("Save current view…", systemImage: "bookmark.badge.plus", action: saveCurrent)
                .disabled(!canSaveCurrent)
            Button("Manage collections and views…", systemImage: "slider.horizontal.3", action: manage)
        } label: {
            label()
        }
        .accessibilityIdentifier("savedViews.menu")
    }
}

/// Create, rename, reorder and delete collections and saved views. Deleting a
/// collection asks first and moves its entries to Unfiled; deleting a view
/// never touches entries.
struct OrganizationManagerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var collections: [JournalCollection]
    @Query private var views: [SavedEntryView]

    @State private var renamingCollection: JournalCollection?
    @State private var renamingView: SavedEntryView?
    @State private var nameDraft = ""
    @State private var creatingCollection = false
    @State private var pendingDelete: JournalCollection?
    @State private var errorMessage: String?

    private var sortedCollections: [JournalCollection] {
        collections.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }
    private var sortedViews: [SavedEntryView] {
        views.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    ForEach(sortedCollections) { collection in
                        HStack {
                            Label(collection.payload?.name ?? String(localized: "Locked collection"),
                                  systemImage: collection.payload?.icon ?? "folder")
                            Spacer()
                            Text("\(JournalOrganizationStore.entryCount(in: collection.id, context: modelContext))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { startRename(collection) }
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = collection }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDelete = collection }
                            Button("Rename") { startRename(collection) }
                        }
                    }
                    .onMove { from, to in
                        var ordered = sortedCollections
                        ordered.move(fromOffsets: from, toOffset: to)
                        try? JournalOrganizationStore.reorderCollections(ordered, in: modelContext)
                    }
                    Button("New collection…", systemImage: "folder.badge.plus") {
                        nameDraft = ""
                        creatingCollection = true
                    }
                } header: {
                    Text("Collections")
                } footer: {
                    Text("An entry can be in one collection. Deleting a collection keeps its entries; they move to Unfiled. Reflections still use all entries.")
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    if sortedViews.isEmpty {
                        Text("Search or filter your entries, then choose Save current view.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sortedViews) { view in
                        Label(view.payload?.name ?? String(localized: "Locked view"), systemImage: "bookmark")
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { startRename(view) }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    try? JournalOrganizationStore.delete(view, in: modelContext)
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { try? JournalOrganizationStore.delete(view, in: modelContext) }
                                Button("Rename") { startRename(view) }
                            }
                    }
                    .onMove { from, to in
                        var ordered = sortedViews
                        ordered.move(fromOffsets: from, toOffset: to)
                        try? JournalOrganizationStore.reorderViews(ordered, in: modelContext)
                    }
                } header: {
                    Text("Saved views")
                } footer: {
                    Text("A saved view keeps a search and its filters. Deleting it never deletes entries.")
                }
            }
            .navigationTitle("Organize")
            #if os(macOS)
            .frame(minWidth: 440, idealWidth: 480, minHeight: 480, idealHeight: 560)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                #endif
            }
            .alert("New collection", isPresented: $creatingCollection) {
                TextField("Name", text: $nameDraft)
                Button("Create") { create() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename", isPresented: Binding(get: { renamingCollection != nil || renamingView != nil },
                                                  set: { if !$0 { renamingCollection = nil; renamingView = nil } })) {
                TextField("Name", text: $nameDraft)
                Button("Save") { commitRename() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete collection", role: .destructive) {
                    if let pendingDelete { perform { try JournalOrganizationStore.delete(pendingDelete, in: modelContext) } }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var deleteTitle: String {
        String(localized: "Delete “\(pendingDelete?.payload?.name ?? "")”?")
    }

    private var deleteMessage: String {
        let count = pendingDelete.map { JournalOrganizationStore.entryCount(in: $0.id, context: modelContext) } ?? 0
        return String(localized: "Its \(count) entries stay in your journal and move to Unfiled.")
    }

    private func startRename(_ collection: JournalCollection) {
        nameDraft = collection.payload?.name ?? ""
        renamingCollection = collection
    }

    private func startRename(_ view: SavedEntryView) {
        nameDraft = view.payload?.name ?? ""
        renamingView = view
    }

    private func create() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        perform { try JournalOrganizationStore.createCollection(name: name, in: modelContext) }
    }

    private func commitRename() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let renamingCollection { perform { try JournalOrganizationStore.rename(renamingCollection, to: name, in: modelContext) } }
        if let renamingView { perform { try JournalOrganizationStore.rename(renamingView, to: name, in: modelContext) } }
        renamingCollection = nil
        renamingView = nil
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch {
            errorMessage = String(localized: "This device can't encrypt right now. Try again once it's unlocked.")
        }
    }
}

/// Name prompts the list needs (new collection from "Move to", save current view).
struct OrganizationPrompts: ViewModifier {
    @Binding var newCollectionFor: Entry?
    @Binding var savingView: Bool
    let saveView: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("New collection", isPresented: Binding(get: { newCollectionFor != nil }, set: { if !$0 { newCollectionFor = nil } })) {
                TextField("Name", text: $name)
                Button("Create and move") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let entry = newCollectionFor,
                       let collection = try? JournalOrganizationStore.createCollection(name: trimmed, in: modelContext) {
                        try? JournalOrganizationStore.move([entry], to: collection.id, in: modelContext)
                    }
                    name = ""
                    newCollectionFor = nil
                }
                Button("Cancel", role: .cancel) { name = "" }
            }
            .alert("Save current view", isPresented: $savingView) {
                TextField("Name", text: $name)
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { saveView(trimmed) }
                    name = ""
                }
                Button("Cancel", role: .cancel) { name = "" }
            } message: {
                Text("Saves the search, filters and sort. Relative dates such as This month update when you open it.")
            }
    }
}
