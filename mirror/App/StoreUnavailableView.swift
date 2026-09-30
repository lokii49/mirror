import SwiftUI

/// Shown instead of the app when the journal store can't be opened (see `MirrorModelContainer`).
/// Nothing here deletes or resets data.
struct StoreUnavailableView: View {
    @Environment(\.openURL) private var openURL
    @State private var retryResult: RetryResult?

    private enum RetryResult { case stillFailing, opens }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Your journal couldn't be opened")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Your entries haven't been deleted. This can happen when the phone is very low on storage. Free up some space, then try again.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch retryResult {
            case .opens:
                Text("It opens now. Close mirror completely and open it again.")
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
            case .stillFailing:
                Text("Still can't open it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }

            Button("Try Again") {
                retryResult = MirrorModelContainer.canOpenStoreNow() ? .opens : .stillFailing
            }
            .buttonStyle(.borderedProminent)

            if let url = AppConstants.feedbackURL {
                Button("Contact support") { openURL(url) }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
