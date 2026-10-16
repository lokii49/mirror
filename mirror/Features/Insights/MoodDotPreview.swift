import SwiftUI
import Charts

/// One mood reading drawn as a dot on a mood chart (the week chart on Insights, the Mood Timeline).
struct MoodDot: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let mood: String
    let score: Double
    let origin: MoodOrigin
}

extension Entry {
    /// The entry's writing on one line, photo markers removed, for short previews
    /// (On This Day, a held mood dot). Decrypts: call it from an action, never from `body`.
    var previewSnippet: String {
        if textDecryptionFailed { return "Encrypted entry unavailable" }
        var raw = text.isEmpty ? (voiceNoteTranscript ?? "") : text
        for (range, _) in allPhotoTokens(in: raw).reversed() { raw.removeSubrange(range) }
        let oneLine = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !oneLine.isEmpty { return oneLine }
        if hasVoiceNotes { return "Voice note" }
        if hasPhoto { return "Photo entry" }
        return "Untitled"
    }
}

/// What a held dot shows: its entry's first lines, or a line saying it was a check-in.
/// `entry` looks the reading's entry up by id; nil (a check-in, or a deleted entry) shows the
/// check-in line.
func moodDotPreviewText(for dot: MoodDot, entry: (UUID) -> Entry?) -> String {
    if dot.origin == .entry, let found = entry(dot.id) { return found.previewSnippet }
    return String(localized: "Mood check-in, no writing")
}

/// Press and hold a mood chart, then slide: the dot nearest the finger is selected and its
/// writing shows over the plot, on the half away from the dot. Letting go clears it. A plain
/// swipe still scrolls the page.
struct MoodDotScrubOverlay: View {
    let proxy: ChartProxy
    let dots: [MoodDot]
    @Binding var selected: MoodDot?
    /// Text for the selected dot, set by the chart when the selection changes.
    let previewText: String

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    var body: some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? CGRect(origin: .zero, size: geo.size)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .holdToScrub { location in
                        if let location { select(near: location, plot: plot) } else { selected = nil }
                    }

                if let selected, let point = position(of: selected, plot: plot) {
                    callout
                        .frame(width: plot.width - 8)
                        .frame(height: plot.height / 2 - 6, alignment: point.y < plot.midY ? .bottom : .top)
                        .position(
                            x: plot.midX,
                            y: point.y < plot.midY ? plot.maxY - plot.height / 4 - 2 : plot.minY + plot.height / 4 + 2
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
        .animation(.easeOut(duration: 0.15), value: selected?.id)
    }

    private var callout: some View {
        Text(previewText)
            .font(isSentinel ? MirrorTheme.mono(11.5, weight: .medium) : .system(size: 13, weight: .medium))
            .foregroundStyle(MirrorTheme.textPrimary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: isSentinel ? 4 : 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: isSentinel ? 4 : 12, style: .continuous)
                    .stroke(
                        isSentinel ? MirrorTheme.ember.opacity(0.45) : MirrorTheme.moodColor(for: selected?.mood ?? "").opacity(0.5),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    /// Where the dot is drawn. The marks bin dates by day, so the dot sits mid-day.
    private func position(of dot: MoodDot, plot: CGRect) -> CGPoint? {
        let day = Calendar.current.startOfDay(for: dot.date)
        let midDay = Calendar.current.date(byAdding: .hour, value: 12, to: day) ?? day
        guard let x = proxy.position(forX: midDay), let y = proxy.position(forY: dot.score) else { return nil }
        return CGPoint(x: plot.minX + x, y: plot.minY + y)
    }

    /// Nearest dot by distance on screen, not by date: two readings on one day stack vertically.
    private func select(near location: CGPoint, plot: CGRect) {
        let nearest = dots.min { a, b in
            distance(position(of: a, plot: plot), location) < distance(position(of: b, plot: plot), location)
        }
        if nearest?.id != selected?.id { selected = nearest }
    }

    private func distance(_ p: CGPoint?, _ q: CGPoint) -> CGFloat {
        guard let p else { return .infinity }
        return hypot(p.x - q.x, p.y - q.y)
    }
}

private extension View {
    /// Calls `onChange` with the finger's location while a press-and-hold lasts, then with nil.
    /// On iOS 18+ a UIKit long press: it reports the location as soon as the hold begins, even
    /// with the finger still, and a swipe that starts here still scrolls the page. SwiftUI's
    /// long press + drag reported nothing until the finger moved, and kept the page from
    /// scrolling.
    @ViewBuilder
    func holdToScrub(_ onChange: @escaping (CGPoint?) -> Void) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            gesture(HoldToScrubGesture(onChange: onChange))
        } else {
            swiftUIHoldToScrub(onChange)
        }
        #else
        swiftUIHoldToScrub(onChange)
        #endif
    }

    func swiftUIHoldToScrub(_ onChange: @escaping (CGPoint?) -> Void) -> some View {
        gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    guard case .second(true, let drag?) = value else { return }
                    onChange(drag.location)
                }
                .onEnded { _ in onChange(nil) }
        )
    }
}

#if os(iOS)
@available(iOS 18.0, *)
private struct HoldToScrubGesture: UIGestureRecognizerRepresentable {
    let onChange: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.3
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: onChange(context.converter.localLocation)
        default: onChange(nil)
        }
    }
}
#endif
