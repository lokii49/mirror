import SwiftUI
import UIKit

/// Press-and-hold a card to X-ray it — the front dissolves into a wireframe of
/// itself and a "behind the glass" panel fades in over it, for as long as the
/// finger stays down. Releasing springs it straight back. This is a Sentinel-mode
/// signature interaction; in Classic it's inert (renders `front`, no gesture).
///
/// First use: the daily reflection card (`ReflectionSignalSource` as the back).
/// The gesture is a long-press *sequenced before* a zero-distance drag so the
/// finger-lift is caught reliably — `@GestureState` auto-resets to its initial
/// value the instant the gesture ends, which is exactly the "peek while held"
/// semantics with no dismiss state to manage.
struct PeekReveal<Front: View, Back: View>: View {
    var enabled: Bool
    /// Must match the wrapped card's own radius so the wireframe stroke and the
    /// clipped back-face line up with the card edge. Sentinel's `themedCard` is
    /// 10; pass the card's value when wrapping something else.
    var cornerRadius: CGFloat = 10
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back

    @GestureState private var holding = false
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if DEBUG
    // Screenshot/QA hook: `--peekRevealAlwaysOn` pins the back-face open so the
    // held state is capturable without a live touch. `--peekRevealStayOpen`
    // keeps it open after the finger lifts, so a UI test can press-and-release
    // and still assert the reveal fired (a mid-gesture screenshot isn't
    // possible from XCUITest). No effect in release.
    private let forceOpen = ProcessInfo.processInfo.arguments.contains("--peekRevealAlwaysOn")
    private let stayOpen = ProcessInfo.processInfo.arguments.contains("--peekRevealStayOpen")
    #else
    private let forceOpen = false
    private let stayOpen = false
    #endif
    private var showBack: Bool { revealed || forceOpen }

    private var holdGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($holding) { value, state, _ in
                // .second(true, _) = long-press satisfied and the drag (the
                // continued touch) is active. Anything else = not holding.
                if case .second(true, _) = value { state = true } else { state = false }
            }
    }

    var body: some View {
        front
            .opacity(showBack ? 0.06 : 1)
            .blur(radius: showBack ? 2 : 0)
            // `back` as an overlay = exactly the front's frame, so the X-ray
            // panel is the same size as the card it replaces — no ballooning.
            .overlay {
                if showBack {
                    back
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .transition(.opacity)
                }
            }
            // The wireframe: the front's silhouette, left behind as it dissolves.
            .overlay {
                if showBack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(MirrorTheme.ember.opacity(0.55), lineWidth: 1)
                        .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .modifier(HoldGestureModifier(enabled: enabled, gesture: holdGesture))
            .onChange(of: holding) { _, isHolding in
                guard enabled else { return }
                let next = isHolding || stayOpen
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.24)) {
                    revealed = next
                }
                if isHolding {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityHint(enabled ? "Press and hold to inspect how this was generated" : "")
    }
}

/// Attaches the hold gesture only when `enabled`, so Classic mode pays nothing
/// and the card's own taps/long-presses are untouched there. Kept as a modifier
/// because a gesture can't be conditionally applied inline without changing the
/// view's type across the branch.
private struct HoldGestureModifier<G: Gesture>: ViewModifier {
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
    // The gesture needs a device/simulator to fire; this preview is for the
    // resting front and the two card frames lining up. Hold to test the reveal
    // in a running build.
    PeekReveal(enabled: true) {
        Text("Front card content, a few lines tall so the frames differ.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).stroke(MirrorTheme.ember.opacity(0.4), lineWidth: 1)
            }
    } back: {
        Text("BACK · X-RAY PANEL")
            .font(MirrorTheme.mono(12, weight: .bold))
            .foregroundStyle(MirrorTheme.ember)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 10))
    }
    .environment(\.appDisplayMode, .sentinel)
    .padding()
    .background(MirrorTheme.inkBase)
}
#endif
