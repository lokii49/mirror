import SwiftUI

struct WritingPromptCard: View {
    let prompt: String
    let onShuffle: () -> Void
    let onUse: () -> Void

    @Environment(\.appDisplayMode) private var displayMode
    private var isSentinel: Bool { displayMode == .sentinel }

    var body: some View {
        let accent = isSentinel ? MirrorTheme.ember : Color.accentColor

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Prompt")
                    .scaledFont(10, weight: isSentinel ? .bold : .semibold, design: isSentinel ? .monospaced : .default)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(isSentinel ? 0.6 : 0.8)
                Spacer()
                Button(action: onShuffle) {
                    Image(systemName: "shuffle")
                        .scaledFont(13, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Another prompt")
                .buttonStyle(.plain)
            }

            // Prompt copy stays serif in both modes — a sentence to read,
            // not a HUD readout, same as PastNudgeCard's insight text.
            Text(prompt)
                .scaledFont(16, design: .serif)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(5)
                .id(prompt)
                .transition(.asymmetric(
                    insertion: .push(from: .trailing),
                    removal: .push(from: .leading)
                ))

            Button(action: onUse) {
                Text(isSentinel ? "USE THIS PROMPT" : "Use this prompt")
                    .scaledFont(isSentinel ? 11.5 : 12, weight: isSentinel ? .bold : .semibold, design: isSentinel ? .monospaced : .default)
                    .kerning(isSentinel ? 0.3 : 0)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        accent.opacity(0.10),
                        in: isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                    )
                    .overlay {
                        if isSentinel {
                            RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(accent.opacity(0.3), lineWidth: 1)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            isSentinel ? AnyShapeStyle(MirrorTheme.inkMid) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
            in: RoundedRectangle(cornerRadius: isSentinel ? 8 : 16, style: .continuous)
        )
        .overlay {
            if isSentinel {
                RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MirrorTheme.ember.opacity(0.25), lineWidth: 1)
            }
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        .clipShape(RoundedRectangle(cornerRadius: isSentinel ? 8 : 16, style: .continuous))
    }
}
