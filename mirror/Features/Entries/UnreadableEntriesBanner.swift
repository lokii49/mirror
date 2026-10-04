import SwiftUI

/// Shared look for the entry list's journal-safety notices (unreadable entries, not backed
/// up to iCloud, restore from device), in both the classic and Sentinel themes.
struct NoticeBanner<Actions: View>: View {
    let systemImage: String
    let title: Text
    let sentinelTitle: Text
    let message: Text
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var actions: () -> Actions

    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : Color.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if displayMode == .sentinel {
                    sentinelTitle
                        .font(MirrorTheme.mono(12, weight: .bold))
                        .tracking(1)
                } else {
                    title
                        .font(.system(size: 15, weight: .semibold))
                }
                message
                    .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .regular) : .system(size: 13))
                    .foregroundStyle(MirrorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { onDismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(14)
        .background {
            if displayMode == .sentinel {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(MirrorTheme.ember.opacity(0.08))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.10))
            }
        }
        .overlay {
            if displayMode == .sentinel {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(MirrorTheme.ember.opacity(0.4), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension NoticeBanner where Actions == EmptyView {
    init(systemImage: String, title: Text, sentinelTitle: Text, message: Text, onDismiss: (() -> Void)? = nil) {
        self.init(systemImage: systemImage, title: title, sentinelTitle: sentinelTitle, message: message, onDismiss: onDismiss) { EmptyView() }
    }
}

/// Shown above the entry list when some entries can't be decrypted on this device.
///
/// iOS has no public API that reports whether iCloud Keychain is on — a synchronizable
/// Keychain write succeeds either way and simply stays local. So this keys off the symptom
/// the user actually sees: entries whose content key never reached this device, almost
/// always because iCloud Keychain is off here or on the device that wrote them.
///
/// The host owns visibility (see `shouldShow`) and the dismissal, so a List can drop the
/// whole row rather than leave an empty one behind.
struct UnreadableEntriesBanner: View {
    /// UserDefaults key for the unreadable count the user last dismissed. Dismissing hides
    /// the banner until the count changes, so a permanently lost key doesn't nag forever
    /// but a new batch of unreadable entries still surfaces.
    static let dismissedCountKey = "unreadableEntriesBannerDismissedCount"

    static func shouldShow(unreadableCount: Int, dismissedCount: Int) -> Bool {
        unreadableCount > 0 && unreadableCount != dismissedCount
    }

    let unreadableCount: Int
    let onDismiss: () -> Void

    var body: some View {
        NoticeBanner(
            systemImage: "key.slash",
            title: Text("^[\(unreadableCount) entry](inflect: true) can't be read on this device"),
            sentinelTitle: Text("^[\(unreadableCount) LOG ENTRY](inflect: true) LOCKED ON THIS DEVICE"),
            message: Text(guidance),
            onDismiss: onDismiss
        )
    }

    private var guidance: LocalizedStringKey {
        #if os(macOS)
        "If you just installed mirror, they may still be syncing. If this doesn't clear in a few minutes, turn on Passwords & Keychain in System Settings → your name → iCloud on this Mac and on the device where you wrote them."
        #else
        "If you just installed mirror, they may still be syncing. If this doesn't clear in a few minutes, turn on Passwords & Keychain in Settings → your name → iCloud on this device and on the one where you wrote them."
        #endif
    }
}
