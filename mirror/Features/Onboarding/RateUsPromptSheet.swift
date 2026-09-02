import SwiftUI
import StoreKit
import UIKit

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
    @State private var step: Step = .ask

    private enum Step { case ask, notGreat }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            switch step {
            case .ask: askStep
            case .notGreat: notGreatStep
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MirrorTheme.bgBase)
        .presentationDetents([.height(step == .ask ? 372 : 340)])
        .presentationDragIndicator(.visible)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var appLogo: some View {
        Image("AppIconDisplay")
            .resizable()
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary).opacity(0.28), radius: 20, x: 0, y: 8)
    }

    private var askStep: some View {
        VStack(spacing: 20) {
            appLogo
            VStack(spacing: 8) {
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

            Button("Not now") { dismiss() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
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

            Button("Not now") { dismiss() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func requestSystemReview() {
        dismiss()
        // Let the sheet's own dismiss animation finish before the system
        // prompt appears — same interval ReviewRequestManager already used.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            AppStore.requestReview(in: scene)
        }
    }
}
