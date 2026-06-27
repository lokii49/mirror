import SwiftUI
import SwiftData

struct AskView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query(sort: \Insight.generatedAt, order: .reverse) private var allInsights: [Insight]

    @State private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false
    @State private var showSuggestions = false
    @State private var question = ""
    @State private var pendingQuestion = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isInputFocused: Bool

    private var monthLimit: Int {
        subscriptionService.isDeep ? Int.max : 15
    }
    private let bottomAnchorID = "ask-bottom-anchor"

    private let suggestions = [
        "What have I been stressed about lately?",
        "When do I feel most alive?",
        "What patterns keep showing up?",
        "What am I grateful for this week?",
        "What's been draining my energy?",
        "What made me smile recently?",
        "What am I avoiding?",
        "How has my mood changed over time?",
    ]

    private var askHistory: [Insight] {
        allInsights.filter { $0.type == .askResponse }
    }

    private var chatHistory: [Insight] {
        askHistory.sorted { $0.generatedAt < $1.generatedAt }
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
        Group {
            if subscriptionService.isSubscribed {
                VStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    inputBar
                }
                .padding(.bottom, keyboardHeight)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 10) {
                            if !subscriptionService.isDeep {
                                let isLow = remaining <= 3
                                let isCritical = remaining <= 1
                                Text("\(remaining) left")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isCritical ? .red : isLow ? .orange : .secondary)
                                    .monospacedDigit()
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        (isCritical ? Color.red : isLow ? Color.orange : Color.secondary).opacity(0.10),
                                        in: Capsule()
                                    )
                            }
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showSuggestions.toggle()
                                }
                            } label: {
                                Image(systemName: showSuggestions ? "lightbulb.fill" : "lightbulb")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(MirrorTheme.primary)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    updateKeyboardHeight(from: notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
                }
            } else {
                askLockedState
            }
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle("Ask")
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var askLockedState: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 88, height: 88)
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                Text("Ask is a Core feature")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Ask up to 15 questions per month on Core,\nor unlimited on Deep.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showPaywall = true
            } label: {
                Text("Unlock with Core")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(MirrorTheme.accentGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .shadow(color: MirrorTheme.primary.opacity(0.28), radius: 16, x: 0, y: 6)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if askHistory.isEmpty && !isLoading {
            askEmptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        askHeader
                            .padding(.bottom, 8)

                        Spacer(minLength: 12)

                        ForEach(chatHistory) { insight in
                            AskBubblePair(insight: insight)
                        }

                        if isLoading {
                            LoadingAskBubble(question: pendingQuestion)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(MirrorTheme.bgBase)
                .onAppear {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
                .onChange(of: chatHistory.count) { _, _ in
                    scrollToLatest(proxy)
                }
                .onChange(of: isLoading) { _, _ in
                    scrollToLatest(proxy)
                }
                .onChange(of: isInputFocused) { _, focused in
                    if focused {
                        scrollToLatest(proxy)
                    }
                }
            }
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)

                ForEach(suggestions.prefix(3), id: \.self) { prompt in
                    Button {
                        question = prompt
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showSuggestions = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInputFocused = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(prompt)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(MirrorTheme.primary.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(MirrorTheme.inkRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(MirrorTheme.inkBorder, lineWidth: 1)
                        }
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
                Text("Ask MirrorNotes")
                    .font(.system(size: 15, weight: .semibold))
                Text(subscriptionService.isDeep ? "Unlimited questions" : "\(remaining) of 15 questions this month")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(remaining <= 2 && !subscriptionService.isDeep ? .orange : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var suggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { prompt in
                    Button {
                        question = prompt
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showSuggestions = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInputFocused = true
                        }
                    } label: {
                        Text(prompt)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(MirrorTheme.inkRaised, in: Capsule())
                            .overlay(Capsule().stroke(MirrorTheme.inkBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            if showSuggestions {
                suggestionsRow
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
        pendingQuestion = submitted
        question = ""
        isInputFocused = false

        do {
            let answer = try await InsightService.ask(question: submitted, entries: entries)
            let insight = Insight(
                type: .askResponse,
                content: answer,
                periodIdentifier: DateHelpers.monthIdentifier(for: Date()),
                question: submitted
            )
            modelContext.insert(insight)
            try modelContext.save()
        } catch InsightError.subscriptionRequired {
            error = "Core subscription required."
        } catch {
            self.error = "Something went wrong. Try your question again."
        }

        isLoading = false
        pendingQuestion = ""
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func updateKeyboardHeight(from notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
            return
        }
        // TabView forces .ignoresSafeArea(.keyboard) on all descendants.
        // Raw keyboard height includes the home indicator inset (~34pt), subtract it to avoid a gap.
        let bottomInset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
        let rawHeight = max(0, UIScreen.main.bounds.height - frame.minY)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = rawHeight > 0 ? rawHeight - bottomInset : 0
        }
    }

}


private struct AskBubblePair: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let question = insight.question {
                HStack {
                    Spacer(minLength: 48)
                    Text(question)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(MirrorTheme.violetLight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(MirrorTheme.violetDim, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(MirrorTheme.violet.opacity(0.3), lineWidth: 1)
                        }
                }
            }

            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MirrorTheme.violetLight.opacity(0.4))
                    .frame(width: 2)
                    .padding(.vertical, 3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.content)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .lineSpacing(6)
                        .foregroundStyle(MirrorTheme.textPrimary)
                        .textSelection(.enabled)

                    Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(MirrorTheme.textTertiary)
                }
                .padding(.leading, 14)
            }
            .padding(.top, 4)
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

            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MirrorTheme.violetLight.opacity(0.4))
                    .frame(width: 2)
                    .padding(.vertical, 3)

                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(MirrorTheme.violetLight)
                    Text("Searching your journal")
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
                .padding(.leading, 14)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

#Preview("Locked") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Entry.self, Insight.self, UserProfile.self, configurations: config)
    return NavigationStack {
        AskView()
    }
    .modelContainer(container)
}

#Preview("Empty State") {
    NavigationStack {
        VStack(spacing: 0) {
            AskEmptyStatePreview()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your journal…", text: .constant(""))
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.secondary.opacity(0.3), .secondary.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle("Ask")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MirrorTheme.primary)
            }
        }
    }
}

private struct AskEmptyStatePreview: View {
    private let suggestions = [
        "What have I been stressed about lately?",
        "When do I feel most alive?",
        "What patterns keep showing up?",
    ]

    var body: some View {
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
                ForEach(suggestions, id: \.self) { prompt in
                    HStack(spacing: 10) {
                        Text(prompt)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(MirrorTheme.primary.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 4)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MirrorTheme.bgBase)
    }
}
