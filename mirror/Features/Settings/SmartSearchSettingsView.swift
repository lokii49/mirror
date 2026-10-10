import SwiftUI

/// Settings > Smarter Ask search: the user's control over the one-time EmbeddingGemma download that
/// `SemanticSearchService` uses for Ask. Shows what it is, its size and where it comes from, the
/// download (pause/resume) and Download / Remove. Per device (no CloudKit), like the decision in
/// Ask's offer card.
struct SmartSearchSettingsView: View {
    @Environment(\.appDisplayMode) private var displayMode
    @State private var manager = ModelDownloadManager.searchModel
    /// Render harness only: shown instead of the manager's state.
    private var previewState: ModelDownloadState?

    init() {}

    #if DEBUG
    init(previewState: ModelDownloadState) {
        self.previewState = previewState
    }
    #endif

    private var state: ModelDownloadState { previewState ?? manager.state }

    private var sizeText: String {
        SemanticSearchService.modelSizeText
    }

    var body: some View {
        SettingsScroll {
            VStack(spacing: 14) {
                SettingsGroup(title: "Smarter Ask search") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ask finds the entries that match what you mean, not only the words you type. \"Have I been working out?\" finds your run and gym entries.")
                            .font(.system(size: 14))
                            .foregroundStyle(MirrorTheme.textPrimary)
                        Text("It needs a one-time download of a search model (\(sizeText)). Your journal never leaves this device: the model runs here, and the download sends nothing about you or your entries.")
                            .font(.system(size: 13))
                            .foregroundStyle(MirrorTheme.textSecondary)

                        SettingsDivider()

                        if ModelDownloadStage(state) == .active {
                            ModelDownloadProgressPanel(
                                state: state,
                                alignment: .leading,
                                onPause: { manager.pauseDownload() },
                                onResume: { manager.resumeDownload() }
                            )
                            .transition(.opacity)
                        } else {
                            HStack {
                                Text("Status")
                                    .font(displayMode == .sentinel ? MirrorTheme.mono(13, weight: .bold) : .system(size: 14, weight: .medium))
                                    .foregroundStyle(MirrorTheme.textPrimary)
                                Spacer()
                                Text(statusText)
                                    .font(.system(size: 13))
                                    .foregroundStyle(MirrorTheme.textSecondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .transition(.opacity)
                        }

                        actionButton
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.88), value: ModelDownloadStage(state))
                }

                SettingsGroup(title: "Model") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EmbeddingGemma 300M by Google, downloaded from models.mirrornotes.org. Provided under and subject to the Gemma Terms of Use.")
                            .font(.system(size: 13))
                            .foregroundStyle(MirrorTheme.textSecondary)
                        if let terms = URL(string: "https://ai.google.dev/gemma/terms") {
                            Link("Gemma Terms of Use", destination: terms)
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(MirrorTheme.bgBase)
        .settingsNavigationTitle(displayMode == .sentinel ? "Search model" : "Smarter Ask search")
    }

    private var statusText: LocalizedStringKey {
        switch state {
        case .installed: return "Ready"
        case .failed: return "Download didn't finish."
        default: return "Off"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .installed:
            Button(role: .destructive) {
                Task {
                    await SemanticSearchService.shared.removeModel()
                    SemanticSearchService.consent = .declined
                }
            } label: {
                Text("Remove the search model").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .downloading, .paused, .verifying:
            EmptyView()
        case .failed:
            ModelDownloadButton(title: "Try Again", systemImage: "arrow.clockwise") {
                manager.resumeDownload()
            }
        case .notStarted:
            ModelDownloadButton(title: "Download", byteCount: SemanticSearchService.modelByteCount) {
                SemanticSearchService.consent = .accepted
                manager.startIfIdle()
            }
        }
    }
}

/// Ask's one-time offer of the search model. After Download it stays and shows the download (bar,
/// pause/resume), says Ready when the model is in, then hides itself. Ask shows it again, still
/// downloading or paused, if the download hasn't finished when Ask reopens.
struct SmartSearchOfferCard: View {
    let onAnswer: (Bool) -> Void
    /// Called once the model is ready (after a short "Ready") or when the person hides the card.
    var onDone: () -> Void = {}
    @Environment(\.appDisplayMode) private var displayMode
    @State private var accepted: Bool
    @State private var manager = ModelDownloadManager.searchModel
    /// Render harness only: shown instead of the manager's state.
    private var previewState: ModelDownloadState?

    init(alreadyAccepted: Bool = false, onAnswer: @escaping (Bool) -> Void, onDone: @escaping () -> Void = {}) {
        self.onAnswer = onAnswer
        self.onDone = onDone
        _accepted = State(initialValue: alreadyAccepted)
    }

    #if DEBUG
    init(previewState: ModelDownloadState) {
        self.onAnswer = { _ in }
        _accepted = State(initialValue: true)
        self.previewState = previewState
    }
    #endif

    private var state: ModelDownloadState { previewState ?? manager.state }
    private var isInstalled: Bool { state == .installed }

    private var sizeText: String {
        SemanticSearchService.modelSizeText
    }

    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayMode == .sentinel ? "SMARTER SEARCH" : "Smarter search for Ask")
                    .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 14, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textPrimary)
                Spacer(minLength: 0)
                if accepted, !isInstalled {
                    // Hides the card only; the download carries on (Settings shows it too).
                    Button(action: onDone) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MirrorTheme.textSecondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
            if accepted {
                progressContent
            } else {
                offerContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: displayMode == .sentinel ? 8 : 14)
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: accepted)
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: ModelDownloadStage(state))
        .task(id: isInstalled) {
            guard accepted, isInstalled, previewState == nil else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { onDone() }
        }
    }

    private var offerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find entries by meaning, not just matching words. One-time \(sizeText) download. Your journal never leaves this device.")
                .font(.system(size: 12.5))
                .foregroundStyle(MirrorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ModelDownloadButton(title: "Download", byteCount: SemanticSearchService.modelByteCount, compact: true) {
                    accepted = true
                    onAnswer(true)
                }
                Button("Not now") { onAnswer(false) }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 38)
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var progressContent: some View {
        switch state {
        case .installed:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .transition(.opacity)
        case .failed:
            HStack(spacing: 10) {
                Text("Download didn't finish.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(MirrorTheme.textSecondary)
                Spacer(minLength: 0)
                ModelDownloadButton(title: "Try Again", systemImage: "arrow.clockwise", compact: true) {
                    manager.resumeDownload()
                }
            }
            .transition(.opacity)
        case .downloading, .paused, .verifying:
            ModelDownloadProgressPanel(
                state: state,
                alignment: .leading,
                showsBackgroundHint: false,
                onPause: { manager.pauseDownload() },
                onResume: { manager.resumeDownload() }
            )
            .transition(.opacity)
        case .notStarted:
            ModelDownloadButton(title: "Download", byteCount: SemanticSearchService.modelByteCount, compact: true) {
                manager.startIfIdle()
            }
            .transition(.opacity)
        }
    }
}
