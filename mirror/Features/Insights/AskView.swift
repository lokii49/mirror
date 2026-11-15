import SwiftUI
import SwiftData

struct AskView: View {
    let viewModel: InsightViewModel
    /// Seeds the question field on first appear (e.g. from a Brain View node).
    /// Prefill only — never auto-submits.
    var initialQuestion: String? = nil
    /// Set when Ask is shown in a sheet (Brain View), so Mac can show a Done button.
    var onClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.appDisplayMode) private var displayMode
    /// The whole journal. Read `entries`, which leaves out collections kept out of insights.
    @Query(sort: \Entry.createdAt, order: .reverse) private var journalEntries: [Entry]
    @Query private var scopeCollections: [JournalCollection]
    @State private var insightEntries = InsightEntriesMemo()
    private var entries: [Entry] { insightEntries.entries(journalEntries, collections: scopeCollections) }
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
    /// The language notice (`InsightService.isUnsupportedLanguageNotice`) for the last question, shown above
    /// the input instead of being saved: it isn't an answer, so it takes no question from the monthly cap
    /// and doesn't sync into the chat history.
    @State private var languageNotice: String?
    @State private var keyboardHeight: CGFloat = 0
    /// One-time offer of the semantic-search model: shown to anyone who can ask (Core/Deep) and
    /// hasn't answered yet, never re-shown after Download or Not now.
    /// The offer before an answer; after Download, the same card shows the download until the model is in.
    /// Not offered where Foundation Models answers (owner, 2026-11-06): a 333 MB download is a lot
    /// to ask there, and Settings › Smart Search still has it. Someone who already chose Download
    /// keeps seeing its progress.
    @State private var showSmartSearchOffer = SemanticSearchService.consent != .declined && !SemanticSearchService.isModelOnDisk
        && (SemanticSearchService.consent == .accepted || !FoundationModelEngine.isAvailable)
    @FocusState private var isInputFocused: Bool

    private var monthLimit: Int {
        SubscriptionService.askMonthlyLimit(for: subscriptionService.tier)
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

    /// "N left" for Core; the toolbar shows it on iOS and the title bar on Mac.
    private var remainingBadge: some View {
        let isLow = remaining <= 3
        let isCritical = remaining <= 1
        return Text("\(remaining) left")
            .scaledFont(12, weight: .semibold, design: .default)
            .foregroundStyle(isCritical ? .red : isLow ? .orange : MirrorTheme.textSecondary)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                (isCritical ? Color.red : isLow ? Color.orange : MirrorTheme.textSecondary).opacity(0.10),
                in: Capsule()
            )
    }

    private var suggestionsToggle: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showSuggestions.toggle()
            }
        } label: {
            Image(systemName: showSuggestions ? "lightbulb.fill" : "lightbulb")
                .scaledFont(17, weight: .medium)
                .foregroundStyle(MirrorTheme.primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Suggested questions")
        .accessibilityAddTraits(showSuggestions ? .isSelected : [])
        #if os(macOS)
        .buttonStyle(MacHoverButtonStyle())
        .help("Suggested questions")
        #endif
    }

    var body: some View {
        askScreen
        #if os(macOS)
            .macPage("Ask") {
                if case .ready = viewModel.askState {
                    if !subscriptionService.isDeep { remainingBadge }
                    suggestionsToggle
                }
                if let onClose {
                    Button("Done", action: onClose).keyboardShortcut(.cancelAction)
                }
            }
        #endif
    }

    private var askScreen: some View {
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
                #if os(iOS)
                .toolbar {
                    if !subscriptionService.isDeep {
                        ToolbarItem(placement: .topBarTrailing) { remainingBadge }
                    }
                    // On iPhone Duo it joins the back button in the vertical strip on the right,
                    // instead of staying alone in the top bar (owner, 2026-10-18).
                    ToolbarItem(placement: .topBarTrailing) { suggestionsToggle }
                        .preferringVerticalBar()
                }
                #endif
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    updateKeyboardHeight(from: notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
                }
            }
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle("Ask")
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .sheet(isPresented: $showPaywall) { PaywallView().environment(\.appDisplayMode, displayMode) }
        .onAppear {
            viewModel.loadAskState(entries: entries)
            #if os(macOS)
            // Ready to type as soon as the page opens.
            if initialQuestion == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isInputFocused = true }
            }
            #endif
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
                Circle()
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 88, height: 88)
                Image(systemName: "lock.fill")
                    .scaledFont(34, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                Text("Ask is a Core feature")
                    .scaledFont(22, weight: .bold, design: .rounded)
                    .kerning(0)
                    .foregroundStyle(MirrorTheme.textPrimary)
                Text("Ask up to 15 questions per month on Core,\nor unlimited on Deep.")
                    .scaledFont(15, weight: .regular, design: .default)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showPaywall = true
            } label: {
                Text("Unlock with Core")
                    .scaledFont(16, weight: .semibold, design: .default)
                    .kerning(0)
                    .foregroundStyle(Color.white)
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
        let stack = VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(MirrorTheme.accentGradient)
                    .frame(width: 88, height: 88)
                    .shadow(color: MirrorTheme.primary.opacity(0.35), radius: 24, x: 0, y: 10)
                Image(systemName: icon)
                    .scaledFont(34, weight: .semibold)
                    .foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Text(title)
                    .scaledFont(22, weight: .bold, design: .rounded)
                    .kerning(0)
                    .textCase(nil)
                    .foregroundStyle(MirrorTheme.textPrimary)
                Text(subtitle)
                    .scaledFont(15, weight: .regular, design: .default)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }
            trailing()
        }
        .padding(28)
        // Centered when it fits; at large text sizes it scrolls instead of cutting the text off.
        return ViewThatFits(in: .vertical) {
            stack.frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView { stack.frame(maxWidth: .infinity) }
        }
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

    private var askEmptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(MirrorTheme.accentGradient)
                    .frame(width: 88, height: 88)
                    .shadow(color: MirrorTheme.primary.opacity(0.35), radius: 24, x: 0, y: 10)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .scaledFont(34, weight: .semibold)
                    .foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Text("Ask your journal")
                    .scaledFont(26, weight: .bold, design: .rounded)
                Text("Answers come only from entries you've written.")
                    .scaledFont(15, weight: .medium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking")
                    .scaledFont(12, weight: .semibold, design: .default)
                    .kerning(0)
                    .foregroundStyle(MirrorTheme.textTertiary)
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
                                .scaledFont(14, weight: .medium)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .scaledFont(18)
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
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask MirrorNotes")
                    .scaledFont(15, weight: .semibold, design: .default)
                Text(subscriptionService.isDeep ? "Unlimited questions" : "\(remaining) of 15 questions this month")
                    .scaledFont(12, weight: .medium)
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
                            .scaledFont(13, weight: .medium)
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

                if let languageNotice {
                    Text(languageNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                if showSmartSearchOffer {
                    SmartSearchOfferCard(alreadyAccepted: SemanticSearchService.consent == .accepted) { accepted in
                        // Not now hides the card; Download keeps it, now showing the download.
                        if !accepted { showSmartSearchOffer = false }
                        SemanticSearchService.consent = accepted ? .accepted : .declined
                        if accepted { Task { await SemanticSearchService.shared.ensureModelDownloadStarted() } }
                    } onDone: {
                        withAnimation { showSmartSearchOffer = false }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                if showSuggestions {
                    suggestionsRow
                }

                HStack(alignment: .bottom, spacing: 10) {
                    HStack(alignment: .center, spacing: 6) {
                        TextField(
                            remaining == 0 ? "Monthly limit reached" : "Ask about your journal…",
                            text: $question, axis: .vertical
                        )
                            .lineLimit(1...5)
                            .onChange(of: question) { _, new in
                                if new.count > InsightService.maxAskQuestionLength {
                                    question = String(new.prefix(InsightService.maxAskQuestionLength))
                                }
                            }
                            .textFieldStyle(.plain)
                            .focused($isInputFocused)
                            #if os(macOS)
                            // Return sends, as in a chat; Shift-Return adds a line.
                            .onSubmit { if canAsk { Task { await submitQuestion() } } }
                            #endif
                            .disabled(remaining == 0)
                            .scaledFont(15, weight: .regular, design: .default)
                    }
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
                                .scaledFont(16, weight: .bold)
                                .foregroundStyle(.white)
                        }
                    }
                    .accessibilityLabel("Ask")
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
        .background(AnyShapeStyle(MirrorTheme.inkMid))
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
        languageNotice = nil
        let submitted = q
        pendingQuestion = submitted
        question = ""
        isInputFocused = false

        // Keyword search answers until the search model is installed and indexed. Asking never
        // starts or retries its download: only a tap does (3.1.1 downloads on mobile data too,
        // and 3.1.0 users agreed to Wi-Fi only).
        do {
            // The answer and question are saved encrypted.
            guard MirrorEncryption.canEncrypt(creatingIfNeeded: false) else { throw InsightError.serviceUnavailable("content key unavailable") }
            let (answer, engine) = try await InsightService.ask(question: submitted, entries: entries)
            if InsightService.isUnsupportedLanguageNotice(answer) {
                languageNotice = InsightService.unsupportedLanguageCardMessage(answer)
                isLoading = false
                pendingQuestion = ""
                return
            }
            let insight = Insight(
                type: .askResponse,
                content: answer,
                periodIdentifier: DateHelpers.monthIdentifier(for: Date()),
                question: submitted,
                generatedByEngine: engine
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
        #if os(macOS)
        keyboardHeight = 0
        #else
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
            return
        }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow }) else {
            withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
            return
        }
        // keyboardFrameEndUserInfoKey is in screen coordinates, not window coordinates — in Split
        // View / Stage Manager the app's window is smaller than (and offset within) the screen, so
        // comparing it against the raw screen-space frame overstates the overlap. Convert into the
        // window's own coordinate space and intersect before measuring height.
        let kbInWindow = window.convert(frame, from: nil)
        let overlap = window.bounds.intersection(kbInWindow).height
        // TabView forces .ignoresSafeArea(.keyboard) on all descendants.
        // Raw keyboard height includes the home indicator inset (~34pt), subtract it to avoid a gap.
        let bottomInset = window.safeAreaInsets.bottom
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = overlap > 0 ? overlap - bottomInset : 0
        }
        #endif
    }

}


private struct AskBubblePair: View {
    let insight: Insight

    private var accent: Color { MirrorTheme.violetLight }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let question = insight.question {
                HStack {
                    Spacer(minLength: 48)
                    Text(question)
                        .scaledFont(15, weight: .medium)
                        .foregroundStyle(MirrorTheme.violetLight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            MirrorTheme.violetDim,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(MirrorTheme.violet.opacity(0.3), lineWidth: 1)
                        }
                }
            }

            classicAnswer
                .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    // Left-rule answer block.
    private var classicAnswer: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.4))
                .frame(width: 2)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(insight.content)
                    .readingFont(size: 15)
                    .lineSpacing(6)
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .textSelection(.enabled)

                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .scaledFont(11, weight: .medium, design: .monospaced)
                    .foregroundStyle(MirrorTheme.textTertiary)
            }
            .padding(.leading, 14)
        }
    }
}

private struct LoadingAskBubble: View {
    let question: String

    private var accent: Color { MirrorTheme.violetLight }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !question.isEmpty {
                HStack {
                    Spacer(minLength: 48)
                    Text(question)
                        .scaledFont(15, weight: .medium)
                        .foregroundStyle(MirrorTheme.violetLight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            MirrorTheme.violetDim,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(MirrorTheme.violet.opacity(0.3), lineWidth: 1)
                        }
                }
            }

            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent.opacity(0.4))
                    .frame(width: 2)
                    .padding(.vertical, 3)

                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(accent)
                    Text("Searching your journal")
                        .scaledFont(14, design: .serif)
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
                    .scaledFont(15)
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
                        .scaledFont(16, weight: .bold)
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
                    .scaledFont(17, weight: .medium)
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
                    .scaledFont(34, weight: .semibold)
                    .foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Text("Ask your journal")
                    .scaledFont(26, weight: .bold, design: .rounded)
                Text("Answers come only from entries you've written.")
                    .scaledFont(15, weight: .medium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking")
                    .scaledFont(12, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
                ForEach(suggestions, id: \.self) { prompt in
                    HStack(spacing: 10) {
                        Text(prompt)
                            .scaledFont(14, weight: .medium)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill")
                            .scaledFont(18)
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
