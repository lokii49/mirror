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
    /// Forwarded to the list's own reset. A width-class change doesn't reset: the list hands the
    /// open entry between the pushed reader and the reader column (`handOverReader`).
    @State private var listResetID = UUID()
    /// Half-folded iPhone Duo: the list ends at the fold and the reader starts after it.
    @State private var fold: FoldSpan?
    @State private var width: CGFloat = 0

    private var sideBySide: Bool { sizeClass == .regular }
    private var foldSplit: FoldColumnSplit? {
        sideBySide ? FoldColumnSplit(fold: fold, width: width, minimumColumn: 300) : nil
    }

    var body: some View {
        // One NavigationStack for the whole tab, not one per column: the list's buttons and the
        // reader's Edit/More share a single bar at the trailing edge (beside iPad's top tab bar,
        // in the Duo's vertical bar). A narrow list column's own bar had its buttons collapsed
        // under iPad's centred tab bar, and reserved the Duo bar's width inside the list.
        NavigationStack {
            HStack(spacing: 0) {
                EntriesTabView(
                    navResetID: listResetID,
                    deepLinkEntryID: deepLinkEntryID,
                    macSelection: sideBySide ? $selection : nil,
                    ownsNavigationStack: false
                )
                .frame(width: sideBySide ? listWidth : nil)
                .frame(maxWidth: sideBySide ? listWidth : .infinity)

                if sideBySide {
                    // Flat: a hairline. Half-folded: the fold is the gap, so no text sits on it.
                    Rectangle()
                        .fill(foldSplit == nil ? MirrorTheme.inkBorder : MirrorTheme.bgBase)
                        .frame(width: foldSplit?.gap ?? 1)
                        .ignoresSafeArea(edges: .vertical)
                    reader
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onWidthChange($width)
            .onFoldChange { fold = $0 }
        }
        .onChange(of: navResetID) { _, _ in listResetID = UUID() }
        // Compact, the list pushes the entry itself. Clearing here means an unfold can't draw
        // the reader for an entry deleted meanwhile before the list hands its pushed one over.
        .onChange(of: sideBySide) { _, side in if !side { selection = nil } }
    }

    private var listWidth: CGFloat { foldSplit?.leading ?? 420 }

    @ViewBuilder
    private var reader: some View {
        if let selection {
            EntryDetailView(entry: selection) { self.selection = nil }
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

#if os(iOS)
/// Reports whether the system can place a vertical bar here (iPhone Duo: yes; iPad: no), from
/// UIKit's `verticalBarEdge` trait (iOS 27.1). SwiftUI has no environment value for it.
struct VerticalBarProbe: UIViewRepresentable {
    @Binding var hasVerticalBar: Bool

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = { value in
            if hasVerticalBar != value { hasVerticalBar = value }
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        var onChange: ((Bool) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            if #available(iOS 27.1, *) {
                registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (view: ProbeView, _) in
                    view.report()
                }
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        func report() {
            guard window != nil else { return }
            var value = false
            if #available(iOS 27.1, *) { value = traitCollection.verticalBarEdge != .unspecified }
            let callback = onChange
            DispatchQueue.main.async { callback?(value) }
        }
    }
}
#endif
