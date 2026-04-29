import SwiftUI
import StoreKit

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
                Text(subscriptionService.isSubscribed ? "Mirror Core" : "Free Plan")
                    .font(.system(size: 17, weight: .semibold))
                Text(subscriptionService.isSubscribed
                     ? "Daily nudges, weekly digest, Ask Mirror"
                     : "Unlimited writing, full history, iCloud sync")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var upgradeSection: some View {
        VStack(spacing: 12) {
            Text("Upgrade to Core")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(subscriptionService.products, id: \.id) { product in
                Button {
                    Task {
                        isLoading = true
                        await subscriptionService.purchase(product)
                        isLoading = false
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Text(product.description)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(product.displayPrice)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Manage or cancel your subscription in the App Store.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
