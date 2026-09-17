import SwiftUI

extension WriteView {
    /// Gates on the same Core/Deep tiers as every other AI surface in the app (Ask, nudges,
    /// digest) — consistent with precedent, not something the user was separately asked about.
    /// Also checks `LocalLLMService.isModelAvailable` first, matching its own documented
    /// contract — without this, a paying subscriber whose Gemma model isn't downloaded yet
    /// (Foundation Models unavailable) would open the sheet and have its first question
    /// generation fail immediately.
    func presentTalkItOut() {
        let sub = SubscriptionService.shared
        guard sub.tier == .core || sub.tier == .deep else {
            showTalkItOutPaywall = true
            return
        }
        guard LocalLLMService.isModelAvailable else {
            talkItOutUnavailableMessage = String(localized: "Mirror's on-device AI isn't ready yet — try again in a moment.")
            return
        }
        showTalkItOut = true
    }

    /// Appends into the already-open draft — this is invoked from inside an already-open
    /// WriteView (the chip only shows on a blank new entry), so there's no `initialText`
    /// prefill involved and no risk of the stale-draft-precedence bug that path once had.
    func appendTalkItOutText(_ text: String) {
        let trimmed = viewModel.text.trimmingCharacters(in: .newlines)
        viewModel.text = trimmed.isEmpty ? text : "\(trimmed)\n\n\(text)"
        // Same clamped-stale-selection bug templates hit (see WritingTemplate.cursorOffset) —
        // without this, the caret lands wherever it was before the append, not at the end where
        // the user would actually continue writing. Int.max relies on NoteEditorTextView's
        // `bounded(_:in:)` clamping to the text's true UTF-16 length, so this is exact even if
        // the appended text contains emoji or other multi-code-unit characters.
        applyTextCommand(.moveCursor(location: .max))
    }
}
