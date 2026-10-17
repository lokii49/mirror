import SwiftUI

// iPhone Duo fold awareness, ported from TinyAct's FoldLayout.swift (owner's reference design,
// 2026-10-11). Half-folded, the Duo's inner display has a vertical fold down the middle that
// SwiftUI reports as a `.division` reserved region (iOS 27.1). Columns split at the fold and
// single columns move to one side of it, so no text bends across the crease. Flat, closed, on
// every other device and before iOS 27.1, there is no fold and layouts are unchanged. On the Mac
// the modifiers do nothing.

/// Horizontal span of an active vertical fold crossing a view, in that view's local coordinates.
nonisolated struct FoldSpan: Equatable, Sendable {
    var minX: CGFloat
    var maxX: CGFloat

    var width: CGFloat { maxX - minX }

    /// Sub-point changes are layout rounding, not a moved fold. Reacting to them looped: the
    /// half-folded Write column's width wobbled between 867 and 867.5 pt, each wobble moved the
    /// measured fold, and the new padding started the next layout pass.
    static func differs(_ a: FoldSpan?, _ b: FoldSpan?) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case let (a?, b?): return abs(a.minX - b.minX) >= 1 || abs(a.maxX - b.maxX) >= 1
        default: return true
        }
    }
}

extension Animation {
    /// Columns sliding to either side of the fold as the Duo half-folds, and back as it opens.
    static let foldSplit = Animation.spring(response: 0.45, dampingFraction: 0.86)
}

extension View {
    /// Tracks this view's width, ignoring sub-point changes (see `FoldSpan.differs`).
    func onWidthChange(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
            if abs(new - width.wrappedValue) >= 1 { width.wrappedValue = new }
        }
    }
}

#if os(iOS)
extension ToolbarContent {
    /// Prefers the vertical side bar for this item where the system shows one (iPhone Duo). Left
    /// to the system, a leading item can stay in a horizontal bar at the top while the trailing
    /// ones move to the side (TinyAct). Elsewhere there is no vertical bar and nothing changes.
    @ToolbarContentBuilder
    func preferringVerticalBar() -> some ToolbarContent {
        if #available(iOS 27.1, *) {
            axisBehavior(.verticalPreferred)
        } else {
            self
        }
    }
}
#endif

#if os(macOS)
extension View {
    func onFoldChange(_ action: @escaping (FoldSpan?) -> Void) -> some View { self }
    func avoidingFold() -> some View { self }
}

extension ToolbarContent {
    func preferringVerticalBar() -> some ToolbarContent { self }
}
#else
extension View {
    /// Reports the active vertical fold crossing this view, or nil when there is none
    /// (device flat or closed, fold outside the view, or iOS before 27.1).
    func onFoldChange(_ action: @escaping (FoldSpan?) -> Void) -> some View {
        modifier(FoldChangeModifier(action: action))
    }

    /// Keeps this view entirely on the wider side of an active fold.
    func avoidingFold() -> some View {
        modifier(FoldAvoidingModifier())
    }
}

/// A view's geometry callback only reruns when its own frame changes, and folding or unfolding
/// often leaves the frame as it was, so a view could keep a fold that's gone. The hinge callback
/// re-creates the measuring view to force a fresh read, and while the hinge isn't partially open
/// any measured fold is ignored: right after unfolding the division region can still read as
/// active for a moment (TinyAct, verified on the Duo simulator).
private struct FoldChangeModifier: ViewModifier {
    let action: (FoldSpan?) -> Void
    @State private var measured: FoldSpan?
    /// nil until the first hinge change (unknown: trust the measurement)
    @State private var partiallyOpen: Bool?
    @State private var generation = 0

    private var fold: FoldSpan? {
        partiallyOpen == false ? nil : measured
    }

    func body(content: Content) -> some View {
        content
            // Measured on a background so re-creating it doesn't reset the content's state
            .background {
                Color.clear
                    .onGeometryChange(for: FoldSpan?.self) { proxy in
                        Self.fold(in: proxy)
                    } action: { new in
                        if FoldSpan.differs(measured, new) { measured = new }
                    }
                    .id(generation)
            }
            .onHingeStatusChange { isPartiallyOpen in
                partiallyOpen = isPartiallyOpen
                generation += 1
            }
            .onChange(of: fold, initial: true) { _, fold in action(fold) }
    }

    private static func fold(in proxy: GeometryProxy) -> FoldSpan? {
        guard #available(iOS 27.1, *) else { return nil }
        let width = proxy.size.width
        return proxy.reservedRegions(kind: .division)
            .first { region in
                region.isActive
                    && region.frame.height >= region.frame.width
                    && region.frame.minX > 0
                    && region.frame.maxX < width
            }
            .map { region in
                FoldSpan(
                    minX: region.frame.minX - region.margins.leading,
                    maxX: region.frame.maxX + region.margins.trailing
                )
            }
    }
}

private extension View {
    /// Calls `action` when the hinge status changes, with whether it's now partially open.
    @ViewBuilder
    func onHingeStatusChange(_ action: @escaping (Bool) -> Void) -> some View {
        if #available(iOS 27.1, *) {
            onHingeChange { _, new in
                action(new.hinge?.status == .partiallyOpen)
            }
        } else {
            self
        }
    }
}

private struct FoldAvoidingModifier: ViewModifier {
    @State private var fold: FoldSpan?
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .animation(.foldSplit, value: fold)
            // Measured outside the padding, so the measured width doesn't change with it
            .frame(maxWidth: .infinity)
            .onWidthChange($width)
            .onFoldChange { fold = $0 }
    }

    private var insets: (leading: CGFloat, trailing: CGFloat) {
        guard let fold else { return (0, 0) }
        let leadingRoom = fold.minX
        let trailingRoom = width - fold.maxX
        return trailingRoom >= leadingRoom ? (fold.maxX, 0) : (0, width - fold.minX)
    }
}

#endif

/// Where two side-by-side columns split, in the container's local coordinates: the leading
/// column's width and the gap after it. The trailing column takes the rest.
nonisolated struct FoldColumnSplit: Equatable, Sendable {
    var leading: CGFloat
    var gap: CGFloat

    /// Half-folded, the fold itself, when each side has at least `minimumColumn` points; nil
    /// otherwise (the caller keeps its flat layout).
    init?(fold: FoldSpan?, width: CGFloat, minimumColumn: CGFloat = 240) {
        guard let fold, fold.minX >= minimumColumn, width - fold.maxX >= minimumColumn else {
            return nil
        }
        leading = fold.minX
        gap = fold.width
    }
}
