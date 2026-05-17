import SwiftUI
import SwiftData

struct WeeklyDigestView: View {
    let insight: Insight

    private var sections: [(title: String, body: String)] {
        parseDigest(insight.content)
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

            Divider().overlay(Color.indigo.opacity(0.18)).padding(.bottom, 16)

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
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.4), Color.purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .opacity(0.55)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: sectionIcon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundStyle(sectionColor)

            Text(content)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}
