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
    @Environment(\.appDisplayMode) private var displayMode
    @State private var selection: Entry?
    /// The layout while an entry editor is open over a reader (pushed or in the column), nil
    /// otherwise. A fold or unfold mid-edit keeps this layout until the editor closes: the
    /// hand-over would pop a pushed reader and its editor (compact to side by side), and the
    /// reader column declares its editor's destination, so removing it pops the editor (side by
    /// side to compact). WriteView's flush on disappear keeps only the text: photo and voice
    /// edits, an inline recording and undo were lost. The editor covers the whole stack, so the
    /// held layout only shows behind it; closing the editor applies the current width class,
    /// and the usual hand-over moves the reader.
    @State private var heldSideBySide: Bool?
    /// Forwarded to the list's own reset. A width-class change doesn't reset: the list hands the
    /// open entry between the pushed reader and the reader column (`handOverReader`).
    @State private var listResetID = UUID()
    /// Half-folded iPhone Duo: the list ends at the fold and the reader starts after it.
    @State private var fold: FoldSpan?
    @State private var width: CGFloat = 0
    /// iPhone Duo (a vertical bar beside the status bar): flat, the list ends at the middle of the
    /// screen, where the fold is, so half-folding only opens a gap there (owner, 2026-10-11).
    @State private var hasVerticalBar = false
    /// The screen's middle and this split's leading edge, in window coordinates.
    @State private var screenMidX: CGFloat = 0
    @State private var splitMinX: CGFloat = 0

    private var sideBySide: Bool { heldSideBySide ?? (sizeClass == .regular) }
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
                    ownsNavigationStack: false,
                    onReaderEditorPresented: holdLayout
                )
                .frame(width: sideBySide ? listWidth : nil)
                .frame(maxWidth: sideBySide ? listWidth : .infinity)

                if sideBySide {
                    // Flat: a hairline. Half-folded: the fold is the gap, so no text sits on it.
                    Rectangle()
                        .fill(foldSplit == nil ? MirrorTheme.inkBorder : MirrorTheme.bgBase)
                        .frame(width: foldSplit?.gap ?? 1)
                        .ignoresSafeArea(edges: .vertical)
                    // Opaque and drawn after the list, so the list header's scrolling rows (moods,
                    // week strip) end at the column edge instead of running into the reader.
                    // (Clipping the list instead cut its background off under the bars.)
                    reader
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MirrorTheme.bgBase.ignoresSafeArea())
                }
            }
            // Half-folding slides the columns apart to either side of the fold, and back.
            .animation(.foldSplit, value: foldSplit)
            .onWidthChange($width)
            .onFoldChange { fold = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX.rounded() } action: { splitMinX = $0 }
        }
        // The window's own middle: SwiftUI lays the tab content out beside the vertical bar, so
        // even a safe-area-ignoring background stops short of the screen's edge.
        .background(VerticalBarProbe(hasVerticalBar: $hasVerticalBar, windowMidX: $screenMidX))
        .onChange(of: navResetID) { _, _ in
            heldSideBySide = nil
            listResetID = UUID()
        }
        // A new entry in the column (a deep link) or none (deleted, closed) removes the reader and
        // any editor on it.
        .onChange(of: selection?.id) { _, _ in heldSideBySide = nil }
        // Compact, the list pushes the entry itself. Clearing here means an unfold can't draw
        // the reader for an entry deleted meanwhile before the list hands its pushed one over.
        .onChange(of: sideBySide) { _, side in if !side { selection = nil } }
    }

    /// Called by a reader when its editor opens or closes (see `heldSideBySide`).
    private func holdLayout(_ editorOpen: Bool) {
        heldSideBySide = editorOpen ? sideBySide : nil
    }

    /// Half-folded: up to the fold. Flat on iPhone Duo: up to the screen's middle, so half-folding
    /// springs the columns apart toward the screen's edges. Elsewhere (iPad): 420 pt.
    private var listWidth: CGFloat {
        if let foldSplit { return foldSplit.leading }
        let toMiddle = screenMidX - splitMinX
        if hasVerticalBar, toMiddle >= 300, width - toMiddle >= 300 { return toMiddle }
        return 420
    }

    @ViewBuilder
    private var reader: some View {
        if let selection {
            EntryDetailView(entry: selection, onDone: { self.selection = nil }, onEditorPresented: holdLayout)
            .id(selection.id)
            // Deleted from the list (swipe) or on another device: close the reader instead of
            // showing a deleted record.
            .background(EntrySelectionGuard(entryID: selection.id) { self.selection = nil })
        } else if displayMode == .sentinel {
            // The Log's empty-state look (EntriesTabView.emptyState): viewfinder, mono capitals.
            VStack(spacing: 16) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.quaternary)
                Text("Select an entry")
                    .textCase(.uppercase)
                    .font(MirrorTheme.mono(14, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MirrorTheme.bgBase)
        } else {
            ContentUnavailableView("Select an entry", systemImage: "book.closed")
                .background(MirrorTheme.bgBase)
        }
    }
}

/// Calls `onGone` once the entry with this id no longer exists (the iOS counterpart of the Mac's
/// `MacSelectionGuard`). An entry already gone is never handed over (`EntriesTabView.isLive`). Only the
/// reader column has one: behind the pushed reader (inside its navigationDestination) the guard's
/// query hung the push on the iPhone 14 Pro (UI tests, 2026-10-17).
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
    /// The window's horizontal middle, in window (SwiftUI `.global`) coordinates.
    var windowMidX: Binding<CGFloat>? = nil

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = { value in
            if hasVerticalBar != value { hasVerticalBar = value }
        }
        if let windowMidX {
            view.onWindowWidth = { width in
                let mid = (width / 2).rounded()
                if abs(windowMidX.wrappedValue - mid) >= 1 { windowMidX.wrappedValue = mid }
            }
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        var onChange: ((Bool) -> Void)?
        var onWindowWidth: ((CGFloat) -> Void)?
        private var reportedWindowWidth: CGFloat = 0

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

        /// A fold or unfold resizes the window, which lays this view out again.
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let width = window?.bounds.width, width != reportedWindowWidth else { return }
            reportedWindowWidth = width
            let callback = onWindowWidth
            DispatchQueue.main.async { callback?(width) }
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
