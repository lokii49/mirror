import SwiftUI

/// The paid-plans notice on its own (`PaidPlansNotice`): the What's New card's title and text,
/// for installs that never see it in What's New. Marked seen when shown.
struct PaidPlansNoticeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode

    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            Image(systemName: PaidPlansNotice.card?.symbolName ?? "calendar.badge.clock")
                .scaledFont(44, weight: .medium)
                .foregroundStyle(accent)
                .frame(width: 88, height: 88)
                .background(accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            if let card = PaidPlansNotice.card {
                Text(card.title)
                    .scaledFont(displayMode == .sentinel ? 20 : 24, weight: .bold, design: displayMode == .sentinel ? .monospaced : .default)
                    .multilineTextAlignment(.center)
                Text(card.body)
                    .scaledFont(16)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .scaledFont(17, weight: .semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .accessibilityIdentifier("paidPlansNotice.gotIt")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 520)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .onAppear { PaidPlansNotice.markSeen() }
    }
}
