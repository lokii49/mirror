import SwiftUI

enum WritingPrompts {
    static let all: [String] = [
        String(localized: "What's been quietly weighing on you that you haven't said out loud yet?", comment: "Writing prompt"),
        String(localized: "Describe a small moment from today that you don't want to forget.", comment: "Writing prompt"),
        String(localized: "What are you pretending not to know?", comment: "Writing prompt"),
        String(localized: "What does your body feel like right now? Where do you feel tension?", comment: "Writing prompt"),
        String(localized: "What would you tell yourself three years ago?", comment: "Writing prompt"),
        String(localized: "What's something you're grateful for that you usually overlook?", comment: "Writing prompt"),
        String(localized: "Who did you think about today, and why?", comment: "Writing prompt"),
        String(localized: "What are you avoiding, and what's one small step toward it?", comment: "Writing prompt"),
        String(localized: "Finish this sentence: Right now, I need…", comment: "Writing prompt"),
        String(localized: "What story are you telling yourself that might not be true?", comment: "Writing prompt"),
        String(localized: "What made you smile today, even briefly?", comment: "Writing prompt"),
        String(localized: "What would you do differently if no one was watching?", comment: "Writing prompt"),
        String(localized: "What is feeling heavy right now? Just name it.", comment: "Writing prompt"),
        String(localized: "What do you want more of in your life? What's stopping you?", comment: "Writing prompt"),
        String(localized: "Describe where you are right now using only your senses.", comment: "Writing prompt"),
        String(localized: "What did you learn this week — about yourself, not the world?", comment: "Writing prompt"),
        String(localized: "What's one thing you keep putting off? Why?", comment: "Writing prompt"),
        String(localized: "Who do you feel most yourself around? Why?", comment: "Writing prompt"),
        String(localized: "What emotion have you been carrying longest?", comment: "Writing prompt"),
        String(localized: "What's going well that you haven't acknowledged yet?", comment: "Writing prompt"),
        String(localized: "If today were a chapter in your story, what would it be called?", comment: "Writing prompt"),
        String(localized: "What fear showed up today?", comment: "Writing prompt"),
        String(localized: "What do you need to forgive yourself for?", comment: "Writing prompt"),
        String(localized: "What's a belief you hold that you've never questioned?", comment: "Writing prompt"),
        String(localized: "What does success feel like to you right now — not what you think it should be?", comment: "Writing prompt"),
        String(localized: "What conversation do you keep rehearsing in your head?", comment: "Writing prompt"),
        String(localized: "What's one thing you wish someone understood about you?", comment: "Writing prompt"),
        String(localized: "Where are you being too hard on yourself?", comment: "Writing prompt"),
        String(localized: "What surprised you recently?", comment: "Writing prompt"),
        String(localized: "What do you want tomorrow to feel like?", comment: "Writing prompt"),
    ]

    /// Same prompt for the whole day, changing at midnight — previously this
    /// was `Int.random` on every view load, so a card that looked like a
    /// "daily" prompt actually reshuffled itself just from leaving and
    /// re-entering the tab. Swift's built-in `String.hashValue` is
    /// randomized per process launch, so it can't be used for a stable
    /// day-to-index mapping; FNV-1a on the day identifier is deterministic.
    static func indexForToday(_ date: Date = Date()) -> Int {
        let dayID = DateHelpers.dayIdentifier(for: date)
        let hash = fnv1a(dayID)
        return Int(hash % UInt64(all.count))
    }

    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// One-tap entry starters — same idea as a prompt, just structured instead of a single
/// question. Seeds plain text only (no paragraph-style/checklist encoding) to keep this
/// additive and low-risk; the user can format after the fact with the existing editor.
enum WritingTemplate: CaseIterable, Identifiable {
    case gratitude, threeWins, moodLog

    var id: Self { self }

    var title: String {
        switch self {
        case .gratitude: return String(localized: "Gratitude", comment: "Entry template name")
        case .threeWins: return String(localized: "3 Wins", comment: "Entry template name")
        case .moodLog:   return String(localized: "Mood Log", comment: "Entry template name")
        }
    }

    var icon: String {
        switch self {
        case .gratitude: return "heart.circle"
        case .threeWins: return "checklist"
        case .moodLog:   return "face.smiling"
        }
    }

    /// Text before the cursor's target resting position — see `cursorOffset`.
    private var seedPrefix: String {
        switch self {
        case .gratitude:
            return String(localized: "Today I'm grateful for…", comment: "Gratitude entry template seed text, before the cursor")
        case .threeWins:
            return String(localized: "1. ", comment: "3 Wins entry template seed text, before the cursor")
        case .moodLog:
            return String(localized: "Right now I feel…", comment: "Mood log entry template seed text, before the cursor")
        }
    }

    /// Text after the cursor's target resting position.
    private var seedSuffix: String {
        switch self {
        case .gratitude: return "\n\n"
        case .threeWins: return String(localized: "\n2. \n3. ", comment: "3 Wins entry template seed text, after the cursor")
        case .moodLog:   return String(localized: "\n\nBecause…", comment: "Mood log entry template seed text, after the cursor")
        }
    }

    var seedText: String { seedPrefix + seedSuffix }

    /// Where the caret should land once this template is inserted — right where the user is
    /// meant to start typing (end of "Today I'm grateful for…", inside "1. ", end of "Right now
    /// I feel…"). Real on-device bug this fixes: `NoteEditorTextView.updateUIView` only clamps
    /// the *old* selectedRange into the new text's bounds when `text` is set externally, it
    /// doesn't reposition it meaningfully — without an explicit `.moveCursor` command, the caret
    /// landed wherever that clamp happened to fall for each template's specific text shape.
    var cursorOffset: Int { seedPrefix.count }
}
