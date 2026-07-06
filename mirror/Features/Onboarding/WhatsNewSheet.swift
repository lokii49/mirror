import SwiftUI

enum WhatsNewMode {
    case whatsNew       // only current-version cards, auto-shown on upgrade
    case allFeatures    // full feature guide, opened from Settings
}

struct WhatsNewSheet: View {
    let mode: WhatsNewMode
    @Environment(\.dismiss) private var dismiss
    @State private var service = FeatureCardService.shared
    @State private var selectedTier: CardTier? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if mode == .whatsNew {
                        whatsNewHero
                    } else {
                        tierFilter.padding(.top, 4)
                    }
                    cardsList
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle(mode == .whatsNew ? Text(verbatim: "") : Text("Feature Guide"))
            .navigationBarTitleDisplayMode(mode == .whatsNew ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if mode == .whatsNew {
                service.markWhatsNewSeen()
            }
        }
    }

    // MARK: - What's New hero card

    private var whatsNewHero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.indigo, MirrorTheme.primary, MirrorTheme.violet.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 140, height: 140)
                .offset(x: 210, y: -50)
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 90, height: 90)
                .offset(x: 250, y: 20)

            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 58, height: 58)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("What's New")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                            Text("v\(v)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.18), in: Capsule())
                        }
                    }
                    Text("The latest additions to MirrorNotes.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: MirrorTheme.primary.opacity(0.3), radius: 28, x: 0, y: 12)
    }

    // MARK: - Tier filter chips (allFeatures mode)

    private var tierFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", icon: "square.grid.2x2", color: MirrorTheme.primary, isSelected: selectedTier == nil) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedTier = nil }
                }
                ForEach(CardTier.allCases, id: \.self) { tier in
                    FilterChip(label: tier.label, icon: tier.sectionIcon, color: tier.color, isSelected: selectedTier == tier) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedTier = selectedTier == tier ? nil : tier
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cards list

    @ViewBuilder
    private var cardsList: some View {
        if mode == .whatsNew {
            VStack(spacing: 12) {
                ForEach(service.whatsNewCards) { card in
                    FeatureCardRow(card: card, showTierBadge: true)
                }
            }
        } else if let tier = selectedTier {
            VStack(spacing: 12) {
                ForEach(service.allCards.filter { $0.tier == tier && $0.id != "feature-guide" }) { card in
                    FeatureCardRow(card: card, showTierBadge: false)
                }
            }
        } else {
            VStack(spacing: 28) {
                ForEach(CardTier.allCases, id: \.self) { tier in
                    tierSection(tier)
                }
            }
        }
    }

    @ViewBuilder
    private func tierSection(_ tier: CardTier) -> some View {
        // Exclude meta-cards that describe the feature guide itself — self-referential here
        let cards = service.allCards.filter { $0.tier == tier && $0.id != "feature-guide" }
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tier.color.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: tier.sectionIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tier.color)
                    }
                    Text(tier.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tier.color)
                    Spacer()
                    if let price = tier.pricingLabel {
                        Text(price)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tier.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(tier.color.opacity(0.10), in: Capsule())
                    } else {
                        Text("Always free")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(cards) { card in
                        FeatureCardRow(card: card, showTierBadge: false)
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

private struct FilterChip: View {
    let label: LocalizedStringKey
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? color : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? color.opacity(0.12) : Color.secondary.opacity(0.07),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? color.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }
}

struct FeatureCardRow: View {
    let card: FeatureCard
    let showTierBadge: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [card.accentColor.opacity(0.18), card.accentColor.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 50, height: 50)
                Image(systemName: card.symbolName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(card.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(card.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if showTierBadge && card.tier != .free {
                        Text(card.tier.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(card.tier.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(card.tier.color.opacity(0.12), in: Capsule())
                    }
                }
                Text(card.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color(white: 1, opacity: 0.22), Color(white: 0, opacity: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(card.accentColor.opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, 12)
                .padding(.leading, 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview("What's New") {
    WhatsNewSheet(mode: .whatsNew)
}

#Preview("Feature Guide") {
    WhatsNewSheet(mode: .allFeatures)
}
