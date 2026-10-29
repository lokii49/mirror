import SwiftUI
import RevenueCat
import StoreKit
import SwiftData

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @State private var subscriptionService = SubscriptionService.shared
    @State private var selectedTier: PaywallTier
    @State private var selectedProductID = ""
    @State private var showRedeemCode = false

    init(initialTier: PaywallTier = .core) {
        _selectedTier = State(initialValue: initialTier)
    }

    enum PaywallTier: String, CaseIterable {
        case core = "Core"
        case deep = "Deep"

        var displayName: LocalizedStringKey {
            switch self {
            case .core: return "Core"
            case .deep: return "Deep"
            }
        }

        var subscriptionTier: SubscriptionTier { self == .core ? .core : .deep }
    }

    private struct Feature: Identifiable {
        let icon: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey?
        let color: Color
        var id: String { icon }
    }

    private var isSentinel: Bool { displayMode == .sentinel }
    private var accent: Color { isSentinel ? MirrorTheme.ember : MirrorTheme.primary }

    private var currentPackages: [Package] {
        selectedTier == .core ? subscriptionService.corePackages : subscriptionService.deepPackages
    }

    private var selectedPackage: Package? {
        currentPackages.first { $0.storeProduct.productIdentifier == selectedProductID }
    }

    private var defaultProductID: String {
        currentPackages.first(where: { Self.isYearly($0) })?.storeProduct.productIdentifier
            ?? currentPackages.first?.storeProduct.productIdentifier
            ?? ""
    }

    /// The trial is promised only where this Apple ID can still use it (one per subscription group).
    private var showsTrial: Bool {
        if let selectedPackage { return subscriptionService.isTrialEligible(selectedPackage) }
        return currentPackages.contains { subscriptionService.isTrialEligible($0) }
    }

    /// The badge's trial length, from the store's own offer; nil (no badge) when it isn't known.
    private var trialLength: String? {
        guard showsTrial else { return nil }
        if let selectedPackage { return Self.freeTrialLength(selectedPackage) }
        return currentPackages.lazy
            .filter { subscriptionService.isTrialEligible($0) }
            .compactMap { Self.freeTrialLength($0) }
            .first
    }

    /// "7 days", "1 week": the introductory offer's period in the app's language, only when that
    /// offer is a free trial (a paid intro price is not a trial).
    static func freeTrialLength(_ package: Package) -> String? {
        guard let offer = package.storeProduct.introductoryDiscount, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.subscriptionPeriod
        guard period.value > 0 else { return nil }
        var components = DateComponents()
        let unit: NSCalendar.Unit
        switch period.unit {
        case .day: components.day = period.value; unit = .day
        case .week: components.weekOfMonth = period.value; unit = .weekOfMonth
        case .month: components.month = period.value; unit = .month
        case .year: components.year = period.value; unit = .year
        @unknown default: return nil
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [unit]
        formatter.maximumUnitCount = 1
        // The app's language, not the device region's, so the length matches the sentence around it.
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        formatter.calendar = calendar
        return formatter.string(from: components)
    }

    /// Yearly vs twelve months, from the store's own prices in the user's currency.
    static func yearlySavingsPercent(in packages: [Package]) -> Int? {
        guard let monthly = packages.first(where: { !isYearly($0) })?.storeProduct.price,
              let yearly = packages.first(where: { isYearly($0) })?.storeProduct.price,
              monthly > 0 else { return nil }
        let fullYear = monthly * 12
        let percent = NSDecimalNumber(decimal: (fullYear - yearly) / fullYear * 100).doubleValue
        return percent >= 1 ? Int(percent.rounded()) : nil
    }

    private var selectedIsCurrentPlan: Bool {
        subscriptionService.activeProductIDs.contains(selectedProductID)
    }

    static func isYearly(_ package: Package) -> Bool {
        let id = package.storeProduct.productIdentifier
        return id.contains("yearly") || id.contains("annual")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    heroSection
                    tierPicker
                    featuresSection
                    planSection
                }
                .padding(16)
            }
            .background(MirrorTheme.bgBase)
            .safeAreaInset(edge: .bottom, spacing: 0) { ctaBar }
            .navigationBarTitleDisplayMode(.inline)
            #if os(macOS)
            // A Mac sheet puts toolbar items in a strip under the content, below the pinned bar,
            // so the close button sits on the hero's corner instead, and the sheet opens big
            // enough to show the features without scrolling first.
            .overlay(alignment: .topTrailing) { closeButton.padding(28) }
            .frame(minWidth: 500, idealWidth: 540, minHeight: 720, idealHeight: 840)
            #else
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { closeButton }
            }
            #endif
            .task {
                // A previous open's message must not greet this one (the service is shared).
                subscriptionService.clearMessages()
                // Plans are usually preloaded at launch; selecting here covers the case where
                // they were, since no package change will fire below.
                selectDefaultIfNeeded()
                await subscriptionService.loadProducts()
                selectDefaultIfNeeded()
            }
            // Watch the tier, not "subscribed": a Core → Deep upgrade keeps `isSubscribed` true.
            // Also covers a purchase that lands from another device while the paywall is open.
            .onChange(of: subscriptionService.tier) { old, new in
                if Self.rank(new) > Self.rank(old) { finishPurchase() }
            }
            .onChange(of: selectedTier) { _, _ in
                selectedProductID = defaultProductID
            }
            .onChange(of: subscriptionService.corePackages) { _, _ in selectDefaultIfNeeded() }
            .onChange(of: subscriptionService.deepPackages) { _, _ in selectDefaultIfNeeded() }
            #if os(iOS)
            // A redeemed code raises the tier, and the tier change above closes the paywall.
            .offerCodeRedemption(isPresented: $showRedeemCode) { _ in
                Task { await subscriptionService.offerCodeSheetClosed() }
            }
            #endif
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .scaledFont(22)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(MirrorTheme.textSecondary)
        }
        .accessibilityLabel("Close")
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }

    private static func rank(_ tier: SubscriptionTier) -> Int {
        switch tier {
        case .free: 0
        case .core: 1
        case .deep: 2
        }
    }

    private func selectDefaultIfNeeded() {
        if selectedPackage == nil { selectedProductID = defaultProductID }
    }

    private func finishPurchase() {
        // Generate right away: don't make a new subscriber wait for Sunday or the month's end.
        let ctx = modelContext
        Task { @MainActor in
            await mirrorApp.runWeeklyDigestIfNeeded(context: ctx)
            await mirrorApp.runMonthlyReportIfNeeded(context: ctx)
        }
        dismiss()
    }

    // MARK: Hero

    private var heroSection: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: selectedTier == .core
                    ? [Color.indigo, MirrorTheme.primary, MirrorTheme.violet.opacity(0.85)]
                    : [MirrorTheme.violet, Color.indigo, MirrorTheme.violetLight.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 180, height: 180)
                .offset(x: 60, y: -70)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: selectedTier == .core ? "sparkles" : "flame.fill")
                        .scaledFont(20, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.18), in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                    if let trialLength {
                        trialBadge(trialLength)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if isSentinel {
                            Text(selectedTier == .core ? "SENTINEL CORE" : "SENTINEL DEEP")
                                .scaledFont(26, weight: .bold, design: .monospaced)
                                .tracking(0.5)
                        } else {
                            Text(selectedTier == .core ? "MirrorNotes Core" : "MirrorNotes Deep")
                                .scaledFont(30, weight: .bold, design: .rounded)
                        }
                    }
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)

                    Group {
                        if isSentinel {
                            Text(selectedTier == .core
                                 ? "PRIVATE SIGNAL INTELLIGENCE,\nBUILT AROUND YOUR OWN LOG."
                                 : "FULL SPECTRUM: MOOD, PATTERNS,\nAND MONTHLY DEEP DEBRIEF.")
                                .scaledFont(12, weight: .medium, design: .monospaced)
                        } else {
                            Text(selectedTier == .core
                                 ? "Private journal intelligence,\nbuilt around your writing."
                                 : "The full picture: mood, patterns,\nand monthly deep reflection.")
                                .scaledFont(15, weight: .medium)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: isSentinel ? 10 : 26, style: .continuous))
        .shadow(color: MirrorTheme.primary.opacity(0.18), radius: 14, x: 0, y: 8)
        .animation(.easeInOut(duration: 0.25), value: selectedTier)
    }

    private func trialBadge(_ length: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "gift")
                .scaledFont(12, weight: .semibold)
            Text("Free for \(length)")
                .scaledFont(isSentinel ? 12 : 13, weight: isSentinel ? .bold : .semibold, design: isSentinel ? .monospaced : .default)
                .textCase(isSentinel ? .uppercase : nil)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.18), in: Capsule())
    }

    // MARK: Tier picker

    private var tierPicker: some View {
        HStack(spacing: 0) {
            ForEach(PaywallTier.allCases, id: \.self) { tier in
                let isSelected = selectedTier == tier
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTier = tier
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(tier.displayName)
                            .font(isSentinel
                                  ? MirrorTheme.mono(14, weight: isSelected ? .bold : .medium)
                                  : .system(size: 16, weight: isSelected ? .bold : .medium))
                            .textCase(isSentinel ? .uppercase : nil)
                            .foregroundStyle(isSelected ? accent : MirrorTheme.textSecondary)
                        tierCaption(tier, isSelected: isSelected)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: isSentinel ? 6 : 14, style: .continuous)
                                .fill(isSentinel ? MirrorTheme.ember.opacity(0.12) : MirrorTheme.violetDim)
                                .overlay {
                                    if isSentinel {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(MirrorTheme.ember.opacity(0.4), lineWidth: 1)
                                    }
                                }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .themedCard(cornerRadius: 18)
    }

    /// "Current plan" for the subscriber's own tier, otherwise the tier's tagline.
    @ViewBuilder
    private func tierCaption(_ tier: PaywallTier, isSelected: Bool) -> some View {
        let caption: LocalizedStringKey = subscriptionService.tier == tier.subscriptionTier && !SubscriptionService.allFeaturesFree
            ? "Current plan"
            : (tier == .core ? "Most popular" : "More AI")
        Text(caption)
            .scaledFont(isSentinel ? 9 : 11, weight: .semibold, design: isSentinel ? .monospaced : .default)
            .textCase(isSentinel ? .uppercase : nil)
            .foregroundStyle(isSelected ? accent.opacity(0.85) : MirrorTheme.textTertiary)
    }

    // MARK: Features

    private var coreFeatures: [Feature] {
        [
            Feature(icon: "sparkles", title: "Daily Reflection",
                    detail: "Personal observations from your recent entries.", color: MirrorTheme.primary),
            Feature(icon: "bubble.left.and.bubble.right", title: "Ask",
                    detail: "15 grounded questions per month from your own writing.", color: .blue),
            Feature(icon: "calendar.badge.clock", title: "Weekly Digest",
                    detail: "A pattern summary every Sunday.", color: .indigo),
            Feature(icon: "face.smiling", title: "Auto Mood Detection",
                    detail: "Mood tagged automatically on every save.", color: .pink),
            Feature(icon: "square.grid.2x2", title: "Home screen widget", detail: nil, color: .orange),
        ]
    }

    private var deepFeatures: [Feature] {
        [
            Feature(icon: "checkmark.circle", title: "Everything in Core", detail: nil, color: .green),
            Feature(icon: "bubble.left.and.bubble.right.fill", title: "Ask",
                    detail: "Unlimited questions, no monthly cap.", color: .blue),
            Feature(icon: "doc.text.magnifyingglass", title: "Monthly Deep Report",
                    detail: "A full reflection on your month.", color: MirrorTheme.violet),
            Feature(icon: "waveform.path.ecg", title: "Mood Timeline",
                    detail: "30/90/all-time chart + analytics.", color: .pink),
            Feature(icon: "bell.badge", title: "Mood Alerts",
                    detail: "A heads-up after three low-mood days.", color: .orange),
        ]
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(isSentinel ? "PAYLOAD" : "What's included")

            VStack(alignment: .leading, spacing: 14) {
                ForEach(selectedTier == .core ? coreFeatures : deepFeatures) { feature in
                    featureRow(feature)
                }
            }
            .id(selectedTier)
            .transition(.opacity)

            Divider().overlay(MirrorTheme.inkBorder).padding(.vertical, 16)

            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .scaledFont(15, weight: .semibold)
                    .foregroundStyle(.green)
                Text("AI runs on your device")
                    .scaledFont(isSentinel ? 12 : 14, weight: .semibold, design: isSentinel ? .monospaced : .default)
                    .textCase(isSentinel ? .uppercase : nil)
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: 24)
        .animation(.easeInOut(duration: 0.2), value: selectedTier)
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: feature.detail == nil ? .center : .top, spacing: 14) {
            Image(systemName: feature.icon)
                .scaledFont(16, weight: .semibold)
                .foregroundStyle(isSentinel ? MirrorTheme.ember : feature.color)
                .frame(width: 38, height: 38)
                .background(
                    (isSentinel ? MirrorTheme.ember : feature.color).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: isSentinel ? 6 : 10, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .scaledFont(isSentinel ? 13 : 15, weight: isSentinel ? .bold : .semibold, design: isSentinel ? .monospaced : .default)
                    .textCase(isSentinel ? .uppercase : nil)
                    .foregroundStyle(MirrorTheme.textPrimary)
                if let detail = feature.detail {
                    Text(detail)
                        .scaledFont(isSentinel ? 11 : 13, weight: isSentinel ? .semibold : .regular, design: isSentinel ? .monospaced : .default)
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .scaledFont(isSentinel ? 11 : 12, weight: .semibold, design: isSentinel ? .monospaced : .default)
            .foregroundStyle(MirrorTheme.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.bottom, 14)
    }

    // MARK: Plans

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(isSentinel ? "SELECT PLAN" : "Choose a plan")

            if currentPackages.isEmpty {
                if subscriptionService.productsLoadFailed {
                    plansUnavailable
                } else {
                    // Placeholder rows the size of real ones, so nothing jumps when plans arrive.
                    VStack(spacing: 10) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: isSentinel ? 6 : 16, style: .continuous)
                                .fill(MirrorTheme.inkMid)
                                .frame(height: 70)
                        }
                    }
                    .overlay { ProgressView() }
                    .accessibilityLabel("Loading plans…")
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(currentPackages, id: \.storeProduct.productIdentifier) { package in
                        let id = package.storeProduct.productIdentifier
                        PlanCard(
                            package: package,
                            savingsPercent: Self.isYearly(package) ? yearlySavingsPercent : nil,
                            isSelected: selectedProductID == id,
                            isCurrent: subscriptionService.activeProductIDs.contains(id),
                            onTap: { selectedProductID = id }
                        )
                    }
                }
            }
        }
        .padding(20)
        .themedCard(cornerRadius: 24)
    }

    private var plansUnavailable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couldn't load plans. Check your connection.")
                .scaledFont(isSentinel ? 12 : 14, weight: isSentinel ? .semibold : .regular, design: isSentinel ? .monospaced : .default)
                .foregroundStyle(MirrorTheme.textSecondary)
            Button {
                Task {
                    await subscriptionService.loadProducts()
                    selectDefaultIfNeeded()
                }
            } label: {
                Text("Try Again")
                    .scaledFont(isSentinel ? 13 : 14, weight: .semibold, design: isSentinel ? .monospaced : .default)
                    .textCase(isSentinel ? .uppercase : nil)
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var yearlySavingsPercent: Int? { Self.yearlySavingsPercent(in: currentPackages) }

    // MARK: CTA

    private var ctaTitle: LocalizedStringKey {
        if selectedIsCurrentPlan { return "Current plan" }
        if subscriptionService.tier == .core && selectedTier == .deep && !SubscriptionService.allFeaturesFree {
            return "Upgrade to Deep"
        }
        return showsTrial ? "Start Free Trial" : "Subscribe"
    }

    private var ctaDisabled: Bool {
        subscriptionService.isPurchasing || selectedPackage == nil || selectedIsCurrentPlan
    }

    private var ctaBar: some View {
        VStack(spacing: 10) {
            if let message = subscriptionService.purchaseError ?? subscriptionService.restoreMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(subscriptionService.purchaseError != nil ? Color.red : MirrorTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Button {
                guard let package = selectedPackage else { return }
                Task { await subscriptionService.purchase(package) }
            } label: {
                ZStack {
                    if subscriptionService.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaTitle)
                            .scaledFont(isSentinel ? 15 : 17, weight: isSentinel ? .bold : .semibold, design: isSentinel ? .monospaced : .default)
                            .textCase(isSentinel ? .uppercase : nil)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    ctaDisabled ? AnyShapeStyle(Color.secondary.opacity(0.3)) : AnyShapeStyle(MirrorTheme.ember),
                    in: RoundedRectangle(cornerRadius: isSentinel ? 8 : 27, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ctaDisabled)

            Text(showsTrial ? "Cancel anytime in App Store settings. No charge during trial." : "Cancel anytime in App Store settings.")
                .scaledFont(isSentinel ? 10 : 12, weight: isSentinel ? .medium : .regular, design: isSentinel ? .monospaced : .default)
                .textCase(isSentinel ? .uppercase : nil)
                .foregroundStyle(MirrorTheme.textTertiary)
                .multilineTextAlignment(.center)

            // One line when it fits, else purchase links over legal links; at large text sizes
            // every link gets its own line instead of truncating ("Restore P… · Privacy…").
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    purchaseLinks(separated: true)
                    legalLinks(separated: true, followsOthers: true)
                }
                .lineLimit(1)
                VStack(spacing: 6) {
                    HStack(spacing: 6) { purchaseLinks(separated: true) }
                    HStack(spacing: 6) { legalLinks(separated: true, followsOthers: false) }
                }
                .lineLimit(1)
                VStack(spacing: 8) {
                    purchaseLinks(separated: false)
                    legalLinks(separated: false, followsOthers: false)
                }
            }
            .scaledFont(isSentinel ? 11 : 12, weight: .medium, design: isSentinel ? .monospaced : .default)
            .textCase(isSentinel ? .uppercase : nil)
            .foregroundStyle(MirrorTheme.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider().overlay(MirrorTheme.inkBorder) }
    }
}

extension PaywallView {
    /// Apple's offer-code sheet. Hidden for the iPhone app on a Mac, where RevenueCat found the older
    /// StoreKit 1 version of this sheet crashes.
    fileprivate var offersRedeemCode: Bool {
        #if os(iOS)
        !ProcessInfo.processInfo.isiOSAppOnMac
        #else
        false
        #endif
    }

    @ViewBuilder
    fileprivate func purchaseLinks(separated: Bool) -> some View {
        Button("Restore Purchases") {
            Task { await subscriptionService.restorePurchases() }
        }
        .buttonStyle(.plain)
        if offersRedeemCode {
            if separated { Text(verbatim: "·") }
            Button("Redeem Code") { showRedeemCode = true }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    fileprivate func legalLinks(separated: Bool, followsOthers: Bool) -> some View {
        if let privacyURL = AppConstants.privacyPolicyURL {
            if separated && followsOthers { Text(verbatim: "·") }
            Link("Privacy Policy", destination: privacyURL)
        }
        if let termsURL = AppConstants.termsOfUseURL {
            if separated && (followsOthers || AppConstants.privacyPolicyURL != nil) { Text(verbatim: "·") }
            Link("Terms of Use", destination: termsURL)
        }
    }
}

private struct PlanCard: View {
    let package: Package
    let savingsPercent: Int?
    let isSelected: Bool
    let isCurrent: Bool
    let onTap: () -> Void
    @Environment(\.appDisplayMode) private var displayMode

    private var isSentinel: Bool { displayMode == .sentinel }
    private var isYearly: Bool { PaywallView.isYearly(package) }
    private var price: String { package.storeProduct.localizedPriceString }
    private var accent: Color { isSentinel ? MirrorTheme.ember : MirrorTheme.primary }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                selectionMark

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Yearly" : "Monthly")
                            .scaledFont(isSentinel ? 14 : 16, weight: .semibold, design: isSentinel ? .monospaced : .default)
                            .textCase(isSentinel ? .uppercase : nil)
                            .foregroundStyle(MirrorTheme.textPrimary)
                        if isCurrent {
                            badge("Current plan")
                        } else if isYearly {
                            badge("Best value")
                        }
                    }
                    priceLine
                        .scaledFont(isSentinel ? 12 : 13, weight: isSentinel ? .medium : .regular, design: isSentinel ? .monospaced : .default)
                        .foregroundStyle(MirrorTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                isSelected ? (isSentinel ? MirrorTheme.ember.opacity(0.10) : MirrorTheme.violetDim) : MirrorTheme.inkMid,
                in: RoundedRectangle(cornerRadius: isSentinel ? 6 : 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: isSentinel ? 6 : 16, style: .continuous)
                    .stroke(
                        isSelected ? (isSentinel ? MirrorTheme.ember.opacity(0.5) : MirrorTheme.violet.opacity(0.45)) : MirrorTheme.inkBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }

    @ViewBuilder
    private var priceLine: some View {
        if isYearly, let savingsPercent {
            Text(isSentinel ? "\(price) / YR (SAVE ~\(savingsPercent)%)" : "\(price) / year (save ~\(savingsPercent)%)")
        } else if isYearly {
            Text("\(price) / year").textCase(isSentinel ? .uppercase : nil)
        } else {
            Text(isSentinel ? "\(price) / MO" : "\(price) / month")
        }
    }

    private var selectionMark: some View {
        ZStack {
            if isSentinel {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isSelected ? MirrorTheme.ember : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1.5)
                    .frame(width: 20, height: 20)
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(MirrorTheme.ember)
                        .frame(width: 10, height: 10)
                }
            } else {
                Circle()
                    .stroke(isSelected ? MirrorTheme.primary : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1.5)
                    .frame(width: 22, height: 22)
                if isSelected {
                    Circle()
                        .fill(MirrorTheme.accentGradient)
                        .frame(width: 12, height: 12)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private func badge(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .scaledFont(isSentinel ? 10 : 11, weight: .bold, design: isSentinel ? .monospaced : .default)
            .textCase(isSentinel ? .uppercase : nil)
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: Capsule())
    }
}
