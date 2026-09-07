import SwiftUI
import UIKit

/// Press-and-hold a card, then swipe, to wipe it clear and see what's behind —
/// like a flashlight moving over frosted glass. The front stays fully opaque; a
/// soft-edged hole follows the finger, and the swept trail slowly re-frosts
/// behind it (~1.4s). Lift the finger and the whole thing frosts back over.
///
/// Sentinel-mode signature interaction; in Classic it's inert (renders `front`,
/// no gesture). First use: the daily reflection card, with `ReflectionSignalSource`
/// as `back`.
///
/// The gesture is a long-press *sequenced before* a zero-distance drag: the
/// long-press arms it, the drag reports the finger position for as long as it's
/// down, and `.onEnded` fires on lift.
struct PeekReveal<Front: View, Back: View>: View {
    var enabled: Bool
    /// Match the wrapped card's own corner radius so the clip and the "inspecting"
    /// border sit on the card edge. Sentinel's `themedCard` is 10.
    var cornerRadius: CGFloat = 10
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One dab of "wiped clear", spawned per drag sample. Fades over `lifetime`.
    private struct Smudge: Identifiable {
        let id = UUID()
        var point: CGPoint
        var birth: Date
    }

    @State private var trail: [Smudge] = []
    @State private var active = false

    private let lifetime: TimeInterval = 1.4
    private let holeRadius: CGFloat = 78  // wide enough that consecutive drag dabs overlap in their solid cores
    private let maxSmudges = 64

    #if DEBUG
    // `--peekRevealAlwaysOn` fully reveals the back (no wipe) for screenshots.
    // `--peekRevealStayOpen` freezes the wiped trail (no decay, no clear) so a UI
    // test can press-drag-release and still screenshot the swept path.
    // `--peekRevealDemoTrail` paints a fixed diagonal of feathered holes on
    // appear — screenshots the wipe *rendering* (feather, back-through-holes)
    // without a live drag.
    private let forceOpen = ProcessInfo.processInfo.arguments.contains("--peekRevealAlwaysOn")
    private let stayOpen = ProcessInfo.processInfo.arguments.contains("--peekRevealStayOpen")
    private let demoTrail = ProcessInfo.processInfo.arguments.contains("--peekRevealDemoTrail")
    #else
    private let forceOpen = false
    private let stayOpen = false
    private let demoTrail = false
    #endif

    private var showReveal: Bool { active || !trail.isEmpty || forceOpen || demoTrail }

    var body: some View {
        ZStack {
            // Only mounted while something could show through — keeps
            // `ReflectionSignalSource.resolve()` off the idle render path.
            if showReveal { back }
            frontLayer
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if active || forceOpen {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MirrorTheme.ember.opacity(0.5), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .modifier(RevealGestureModifier(enabled: enabled, gesture: revealGesture))
        .accessibilityElement(children: .contain)
        .accessibilityHint(enabled ? "Press, hold and swipe to reveal how this was generated" : "")
    }

    // MARK: Front (the frosted layer)

    @ViewBuilder private var frontLayer: some View {
        if forceOpen {
            front.opacity(0)
        } else if reduceMotion {
            // Motion-free fallback: hold reveals the whole back, no wipe/trail.
            front.opacity(active ? 0 : 1).animation(.easeInOut(duration: 0.2), value: active)
        } else if trail.isEmpty && !active && !demoTrail {
            front
        } else {
            front.mask {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        // Start fully opaque (front visible everywhere)…
                        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                        // …then subtract a feathered circle per smudge.
                        ctx.blendMode = .destinationOut
                        let now = timeline.date
                        let dabs: [(CGPoint, Double)] = demoTrail
                            ? Self.demoDabs(in: size)
                            : trail.enumerated().map { i, s in
                                let isLive = (active && i == trail.count - 1) || stayOpen
                                let strength = isLive
                                    ? 1.0
                                    : max(0, 1 - now.timeIntervalSince(s.birth) / lifetime)
                                return (s.point, strength)
                            }
                        for (point, strength) in dabs where strength > 0.001 {
                            let r = holeRadius
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r,
                                                       width: r * 2, height: r * 2)),
                                with: .radialGradient(
                                    // Tight feather: fully clear core out to ~0.68r, the
                                    // soft edge lives in the last third only — keeps
                                    // front/back text from overlapping across a wide band.
                                    Gradient(stops: [
                                        .init(color: .white.opacity(strength), location: 0),
                                        .init(color: .white.opacity(strength), location: 0.68),
                                        .init(color: .white.opacity(strength * 0.5), location: 0.86),
                                        .init(color: .clear, location: 1),
                                    ]),
                                    center: point, startRadius: 0, endRadius: r
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: Gesture

    private var revealGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if !active {
                    active = true
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
                addSmudge(at: drag.location)
            }
            .onEnded { _ in
                active = false
                scheduleTrailClear()
            }
    }

    #if DEBUG
    /// A fixed diagonal sweep, decaying head→tail, for `--peekRevealDemoTrail`.
    private static func demoDabs(in size: CGSize) -> [(CGPoint, Double)] {
        let ts: [Double] = [1.0, 0.8, 0.62, 0.45, 0.3, 0.16]
        return ts.enumerated().map { i, strength in
            let f = CGFloat(ts.count - 1 - i) / CGFloat(ts.count - 1)  // 0 (tail) → 1 (head)
            return (CGPoint(x: size.width * (0.2 + 0.6 * f),
                            y: size.height * (0.25 + 0.4 * f)), strength)
        }
    }
    #endif

    private func addSmudge(at point: CGPoint) {
        let now = Date()
        trail.append(Smudge(point: point, birth: now))
        if !stayOpen {
            trail.removeAll { now.timeIntervalSince($0.birth) > lifetime }
        }
        if trail.count > maxSmudges { trail.removeFirst(trail.count - maxSmudges) }
    }

    /// After the finger lifts, the trail keeps decaying on its own; once it's had
    /// time to fade, drop it so `frontLayer` stops driving the per-frame Canvas.
    private func scheduleTrailClear() {
        guard !stayOpen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime + 0.2) {
            if !active { trail.removeAll() }
        }
    }
}

/// Attaches the gesture only when `enabled` — Classic mode pays nothing and the
/// card's own taps are untouched. A gesture can't be conditionally applied inline
/// without changing the view's type across the branch.
private struct RevealGestureModifier<G: Gesture>: ViewModifier {
    let enabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(gesture)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("Peek reveal") {
    // The wipe needs a live touch; this preview just shows the resting front and
    // that the two layers line up. Hold-and-swipe to test in a running build.
    PeekReveal(enabled: true) {
        Text("Front card content, a few lines tall so the frames differ.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).stroke(MirrorTheme.ember.opacity(0.4), lineWidth: 1)
            }
    } back: {
        Text("BEHIND · SIGNAL SOURCE")
            .font(MirrorTheme.mono(12, weight: .bold))
            .foregroundStyle(MirrorTheme.ember)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(22)
            .background(MirrorTheme.inkMid)
    }
    .frame(height: 220)
    .environment(\.appDisplayMode, .sentinel)
    .padding()
    .background(MirrorTheme.inkBase)
}
#endif
