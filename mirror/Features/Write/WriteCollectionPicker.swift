import SwiftUI
import SwiftData

/// Which collection the entry goes in: Unfiled, an existing one, or a new one made here.
/// Its own view with its own query, so `WriteView.body` gains no modifiers (Debug stack limit).
struct WriteCollectionPicker: View {
    enum Style { case chip, macToolbar }

    @Binding var selection: UUID?
    var style: Style = .chip
    /// Called after the selection changes, so the editor can save its draft.
    var onChange: () -> Void = {}

    @Query private var collections: [JournalCollection]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @State private var creating = false
    @State private var name = ""
    @State private var failed = false

    private var lookup: CollectionLookup { CollectionLookup(collections) }

    /// A collection deleted (or not synced yet) reads as Unfiled; the id is kept until changed.
    private var selectedItem: CollectionLookup.Item? {
        selection.flatMap { id in lookup.items.first { $0.id == id } }
    }

    var body: some View {
        Menu {
            Button {
                select(nil)
            } label: {
                Label("Unfiled", systemImage: selectedItem == nil ? "checkmark" : "tray")
            }
            ForEach(lookup.items) { item in
                Button {
                    select(item.id)
                } label: {
                    Label(item.name, systemImage: selectedItem?.id == item.id ? "checkmark" : item.icon)
                }
            }
            Divider()
            Button("New collection…", systemImage: "folder.badge.plus") {
                name = ""
                creating = true
            }
        } label: {
            label
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Collection")
        .accessibilityValue(selectedItem?.name ?? String(localized: "Unfiled"))
        .accessibilityIdentifier("write.collection")
        .alert("New collection", isPresented: $creating) {
            TextField("Name", text: $name)
            Button("Create") { create() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This entry goes in it when you save.")
        }
        .alert("Couldn't save", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't encrypt right now. Try again once it's unlocked.")
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .chip:
            // Option A (owner 2026-11-06): the collection by name, as quiet text like Add tag, in
            // both themes.
            WriteHeaderTextLabel(title: "Unfiled",
                                 systemImage: selectedItem?.icon ?? "folder",
                                 isVerbatim: selectedItem != nil,
                                 verbatim: selectedItem?.name,
                                 tint: selectedItem == nil ? nil : (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet),
                                 isSentinel: displayMode == .sentinel)
        case .macToolbar:
            Image(systemName: selectedItem == nil ? "folder" : "folder.fill")
                .scaledFont(15)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
    }

    private func select(_ id: UUID?) {
        selection = id
        onChange()
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = ""
        guard !trimmed.isEmpty else { return }
        do {
            let collection = try JournalOrganizationStore.createCollection(name: trimmed, in: modelContext)
            select(collection.id)
        } catch {
            failed = true
        }
    }
}

/// The collection Entries is showing, so a new entry in Write can start there. Per device.
enum WriteCollectionDefault {
    private static let key = "mirror.write.viewedCollection"

    static var viewed: EntryFilterCriteria.CollectionScope {
        get {
            UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)).map { .collection($0) } ?? .all
        }
        set {
            if case .collection(let id) = newValue {
                UserDefaults.standard.set(id.uuidString, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// The viewed collection's id if it still exists.
    @MainActor
    static func collectionForNewEntry(in context: ModelContext) -> UUID? {
        guard case .collection(let id) = viewed else { return nil }
        var descriptor = FetchDescriptor<JournalCollection>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0 ? id : nil
    }
}

/// A quiet text button in the classic Write header's second row (collection, Add tag): icon and
/// words in the secondary colour, no pill, a 32 pt target.
struct WriteHeaderTextLabel: View {
    var title: LocalizedStringKey
    var systemImage: String
    var isVerbatim = false
    /// The user's own text (a collection name), shown as typed.
    var verbatim: String? = nil
    var tint: Color? = nil
    /// Sentinel: the same quiet text in mono capitals.
    var isSentinel = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .scaledFont(isSentinel ? 12 : 13, weight: .semibold)
            Group {
                if isVerbatim, let verbatim {
                    Text(verbatim)
                } else {
                    Text(title)
                }
            }
            .scaledFont(isSentinel ? 12.5 : 14, weight: isSentinel ? .semibold : .medium, design: isSentinel ? .monospaced : .default)
            .textCase(isSentinel ? .uppercase : nil)
            .kerning(isSentinel ? 0.4 : 0)
            .lineLimit(1)
        }
        .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(MirrorTheme.textSecondary))
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
}
