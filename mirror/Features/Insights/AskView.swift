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
                    Text("\(remaining) left")
                        .font(.caption)
                        .foregroundStyle(remaining <= 2 ? .orange : .secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if askHistory.isEmpty && !isLoading {
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
                    .frame(width: 86, height: 86)
                    .background(MirrorTheme.primary.opacity(0.12), in: Circle())
                VStack(spacing: 6) {
                    Text("Ask your journal")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Answers are grounded only in entries you’ve written.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MirrorTheme.bgBase)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    askHeader
                    if isLoading {
                        LoadingAskRow(question: question)
                    }
                    ForEach(askHistory) { insight in
                        AskRow(insight: insight)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(MirrorTheme.bgBase)
        }
    }

    private var askHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(remaining) questions left", systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(remaining <= 2 ? .orange : MirrorTheme.primary)
            Text("Search memory without leaving the writing flow.")
                .font(.system(size: 22, weight: .bold, design: .rounded))
        }
        .padding(18)
        .futureSurface(cornerRadius: 26)
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
                TextField("Ask about your journal", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .disabled(remaining == 0)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                Button {
                    Task { await submitQuestion() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!canAsk)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if remaining == 0 {
                Text("Monthly limit reached. Resets next month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func submitQuestion() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, remaining > 0 else { return }
        guard let token = KeychainManager.load() else {
            error = "Sign in to use Ask."
            return
        }

        isLoading = true
        error = nil
        let submitted = q
        question = ""
        isInputFocused = false

        do {
            let answer = try await InsightService.ask(question: submitted, entries: entries, token: token)
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

private struct AskRow: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let question = insight.question {
                Text(question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(insight.content)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)

            Text(insight.generatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .futureSurface(cornerRadius: 20)
    }
}

private struct LoadingAskRow: View {
    let question: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(question.isEmpty ? "Searching your journal" : question)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .futureSurface(cornerRadius: 20)
    }
}
