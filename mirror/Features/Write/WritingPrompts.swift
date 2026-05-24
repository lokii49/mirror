import SwiftUI

enum WritingPrompts {
    static let all: [String] = [
        "What's been quietly weighing on you that you haven't said out loud yet?",
        "Describe a small moment from today that you don't want to forget.",
        "What are you pretending not to know?",
        "What does your body feel like right now? Where do you feel tension?",
        "What would you tell yourself three years ago?",
        "What's something you're grateful for that you usually overlook?",
        "Who did you think about today, and why?",
        "What are you avoiding, and what's one small step toward it?",
        "Finish this sentence: Right now, I need…",
        "What story are you telling yourself that might not be true?",
        "What made you smile today, even briefly?",
        "What would you do differently if no one was watching?",
        "What is feeling heavy right now? Just name it.",
        "What do you want more of in your life? What's stopping you?",
        "Describe where you are right now using only your senses.",
        "What did you learn this week — about yourself, not the world?",
        "What's one thing you keep putting off? Why?",
        "Who do you feel most yourself around? Why?",
        "What emotion have you been carrying longest?",
        "What's going well that you haven't acknowledged yet?",
        "If today were a chapter in your story, what would it be called?",
        "What fear showed up today?",
        "What do you need to forgive yourself for?",
        "What's a belief you hold that you've never questioned?",
        "What does success feel like to you right now — not what you think it should be?",
        "What conversation do you keep rehearsing in your head?",
        "What's one thing you wish someone understood about you?",
        "Where are you being too hard on yourself?",
        "What surprised you recently?",
        "What do you want tomorrow to feel like?",
    ]
}

struct WritingPromptCard: View {
    let prompt: String
    let onShuffle: () -> Void
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Prompt")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                Button(action: onShuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(prompt)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.primary.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
                .id(prompt)
                .transition(.asymmetric(
                    insertion: .push(from: .trailing),
                    removal: .push(from: .leading)
                ))

            Button(action: onUse) {
                Text("Use this prompt")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.45))
                .frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
