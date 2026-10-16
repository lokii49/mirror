import SwiftUI

// One-shot SF Symbol animations for the Write screen. Each plays on a change the screen already
// has (a tap, the entry becoming saveable, the word goal reached) and none repeats, so nothing
// keeps moving while someone writes. Reduce Motion turns them all off.

extension View {
    /// Bounces the symbol each time `value` changes.
    func glyphBounce<V: Equatable>(value: V, byLayer: Bool = false) -> some View {
        modifier(GlyphBounce(value: value, byLayer: byLayer, playsFor: { _ in true }))
    }

    /// Bounces the symbol when `isOn` turns true, not when it turns back off.
    func glyphBounce(whenTurnsOn isOn: Bool, byLayer: Bool = false) -> some View {
        modifier(GlyphBounce(value: isOn, byLayer: byLayer, playsFor: { $0 }))
    }

    /// Swaps one symbol for the next with the system's replace animation instead of a cut.
    func glyphReplaceTransition() -> some View {
        modifier(GlyphReplace())
    }

    /// The symbol draws itself on as it's inserted (iOS 26 and later; it scales in before that).
    /// Like any transition it plays only when the insertion is animated. Only symbols with draw
    /// paths draw; a filled one (checkmark.circle.fill) just fades, so use `glyphPopIn` there.
    func glyphDrawOnInsertion() -> some View {
        modifier(GlyphDrawOnInsertion())
    }

    /// The symbol scales in as it's inserted and then bounces once: a small "done" moment.
    func glyphPopIn() -> some View {
        modifier(GlyphPopIn())
    }
}

private struct GlyphBounce<V: Equatable>: ViewModifier {
    let value: V
    let byLayer: Bool
    let playsFor: (V) -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts plays rather than handing `value` to the effect, so a change Reduce Motion or
    /// `playsFor` rules out doesn't play.
    @State private var plays = 0

    func body(content: Content) -> some View {
        content
            .symbolEffect(byLayer ? BounceSymbolEffect.bounce.byLayer : .bounce, value: plays)
            .onChange(of: value) { _, newValue in
                if !reduceMotion && playsFor(newValue) { plays &+= 1 }
            }
    }
}

private struct GlyphReplace: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
    }
}

private struct GlyphPopIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plays = 0

    func body(content: Content) -> some View {
        content
            .symbolEffect(.bounce, value: plays)
            .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.appear)).combined(with: .opacity))
            .onAppear {
                guard !reduceMotion else { return }
                // A beat after insertion, so the bounce follows the scale-in.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { plays &+= 1 }
            }
    }
}

private struct GlyphDrawOnInsertion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : Self.drawOn)
    }

    private static var drawOn: AnyTransition {
        if #available(iOS 26, macOS 26, *) {
            return AnyTransition(.symbolEffect(.drawOn)).combined(with: .opacity)
        }
        return AnyTransition(.symbolEffect(.appear)).combined(with: .opacity)
    }
}
