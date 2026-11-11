import SwiftUI

#if os(iOS)
/// A one-time hint above the keyboard: swipe down on the page to hide it. The bar has no
/// hide-keyboard button (WriteView's scroll view dismisses interactively instead), so the
/// gesture is shown once, the first time the on-screen keyboard comes up (owner, 2026-11-03).
///
/// Its own view with its own flag, so WriteView gains one child and no modifiers (the Debug
/// build sits at the main-thread stack limit). It counts as seen when the keyboard goes away
/// while it's up, when it's tapped, or after `visibleSeconds`.
struct KeyboardDismissHint: View {
    let isKeyboardVisible: Bool
    /// Another bottom card is showing; the hint waits (and isn't counted as seen).
    let isBlocked: Bool

    static let seenKey = "hasSeenKeyboardSwipeHint"
    private static let visibleSeconds: Double = 6

    @AppStorage(KeyboardDismissHint.seenKey) private var hasSeen = false
    @State private var isPresented = false
    @State private var chevronDown = false
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSentinel: Bool { displayMode == .sentinel }
    private var accent: Color { isSentinel ? MirrorTheme.ember : MirrorTheme.violet }

    /// UI tests and store screenshots keep the Write screen as it is.
    private static let isSuppressed: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--uitesting") || args.contains("--macSnapshot")
    }()

    var body: some View {
        ZStack {
            if isPresented && !isBlocked {
                hint
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .avoidingFold()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 16)
        .task(id: isKeyboardVisible && !isBlocked) {
            if isKeyboardVisible && !isBlocked {
                guard !hasSeen, !Self.isSuppressed else { return }
                // Let the keyboard finish rising before the hint arrives.
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, isKeyboardVisible, !isBlocked, !hasSeen else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isPresented = true }
                try? await Task.sleep(for: .seconds(Self.visibleSeconds))
                guard !Task.isCancelled else { return }
                finish()
            } else if isPresented {
                if isKeyboardVisible {
                    // Another card took the slot: step aside, show again next time.
                    isPresented = false
                } else {
                    // They swiped (or closed the keyboard another way) while it was showing.
                    finish()
                }
            }
        }
    }

    private var hint: some View {
        Button(action: finish) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.down")
                    .scaledFont(13, weight: .bold)
                    .foregroundStyle(accent)
                    .offset(y: chevronDown ? 4 : -3)
                    .opacity(chevronDown ? 0.45 : 1)
                    .frame(width: 18, height: 18)
                Text("Swipe down to hide the keyboard")
                    .textCase(isSentinel ? .uppercase : nil)
                    .scaledFont(isSentinel ? 11 : 13, weight: .semibold, design: isSentinel ? .monospaced : .default)
                    .kerning(isSentinel ? 0.4 : 0)
                    .foregroundStyle(MirrorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(accent.opacity(isSentinel ? 0.3 : 0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Swipe down to hide the keyboard")
        .accessibilityHint("Dismisses this tip")
        .onAppear {
            // Reset first: on a second showing the value is already true and wouldn't animate.
            chevronDown = false
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                chevronDown = true
            }
        }
    }

    private func finish() {
        hasSeen = true
        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
    }
}
#endif
