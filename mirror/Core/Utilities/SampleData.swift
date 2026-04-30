#if DEBUG
import SwiftData
import Foundation

enum SampleData {
    static func seed(into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()

        func daysAgo(_ n: Int) -> Date {
            calendar.date(byAdding: .day, value: -n, to: now) ?? now
        }

        let entries: [(text: String, mood: String?, daysAgo: Int)] = [
            (
                """
                Woke up already exhausted. The alarm went off and I just lay there for twenty minutes staring at the ceiling. Not a great start. Work was fine technically but I sat through three back-to-back calls and by the end I couldn't tell you what any of them were about. Had leftover pasta for dinner, didn't feel like cooking. Going to bed early and hoping tomorrow feels different.
                """,
                "Drained",
                14
            ),
            (
                """
                Had lunch with Priya today which was genuinely the best part of my week so far. We ended up talking for almost two hours — she always makes me feel like myself again. But then I came back to the office and saw the project timeline had shifted again, now we're somehow expected to deliver by Friday instead of next week. I don't know how that's supposed to work. Feeling stretched thin.
                """,
                "Anxious",
                12
            ),
            (
                """
                Went for a run this morning before work. 5k, nothing crazy, but I felt so much better afterward. There's something about moving my body early that resets everything. The project is still a mess but I managed to carve out a focused two-hour block and actually made real progress. Then called mom in the evening — she mentioned some health stuff she's been dealing with that she hadn't told me about. Hard to hear from far away. Wish I could be there.
                """,
                "Hopeful",
                11
            ),
            (
                """
                Deadline pushed to next week. At first I felt relieved and then immediately guilty for being relieved, like I should have been able to hit the original timeline. The team is frustrated and I get it. I stayed late to help Rohan finish his part. Got home at almost 10. The apartment felt very quiet. Made tea and just sat for a while without doing anything, which I actually needed even if it didn't feel productive.
                """,
                "Overwhelmed",
                10
            ),
            (
                """
                Good Saturday. Slept until 8 which felt like a luxury. Went to the farmers market and bought stuff I actually had to think about cooking — some kind of squash I'd never used before. Spent most of the afternoon in the kitchen just experimenting. It turned out okay. Not great, but I liked the process. No phone for most of the day. This is what weekends are supposed to feel like and I forget that too often.
                """,
                "Peaceful",
                8
            ),
            (
                """
                Sunday evening anxiety has entered the building. I know Monday is coming. I know it's going to be fine. I know I've gotten through harder weeks than this one will be. None of this stops the knot in my stomach. Spent too long on my phone and now it's late and I'm not going to get enough sleep which will make everything worse. Writing this down because at least that's something.
                """,
                "Anxious",
                7
            ),
            (
                """
                The presentation went well. Better than well actually — my manager pulled me aside afterward and said it was the clearest technical breakdown she'd seen from the team all quarter. I didn't know what to do with that so I just said thank you and went back to my desk. But I'm still thinking about it. I worked hard on that. It's nice when effort shows up in the right place. Felt like myself at work for the first time in weeks.
                """,
                "Energized",
                6
            ),
            (
                """
                Didn't sleep well at all. Kept waking up at 2, 4, then gave up at 5:30. Dragged myself through the day running on coffee and sheer stubbornness. Had a 1:1 with my manager which was fine but I was barely present. Came home and cancelled plans with Vikram because I genuinely couldn't face being around people. Felt bad about it. He was understanding. I need to take better care of how I'm sleeping.
                """,
                "Drained",
                5
            ),
            (
                """
                Had a fight with my sister. Not a big explosive one — worse, the quiet kind where things are said carefully and still land wrong. It was about mom's health situation and what we're supposed to do about it from so far away. I don't think either of us was wrong exactly, we're both scared and handling it differently. But we hung up without really resolving anything and now I'm just sitting with that.
                """,
                "Sad",
                3
            ),
            (
                """
                Called my sister again this morning. We talked properly this time, not about logistics, just about how we're both feeling. It helped. She cried a little. I almost did. We made a plan to both visit mom next month. Having that concrete thing to look forward to made the whole situation feel less like fog. Still heavy, but manageable. Still worried about mom. But less alone in it.
                """,
                "Grateful",
                2
            ),
            (
                """
                It has been a lot. I don't have much to say tonight except that I'm tired in the bone-deep way that a good night's sleep won't fully fix. I've been going and going and I think I forgot to just stop and be. Not productive. Not social. Just exist. I'm going to try to do that this weekend — not plan anything, not optimize anything, just let it be quiet for a bit.
                """,
                "Numb",
                1
            ),
        ]

        for (text, mood, age) in entries {
            let entry = Entry(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                mood: mood,
                source: .typed
            )
            entry.createdAt = daysAgo(age)
            entry.wordCount = text.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
            context.insert(entry)
        }
    }

    static func clearInsights(from context: ModelContext) {
        try? context.delete(model: Insight.self)
    }

    static func clear(from context: ModelContext) {
        try? context.delete(model: Entry.self)
        try? context.delete(model: Insight.self)
    }
}
#endif
