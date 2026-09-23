import SwiftUI

/// Third-party model attribution. Required by the Gemma Terms of Use (Section 3.1(4)):
/// distributing Gemma requires accompanying it with the notice below, a copy of the
/// full terms, and a link to the Prohibited Use Policy.
struct AcknowledgmentsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                acknowledgmentCard(
                    title: "Gemma",
                    body: "mirror's on-device AI falls back to Gemma 3 1B (google/gemma-3-1b-it) when Apple's Foundation Models framework isn't available on your device. Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms.",
                    links: [
                        ("Gemma Terms of Use", URL(string: "https://ai.google.dev/gemma/terms")),
                        ("Gemma Prohibited Use Policy", URL(string: "https://ai.google.dev/gemma/prohibited_use_policy")),
                        ("Model card (GGUF build used by mirror)", URL(string: "https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF")),
                    ]
                )

                acknowledgmentCard(
                    title: "Foundation Models",
                    body: "On supported devices with Apple Intelligence enabled, mirror instead uses Apple's on-device Foundation Models framework. This ships as part of iOS and isn't a separate redistributed model.",
                    links: []
                )
            }
            .padding(20)
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle("Acknowledgments")
        .navigationBarTitleDisplayMode(.large)
    }

    private func acknowledgmentCard(title: String, body: LocalizedStringKey, links: [(String, URL?)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(MirrorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(links.indices, id: \.self) { index in
                if let url = links[index].1 {
                    Link(links[index].0, destination: url)
                        .font(.system(size: 13, weight: .medium))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: 20)
    }
}
