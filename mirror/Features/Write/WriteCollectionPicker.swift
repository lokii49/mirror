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
            let accent = displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary
            let filed = selectedItem != nil
            HStack(spacing: 4) {
                Image(systemName: selectedItem?.icon ?? "folder")
                    .font(.system(size: 11, weight: .semibold))
                // Unfiled shows the icon alone, so the row looks as before for people who
                // don't use collections.
                if let item = selectedItem {
                    Text(item.name)
                        .lineLimit(1)
                        .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .semibold) : .system(size: 12, weight: .medium))
                        .textCase(displayMode == .sentinel ? .uppercase : nil)
                }
            }
            .foregroundStyle(filed ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
            // Unfiled is a bare icon: no capsule, so no inset before it.
            .padding(.horizontal, filed ? 8 : 2)
            .padding(.vertical, 4)
            .background(
                filed ? AnyShapeStyle(accent.opacity(0.10)) : AnyShapeStyle(Color.clear),
                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
            )
            .contentShape(Rectangle())
        case .macToolbar:
            Image(systemName: selectedItem == nil ? "folder" : "folder.fill")
                .font(.system(size: 15))
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
