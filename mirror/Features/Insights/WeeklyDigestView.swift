import SwiftUI
import SwiftData

struct WeeklyDigestView: View {
    let insight: Insight
    var isExpanded: Bool = true
    var onToggleExpanded: (() -> Void)? = nil

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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                Text(insight.generatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 14)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.35), Color.indigo.opacity(0.06)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.bottom, 16)

            if isExpanded {
                if sections.isEmpty {
                    Text(insight.content)
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(5)
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
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(color(for: section.title))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(color(for: section.title).opacity(0.12), in: Capsule())
                        }
                    }

                    Text(previewText)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            if let onToggleExpanded {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "Show Less" : "Read Full Digest")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.indigo.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.07), Color(.secondarySystemGroupedBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.indigo.opacity(0.20), radius: 20, x: 0, y: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.55), Color.purple.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.0
                )
        }
    }

    private func parseDigest(_ text: String) -> [(title: String, body: String)] {
        let normalized = text
            .replacingOccurrences(of: "###", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        let headers = ["THIS WEEK'S THEME", "YOUR ENERGY", "WHAT'S BUILDING", "WATCH OUT FOR", "MOOD BOOST", "NEXT WEEK"]
        var results: [(title: String, body: String)] = []

        for (i, header) in headers.enumerated() {
            guard let headerRange = normalized.range(of: header + ":", options: [.caseInsensitive]) else { continue }
            let afterHeader = String(normalized[headerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            var bodyEnd = afterHeader.endIndex
            for nextHeader in headers[(i+1)...] {
                if let nextRange = afterHeader.range(of: nextHeader + ":", options: [.caseInsensitive]) {
                    bodyEnd = nextRange.lowerBound
                    break
                }
            }

            let body = String(afterHeader[..<bodyEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n\n", with: "\n")
            results.append((title: header, body: body))
        }

        return results
    }

    private func shortTitle(for title: String) -> String {
        switch title {
        case "THIS WEEK'S THEME": return "Theme"
        case "YOUR ENERGY": return "Energy"
        case "WHAT'S BUILDING": return "Building"
        case "WATCH OUT FOR": return "Watch"
        case "MOOD BOOST": return "Boost"
        case "NEXT WEEK": return "Next"
        default: return title.capitalized
        }
    }

    private func color(for title: String) -> Color {
        switch title {
        case "THIS WEEK'S THEME": return .indigo
        case "YOUR ENERGY": return .orange
        case "WHAT'S BUILDING": return .green
        case "WATCH OUT FOR": return .red
        case "MOOD BOOST": return .purple
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

    private var sectionColor: Color {
        switch title {
        case "THIS WEEK'S THEME": return .indigo
        case "YOUR ENERGY": return .orange
        case "WHAT'S BUILDING": return .green
        case "WATCH OUT FOR": return .red
        case "MOOD BOOST": return .purple
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
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
            }
            .foregroundStyle(sectionColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(sectionColor.opacity(0.12), in: Capsule())

            Text(content)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}
