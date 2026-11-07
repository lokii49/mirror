import SwiftUI

/// Settings › Diagnostics › "Show how insights are made" (3.1.8, owner): the engine tags and the
/// "How this was generated" button that only Sentinel showed before it was retired. Off by default.
enum GenerationDetails {
    static let key = "diagnostics.showGenerationDetails"
}

/// A small "how this was generated" control on an insight card (Settings › Diagnostics switch).
/// Tapping it opens `InsightSourceSheet`: the on-device provenance HUD plus the
/// verbatim system prompt. No card-surface gesture — just a button.
struct InsightSourceButton: View {
    let insight: Insight
    @State private var show = false

    var body: some View {
        Button {
            show = true
        } label: {
            Image(systemName: "shield.lefthalf.filled")
                .scaledFont(11, weight: .bold)
                .foregroundStyle(MirrorTheme.violet)
                .padding(5)
                .background(MirrorTheme.violetDim, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How this was generated")
        .sheet(isPresented: $show) { InsightSourceSheet(insight: insight) }
    }
}

/// `.textSelection(.enabled)` and `.textSelection(.disabled)` resolve to
/// different types, so the choice can't be a ternary at the call site. Sentinel
/// insight bodies stay non-selectable to keep the mono/terminal read clean;
/// Classic keeps copy-to-select.
struct ConditionalTextSelection: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.textSelection(.enabled) }
        else { content.textSelection(.disabled) }
    }
}

extension View {
    func selectableUnlessSentinel(_ isSentinel: Bool) -> some View {
        modifier(ConditionalTextSelection(enabled: !isSentinel))
    }
}
