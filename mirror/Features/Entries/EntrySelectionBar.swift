import SwiftUI
import SwiftData

/// The bottom bar while selecting entries in the list: count, Select All, Move to…, Delete, Done.
/// Delete moves them to Recently Deleted (with the app's Undo toast).
struct EntrySelectionBar: View {
    let count: Int
    let lookup: CollectionLookup
    let allSelected: Bool
    let toggleAll: () -> Void
    let move: (UUID?) -> Void
    let delete: () -> Void
    let done: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @State private var creating = false
    @State private var name = ""
    @State private var failed = false

    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor }

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(MirrorTheme.inkBorder)
            HStack(spacing: 16) {
                Button(allSelected ? "Deselect All" : "Select All", action: toggleAll)
                    .font(.system(size: 15, weight: .medium))
                Spacer(minLength: 4)
                Text(count == 0 ? String(localized: "Select entries") : String(localized: "\(count) selected"))
                    .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .semibold) : .system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 4)
                Menu {
                    Button("Unfiled", systemImage: "tray") { move(nil) }
                    ForEach(lookup.items) { item in
                        Button(item.name, systemImage: item.icon) { move(item.id) }
                    }
                    Divider()
                    Button("New collection…", systemImage: "folder.badge.plus") {
                        name = ""
                        creating = true
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .disabled(count == 0)
                .accessibilityLabel("Move to")
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .disabled(count == 0)
                .accessibilityLabel("Delete")
                Button("Done", action: done)
                    .font(.system(size: 15, weight: .semibold))
            }
            .tint(accent)
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .alert("New collection", isPresented: $creating) {
            TextField("Name", text: $name)
            Button("Create and move") { create() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't save", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't encrypt right now. Try again once it's unlocked.")
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = ""
        guard !trimmed.isEmpty else { return }
        do {
            let collection = try JournalOrganizationStore.createCollection(name: trimmed, in: modelContext)
            move(collection.id)
        } catch {
            failed = true
        }
    }
}

/// The row's selection mark while selecting.
struct EntrySelectionMark: View {
    let selected: Bool
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(selected ? AnyShapeStyle(displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor) : AnyShapeStyle(.tertiary))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}
