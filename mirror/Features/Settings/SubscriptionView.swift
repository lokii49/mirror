import SwiftUI
import RevenueCat
import StoreKit

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
    @State private var showRedeemCode = false
    /// Shown as a tab of the Mac Settings window: no navigation bar or Done, and no own scroll view.
    var embedded = false

    private var statusSections: some View {
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

    var body: some View {
        Group {
            if embedded {
                statusSections
            } else {
                NavigationStack {
                    ScrollView { statusSections }
                    .navigationTitle(displayMode == .sentinel ? "Clearance" : "Subscription")
                    .navigationBarTitleDisplayMode(.inline)
                    .background(MirrorTheme.bgBase)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                        .cancelActionOnMac()
                                .scaledFont(16, weight: .medium)
                        }
                    }
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
        #if os(iOS)
        .offerCodeRedemption(isPresented: $showRedeemCode) { _ in
            Task { await subscriptionService.offerCodeSheetClosed() }
        }
        #endif
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: subscriptionService.isSubscribed ? "checkmark.seal.fill" : "seal")
                .scaledFont(28, weight: .semibold)
                .foregroundStyle(subscriptionService.isDeep ? MirrorTheme.violet : subscriptionService.isSubscribed ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if displayMode == .sentinel {
                        Text(tierName).scaledFont(16, weight: .bold, design: .monospaced).textCase(.uppercase)
                    } else {
                        Text(tierName).scaledFont(17, weight: .semibold)
                    }
                }
                Group {
                    if displayMode == .sentinel {
                        Text(tierDescription).scaledFont(11, weight: .medium, design: .monospaced)
                    } else {
                        Text(tierDescription).scaledFont(14)
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
        switch subscriptionService.tier {
        case .free: return "Free Plan"
        case .core: return "MirrorNotes Core"
        case .deep: return "MirrorNotes Deep"
        }
    }

    private var tierDescription: LocalizedStringKey {
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
            Group {
                if displayMode == .sentinel {
                    Text("SELECT CLEARANCE LEVEL").scaledFont(18, weight: .bold, design: .monospaced).tracking(0.5)
                } else {
                    Text("Upgrade your plan").scaledFont(20, weight: .bold, design: .rounded)
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
                    Text("RESTORE PURCHASES").scaledFont(12, weight: .medium, design: .monospaced)
                } else {
                    Text("Restore Purchases").scaledFont(14, weight: .medium)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            redeemCodeButton

            HStack(spacing: 16) {
                if let privacyURL = AppConstants.privacyPolicyURL {
                    Link("Privacy Policy", destination: privacyURL)
                }
                if let termsURL = AppConstants.termsOfUseURL {
                    Link("Terms of Use", destination: termsURL)
                }
            }
            .scaledFont(12)
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
                        .scaledFont(16, weight: .semibold)
                        .foregroundStyle(iconColor)
                }
                Group {
                    if displayMode == .sentinel {
                        Text(title).textCase(.uppercase).scaledFont(15, weight: .bold, design: .monospaced)
                    } else {
                        (Text("MirrorNotes ") + Text(title)).font(.system(size: 16, weight: .bold))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    Label(bullet, systemImage: "checkmark")
                        .scaledFont(displayMode == .sentinel ? 12 : 13, weight: displayMode == .sentinel ? .medium : .regular, design: displayMode == .sentinel ? .monospaced : .default)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            if packages.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Group {
                        if displayMode == .sentinel {
                            Text("LOADING…").scaledFont(12, weight: .medium, design: .monospaced)
                        } else {
                            Text("Loading…").scaledFont(13)
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
                                            Text(packageLabel(package)).scaledFont(14, weight: .semibold, design: .monospaced).textCase(.uppercase)
                                        } else {
                                            Text(packageLabel(package)).scaledFont(15, weight: .semibold)
                                        }
                                    }
                                    if let subtitle = packageSubtitle(package, in: packages) {
                                        Group {
                                            if displayMode == .sentinel {
                                                Text(subtitle).scaledFont(10.5, weight: .medium, design: .monospaced)
                                            } else {
                                                Text(subtitle).scaledFont(12)
                                            }
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(package.storeProduct.localizedPriceString)
                                    .scaledFont(15, weight: .bold, design: displayMode == .sentinel ? .monospaced : .default)
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
        // Full width while plans load too, not only once a price row's Spacer stretches it.
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Savings come from the store's own prices (as on the paywall); a trial is mentioned only
    /// when this Apple ID can still use it, with the length the store gives.
    private func packageSubtitle(_ package: Package, in packages: [Package]) -> LocalizedStringKey? {
        switch package.packageType {
        case .monthly:
            return "Billed monthly · cancel anytime"
        case .annual:
            if let percent = PaywallView.yearlySavingsPercent(in: packages) {
                return "Billed yearly · save ~\(percent)%"
            }
            return "Billed yearly"
        default:
            guard subscriptionService.isTrialEligible(package),
                  let length = PaywallView.freeTrialLength(package) else { return nil }
            return "Free for \(length)"
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
                                    Text("UPGRADE TO DEEP").scaledFont(14, weight: .semibold, design: .monospaced)
                                } else {
                                    Text("Upgrade to Deep").scaledFont(16, weight: .semibold)
                                }
                            }
                            Group {
                                if displayMode == .sentinel {
                                    Text("UNLIMITED ASK, MONTHLY DEBRIEF, VITALS").scaledFont(10.5, weight: .medium, design: .monospaced)
                                } else {
                                    Text("Unlimited Ask, monthly report, mood timeline").scaledFont(13)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "flame.fill")
                            .scaledFont(15)
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
                            Text("MANAGE SUBSCRIPTION").scaledFont(14, weight: .medium, design: .monospaced)
                        } else {
                            Text("Manage Subscription").scaledFont(16, weight: .medium)
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .scaledFont(14)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .subscriptionCard(cornerRadius: 16)
            }
            .buttonStyle(.plain)

            Text("Manage or cancel your subscription in the App Store.")
                .scaledFont(13)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // Subscribers too: an offer code can be for existing subscribers, and the What's New
            // card sends everyone here.
            redeemCodeButton
                .padding(.top, 4)
        }
    }

    /// Apple's offer-code sheet (`offerCodeRedemption` on the body). Hidden for the iPhone app on
    /// a Mac, where RevenueCat found the older StoreKit 1 version of this sheet crashes.
    @ViewBuilder
    private var redeemCodeButton: some View {
        #if os(iOS)
        if !ProcessInfo.processInfo.isiOSAppOnMac {
            Button { showRedeemCode = true } label: {
                if displayMode == .sentinel {
                    Text("REDEEM CODE").scaledFont(12, weight: .medium, design: .monospaced)
                } else {
                    Text("Redeem Code").scaledFont(14, weight: .medium)
                }
            }
            .foregroundStyle(.secondary)
        }
        #endif
    }
}
