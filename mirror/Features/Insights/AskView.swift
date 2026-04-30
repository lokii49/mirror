import SwiftUI
import SwiftData

struct AskView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query(sort: \Insight.generatedAt, order: .reverse) private var allInsights: [Insight]

    @State private var question = ""
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var isInputFocused: Bool

    private let monthLimit = 10

    private var askHistory: [Insight] {
        allInsights.filter { $0.type == .askResponse }
    }

    private var thisMonthCount: Int {
        let monthID = DateHelpers.monthIdentifier(for: Date())
        return askHistory.filter { $0.periodIdentifier == monthID }.count
    }

    private var remaining: Int { max(0, monthLimit - thisMonthCount) }
    private var canAsk: Bool {
        remaining > 0 && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                inputBar
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle("Ask")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if remaining <= 3 {
                        Text("\(remaining) left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(remaining <= 2 ? .orange : .secondary)
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                (remaining <= 2 ? Color.orange : Color.secondary).opacity(0.10),
                                in: Capsule()
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if askHistory.isEmpty && !isLoading {
            askEmptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    askHeader
                        .padding(.bottom, 8)
                    if isLoading {
                        LoadingAskBubble(question: question)
                    }
                    ForEach(askHistory) { insight in
                        AskBubblePair(insight: insight)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MirrorTheme.bgBase)
        }
    }

    private var askEmptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(MirrorTheme.accentGradient)
                    .frame(width: 88, height: 88)
                    .shadow(color: MirrorTheme.primary.opacity(0.35), radius: 24, x: 0, y: 10)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Text("Ask your journal")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Answers come only from entries you've written.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                ForEach(promptSuggestions, id: \.self) { prompt in
                    Button { question = prompt; isInputFocused = true } label: {
                        Text(prompt)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .futureSurface(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MirrorTheme.bgBase)
    }

    private let promptSuggestions = [
        "What have I been stressed about lately?",
        "When do I feel most alive?",
        "What patterns keep showing up?",
    ]

    private var askHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MirrorTheme.accentGradient)
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask Mirror")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(remaining) of \(monthLimit) questions this month")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(remaining <= 2 ? .orange : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(remaining == 0 ? "Monthly limit reached" : "Ask about your journal…", text: $question, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .disabled(remaining == 0)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(isInputFocused ? MirrorTheme.primary.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .animation(.easeInOut(duration: 0.2), value: isInputFocused)

                Button {
                    Task { await submitQuestion() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(canAsk ? MirrorTheme.accentGradient : LinearGradient(colors: [.secondary.opacity(0.3), .secondary.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 40, height: 40)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(!canAsk)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canAsk)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    private func submitQuestion() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, remaining > 0 else { return }
        isLoading = true
        error = nil
        let submitted = q
        question = ""
        isInputFocused = false

        do {
            let answer = try await InsightService.ask(question: submitted, entries: entries, token: "")
            let insight = Insight(
                type: .askResponse,
                content: answer,
                periodIdentifier: DateHelpers.monthIdentifier(for: Date()),
                question: submitted
            )
            modelContext.insert(insight)
        } catch InsightError.subscriptionRequired {
            error = "Core subscription required."
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

private struct AskBubblePair: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Question — right-aligned bubble
            if let question = insight.question {
                HStack {
                    Spacer(minLength: 48)
                    Text(question)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(MirrorTheme.accentGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }

            // Answer — left-aligned with avatar
            HStack(alignment: .bottom, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.accentGradient)
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.content)
                        .font(.system(size: 15))
                        .lineSpacing(5)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .futureSurface(cornerRadius: 18)

                Spacer(minLength: 28)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LoadingAskBubble: View {
    let question: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !question.isEmpty {
                HStack {
                    Spacer(minLength: 48)
                    Text(question)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(MirrorTheme.accentGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.accentGradient)
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                }

                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching your journal")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .futureSurface(cornerRadius: 18)

                Spacer(minLength: 28)
            }
        }
        .padding(.vertical, 4)
    }
}
