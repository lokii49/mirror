import SwiftUI
import SwiftData

struct WeeklyDigestView: View {
    let insight: Insight
    var isExpanded: Bool = true
    var onToggleExpanded: (() -> Void)? = nil

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    private var sections: [(title: String, body: String)] {
        parseDigest(insight.content)
    }

    private var previewText: String {
        if let firstSection = sections.first {
            return firstSection.body
        }
        return insight.content
            .replacingOccurrences(of: "###", with: "")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Weekly Digest", systemImage: "calendar.badge.clock")
                    .font(isSentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 11, weight: .bold))
                    .textCase(isSentinel ? .uppercase : nil)
                    .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
                    .tracking(0.8)
                Spacer()
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MirrorTheme.textTertiary)
            }
            .padding(.bottom, 14)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [MirrorTheme.violet.opacity(0.40), MirrorTheme.violet.opacity(0.06)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.bottom, 16)

            if isExpanded {
                if sections.isEmpty {
                    Text(insight.content)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .lineSpacing(6)
                        .foregroundStyle(MirrorTheme.textPrimary)
                        .textSelection(.enabled)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(sections, id: \.title) { section in
                            DigestSectionView(title: section.title, content: section.body)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(Array(sections.prefix(3)), id: \.title) { section in
                            Label(shortTitle(for: section.title), systemImage: iconName(for: section.title))
                                .font(isSentinel ? MirrorTheme.mono(9.5, weight: .bold) : .system(size: 10, weight: .bold))
                                .textCase(isSentinel ? .uppercase : nil)
                                .foregroundStyle(color(for: section.title))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    color(for: section.title).opacity(0.12),
                                    in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                                )
                                .overlay {
                                    if isSentinel {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(color(for: section.title).opacity(0.3), lineWidth: 1)
                                    }
                                }
                        }
                    }

                    Text(previewText)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .lineSpacing(6)
                        .foregroundStyle(MirrorTheme.textPrimary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            if let onToggleExpanded {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 6) {
                        Text(isSentinel
                             ? (isExpanded ? "SHOW LESS" : "FULL DIGEST")
                             : (isExpanded ? "Show Less" : "Read Full Digest"))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(isSentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 13, weight: .semibold))
                    .kerning(isSentinel ? 0.4 : 0)
                    .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        isSentinel ? AnyShapeStyle(MirrorTheme.ember.opacity(0.12)) : AnyShapeStyle(MirrorTheme.violetDim),
                        in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) : AnyShape(Capsule())
                    )
                    .overlay {
                        if isSentinel {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(MirrorTheme.ember.opacity(0.35), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .padding(22)
        .themedHeroCard(cornerRadius: 26, classicBase: .elevated)
    }

    private func parseDigest(_ text: String) -> [(title: String, body: String)] {
        let normalized = text
            .replacingOccurrences(of: "###", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        var results: [(title: String, body: String)] = []

        for (i, header) in sectionHeaderAliases.enumerated() {
            guard let headerRange = firstHeaderRange(in: normalized, aliases: header.aliases) else { continue }
            let afterHeader = String(normalized[headerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            var bodyEnd = afterHeader.endIndex
            for nextHeader in sectionHeaderAliases.dropFirst(i + 1) {
                if let nextRange = firstHeaderRange(in: afterHeader, aliases: nextHeader.aliases) {
                    bodyEnd = nextRange.lowerBound
                    break
                }
            }

            let body = String(afterHeader[..<bodyEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n\n", with: "\n")
            results.append((title: header.canonical, body: body))
        }

        return results
    }

    private func firstHeaderRange(in text: String, aliases: [String]) -> Range<String.Index>? {
        aliases
            .lazy
            .compactMap { text.range(of: "\($0):", options: [.caseInsensitive, .diacriticInsensitive]) }
            .min(by: { $0.lowerBound < $1.lowerBound })
    }

    private var sectionHeaderAliases: [(canonical: String, aliases: [String])] {
        InsightService.weeklyDigestSectionLabels.map { section in
            (canonical: section["en"] ?? "", aliases: Array(section.values))
        }
    }

    private func shortTitle(for title: String) -> LocalizedStringKey {
        switch title {
        case "THIS WEEK'S THEME": return "Theme"
        case "YOUR ENERGY": return "Energy"
        case "WHAT'S BUILDING": return "Building"
        case "WATCH OUT FOR": return "Watch"
        case "MOOD BOOST": return "Boost"
        case "NEXT WEEK": return "Next"
        default: return LocalizedStringKey(title.capitalized)
        }
    }

    private func color(for title: String) -> Color {
        switch title {
        case "THIS WEEK'S THEME": return .indigo
        case "YOUR ENERGY": return .orange
        case "WHAT'S BUILDING": return .green
        case "WATCH OUT FOR": return .red
        case "MOOD BOOST": return MirrorTheme.violetLight
        default: return .accentColor
        }
    }

    private func iconName(for title: String) -> String {
        switch title {
        case "THIS WEEK'S THEME": return "quote.bubble"
        case "YOUR ENERGY": return "bolt"
        case "WHAT'S BUILDING": return "arrow.up.forward"
        case "WATCH OUT FOR": return "eye"
        case "MOOD BOOST": return "heart"
        case "NEXT WEEK": return "arrow.right.circle"
        default: return "circle"
        }
    }
}

struct DigestSectionView: View {
    let title: String
    let content: String

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    // `title` is normalized to the canonical section id before display.
    private var displayName: LocalizedStringKey {
        switch title {
        case "THIS WEEK'S THEME": return "This Week's Theme"
        case "YOUR ENERGY": return "Your Energy"
        case "WHAT'S BUILDING": return "What's Building"
        case "WATCH OUT FOR": return "Watch Out For"
        case "MOOD BOOST": return "Mood Boost"
        case "NEXT WEEK": return "Next Week"
        default: return LocalizedStringKey(title.capitalized)
        }
    }

    private var sectionColor: Color {
        switch title {
        case "THIS WEEK'S THEME": return .indigo
        case "YOUR ENERGY": return .orange
        case "WHAT'S BUILDING": return .green
        case "WATCH OUT FOR": return .red
        case "MOOD BOOST": return MirrorTheme.violetLight
        default: return .accentColor
        }
    }

    private var sectionIcon: String {
        switch title {
        case "THIS WEEK'S THEME": return "quote.bubble"
        case "YOUR ENERGY": return "bolt"
        case "WHAT'S BUILDING": return "arrow.up.forward"
        case "WATCH OUT FOR": return "eye"
        case "MOOD BOOST": return "heart"
        case "NEXT WEEK": return "arrow.right.circle"
        default: return "circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: sectionIcon)
                    .font(.system(size: 10, weight: .bold))
                Text(displayName)
                    .font(isSentinel ? MirrorTheme.mono(10, weight: .bold) : .system(size: 10, weight: .bold))
                    .textCase(isSentinel ? .uppercase : nil)
                    .tracking(0.6)
            }
            .foregroundStyle(sectionColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                sectionColor.opacity(0.12),
                in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
            )
            .overlay {
                if isSentinel {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(sectionColor.opacity(0.3), lineWidth: 1)
                }
            }

            Text(content)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(MirrorTheme.textPrimary)
                .textSelection(.enabled)
        }
    }
}
