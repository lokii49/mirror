import SwiftUI
import SwiftData

struct AskView: View {
    let viewModel: InsightViewModel
    /// Seeds the question field on first appear (e.g. from a Brain View node).
    /// Prefill only — never auto-submits.
    var initialQuestion: String? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.appDisplayMode) private var displayMode
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query(sort: \Insight.generatedAt, order: .reverse) private var allInsights: [Insight]

    @State private var subscriptionService = SubscriptionService.shared
    @State private var modelManager = ModelDownloadManager.shared
    @State private var showPaywall = false
    @State private var cachedAskHistory: [Insight] = []
    @State private var cachedChatHistory: [Insight] = []

    private var contentMaxWidth: CGFloat { hSizeClass == .regular ? 700 : .infinity }
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
        String(localized: "What have I been stressed about lately?"),
        String(localized: "When do I feel most alive?"),
        String(localized: "What patterns keep showing up?"),
        String(localized: "What am I grateful for this week?"),
        String(localized: "What's been draining my energy?"),
        String(localized: "What made me smile recently?"),
        String(localized: "What am I avoiding?"),
        String(localized: "How has my mood changed over time?"),
    ]

    // Cached via .task(id: allInsights.count) below — allInsights spans full history with
    // no date/range predicate, and this view holds frequently-churning @State (question,
    // keyboardHeight, isInputFocused) that re-evaluates body on every keystroke/keyboard
    // event, which would otherwise re-run this filter+sort on every one of those.
    private var askHistory: [Insight] { cachedAskHistory }

    private var chatHistory: [Insight] { cachedChatHistory }

    private var thisMonthCount: Int {
        let monthID = DateHelpers.monthIdentifier(for: Date())
        return cachedAskHistory.filter { $0.periodIdentifier == monthID }.count
    }

    private var remaining: Int { max(0, monthLimit - thisMonthCount) }
    private var canAsk: Bool {
        remaining > 0 && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        Group {
            switch viewModel.askState {
            case .idle:
                Color.clear
            case .subscriptionRequired:
                askLockedState
            case .notEnoughEntries(let remaining):
                askNotEnoughEntriesState(remaining: remaining)
            case .modelNotInstalled:
                askModelNotInstalledState
            case .ready:
                VStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    inputBar
                }
                .padding(.bottom, keyboardHeight)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .toolbar {
                    if !subscriptionService.isDeep {
                        ToolbarItem(placement: .topBarTrailing) {
                            let isLow = remaining <= 3
                            let isCritical = remaining <= 1
                            Text(displayMode == .sentinel ? "\(remaining) LEFT" : "\(remaining) left")
                                .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 12, weight: .semibold))
                                .foregroundStyle(isCritical ? .red : isLow ? .orange : MirrorTheme.textSecondary)
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    (isCritical ? Color.red : isLow ? Color.orange : MirrorTheme.textSecondary).opacity(0.10),
                                    in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous)) : AnyShape(Capsule())
                                )
                                .overlay {
                                    if displayMode == .sentinel {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke((isCritical ? Color.red : isLow ? Color.orange : MirrorTheme.textSecondary).opacity(0.3), lineWidth: 1)
                                    }
                                }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showSuggestions.toggle()
                            }
                        } label: {
                            Image(systemName: showSuggestions ? "lightbulb.fill" : "lightbulb")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    updateKeyboardHeight(from: notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
                }
            }
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle(displayMode == .sentinel ? "Comms" : "Ask")
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showPaywall) { PaywallView().environment(\.appDisplayMode, displayMode) }
        .onAppear {
            viewModel.loadAskState(entries: entries)
            if let initialQuestion, question.isEmpty {
                question = initialQuestion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isInputFocused = true
                }
            }
        }
        .onChange(of: entries.count) { _, _ in
            viewModel.loadAskState(entries: entries)
        }
        .onChange(of: modelManager.state) { _, _ in
            viewModel.loadAskState(entries: entries)
        }
        .onChange(of: SubscriptionService.shared.tier) { _, _ in
            viewModel.loadAskState(entries: entries)
        }
        .task(id: allInsights.count) {
            recomputeAskHistoryCache()
        }
    }

    private func recomputeAskHistoryCache() {
        cachedAskHistory = allInsights.filter { $0.type == .askResponse }
        cachedChatHistory = cachedAskHistory.sorted { $0.generatedAt < $1.generatedAt }
    }

    private var askLockedState: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                if displayMode == .sentinel {
                    Circle().stroke(MirrorTheme.ember.opacity(0.4), lineWidth: 1.4).frame(width: 88, height: 88)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(MirrorTheme.ember.opacity(0.7))
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(width: 88, height: 88)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                Text(displayMode == .sentinel ? "COMMS LOCKED" : "Ask is a Core feature")
                    .font(displayMode == .sentinel ? MirrorTheme.mono(16, weight: .bold) : .system(size: 22, weight: .bold, design: .rounded))
                    .kerning(displayMode == .sentinel ? 0.4 : 0)
                    .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.textPrimary)
                Text("Ask up to 15 questions per month on Core,\nor unlimited on Deep.")
                    .font(displayMode == .sentinel ? MirrorTheme.mono(12.5, weight: .medium) : .system(size: 15))
                    .foregroundStyle(displayMode == .sentinel ? MirrorTheme.textSecondary : Color.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showPaywall = true
            } label: {
                Text(displayMode == .sentinel ? "UNLOCK WITH CORE" : "Unlock with Core")
                    .font(displayMode == .sentinel ? MirrorTheme.mono(14, weight: .bold) : .system(size: 16, weight: .semibold))
                    .kerning(displayMode == .sentinel ? 0.4 : 0)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(MirrorTheme.accentGradient), in: Capsule())
            }
            .buttonStyle(.plain)
            .shadow(color: (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary).opacity(0.28), radius: 16, x: 0, y: 6)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func askNotEnoughEntriesState(remaining: Int) -> some View {
        heroState(
            icon: "pencil.and.scribble",
            title: "Mirror is still learning",
            subtitle: remaining == 1
                ? "Ask needs 1 more entry before it can find patterns in your journal."
                : "Ask needs \(remaining) more entries before it can find patterns in your journal."
        )
    }

    private var askModelNotInstalledState: some View {
        heroState(
            icon: "brain.head.profile",
            title: "Ask needs the on-device model",
            subtitle: "MirrorNotes uses Gemma 3 1B — it runs fully on your device, so nothing you write is ever sent anywhere. One-time ~800MB download."
        ) {
            ModelDownloadStateControl()
        }
    }

    private func heroState<Trailing: View>(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                if displayMode == .sentinel {
                    Circle().stroke(MirrorTheme.ember.opacity(0.55), lineWidth: 1.4).frame(width: 88, height: 88)
                    Circle().stroke(MirrorTheme.ember.opacity(0.28), lineWidth: 1).frame(width: 112, height: 112)
                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(MirrorTheme.ember)
                } else {
                    Circle()
                        .fill(MirrorTheme.accentGradient)
                        .frame(width: 88, height: 88)
                        .shadow(color: MirrorTheme.primary.opacity(0.35), radius: 24, x: 0, y: 10)
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            VStack(spacing: 8) {
                Text(title)
                    .font(displayMode == .sentinel ? MirrorTheme.mono(16, weight: .bold) : .system(size: 22, weight: .bold, design: .rounded))
                    .kerning(displayMode == .sentinel ? 0.4 : 0)
                    .textCase(displayMode == .sentinel ? .uppercase : nil)
                    .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.textPrimary)
                Text(subtitle)
                    .font(displayMode == .sentinel ? MirrorTheme.mono(12.5, weight: .medium) : .system(size: 15))
                    .foregroundStyle(displayMode == .sentinel ? MirrorTheme.textSecondary : Color.secondary)
                    .multilineTextAlignment(.center)
            }
            trailing()
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
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity)
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

    /// Radial hub of up to 6 recent entries, mood-colored — a lightweight
    /// stand-in for the full BrainGraphBuilder constellation (which needs
    /// per-entry term extraction and isn't worth invoking just to decorate
    /// this empty state). Real data, cheap computation.
    private var pulseHub: some View {
        let recent = Array(entries.prefix(6))
        let angleStep = Double.pi * 2 / Double(max(recent.count, 1))
        return ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.42
                for (index, entry) in recent.enumerated() {
                    let angle = angleStep * Double(index) - .pi / 2
                    let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: point)
                    context.stroke(path, with: .color(MirrorTheme.violetLight.opacity(0.35)), lineWidth: 1)
                    let dotColor = entry.mood.map { MirrorTheme.moodColor(for: $0) } ?? MirrorTheme.violetLight
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(dotColor))
                }
            }
            Circle().stroke(MirrorTheme.ember.opacity(0.55), lineWidth: 1.4).frame(width: 84, height: 84)
            Circle().stroke(MirrorTheme.ember.opacity(0.28), lineWidth: 1).frame(width: 118, height: 118)
            Circle()
                .fill(MirrorTheme.ember)
                .frame(width: 22, height: 22)
                .shadow(color: MirrorTheme.ember.opacity(0.6), radius: 12)
        }
        .frame(width: 140, height: 140)
    }

    private var askEmptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            if displayMode == .sentinel {
                pulseHub
                HStack(spacing: 6) {
                    Circle().fill(MirrorTheme.ember).frame(width: 6, height: 6)
                    Text("SENTINEL — LISTENING")
                        .font(MirrorTheme.mono(10, weight: .bold))
                        .foregroundStyle(MirrorTheme.ember)
                        .kerning(0.6)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.accentGradient)
                        .frame(width: 88, height: 88)
                        .shadow(color: MirrorTheme.primary.opacity(0.35), radius: 24, x: 0, y: 10)
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            VStack(spacing: 8) {
                Text(displayMode == .sentinel ? "Ask anything" : "Ask your journal")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Answers come only from entries you've written.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(displayMode == .sentinel ? "SUGGESTED QUERIES" : "Try asking")
                    .font(displayMode == .sentinel ? MirrorTheme.mono(10.5, weight: .bold) : .system(size: 12, weight: .semibold))
                    .kerning(displayMode == .sentinel ? 0.3 : 0)
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
                                .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.7) : MirrorTheme.primary.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(MirrorTheme.inkRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.25) : MirrorTheme.inkBorder, lineWidth: 1)
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
                    .fill(displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(MirrorTheme.accentGradient))
                    .frame(width: 36, height: 36)
                Image(systemName: displayMode == .sentinel ? "dot.radiowaves.left.and.right" : "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(displayMode == .sentinel ? "SENTINEL" : "Ask MirrorNotes")
                    .font(displayMode == .sentinel ? MirrorTheme.mono(15, weight: .bold) : .system(size: 15, weight: .semibold))
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
                    HStack(alignment: .center, spacing: 6) {
                        if displayMode == .sentinel {
                            Text(">")
                                .font(MirrorTheme.mono(15, weight: .bold))
                                .foregroundStyle(MirrorTheme.ember)
                        }
                        TextField(
                            remaining == 0 ? (displayMode == .sentinel ? "MONTHLY LIMIT REACHED" : "Monthly limit reached") : (displayMode == .sentinel ? "ask anything_" : "Ask about your journal…"),
                            text: $question, axis: .vertical
                        )
                            .lineLimit(1...5)
                            .textFieldStyle(.plain)
                            .focused($isInputFocused)
                            .disabled(remaining == 0)
                            .font(displayMode == .sentinel ? MirrorTheme.mono(14) : .system(size: 15))
                    }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(.ultraThinMaterial),
                            in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) : AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        )
                        .overlay {
                            if displayMode == .sentinel {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isInputFocused ? MirrorTheme.ember.opacity(0.5) : MirrorTheme.inkBorder, lineWidth: 1)
                            } else {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(isInputFocused ? MirrorTheme.primary.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: isInputFocused)

                    Button {
                        Task { await submitQuestion() }
                    } label: {
                        ZStack {
                            if displayMode == .sentinel {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(canAsk ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                                    .frame(width: 40, height: 40)
                            } else {
                                Circle()
                                    .fill(canAsk ? MirrorTheme.accentGradient : LinearGradient(colors: [.secondary.opacity(0.3), .secondary.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 40, height: 40)
                            }
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
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.inkBase) : AnyShapeStyle(.bar))
    }

    // Single global key: LocalLLMService holds one shared llama context, so two
    // concurrent Ask generations (e.g. iPad split view, a rapid double-submit)
    // would stomp on each other's in-flight completion. Matches the claim/release
    // dedup pattern InsightViewModel already uses for Digest/Monthly Report.
    private static let coordinatorKey = "ask"

    private func submitQuestion() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, remaining > 0 else { return }
        guard InsightGenerationCoordinator.shared.claim(key: Self.coordinatorKey) else { return }
        defer { InsightGenerationCoordinator.shared.release(key: Self.coordinatorKey) }

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
        } catch {
            self.error = friendlyLLMError(error)
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
    @Environment(\.appDisplayMode) private var displayMode

    private var isSentinel: Bool { displayMode == .sentinel }
    private var accent: Color { isSentinel ? MirrorTheme.ember : MirrorTheme.violetLight }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let question = insight.question {
                HStack {
                    Spacer(minLength: 48)
                    Text(question)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSentinel ? MirrorTheme.textPrimary : MirrorTheme.violetLight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            isSentinel ? MirrorTheme.inkMid : MirrorTheme.violetDim,
                            in: RoundedRectangle(cornerRadius: isSentinel ? 8 : 20, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: isSentinel ? 8 : 20, style: .continuous)
                                .stroke(isSentinel ? MirrorTheme.ember.opacity(0.4) : MirrorTheme.violet.opacity(0.3), lineWidth: 1)
                        }
                }
            }

            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent.opacity(isSentinel ? 0.6 : 0.4))
                    .frame(width: 2)
                    .padding(.vertical, 3)

                VStack(alignment: .leading, spacing: 6) {
                    if isSentinel {
                        Text("◆ SIGNAL")
                            .font(MirrorTheme.mono(9, weight: .bold))
                            .foregroundStyle(MirrorTheme.ember)
                            .kerning(0.4)
                    }
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
        AskView(viewModel: InsightViewModel())
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
