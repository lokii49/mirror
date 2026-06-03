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
                        whatsNewHeader
                    }
                    if mode == .allFeatures {
                        tierFilter
                    }
                    cardsList
                }
                .padding(.horizontal, 16)
                .padding(.top, mode == .allFeatures ? 8 : 0)
                .padding(.bottom, 32)
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle(mode == .whatsNew ? "What's New" : "Feature Guide")
            .navigationBarTitleDisplayMode(mode == .whatsNew ? .large : .large)
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

    // MARK: - What's New header

    private var whatsNewHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(MirrorTheme.accentGradient)
                    .frame(width: 56, height: 56)
                    .shadow(color: MirrorTheme.primary.opacity(0.35), radius: 16, x: 0, y: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("New in this update")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Here's what arrived in the latest version of MirrorNotes.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Tier filter chips (allFeatures mode)

    private var tierFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", color: MirrorTheme.primary, isSelected: selectedTier == nil) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedTier = nil }
                }
                ForEach(CardTier.allCases, id: \.label) { tier in
                    FilterChip(label: tier.label, color: tier.color, isSelected: selectedTier == tier) {
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
                ForEach(service.allCards.filter { $0.tier == tier }) { card in
                    FeatureCardRow(card: card, showTierBadge: false)
                }
            }
        } else {
            VStack(spacing: 24) {
                ForEach(CardTier.allCases, id: \.label) { tier in
                    tierSection(tier)
                }
            }
        }
    }

    @ViewBuilder
    private func tierSection(_ tier: CardTier) -> some View {
        let cards = service.allCards.filter { $0.tier == tier }
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: tier.sectionIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tier.color)
                    Text(tier.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                    if let price = tier.pricingLabel {
                        Text(price)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 2)

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
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? color : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? color.opacity(0.12) : Color.secondary.opacity(0.08),
                    in: Capsule()
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(card.accentColor.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: card.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(card.accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(card.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if showTierBadge && card.tier != .free {
                        Text(card.tier.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(card.tier.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(card.tier.color.opacity(0.12), in: Capsule())
                    }
                }
                Text(card.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .futureSurface(cornerRadius: 18)
    }
}

#Preview("What's New") {
    WhatsNewSheet(mode: .whatsNew)
}

#Preview("Feature Guide") {
    WhatsNewSheet(mode: .allFeatures)
}
