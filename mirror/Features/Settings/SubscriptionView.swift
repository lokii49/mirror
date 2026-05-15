import SwiftUI
import RevenueCat

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionService = SubscriptionService.shared
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Current status
                    statusCard

                    if !subscriptionService.isSubscribed {
                        // Show upgrade options
                        upgradeSection
                    } else {
                        manageSection
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .background(MirrorTheme.bgBase)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .task {
            await subscriptionService.refresh()
            await subscriptionService.loadProducts()
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: subscriptionService.isSubscribed ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(subscriptionService.isSubscribed ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(subscriptionService.isSubscribed ? "MirrorNotes Core" : "Free Plan")
                    .font(.system(size: 17, weight: .semibold))
                Text(subscriptionService.isSubscribed
                     ? "Daily nudges, weekly digest, 60 Ask questions/month"
                     : "Unlimited writing, full history, iCloud sync")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .futureSurface(cornerRadius: 22)
    }

    private var upgradeSection: some View {
        VStack(spacing: 12) {
            Text("Upgrade to Core")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("60 Ask questions per month")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Ask MirrorNotes about patterns in your journal, grounded only in your entries.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .futureSurface(cornerRadius: 16)

            ForEach(subscriptionService.packages, id: \.storeProduct.productIdentifier) { package in
                Button {
                    Task {
                        isLoading = true
                        await subscriptionService.purchase(package)
                        isLoading = false
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(packageLabel(package))
                                .font(.system(size: 16, weight: .semibold))
                            Text(packageSubtitle(package))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(package.storeProduct.localizedPriceString)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .padding(16)
                    .futureSurface(cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

            if isLoading {
                ProgressView()
                    .padding(.top, 8)
            }

            Button("Restore Purchases") {
                Task {
                    isLoading = true
                    await subscriptionService.refresh()
                    isLoading = false
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    private func packageLabel(_ package: Package) -> String {
        switch package.packageType {
        case .monthly:  return "Monthly"
        case .annual:   return "Yearly"
        case .weekly:   return "Weekly"
        case .lifetime: return "Lifetime"
        default:
            let id = package.storeProduct.productIdentifier
            if id.contains("month") { return "Monthly" }
            if id.contains("year") || id.contains("annual") { return "Yearly" }
            return id
        }
    }

    private func packageSubtitle(_ package: Package) -> String {
        switch package.packageType {
        case .monthly:  return "Billed monthly · cancel anytime"
        case .annual:   return "Billed yearly · save ~33%"
        default:        return "MirrorNotes Core"
        }
    }

    private var manageSection: some View {
        VStack(spacing: 12) {
            Button {
                if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Text("Manage Subscription")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .futureSurface(cornerRadius: 16)
            }
            .buttonStyle(.plain)

            Text("Manage or cancel your subscription in the App Store.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
