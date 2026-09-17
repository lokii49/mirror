import SwiftUI

/// Tier 2 ("Talk it out", writing-roadmap.md) — a short guided, multi-turn on-device
/// conversation that composes into draft text handed back via `onFinish`. Entirely ephemeral:
/// this view owns all state, nothing is persisted anywhere (no SwiftData, no draft store, no
/// CloudKit schema) — every turn is discarded once the view goes away, except the text
/// explicitly handed to `onFinish`.
///
/// Deliberately just content, not a sheet: it's hosted as the body of the "Talk" tab
/// (`ContentView.swift`'s `TalkTabView`), so it owns no `NavigationStack`, title, or dismiss
/// affordance of its own — the caller supplies chrome and decides what "start over" means
/// (`onCancel`), since a persistent tab has no modal to dismiss.
///
/// Deliberately reads as a document, not a chat log — no bubbles. The transcript this view
/// builds *is* a preview of the journal entry it becomes (`composedText(from:)`), so treating
/// it as a flowing page rather than a messaging UI previews the real result and keeps mirror's
/// serif-prose identity instead of the generic cloud-chatbot look every competitor already has.
/// The one accent device (a left rule marking the question currently being answered) is a
/// direct callback to `WritingPromptCard`'s identical mark, not a new invention.
///
/// Scoped deliberately smaller than "Daily Chat" competitors: answers are typed, not voice
/// (wiring VoiceInputManager's full recording/transcription/permission flow into this was
/// judged a separate follow-up, not required to prove the guided-entry value on-device), and
/// the composed result is the raw Q&A pairs handed to the caller — not a second LLM pass that
/// rewrites them into prose. Both keep this a mechanical composition of already-proven pieces
/// (InsightService.generateGuidedQuestion reuses the .followUp task's validator/cleaning)
/// rather than a new failure-prone surface.
struct TalkItOutView: View {
    var onFinish: (String) -> Void
    var onCancel: (() -> Void)? = nil

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }
    private var accent: Color { isSentinel ? MirrorTheme.ember : MirrorTheme.violet }
    private var engineTag: String? {
        switch currentQuestionEngine {
        case .gemma: return "GEMMA"
        case .foundationModels: return "FM"
        case nil: return nil
        }
    }

    // Sizes below are all `base * typeScale` — one shared metric, the same pattern
    // FormattingPanelView's Dynamic Type fix (writeview-audit.md 2.5) established, rather than
    // fifteen independent fixed .system(size:) values that scale inconsistently.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1.0

    // 3, not the original 4 — advisor audit: quality/repetition risk on the 1B (Gemma) path
    // compounds per turn (longer transcript fed back in, "don't repeat a question" is a
    // negative constraint over growing context, exactly what small models do worst), and this
    // hasn't been measured against a real model yet. Cutting one turn caps the exposure without
    // giving up the "multi-turn" shape entirely.
    static let maxQuestions = 3

    @State private var turns: [(question: String, answer: String)] = []
    @State private var currentQuestion: String? = nil
    /// nil for question 1 (seeded from WritingPrompts.all, no model involved). Surfaced only in
    /// Sentinel mode — same X-ray attribution pattern as FollowUpChip (1.2) and
    /// InsightSignalSource, closing the "can't tell which engine produced a bad question" gap
    /// without adding persistence this feature deliberately avoids.
    @State private var currentQuestionEngine: LLMEngine? = nil
    @State private var answerDraft: String = ""
    @State private var isLoadingQuestion = false
    @State private var errorMessage: String? = nil
    @FocusState private var answerFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                    answeredTurn(question: turn.question, answer: turn.answer)
                    if index < turns.count - 1 || currentQuestion != nil || isLoadingQuestion {
                        divider
                    }
                }

                if let currentQuestion {
                    activeQuestion(currentQuestion)
                        .id(currentQuestion)
                        .transition(.asymmetric(
                            insertion: .push(from: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else if isLoadingQuestion {
                    HStack(spacing: 8) {
                        ProgressView().tint(isSentinel ? MirrorTheme.ember : .secondary)
                        Text("Thinking…")
                            .font(bodyFont(13, weight: .medium))
                            .foregroundStyle(MirrorTheme.textSecondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentQuestion)
        }
        .background(MirrorTheme.inkBase)
        // On-device bug, three rounds, all found via real-device screenshots — the simulator
        // never caught any of them: (1) with no way to dismiss the keyboard, the tab bar sat
        // hidden underneath it forever — "no back option." (2) A keyboard-toolbar "Done" button
        // fixed that but sat stacked directly above the bottom bar's own "Next" capsule — two
        // near-identical buttons. (3) Moving the advance action *into* the keyboard toolbar
        // (advisor-reviewed: "one button, one location") removed the duplicate, but
        // `.toolbar(placement: .keyboard)` on a view with no local `NavigationStack` (this one
        // is hosted inside `TalkTabView`'s) simply didn't render on-device at all — not
        // disabled, not hidden by state, just absent, leaving no way to advance whatsoever.
        // Reverted to a single, always-visible bottom-bar button instead of continuing to fight
        // an unreliable API — empirical on-device failure overrides the earlier reasoning.
        // `.scrollDismissesKeyboard(.interactively)` (matches WriteView's own editor) is the
        // sole keyboard-dismiss path now — a real, if imperfect, improvement over the original
        // zero-affordance bug, not a guaranteed one.
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            // Never an OK-only dead end: a failed generation used to leave no question,
            // no Next (disabled without a question), and no Finish (hidden when turns is
            // empty) — the only way out was Cancel. Always offer a retry, plus whichever
            // exit makes sense for what's been collected so far.
            Button("Try Again") { Task { await loadNextQuestion() } }
            if turns.isEmpty {
                Button("Cancel", role: .cancel) { onCancel?() }
            } else {
                Button("Finish", role: .cancel) { finish() }
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if turns.isEmpty && currentQuestion == nil {
                await loadNextQuestion()
            }
        }
    }

    // MARK: - Turns

    private func answeredTurn(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(bodyFont(13, weight: .medium, serif: true))
                .foregroundStyle(MirrorTheme.textSecondary)
            Text(answer)
                .font(bodyFont(16, serif: true))
                .foregroundStyle(MirrorTheme.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(MirrorTheme.inkBorder)
            .frame(height: 1)
    }

    private func activeQuestion(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(question)
                    .font(bodyFont(17, serif: true))
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Shuffle only makes sense for question 1 — it's a random pick from
                // WritingPrompts.all, a fixed pool, so re-picking is instant and free.
                // Questions 2+ are generated from the conversation so far
                // (InsightService.generateGuidedQuestion); "shuffling" one would mean another
                // on-device generation call, re-surfacing the unmeasured model-quality risk
                // this doc already flags, for a feature nobody asked for on those turns.
                if turns.isEmpty {
                    Button(action: shuffleFirstQuestion) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle question")
                }
            }

            if isSentinel, let engineTag {
                Text(engineTag)
                    .font(MirrorTheme.mono(8.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(MirrorTheme.textTertiary)
            }

            ZStack(alignment: .topLeading) {
                if answerDraft.isEmpty {
                    Text("Write your answer…")
                        .font(bodyFont(15, serif: true))
                        .foregroundStyle(MirrorTheme.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $answerDraft)
                    .focused($answerFocused)
                    .font(bodyFont(15, serif: true))
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 90 * typeScale, maxHeight: 160 * typeScale)
            }
            .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MirrorTheme.inkBorder, lineWidth: 1)
            }
        }
        .padding(.top, 16)
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3)
                .padding(.top, 16)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if !turns.isEmpty || currentQuestion != nil {
                Text(progressLabel)
                    .font(bodyFont(11, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textTertiary)
                    .tracking(isSentinel ? 0.6 : 0)
            }
            Spacer()
            if !turns.isEmpty {
                Button(isSentinel ? "FINISH" : "Finish") { finish() }
                    .font(bodyFont(14, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            Button {
                submitAnswer()
            } label: {
                Text(nextButtonLabel)
                    .font(bodyFont(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(currentQuestion == nil || answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(currentQuestion == nil || answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(MirrorTheme.inkMid)
        .overlay(alignment: .top) {
            Rectangle().fill(MirrorTheme.inkBorder).frame(height: 1)
        }
    }

    private var progressLabel: String {
        let position = min(turns.count + 1, Self.maxQuestions)
        return isSentinel
            ? String(localized: "\(position) OF \(Self.maxQuestions)")
            : String(localized: "\(position) of \(Self.maxQuestions)")
    }

    private var nextButtonLabel: String {
        let isLastQuestion = turns.count + 1 >= Self.maxQuestions
        if isSentinel {
            return isLastQuestion ? String(localized: "DONE") : String(localized: "NEXT")
        }
        return isLastQuestion ? String(localized: "Done") : String(localized: "Next")
    }

    private func bodyFont(_ size: CGFloat, weight: Font.Weight = .regular, serif: Bool = false) -> Font {
        if isSentinel && !serif {
            return MirrorTheme.mono(size * typeScale, weight: weight)
        }
        return .system(size: size * typeScale, weight: weight, design: serif ? .serif : .default)
    }

    // MARK: - Logic

    private func shuffleFirstQuestion() {
        guard turns.isEmpty, WritingPrompts.all.count > 1 else { return }
        var next = WritingPrompts.all.randomElement()
        while next == currentQuestion {
            next = WritingPrompts.all.randomElement()
        }
        // Body's own `.animation(value: currentQuestion)` picks this up automatically —
        // matches loadNextQuestion, which doesn't wrap its assignment either.
        currentQuestion = next
        answerDraft = ""
    }

    private func loadNextQuestion() async {
        // Question 1 is seeded from the existing prompt library instead of generated — it's
        // the first thing this tab ever shows (highest cost if it's bad) and the least a model
        // is needed for (GUIDED_ENTRY_SYSTEM's "broad and welcoming" ask is exactly what
        // WritingPrompts.all already is). Also sidesteps the untested case of a 1B model
        // producing a clean single question with zero prior conversation to ground it.
        // Advisor audit: neither this path nor generateGuidedQuestion's multi-turn path has
        // been run against a real model — see the Tier 2 STATUS block in writing-roadmap.md.
        guard !turns.isEmpty else {
            currentQuestion = WritingPrompts.all.randomElement()
            currentQuestionEngine = nil
            answerFocused = true
            return
        }
        isLoadingQuestion = true
        do {
            let result = try await InsightService.generateGuidedQuestion(conversationSoFar: turns)
            isLoadingQuestion = false
            currentQuestion = result.text
            currentQuestionEngine = result.engine
            answerFocused = true
        } catch {
            isLoadingQuestion = false
            errorMessage = String(localized: "Couldn't come up with a question right now. Try again in a moment.")
        }
    }

    private func submitAnswer() {
        guard let currentQuestion else { return }
        let trimmed = answerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        turns.append((question: currentQuestion, answer: trimmed))
        answerDraft = ""
        self.currentQuestion = nil
        if turns.count >= Self.maxQuestions {
            finish()
        } else {
            Task { await loadNextQuestion() }
        }
    }

    private func finish() {
        guard !turns.isEmpty else {
            onCancel?()
            return
        }
        onFinish(Self.composedText(from: turns))
    }

    static func composedText(from turns: [(question: String, answer: String)]) -> String {
        turns.map { "\($0.question)\n\($0.answer)" }.joined(separator: "\n\n")
    }
}
