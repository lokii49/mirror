import SwiftUI
import RevenueCat

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionService = SubscriptionService.shared
    @State private var isLoading = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusCard

                    if !subscriptionService.isSubscribed {
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
        .sheet(isPresented: $showPaywall) { PaywallView(initialTier: subscriptionService.tier == .core ? .deep : .core) }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: subscriptionService.isSubscribed ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(subscriptionService.isDeep ? Color.purple : subscriptionService.isSubscribed ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(tierName)
                    .font(.system(size: 17, weight: .semibold))
                Text(tierDescription)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .futureSurface(cornerRadius: 22)
    }

    private var tierName: String {
        switch subscriptionService.tier {
        case .free: return "Free Plan"
        case .core: return "MirrorNotes Core"
        case .deep: return "MirrorNotes Deep"
        }
    }

    private var tierDescription: String {
        switch subscriptionService.tier {
        case .free:
            return "Unlimited writing, full history, iCloud sync"
        case .core:
            return "Daily nudges, weekly digest, 15 Ask questions/month"
        case .deep:
            return "Everything in Core + unlimited Ask, monthly report, mood timeline"
        }
    }

    private var upgradeSection: some View {
        VStack(spacing: 16) {
            Text("Upgrade your plan")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Core card
            tierUpgradeCard(
                title: "Core",
                icon: "sparkles",
                iconColor: MirrorTheme.primary,
                bullets: [
                    "Daily reflections from your entries",
                    "15 Ask questions per month",
                    "Weekly digest every Sunday",
                ],
                packages: subscriptionService.corePackages
            )

            // Deep card
            tierUpgradeCard(
                title: "Deep",
                icon: "flame.fill",
                iconColor: .purple,
                bullets: [
                    "Everything in Core",
                    "Unlimited Ask questions",
                    "Monthly deep report",
                    "Mood timeline + alerts",
                ],
                packages: subscriptionService.deepPackages
            )

            Button("Restore Purchases") {
                Task {
                    isLoading = true
                    await subscriptionService.restorePurchases()
                    isLoading = false
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            HStack(spacing: 16) {
                if let privacyURL = AppConstants.privacyPolicyURL {
                    Link("Privacy Policy", destination: privacyURL)
                }
                if let termsURL = AppConstants.termsOfUseURL {
                    Link("Terms of Use", destination: termsURL)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            if isLoading {
                ProgressView().padding(.top, 4)
            }
        }
    }

    private func tierUpgradeCard(title: String, icon: String, iconColor: Color, bullets: [String], packages: [Package]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text("MirrorNotes \(title)")
                    .font(.system(size: 16, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(bullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "checkmark")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            if packages.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading…").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(packages, id: \.storeProduct.productIdentifier) { package in
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
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(packageSubtitle(package))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(package.storeProduct.localizedPriceString)
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .padding(14)
                            .background(iconColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(iconColor.opacity(0.15), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                }
            }
        }
        .padding(16)
        .futureSurface(cornerRadius: 18)
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
        let isDeepProduct = package.storeProduct.productIdentifier.contains("deep")
        switch package.packageType {
        case .monthly:  return "Billed monthly · cancel anytime"
        case .annual:   return isDeepProduct ? "Billed yearly · save ~17%" : "Billed yearly · save ~16%"
        default:        return "7-day free trial"
        }
    }

    private var manageSection: some View {
        VStack(spacing: 12) {
            if subscriptionService.tier == .core {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to Deep")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Unlimited Ask, monthly report, mood timeline")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "flame.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.purple)
                    }
                    .padding(16)
                    .futureSurface(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }

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
