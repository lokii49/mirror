import SwiftUI
import RevenueCat
import SwiftData

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @State private var subscriptionService = SubscriptionService.shared
    @State private var selectedTier: PaywallTier
    @State private var selectedProductID = ""

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
    }

    private var currentPackages: [Package] {
        selectedTier == .core ? subscriptionService.corePackages : subscriptionService.deepPackages
    }

    private var defaultProductID: String {
        currentPackages.first(where: { $0.storeProduct.productIdentifier.contains("yearly") })?.storeProduct.productIdentifier
            ?? currentPackages.first?.storeProduct.productIdentifier
            ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    heroSection
                    tierPicker
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
                            .foregroundStyle(MirrorTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .task { await subscriptionService.loadProducts() }
            .onChange(of: subscriptionService.isSubscribed) { _, subscribed in
                if subscribed {
                    // Generate immediately — don't wait for Sunday/1st of month
                    let ctx = modelContext
                    Task { @MainActor in
                        await mirrorApp.runWeeklyDigestIfNeeded(context: ctx)
                        await mirrorApp.runMonthlyReportIfNeeded(context: ctx)
                    }
                    dismiss()
                }
            }
            .onChange(of: selectedTier) { _, _ in
                selectedProductID = defaultProductID
            }
            .onChange(of: subscriptionService.corePackages) { _, _ in
                if selectedProductID.isEmpty { selectedProductID = defaultProductID }
            }
            .onChange(of: subscriptionService.deepPackages) { _, _ in
                if selectedProductID.isEmpty { selectedProductID = defaultProductID }
            }
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: selectedTier == .core
                            ? [Color.indigo, MirrorTheme.primary, MirrorTheme.violet.opacity(0.85)]
                            : [MirrorTheme.violet, Color.indigo, MirrorTheme.violetLight.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 160, height: 160)
                .offset(x: 200, y: -60)
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 100, height: 100)
                .offset(x: 240, y: 20)

            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 64, height: 64)
                    Image(systemName: selectedTier == .core ? "sparkles" : "flame.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if displayMode == .sentinel {
                            Text(selectedTier == .core ? "SENTINEL CORE" : "SENTINEL DEEP")
                                .font(MirrorTheme.mono(28, weight: .bold))
                                .tracking(0.5)
                        } else {
                            Text(selectedTier == .core ? "MirrorNotes Core" : "MirrorNotes Deep")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundStyle(.white)
                    Group {
                        if displayMode == .sentinel {
                            Text(selectedTier == .core
                                 ? "PRIVATE SIGNAL INTELLIGENCE,\nBUILT AROUND YOUR OWN LOG."
                                 : "FULL SPECTRUM — MOOD, PATTERNS,\nAND MONTHLY DEEP DEBRIEF.")
                                .font(MirrorTheme.mono(12, weight: .medium))
                        } else {
                            Text(selectedTier == .core
                                 ? "Private journal intelligence,\nbuilt around your writing."
                                 : "The full picture — mood, patterns,\nand monthly deep reflection.")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.75))
                }

                HStack(spacing: 6) {
                    Image(systemName: "gift")
                        .font(.system(size: 12, weight: .semibold))
                    Text(displayMode == .sentinel ? "7-DAY TRIAL" : "7-day free trial")
                        .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 13, weight: .semibold))
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
        .animation(.easeInOut(duration: 0.25), value: selectedTier)
    }

    private var tierPicker: some View {
        HStack(spacing: 0) {
            ForEach(PaywallTier.allCases, id: \.self) { tier in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTier = tier
                    }
                } label: {
                    VStack(spacing: 4) {
                        Group {
                            if displayMode == .sentinel {
                                Text(tier.displayName)
                                    .font(MirrorTheme.mono(14, weight: selectedTier == tier ? .bold : .medium))
                                    .textCase(.uppercase)
                            } else {
                                Text(tier.displayName)
                                    .font(.system(size: 15, weight: selectedTier == tier ? .bold : .medium))
                            }
                        }
                        .foregroundStyle(selectedTier == tier ? (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary) : .secondary)
                        if tier == .deep {
                            Group {
                                if displayMode == .sentinel {
                                    Text("MORE AI").font(MirrorTheme.mono(9, weight: .semibold))
                                } else {
                                    Text("More AI").font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .foregroundStyle(selectedTier == .deep ? (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violetLight) : MirrorTheme.textTertiary)
                            .opacity(0.85)
                        } else {
                            Group {
                                if displayMode == .sentinel {
                                    Text("MOST POPULAR").font(MirrorTheme.mono(9, weight: .bold))
                                } else {
                                    Text("Most popular").font(.system(size: 10, weight: .bold))
                                }
                            }
                            .foregroundStyle(selectedTier == .core ? MirrorTheme.ember : MirrorTheme.textTertiary)
                            .opacity(selectedTier == .core ? 1.0 : 0.6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selectedTier == tier
                            ? (displayMode == .sentinel ? MirrorTheme.ember.opacity(0.12) : MirrorTheme.violetDim)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 14, style: .continuous)
                    )
                    .overlay {
                        if displayMode == .sentinel && selectedTier == tier {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(MirrorTheme.ember.opacity(0.4), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .themedCard(cornerRadius: 18)
    }

    private var coreFeatures: [(String, LocalizedStringKey, Color)] {
        [
            ("sparkles", "Daily Reflection — personal observations from your recent entries.", MirrorTheme.primary),
            ("bubble.left.and.bubble.right", "Ask — 15 grounded questions per month from your own writing.", .blue),
            ("calendar.badge.clock", "Weekly Digest — a pattern summary every Sunday.", .indigo),
            ("face.smiling", "Auto Mood Detection — mood tagged automatically on every save.", .pink),
            ("square.grid.2x2", "Home screen widget", .orange),
        ]
    }

    private var deepFeatures: [(String, LocalizedStringKey, Color)] {
        [
            ("checkmark.circle", "Everything in Core", .green),
            ("bubble.left.and.bubble.right.fill", "Ask — unlimited questions, no monthly cap.", .blue),
            ("doc.text.magnifyingglass", "Monthly Deep Report — a full reflection on your month.", MirrorTheme.violet),
            ("waveform.path.ecg", "Mood Timeline — 30/90/all-time chart + analytics.", .pink),
            ("bell.badge", "Mood Alerts — notified when your mood drops for 3 entries.", .orange),
        ]
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if displayMode == .sentinel {
                    Text("PAYLOAD").font(MirrorTheme.mono(11, weight: .semibold))
                } else {
                    Text("What's included").font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(MirrorTheme.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.bottom, 14)

            VStack(spacing: 12) {
                let features = selectedTier == .core ? coreFeatures : deepFeatures
                ForEach(features, id: \.0) { icon, detail, color in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(color.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(color)
                        }
                        Text(detail)
                            .font(.system(size: 14))
                            .foregroundStyle(MirrorTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(20)
        .themedCard(cornerRadius: 24)
        .animation(.easeInOut(duration: 0.2), value: selectedTier)
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if displayMode == .sentinel {
                    Text("SELECT PLAN").font(MirrorTheme.mono(11, weight: .semibold))
                } else {
                    Text("Choose a plan").font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(MirrorTheme.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.bottom, 14)

            if currentPackages.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.9)
                    Group {
                        if displayMode == .sentinel {
                            Text("LOADING PLANS…").font(MirrorTheme.mono(12, weight: .medium))
                        } else {
                            Text("Loading plans…").font(.system(size: 14))
                        }
                    }
                    .foregroundStyle(MirrorTheme.textSecondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(currentPackages, id: \.storeProduct.productIdentifier) { package in
                        PlanCard(
                            package: package,
                            isSelected: selectedProductID == package.storeProduct.productIdentifier,
                            onTap: { selectedProductID = package.storeProduct.productIdentifier }
                        )
                    }
                }
            }
        }
        .padding(20)
        .themedCard(cornerRadius: 24)
    }

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                guard let package = currentPackages.first(where: { $0.storeProduct.productIdentifier == selectedProductID }) else { return }
                Task { await subscriptionService.purchase(package) }
            } label: {
                HStack {
                    Spacer()
                    if subscriptionService.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(displayMode == .sentinel ? "START FREE TRIAL" : "Start Free Trial")
                            .font(displayMode == .sentinel ? MirrorTheme.mono(15, weight: .bold) : .system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .frame(height: 54)
                .background(
                    subscriptionService.isPurchasing || currentPackages.isEmpty
                        ? AnyShapeStyle(Color.secondary.opacity(0.3))
                        : AnyShapeStyle(MirrorTheme.ember),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(subscriptionService.isPurchasing || currentPackages.isEmpty)
            .shadow(color: MirrorTheme.ember.opacity(0.40), radius: 16, x: 0, y: 6)

            Button {
                Task { await subscriptionService.restorePurchases() }
            } label: {
                if displayMode == .sentinel {
                    Text("RESTORE PURCHASES").font(MirrorTheme.mono(13, weight: .semibold))
                } else {
                    Text("Restore Purchases").font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(MirrorTheme.textSecondary)

            Group {
                if displayMode == .sentinel {
                    Text("CANCEL ANYTIME · NO CHARGE DURING TRIAL")
                        .font(MirrorTheme.mono(10, weight: .medium))
                } else {
                    Text("Cancel anytime in App Store settings. No charge during trial.")
                        .font(.system(size: 12))
                }
            }
            .foregroundStyle(MirrorTheme.textTertiary)
            .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                if let privacyURL = AppConstants.privacyPolicyURL {
                    Link("Privacy Policy", destination: privacyURL)
                }
                if let termsURL = AppConstants.termsOfUseURL {
                    Link("Terms of Use", destination: termsURL)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(MirrorTheme.textSecondary)

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
    let package: Package
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.appDisplayMode) private var displayMode

    private var isYearly: Bool { package.storeProduct.productIdentifier.contains("yearly") || package.storeProduct.productIdentifier.contains("annual") }
    private var isDeepProduct: Bool { package.storeProduct.productIdentifier.contains("deep") }
    private var yearlySavingsPercent: Int { isDeepProduct ? 17 : 16 }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    if displayMode == .sentinel {
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

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Group {
                            if displayMode == .sentinel {
                                Text(isYearly ? "YEARLY" : "MONTHLY").font(MirrorTheme.mono(14, weight: .semibold))
                            } else {
                                Text(isYearly ? "Yearly" : "Monthly").font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .foregroundStyle(MirrorTheme.textPrimary)
                        if isYearly {
                            Group {
                                if displayMode == .sentinel {
                                    Text("BEST VALUE")
                                        .font(MirrorTheme.mono(10, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(MirrorTheme.ember.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(MirrorTheme.ember.opacity(0.4), lineWidth: 1)
                                        }
                                        .foregroundStyle(MirrorTheme.ember)
                                } else {
                                    Text("Best value")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(MirrorTheme.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(MirrorTheme.primary.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }
                    Group {
                        if displayMode == .sentinel {
                            Text(isYearly
                                 ? "\(package.storeProduct.localizedPriceString) / YR (SAVE ~\(yearlySavingsPercent)%)"
                                 : "\(package.storeProduct.localizedPriceString) / MO")
                                .font(MirrorTheme.mono(12, weight: .medium))
                        } else {
                            Text(isYearly
                                 ? "\(package.storeProduct.localizedPriceString) / year (save ~\(yearlySavingsPercent)%)"
                                 : "\(package.storeProduct.localizedPriceString) / month")
                                .font(.system(size: 13))
                        }
                    }
                    .foregroundStyle(MirrorTheme.textSecondary)
                }

                Spacer()
            }
            .padding(16)
            .background(
                isSelected ? (displayMode == .sentinel ? MirrorTheme.ember.opacity(0.10) : MirrorTheme.violetDim) : MirrorTheme.inkMid,
                in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 16, style: .continuous)
                    .stroke(
                        isSelected ? (displayMode == .sentinel ? MirrorTheme.ember.opacity(0.5) : MirrorTheme.violet.opacity(0.45)) : MirrorTheme.inkBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }
}
