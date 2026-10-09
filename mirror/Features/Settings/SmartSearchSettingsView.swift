import SwiftUI

/// Settings > Smarter Ask search: the user's control over the one-time EmbeddingGemma download that
/// `SemanticSearchService` uses for Ask. Shows what it is, its size and where it comes from, the
/// current state, and Download / Remove. Per device (no CloudKit), like the decision in Ask's
/// offer card.
struct SmartSearchSettingsView: View {
    @Environment(\.appDisplayMode) private var displayMode
    @State private var state: SemanticSearchService.ModelState = SemanticSearchService.isModelOnDisk ? .installed : .absent
    @State private var consent = SemanticSearchService.consent
    @State private var downloadedBytes: Int64 = 0

    init() {}

    #if DEBUG
    /// Render harness only: start from a given state instead of the service's.
    init(previewState: SemanticSearchService.ModelState, downloadedBytes: Int64) {
        _state = State(initialValue: previewState)
        _downloadedBytes = State(initialValue: downloadedBytes)
        _consent = State(initialValue: .accepted)
        polls = false
    }
    #endif
    private var polls = true

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
                        Text("It needs a one-time download of a search model (\(sizeText)), on Wi-Fi only. Your journal never leaves this device: the model runs here, and the download sends nothing about you or your entries.")
                            .font(.system(size: 13))
                            .foregroundStyle(MirrorTheme.textSecondary)

                        SettingsDivider()

                        HStack {
                            Text("Status")
                                .font(displayMode == .sentinel ? MirrorTheme.mono(13, weight: .bold) : .system(size: 14, weight: .medium))
                                .foregroundStyle(MirrorTheme.textPrimary)
                            Spacer()
                            Text(statusText)
                                .font(.system(size: 13))
                                .foregroundStyle(MirrorTheme.textSecondary)
                        }

                        if state == .downloading {
                            downloadProgress
                        }

                        actionButton
                    }
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
        .task {
            // The service is an actor, so poll while this screen is visible (cheap: one property read).
            while polls, !Task.isCancelled {
                state = await SemanticSearchService.shared.modelState
                downloadedBytes = await SemanticSearchService.shared.downloadedBytes
                consent = SemanticSearchService.consent
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Bar plus "120 MB of 333.6 MB". Before the first bytes arrive (or while waiting for Wi-Fi) the bar
    /// is indeterminate rather than stuck at zero.
    private var downloadProgress: some View {
        let total = SemanticSearchService.modelByteCount
        let fraction = min(1, Double(downloadedBytes) / Double(total))
        let received = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        return VStack(alignment: .leading, spacing: 6) {
            if downloadedBytes > 0 {
                ProgressView(value: fraction)
                Text("\(received) of \(sizeText)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(MirrorTheme.textSecondary)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
        .tint(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary)
        .animation(.linear(duration: 0.4), value: downloadedBytes)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(Int(fraction * 100))%"))
    }

    private var statusText: LocalizedStringKey {
        switch state {
        case .installed: return "Ready"
        case .downloading: return "Downloading… (Wi-Fi only)"
        case .failed: return "Download didn't finish. It'll retry."
        case .absent: return consent == .accepted ? "Waiting for Wi-Fi" : "Off"
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
                    state = .absent
                    consent = .declined
                }
            } label: {
                Text("Remove the search model").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .downloading:
            EmptyView()
        case .absent, .failed:
            Button {
                SemanticSearchService.consent = .accepted
                consent = .accepted
                Task { await SemanticSearchService.shared.ensureModelDownloadStarted() }
            } label: {
                Text("Download (\(sizeText))").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary)
        }
    }
}

/// Ask's one-time offer of the search model, above the question field. `onAnswer(true)` = Download.
struct SmartSearchOfferCard: View {
    let onAnswer: (Bool) -> Void
    @Environment(\.appDisplayMode) private var displayMode

    private var sizeText: String {
        SemanticSearchService.modelSizeText
    }

    var body: some View {
        let accent = displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary
        VStack(alignment: .leading, spacing: 8) {
            Text(displayMode == .sentinel ? "SMARTER SEARCH" : "Smarter search for Ask")
                .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 14, weight: .semibold))
                .foregroundStyle(MirrorTheme.textPrimary)
            Text("Find entries by meaning, not just matching words. One-time \(sizeText) download on Wi-Fi. Your journal never leaves this device.")
                .font(.system(size: 12.5))
                .foregroundStyle(MirrorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Download") { onAnswer(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                Button("Not now") { onAnswer(false) }
                    .buttonStyle(.bordered)
                    .tint(accent)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .semibold))
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: displayMode == .sentinel ? 8 : 14)
    }
}
