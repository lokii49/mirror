import SwiftUI
import StoreKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Publishes when a rate-us moment is ready. `ReviewRequestManager` sets
/// `isPending`; `ContentView` observes it and presents `RateUsPromptSheet`.
/// A shared coordinator — rather than a direct sheet binding — is needed
/// because `ReviewRequestManager` is also called from `AddJournalEntryIntent`
/// (Siri), which has no view hierarchy of its own to present a sheet from.
@Observable
final class ReviewPromptCoordinator {
    static let shared = ReviewPromptCoordinator()
    private init() {}
    var isPending = false
}

/// Two-step gate shown before the system rating prompt. Apple's
/// `SKStoreReviewRequest` allows no custom copy and no way to catch an
/// unhappy user before they leave a public low rating — so happy users go
/// straight to the system prompt, and anyone who taps "not really" is
/// offered a feedback email instead. Nothing here is logged or sent
/// anywhere unless they choose to send that email themselves.
struct RateUsPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode
    /// Whether appearing spends the once-per-install milestone prompt. Off for UI tests and the
    /// DEBUG `--showRatePrompt` launch, which must not consume it.
    var consumesMilestone = true
    @State private var step: Step = .ask
    /// The content's own height: the sheet is exactly that tall. A fixed detent (372) left a third
    /// of the floating iOS 26 sheet empty under "Not now".
    @State private var contentHeight: CGFloat = 320
    /// iOS 26 sheets float above the home indicator but still add its safe area to a `.height`
    /// detent, which left an empty band under "Not now". Earlier sheets sit on the bottom edge
    /// and need it.
    @State private var floatingBottomInset: CGFloat = 0

    private enum Step { case ask, notGreat }

    var body: some View {
        // Scrolls only if the sheet ends up shorter than its content (iOS 17/18 sheets, large
        // Dynamic Type), so "Not now" is never cut off.
        ScrollView {
            VStack(spacing: 0) {
                switch step {
                case .ask: askStep
                case .notGreat: notGreatStep
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = ceil($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { inset in
            if #available(iOS 26, macOS 26, *) { floatingBottomInset = inset }
        }
        .background(MirrorTheme.bgBase)
        .presentationDetents([.height(max(200, contentHeight - floatingBottomInset))])
        .presentationDragIndicator(.visible)
        .animation(.easeInOut(duration: 0.25), value: step)
        .onAppear {
            if consumesMilestone { ReviewRequestManager.markEntryMilestonePromptShown() }
        }
    }

    private var appLogo: some View {
        Image("AppIconDisplay")
            .resizable()
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
    }

    private var askStep: some View {
        VStack(spacing: 20) {
            appLogo
            VStack(spacing: 6) {
                Text(displayMode == .sentinel ? "How's the signal?" : "How's mirror going?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("A quick check before we ask anything else.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button {
                    requestSystemReview()
                } label: {
                    Text("🙂  Good")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(MirrorTheme.accentGradient),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { step = .notGreat }
                } label: {
                    Text("🙁  Not really")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MirrorTheme.inkRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MirrorTheme.inkBorder, lineWidth: 1)
                        }
                        .foregroundStyle(MirrorTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }

            Button { dismiss() } label: {
                Text("Not now")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -10)
        }
    }

    private var notGreatStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 34))
                .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet)
            VStack(spacing: 8) {
                Text("What would make it better?")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Tell us directly — this opens an email, nothing is logged or sent anywhere unless you send it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                if let url = AppConstants.feedbackURL {
                    UIApplication.shared.open(url)
                }
                dismiss()
            } label: {
                Text("Send feedback")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(MirrorTheme.accentGradient),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                Text("Not now")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -10)
        }
    }

    private func requestSystemReview() {
        dismiss()
        // Let the sheet's own dismiss animation finish before the system
        // prompt appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            #if os(iOS)
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            AppStore.requestReview(in: scene)
            #else
            SKStoreReviewController.requestReview()
            #endif
            #if DEBUG
            // `AppStore.requestReview` renders nothing in an Xcode-installed
            // build — Apple only shows it from TestFlight / the App Store. Open
            // the write-review page so the flow is verifiable during dev.
            if let url = AppConstants.appStoreReviewURL {
                UIApplication.shared.open(url)
            }
            #endif
        }
    }
}
