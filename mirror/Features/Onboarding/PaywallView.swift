import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionService = SubscriptionService.shared
    @State private var selectedProductID = "mirror_core_yearly"

    private let features: [(String, String, String, Color)] = [
        ("sparkles", "Daily Reflection", "One focused observation from your recent entries.", MirrorTheme.primary),
        ("bubble.left.and.bubble.right", "Ask", "Ten grounded questions per month — answered from your own writing.", .blue),
        ("calendar.badge.clock", "Weekly Digest", "A deeper pattern summary delivered each Sunday.", .indigo),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    heroSection
                    featuresSection
                    planSection
                    ctaSection
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(MirrorTheme.bgBase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .task { await subscriptionService.loadProducts() }
            .onChange(of: subscriptionService.isSubscribed) { _, subscribed in
                if subscribed { dismiss() }
            }
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.indigo,
                            MirrorTheme.primary,
                            Color.purple.opacity(0.85),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Decorative circles
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 160, height: 160)
                .offset(x: 200, y: -60)
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 100, height: 100)
                .offset(x: 240, y: 20)

            VStack(alignment: .leading, spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 64, height: 64)
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Mirror Core")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Private journal intelligence,\nbuilt around your writing.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }

                // Trial badge
                HStack(spacing: 6) {
                    Image(systemName: "gift")
                        .font(.system(size: 12, weight: .semibold))
                    Text("7-day free trial")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.18), in: Capsule())
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: MirrorTheme.primary.opacity(0.3), radius: 30, x: 0, y: 12)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What's included")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.bottom, 14)

            VStack(spacing: 12) {
                ForEach(features, id: \.1) { icon, title, detail, color in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(color.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                            Text(detail)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(20)
        .futureSurface(cornerRadius: 24)
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a plan")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.bottom, 14)

            if subscriptionService.products.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.9)
                    Text("Loading plans…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(subscriptionService.products, id: \.id) { product in
                        PlanCard(
                            product: product,
                            isSelected: selectedProductID == product.id,
                            onTap: { selectedProductID = product.id }
                        )
                    }
                }
            }
        }
        .padding(20)
        .futureSurface(cornerRadius: 24)
    }

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                guard let product = subscriptionService.products.first(where: { $0.id == selectedProductID }) else { return }
                Task { await subscriptionService.purchase(product) }
            } label: {
                HStack {
                    Spacer()
                    if subscriptionService.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Start Free Trial")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .frame(height: 54)
                .background(
                    subscriptionService.isPurchasing || subscriptionService.products.isEmpty
                        ? AnyShapeStyle(Color.secondary.opacity(0.3))
                        : AnyShapeStyle(MirrorTheme.accentGradient),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(subscriptionService.isPurchasing || subscriptionService.products.isEmpty)
            .shadow(color: MirrorTheme.primary.opacity(0.30), radius: 16, x: 0, y: 6)

            Button("Restore Purchases") {
                Task { await subscriptionService.restorePurchases() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)

            Text("Cancel anytime in App Store settings. No charge during trial.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let error = subscriptionService.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    let onTap: () -> Void

    private var isYearly: Bool { product.id.contains("yearly") }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Selection ring
                ZStack {
                    Circle()
                        .stroke(isSelected ? MirrorTheme.primary : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(MirrorTheme.accentGradient)
                            .frame(width: 12, height: 12)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Yearly" : "Monthly")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        if isYearly {
                            Text("Best value")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MirrorTheme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(MirrorTheme.primary.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(isYearly ? "\(product.displayPrice) / year" : "\(product.displayPrice) / month")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(
                isSelected ? MirrorTheme.primary.opacity(0.06) : MirrorTheme.bgCard,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? MirrorTheme.primary.opacity(0.3) : Color.primary.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }
}
