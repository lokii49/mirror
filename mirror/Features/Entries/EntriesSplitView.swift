#if os(iOS)
import SwiftUI
import SwiftData

/// Entries with the reader beside the list where there's room (iPad, an opened iPhone Duo;
/// owner, 2026-10-11) and today's pushed reader when compact. The list is always the first child
/// of the same stack, so a fold or unfold never rebuilds it: only the reader column comes and goes.
/// Side by side, opening an entry selects it (the same `macSelection` path the Mac uses) instead
/// of pushing.
struct EntriesSplitView: View {
    var navResetID: UUID
    var deepLinkEntryID: Binding<UUID?>

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Entry?
    /// Forwarded to the list's own reset. It also fires when the width class changes, so a reader
    /// pushed while compact doesn't stay stacked inside the narrow list column after an unfold.
    @State private var listResetID = UUID()

    private var sideBySide: Bool { sizeClass == .regular }

    var body: some View {
        HStack(spacing: 0) {
            EntriesTabView(
                navResetID: listResetID,
                deepLinkEntryID: deepLinkEntryID,
                macSelection: sideBySide ? $selection : nil
            )
            .frame(width: sideBySide ? 420 : nil)
            .frame(maxWidth: sideBySide ? 420 : .infinity)

            if sideBySide {
                Rectangle()
                    .fill(MirrorTheme.inkBorder)
                    .frame(width: 1)
                    .ignoresSafeArea(edges: .vertical)
                reader
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: navResetID) { _, _ in listResetID = UUID() }
        .onChange(of: sideBySide) { _, _ in listResetID = UUID() }
    }

    @ViewBuilder
    private var reader: some View {
        if let selection {
            NavigationStack {
                EntryDetailView(entry: selection) { self.selection = nil }
            }
            .id(selection.id)
            // Deleted from the list (swipe) or on another device: close the reader instead of
            // showing a deleted record.
            .background(EntrySelectionGuard(entryID: selection.id) { self.selection = nil })
        } else {
            ContentUnavailableView("Select an entry", systemImage: "book.closed")
                .background(MirrorTheme.bgBase)
        }
    }
}

/// Calls `onGone` once the entry with this id no longer exists (the iOS counterpart of the Mac's
/// `MacSelectionGuard`).
private struct EntrySelectionGuard: View {
    let onGone: () -> Void
    @Query private var matches: [Entry]

    init(entryID: UUID, onGone: @escaping () -> Void) {
        self.onGone = onGone
        _matches = Query(filter: #Predicate<Entry> { $0.id == entryID })
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: matches.isEmpty) { _, gone in
                if gone { onGone() }
            }
    }
}
#endif
