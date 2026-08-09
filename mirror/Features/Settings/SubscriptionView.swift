import SwiftUI
import RevenueCat

// futureSurface has a distinct two-shadow signature from themedCard's .surface
// base (inkSurface), so swapping to themedCard would shift Classic's look.
// This keeps futureSurface verbatim for Classic and only adds the Sentinel
// branch, mirroring ThemedCardModifier's sentinel rendering exactly.
private struct SubscriptionCardModifier: ViewModifier {
    @Environment(\.appDisplayMode) private var displayMode
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if displayMode == .sentinel {
            content
                .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MirrorTheme.ember.opacity(0.24), lineWidth: 1)
                }
        } else {
            content.futureSurface(cornerRadius: cornerRadius)
        }
    }
}

private extension View {
    func subscriptionCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(SubscriptionCardModifier(cornerRadius: cornerRadius))
    }
}

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode
    @State private var subscriptionService = SubscriptionService.shared
    @State private var isLoading = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusCard

                    if SubscriptionService.allFeaturesFree {
                        earlyAccessSection
                    } else if !subscriptionService.isSubscribed {
                        upgradeSection
                    } else {
                        manageSection
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .navigationTitle(displayMode == .sentinel ? "Clearance" : "Subscription")
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
        .sheet(isPresented: $showPaywall) {
            PaywallView(initialTier: subscriptionService.tier == .core ? .deep : .core)
                .environment(\.appDisplayMode, displayMode)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: SubscriptionService.allFeaturesFree ? "sparkles" : (subscriptionService.isSubscribed ? "checkmark.seal.fill" : "seal"))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(SubscriptionService.allFeaturesFree ? MirrorTheme.primary : subscriptionService.isDeep ? MirrorTheme.violet : subscriptionService.isSubscribed ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if displayMode == .sentinel {
                        Text(tierName).font(MirrorTheme.mono(16, weight: .bold)).textCase(.uppercase)
                    } else {
                        Text(tierName).font(.system(size: 17, weight: .semibold))
                    }
                }
                Group {
                    if displayMode == .sentinel {
                        Text(tierDescription).font(MirrorTheme.mono(11, weight: .medium))
                    } else {
                        Text(tierDescription).font(.system(size: 14))
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .subscriptionCard(cornerRadius: 22)
    }

    private var tierName: LocalizedStringKey {
        if SubscriptionService.allFeaturesFree { return "Early Access" }
        switch subscriptionService.tier {
        case .free: return "Free Plan"
        case .core: return "MirrorNotes Core"
        case .deep: return "MirrorNotes Deep"
        }
    }

    private var tierDescription: LocalizedStringKey {
        if SubscriptionService.allFeaturesFree { return "Every feature is free while MirrorNotes is in early access" }
        switch subscriptionService.tier {
        case .free:
            return "Unlimited writing, full history, iCloud sync"
        case .core:
            return "Daily nudges, weekly digest, 15 Ask questions/month"
        case .deep:
            return "Everything in Core + unlimited Ask, monthly report, mood timeline"
        }
    }

    private var earlyAccessSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MirrorTheme.primary.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MirrorTheme.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if displayMode == .sentinel {
                            Text("ALL SYSTEMS UNLOCKED").font(MirrorTheme.mono(14, weight: .semibold))
                        } else {
                            Text("Everything's unlocked").font(.system(size: 16, weight: .semibold))
                        }
                    }
                    Group {
                        if displayMode == .sentinel {
                            Text("NO SUBSCRIPTION, NO PAYMENT, NOTHING TO MANAGE.").font(MirrorTheme.mono(10.5, weight: .medium))
                        } else {
                            Text("No subscription, no payment, nothing to manage.").font(.system(size: 13))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .subscriptionCard(cornerRadius: 16)

            Text("MirrorNotes is currently in early access. Pricing may return in a future update, but your entries and history stay yours either way.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var upgradeSection: some View {
        VStack(spacing: 16) {
            Group {
                if displayMode == .sentinel {
                    Text("SELECT CLEARANCE LEVEL").font(MirrorTheme.mono(18, weight: .bold)).tracking(0.5)
                } else {
                    Text("Upgrade your plan").font(.system(size: 20, weight: .bold, design: .rounded))
                }
            }
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
                iconColor: MirrorTheme.violet,
                bullets: [
                    "Everything in Core",
                    "Unlimited Ask questions",
                    "Monthly deep report",
                    "Mood timeline + alerts",
                ],
                packages: subscriptionService.deepPackages
            )

            Button {
                Task {
                    isLoading = true
                    await subscriptionService.restorePurchases()
                    isLoading = false
                }
            } label: {
                if displayMode == .sentinel {
                    Text("RESTORE PURCHASES").font(MirrorTheme.mono(12, weight: .medium))
                } else {
                    Text("Restore Purchases").font(.system(size: 14, weight: .medium))
                }
            }
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

    private func tierUpgradeCard(title: LocalizedStringKey, icon: String, iconColor: Color, bullets: [LocalizedStringKey], packages: [Package]) -> some View {
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
                Group {
                    if displayMode == .sentinel {
                        Text(title).textCase(.uppercase).font(MirrorTheme.mono(15, weight: .bold))
                    } else {
                        (Text("MirrorNotes ") + Text(title)).font(.system(size: 16, weight: .bold))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    Label(bullet, systemImage: "checkmark")
                        .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .medium) : .system(size: 13))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            if packages.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Group {
                        if displayMode == .sentinel {
                            Text("LOADING…").font(MirrorTheme.mono(12, weight: .medium))
                        } else {
                            Text("Loading…").font(.system(size: 13))
                        }
                    }
                    .foregroundStyle(.secondary)
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
                                    Group {
                                        if displayMode == .sentinel {
                                            Text(packageLabel(package)).font(MirrorTheme.mono(14, weight: .semibold)).textCase(.uppercase)
                                        } else {
                                            Text(packageLabel(package)).font(.system(size: 15, weight: .semibold))
                                        }
                                    }
                                    Group {
                                        if displayMode == .sentinel {
                                            Text(packageSubtitle(package)).font(MirrorTheme.mono(10.5, weight: .medium))
                                        } else {
                                            Text(packageSubtitle(package)).font(.system(size: 12))
                                        }
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(package.storeProduct.localizedPriceString)
                                    .font(displayMode == .sentinel ? MirrorTheme.mono(15, weight: .bold) : .system(size: 15, weight: .bold))
                            }
                            .padding(14)
                            .background(
                                iconColor.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 8 : 14, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: displayMode == .sentinel ? 8 : 14, style: .continuous)
                                    .stroke(iconColor.opacity(displayMode == .sentinel ? 0.30 : 0.15), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                }
            }
        }
        .padding(16)
        .subscriptionCard(cornerRadius: 18)
    }

    private func packageLabel(_ package: Package) -> LocalizedStringKey {
        switch package.packageType {
        case .monthly:  return "Monthly"
        case .annual:   return "Yearly"
        case .weekly:   return "Weekly"
        case .lifetime: return "Lifetime"
        default:
            let id = package.storeProduct.productIdentifier
            if id.contains("month") { return "Monthly" }
            if id.contains("year") || id.contains("annual") { return "Yearly" }
            return LocalizedStringKey(id)
        }
    }

    private func packageSubtitle(_ package: Package) -> LocalizedStringKey {
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
                            Group {
                                if displayMode == .sentinel {
                                    Text("UPGRADE TO DEEP").font(MirrorTheme.mono(14, weight: .semibold))
                                } else {
                                    Text("Upgrade to Deep").font(.system(size: 16, weight: .semibold))
                                }
                            }
                            Group {
                                if displayMode == .sentinel {
                                    Text("UNLIMITED ASK, MONTHLY DEBRIEF, VITALS").font(MirrorTheme.mono(10.5, weight: .medium))
                                } else {
                                    Text("Unlimited Ask, monthly report, mood timeline").font(.system(size: 13))
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "flame.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
                    }
                    .padding(16)
                    .subscriptionCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }

            Button {
                if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Group {
                        if displayMode == .sentinel {
                            Text("MANAGE SUBSCRIPTION").font(MirrorTheme.mono(14, weight: .medium))
                        } else {
                            Text("Manage Subscription").font(.system(size: 16, weight: .medium))
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .subscriptionCard(cornerRadius: 16)
            }
            .buttonStyle(.plain)

            Text("Manage or cancel your subscription in the App Store.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
