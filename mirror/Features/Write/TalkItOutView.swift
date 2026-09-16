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
        // On-device bug, two rounds (both found via real-device screenshots, not the
        // simulator): (1) with no way to dismiss the keyboard, the tab bar sat hidden
        // underneath it forever — "no back option." (2) The first fix added a separate
        // keyboard-toolbar "Done" button, which then sat stacked directly above the bottom
        // bar's own "Next" capsule — two near-identical buttons, correctly reported as
        // confusing. Advisor-reviewed final shape: one button, one location. The advance
        // action now lives *in* the keyboard toolbar — submitting an answer clears
        // `currentQuestion`, which drops focus and dismisses the keyboard as a side effect of
        // the same tap, rather than needing a second gesture or a second button to get back to
        // the tab bar. The bottom bar keeps only the passive "1 of 3" progress label and
        // "Finish" — no CTA competing with the toolbar.
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    submitAnswer()
                } label: {
                    Text(nextButtonLabel)
                        .font(bodyFont(15, weight: .semibold))
                }
                .disabled(currentQuestion == nil || answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
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
            Text(question)
                .font(bodyFont(17, serif: true))
                .foregroundStyle(MirrorTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

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
        VStack(spacing: 10) {
            if !turns.isEmpty || currentQuestion != nil {
                Text(progressLabel)
                    .font(bodyFont(11, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textTertiary)
                    .tracking(isSentinel ? 0.6 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !turns.isEmpty {
                Button(isSentinel ? "FINISH" : "Finish") { finish() }
                    .font(bodyFont(14, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
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
            answerFocused = true
            return
        }
        isLoadingQuestion = true
        do {
            let result = try await InsightService.generateGuidedQuestion(conversationSoFar: turns)
            isLoadingQuestion = false
            currentQuestion = result.text
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
