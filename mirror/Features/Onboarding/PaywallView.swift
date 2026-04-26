import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionService = SubscriptionService.shared
    @State private var selectedProductID = "mirror_core_yearly"

    private let features: [(String, String, String)] = [
        ("sparkles", "Daily reflections", "A focused observation from recent entries."),
        ("bubble.left.and.bubble.right", "Ask your journal", "Ten grounded questions each month."),
        ("calendar", "Weekly context", "A digest when enough history is available."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 68, height: 68)
                            .background(LinearGradient(colors: MirrorTheme.moodSpectrum, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        Text("Mirror Core")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Private journal intelligence, built around your own entries.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Capsule()
                            .fill(LinearGradient(colors: MirrorTheme.moodSpectrum, startPoint: .leading, endPoint: .trailing))
                            .frame(height: 8)
                            .padding(.top, 4)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .futureSurface(cornerRadius: 28)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Included")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(features, id: \.1) { icon, title, detail in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon)
                                    .foregroundStyle(MirrorTheme.primary)
                                    .frame(width: 34, height: 34)
                                    .background(MirrorTheme.primary.opacity(0.10), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(18)
                    .futureSurface(cornerRadius: 24)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Choose a Plan")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        if subscriptionService.products.isEmpty {
                            HStack {
                                ProgressView()
                                Text("Loading plans")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(subscriptionService.products, id: \.id) { product in
                                ProductRow(product: product, isSelected: selectedProductID == product.id) {
                                    selectedProductID = product.id
                                }
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(selectedProductID == product.id ? MirrorTheme.primary.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .futureSurface(cornerRadius: 24)

                    VStack(spacing: 10) {
                        Button {
                            guard let product = subscriptionService.products.first(where: { $0.id == selectedProductID }) else { return }
                            Task { await subscriptionService.purchase(product) }
                        } label: {
                            HStack {
                                Spacer()
                                if subscriptionService.isPurchasing {
                                    ProgressView()
                                } else {
                                    Text("Continue")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                            .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .disabled(subscriptionService.isPurchasing || subscriptionService.products.isEmpty)

                        Button("Restore Purchases") {
                            Task { await subscriptionService.restorePurchases() }
                        }
                        .font(.system(size: 15, weight: .semibold))

                        Text("Cancel anytime in App Store subscription settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let error = subscriptionService.purchaseError {
                            Text(error).foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                    }
                .padding(16)
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await subscriptionService.loadProducts() }
            .onChange(of: subscriptionService.isSubscribed) { _, subscribed in
                if subscribed { dismiss() }
            }
        }
    }
}

private struct ProductRow: View {
    let product: Product
    let isSelected: Bool
    let onTap: () -> Void

    private var isYearly: Bool { product.id.contains("yearly") }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Yearly" : "Monthly")
                            .foregroundStyle(.primary)
                        if isYearly {
                            Text("Best value")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(isYearly ? "\(product.displayPrice) per year" : "\(product.displayPrice) per month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
    }
}
