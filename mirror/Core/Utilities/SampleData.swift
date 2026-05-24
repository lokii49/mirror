#if DEBUG
import SwiftData
import Foundation

enum SampleData {
    // MARK: - Mixed (30 entries: 13 voice + 17 typed)

    static func seed(into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now) ?? now }

        struct E {
            var text: String; var mood: String?; var days: Int; var source: EntrySource
        }

        let entries: [E] = [
            E(text: """
                Woke up already exhausted. The alarm went off and I just lay there for twenty minutes staring at the ceiling. Not a great start. Work was fine technically but I sat through three back-to-back calls and by the end I couldn't tell you what any of them were about. Had leftover pasta for dinner, didn't feel like cooking. Going to bed early and hoping tomorrow feels different.
                """, mood: "Drained", days: 30, source: .typed),
            E(text: "okay so I'm just recording this real quick because I don't have time to type. the morning was actually fine. got coffee made before the chaos started. kids were loud but whatever. I don't know I'm feeling okay today surprisingly. the meeting got cancelled which helped a lot.", mood: "Calm", days: 29, source: .voice),
            E(text: """
                Had lunch with Priya today which was genuinely the best part of my week so far. We ended up talking for almost two hours — she always makes me feel like myself again. But then I came back to the office and saw the project timeline had shifted again, now we're somehow expected to deliver by Friday instead of next week. I don't know how that's supposed to work. Feeling stretched thin.
                """, mood: "Anxious", days: 28, source: .typed),
            E(text: "um yeah so today was a lot. I had this thing in the morning where I just could not focus at all. kept opening the same tab over and over. I think I'm running on empty honestly. lunch was bad. I don't know. I'll figure it out. just wanted to say that out loud I guess.", mood: "Drained", days: 27, source: .voice),
            E(text: """
                Went for a run this morning before work. 5k, nothing crazy, but I felt so much better afterward. There's something about moving my body early that resets everything. The project is still a mess but I managed to carve out a focused two-hour block and actually made real progress. Then called mom in the evening — she mentioned some health stuff she's been dealing with that she hadn't told me about. Hard to hear from far away. Wish I could be there.
                """, mood: "Hopeful", days: 26, source: .typed),
            E(text: "just finished a really long walk. it's cold out but I needed it. been thinking about a lot of things. nothing resolved but I feel lighter somehow. I should do this more often instead of just sitting inside being in my head.", mood: "Peaceful", days: 25, source: .voice),
            E(text: """
                Deadline pushed to next week. At first I felt relieved and then immediately guilty for being relieved, like I should have been able to hit the original timeline. The team is frustrated and I get it. I stayed late to help Rohan finish his part. Got home at almost 10. The apartment felt very quiet. Made tea and just sat for a while without doing anything, which I actually needed even if it didn't feel productive.
                """, mood: "Overwhelmed", days: 24, source: .typed),
            E(text: "recording this from the car before I go inside. work was genuinely terrible today. not like dramatic just death by a thousand small things. every single task had a blocker. I'm going to eat something and not think about it for the rest of the night. that's the plan.", mood: "Frustrated", days: 23, source: .voice),
            E(text: """
                Good Saturday. Slept until 8 which felt like a luxury. Went to the farmers market and bought stuff I actually had to think about cooking — some kind of squash I'd never used before. Spent most of the afternoon in the kitchen just experimenting. It turned out okay. Not great, but I liked the process. No phone for most of the day. This is what weekends are supposed to feel like and I forget that too often.
                """, mood: "Peaceful", days: 22, source: .typed),
            E(text: "woke up feeling good for no particular reason. just one of those days. had breakfast outside, sun was out. finished two things on my list that have been sitting there forever. feeling like myself.", mood: "Energized", days: 21, source: .voice),
            E(text: """
                Sunday evening anxiety has entered the building. I know Monday is coming. I know it's going to be fine. I know I've gotten through harder weeks than this one will be. None of this stops the knot in my stomach. Spent too long on my phone and now it's late and I'm not going to get enough sleep which will make everything worse. Writing this down because at least that's something.
                """, mood: "Anxious", days: 20, source: .typed),
            E(text: "okay it's late and I should sleep but I keep thinking about the conversation from earlier. not in a bad way just replaying it. I said something I actually meant for once and it landed well. that doesn't always happen. feel kind of warm about it.", mood: "Grateful", days: 19, source: .voice),
            E(text: """
                The presentation went well. Better than well actually — my manager pulled me aside afterward and said it was the clearest technical breakdown she'd seen from the team all quarter. I didn't know what to do with that so I just said thank you and went back to my desk. But I'm still thinking about it. I worked hard on that. It's nice when effort shows up in the right place. Felt like myself at work for the first time in weeks.
                """, mood: "Energized", days: 18, source: .typed),
            E(text: "so I went to the gym finally after like two weeks of not going and it was actually fine. I was dreading it for nothing. my body remembered what to do. the music was good. I stayed longer than I planned. why do I always forget that I like doing this.", mood: "Hopeful", days: 17, source: .voice),
            E(text: """
                Didn't sleep well at all. Kept waking up at 2, 4, then gave up at 5:30. Dragged myself through the day running on coffee and sheer stubbornness. Had a 1:1 with my manager which was fine but I was barely present. Came home and cancelled plans with Vikram because I genuinely couldn't face being around people. Felt bad about it. He was understanding. I need to take better care of how I'm sleeping.
                """, mood: "Drained", days: 16, source: .typed),
            E(text: "walking home and just wanted to capture this. ran into an old friend completely by accident. we stood outside talking for half an hour. didn't plan it. those unplanned things are always the best things. made the whole day feel different.", mood: "Joyful", days: 15, source: .voice),
            E(text: """
                Had a fight with my sister. Not a big explosive one — worse, the quiet kind where things are said carefully and still land wrong. It was about mom's health situation and what we're supposed to do about it from so far away. I don't think either of us was wrong exactly, we're both scared and handling it differently. But we hung up without really resolving anything and now I'm just sitting with that.
                """, mood: "Sad", days: 14, source: .typed),
            E(text: "I've been putting off this one task for three days and today I finally just did it. took forty minutes. I built it up in my head into this huge thing and it was forty minutes. I need to remember this the next time I'm avoiding something.", mood: "Calm", days: 13, source: .voice),
            E(text: """
                Called my sister again this morning. We talked properly this time, not about logistics, just about how we're both feeling. It helped. She cried a little. I almost did. We made a plan to both visit mom next month. Having that concrete thing to look forward to made the whole situation feel less like fog. Still heavy, but manageable. Still worried about mom. But less alone in it.
                """, mood: "Grateful", days: 12, source: .typed),
            E(text: "had a really good cooking session tonight. nothing fancy just like getting absorbed in a recipe and forgetting about everything else for a while. ate standing at the counter. weirdly satisfying.", mood: "Peaceful", days: 11, source: .voice),
            E(text: """
                It has been a lot. I don't have much to say tonight except that I'm tired in the bone-deep way that a good night's sleep won't fully fix. I've been going and going and I think I forgot to just stop and be. Not productive. Not social. Just exist. I'm going to try to do that this weekend — not plan anything, not optimize anything, just let it be quiet for a bit.
                """, mood: "Numb", days: 10, source: .typed),
            E(text: "this weekend was exactly what I needed. didn't do much of anything. read a bit. napped. sat outside. I can already feel the difference. I forget that rest is an actual thing I'm allowed to do.", mood: "Calm", days: 9, source: .voice),
            E(text: """
                Started the week with a clear head which hasn't happened in a while. Made a real list, actually followed it, knocked out four things before noon. The afternoon got messier but the morning felt like a win. Small wins matter. I need to let them matter instead of immediately moving on to the next thing.
                """, mood: "Energized", days: 8, source: .typed),
            E(text: "okay just a quick one. feeling kind of anxious today about something I can't even fully name. just this low level hum of unease. nothing specific is wrong. which is somehow worse because I can't fix anything. going to try to breathe through it.", mood: "Anxious", days: 7, source: .voice),
            E(text: """
                Took the afternoon off. First time in months I've done something like that — just stepped away mid-week because I needed to. Went to a museum by myself. Wandered for two hours. Didn't check my phone once while I was inside. Came out and the world was still there. Nothing had collapsed. I think I'd forgotten that's possible.
                """, mood: "Peaceful", days: 6, source: .typed),
            E(text: "something clicked today at work. a problem I've been circling for a week just suddenly made sense. I don't even know what changed. I explained it to a colleague and they got it right away. I love when that happens. rare but when it does it's like yes this is why I do this.", mood: "Energized", days: 5, source: .voice),
            E(text: """
                Checked in with myself today — really checked in, not just the surface version. I've been lonely. Not dramatically, not constantly, but there's a quiet kind of loneliness that comes from going through too many weeks without real conversation. I'm going to reach out to people more. Not as a project. Just actually do it.
                """, mood: "Sad", days: 4, source: .typed),
            E(text: "dinner with Rohan and it was so good. we talked about real things not just work stuff. laughed a lot. I left feeling full in a way that had nothing to do with the food. I need more evenings like that.", mood: "Joyful", days: 3, source: .voice),
            E(text: """
                End of the month. I've been reflecting on how it went — not with a spreadsheet, just sitting with it. There were hard patches. There were good patches. The week where I barely slept was real but so was the afternoon in the museum and the phone call with my sister. I want to be better at holding both of those things at the same time instead of letting one erase the other.
                """, mood: "Grateful", days: 2, source: .typed),
            E(text: "winding down. tomorrow is going to be full but tonight is quiet and I'm going to let it be quiet. no planning, no list-making. just this.", mood: "Calm", days: 1, source: .voice),
        ]

        for e in entries {
            let trimmed = e.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = Entry(text: trimmed, mood: e.mood, source: e.source)
            entry.createdAt = daysAgo(e.days)
            entry.weekIdentifier = DateHelpers.weekIdentifier(for: entry.createdAt)
            if e.source == .voice {
                let wc = trimmed.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
                let (audio, dur) = syntheticVoiceAudio(words: wc)
                entry.voiceNoteData = audio
                entry.voiceNoteDuration = dur
                entry.voiceNoteTranscript = trimmed
            }
            context.insert(entry)
        }
    }

    // MARK: - Year Long Mixed (365 entries: typed + voice)

    static func seedYearLongMixed(into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()

        struct Theme {
            let mood: String
            let typed: String
            let voice: String
        }

        let themes: [Theme] = [
            Theme(
                mood: "Calm",
                typed: "A quieter day than expected. I kept the work simple, answered the things that needed answering, and let a few non-urgent items stay non-urgent. The best part was noticing that nothing fell apart when I moved at a normal pace.",
                voice: "quiet check-in today. kept things simple and did not chase every loose thread. that helped more than I expected."
            ),
            Theme(
                mood: "Energized",
                typed: "Had real momentum today. Started with the task I had been avoiding and that changed the tone of the whole morning. By the afternoon I was still busy, but it felt directed instead of scattered.",
                voice: "good momentum today. I started with the hard thing first and the rest of the day felt cleaner because of it."
            ),
            Theme(
                mood: "Anxious",
                typed: "There was a low hum of worry most of the day. Nothing dramatic happened, but I kept trying to solve three future problems at once. Writing this down because naming the feeling usually makes it less slippery.",
                voice: "anxious day. nothing specific exploded, but my brain kept rehearsing problems that are not actually here yet."
            ),
            Theme(
                mood: "Grateful",
                typed: "Small good things carried the day: a message from a friend, a meal that turned out better than expected, and a moment where I caught myself smiling before I had a reason to explain it.",
                voice: "grateful for small things today. a kind message, decent food, and a little bit of space in the evening."
            ),
            Theme(
                mood: "Drained",
                typed: "I got through the essentials, but everything took more effort than it should have. The day was not a disaster, just heavy. I need to treat sleep like a real commitment tonight.",
                voice: "tired today. not a crisis, just heavy. I did the necessary things and now I need to stop."
            ),
            Theme(
                mood: "Peaceful",
                typed: "Made room for a walk and it changed the texture of the day. I came back with the same responsibilities, but they felt less tangled. It is annoying how often the obvious thing works.",
                voice: "walked for a while and felt my shoulders drop. same problems afterward, but they felt easier to hold."
            ),
            Theme(
                mood: "Frustrated",
                typed: "A lot of little blockers stacked up today. I handled most of them, but not with as much patience as I would have liked. I am trying to separate being right from being useful.",
                voice: "frustrating day. too many small blockers, and I was sharper than I wanted to be. noting it and moving on."
            ),
            Theme(
                mood: "Hopeful",
                typed: "Something about today felt like a small turn in the right direction. No dramatic breakthrough, just a clearer next step and enough energy to take it. That counts.",
                voice: "feeling hopeful. not because everything is fixed, but because the next step is clearer than it was yesterday."
            ),
            Theme(
                mood: "Joyful",
                typed: "There was an easy laugh today that stayed with me longer than I expected. I forget how much lighter everything feels when I am not only measuring the day by what got finished.",
                voice: "good day. laughed properly, got outside, and felt like I was actually in my life instead of managing it."
            ),
            Theme(
                mood: "Sad",
                typed: "A tender day. I missed people, and a few ordinary things reminded me of distance more than I wanted them to. I let myself feel it instead of turning it into a productivity problem.",
                voice: "sad today. missing people and feeling the distance. nothing to solve tonight, just letting it be true."
            ),
            Theme(
                mood: "Overwhelmed",
                typed: "Too many inputs today. Messages, decisions, errands, context switching. I eventually made a tiny list and followed only that. It did not fix everything, but it gave the day edges.",
                voice: "overwhelmed most of the day. made a tiny list and followed it. that was enough structure to get through."
            ),
            Theme(
                mood: "Numb",
                typed: "Everything felt muted today. I was present enough to do what needed doing, but not much more. I am not going to force a big interpretation out of it. Some days are low volume.",
                voice: "kind of numb today. not terrible, just muted. I did what needed doing and I am leaving it there."
            ),
        ]

        let anchors = [
            "work", "family", "health", "friendship", "money", "home", "creative energy",
            "rest", "exercise", "focus", "travel plans", "therapy", "cooking", "reading"
        ]
        let closingNotes = [
            "I want to remember that this was a real day, not just a bridge to the next one.",
            "The pattern is easier to see when I write it down instead of carrying it around.",
            "Tomorrow does not need a perfect plan; it needs one honest next step.",
            "I am trying to notice the signal without turning every feeling into a verdict.",
            "There is more room here than I thought when the day started.",
            "This is enough of a record for tonight."
        ]

        for offset in stride(from: 364, through: 0, by: -1) {
            guard let baseDate = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let dayIndex = 364 - offset
            let theme = themes[dayIndex % themes.count]
            let anchor = anchors[(dayIndex / 3 + offset) % anchors.count]
            let closing = closingNotes[(dayIndex / 5 + offset) % closingNotes.count]
            let isVoice = dayIndex % 4 == 1 || dayIndex % 11 == 0
            let hour = 7 + (dayIndex * 5) % 15
            let minute = (dayIndex * 13) % 60
            let createdAt = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: baseDate
            ) ?? baseDate

            if isVoice {
                let transcript = "\(theme.voice) today mostly circled around \(anchor). \(closing)"
                let entry = Entry(text: "", mood: theme.mood, source: .voice)
                entry.createdAt = createdAt
                entry.weekIdentifier = DateHelpers.weekIdentifier(for: createdAt)
                let wc = transcript.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
                let (audio, dur) = syntheticVoiceAudio(words: wc)
                entry.voiceNoteData = audio
                entry.voiceNoteDuration = dur
                entry.voiceNoteTranscript = transcript
                context.insert(entry)
            } else {
                let text = """
                    \(theme.typed)

                    The thread running through it was \(anchor). \(closing)
                    """
                let entry = Entry(text: text.trimmingCharacters(in: .whitespacesAndNewlines), mood: theme.mood, source: .typed)
                entry.createdAt = createdAt
                entry.weekIdentifier = DateHelpers.weekIdentifier(for: createdAt)
                context.insert(entry)
            }
        }
    }

    // MARK: - Voice Only (22 entries)

    static func seedVoiceOnly(into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now) ?? now }

        let entries: [(text: String, mood: String?, days: Int)] = [
            ("okay recording this on my walk. today was overwhelming. too many things at once and I couldn't figure out which one to start with. ended up just sitting there for like twenty minutes. not great. but I did eventually pick one and finish it so there's that.", "Overwhelmed", 28),
            ("quick one before bed. I had a moment today that I want to remember. someone said something really kind to me out of nowhere and I didn't know what to do with it. I just kind of nodded. I want to get better at receiving things like that.", "Grateful", 26),
            ("in the car waiting. the morning did not go to plan at all. spilled coffee, late to the call, forgot something important. I'm not going to catastrophize it. it's just a morning. tomorrow is a different morning.", "Frustrated", 25),
            ("this is a voice note from my couch. I haven't moved in two hours. watching something mindless and I'm not even sorry. I think I needed this. full stop.", "Calm", 24),
            ("just got back from a run and I want to capture how I feel right now before it fades. like actually good. not just fine. my head is clearer and my shoulders are down and I feel like a person. why don't I run every day. I know why. but still.", "Energized", 22),
            ("rough night. kept waking up thinking about a conversation that happened ages ago. nothing I can do about it now. just my brain doing its thing. I'm tired and I know it'll pass.", "Anxious", 21),
            ("okay so something really good happened today. I'll write it properly later but I wanted to just say it out loud. I got the feedback I've been waiting on and it was positive. really positive. I'm sitting with it.", "Energized", 20),
            ("recording this from the kitchen. I made a full meal from scratch and it came out well. there's something about doing a physical thing well that resets me in a way nothing else does. feeling settled.", "Peaceful", 19),
            ("I don't have much today. kind of hollow. not sad exactly just neutral. like someone turned the volume down on everything. it'll be fine. I just noticed it.", "Numb", 18),
            ("talked to an old friend today. we hadn't spoken in months. the conversation just picked up. I forget how much energy I get from people who've known me for a long time. I should reach out to them more instead of waiting for them to reach out.", "Joyful", 17),
            ("work meeting went sideways. disagreement that could have been an email. I held my position but I don't know if I did it well. I said what I meant but I was sharper than I needed to be. I'm going to sit with that.", "Frustrated", 16),
            ("quick note. bought myself something small today that I've been putting off for months. just a little thing. felt surprisingly good. self-care is sometimes just getting the thing.", "Calm", 15),
            ("I've been thinking a lot about where I want to be in a year. not in a stressful way just genuinely curious. I don't have the answer. but I think asking the question is the right move.", "Hopeful", 14),
            ("bad day. not one big thing, just everything a little off. food was wrong, vibe was wrong, couldn't land anything. some days are like this. I'm going to sleep and try again tomorrow.", "Drained", 13),
            ("just got home from a thing I didn't want to go to. and actually I'm glad I went. the first hour was awkward and then it wasn't. I talked to someone I'd never met who said something that I'm still thinking about. can't even fully explain what it was but it landed.", "Hopeful", 11),
            ("I cried today. not for any dramatic reason just I was watching something and it got me. I think I needed to. I've been very held together lately and sometimes held together is just another word for compressed.", "Sad", 10),
            ("morning voice note. slept well for once. woke up before the alarm. this is rare and I'm marking it. everything feels a bit more possible when I've actually slept.", "Calm", 9),
            ("end of a long week. I don't have coherent thoughts. just tired and a little proud. we shipped a thing. it worked. people were pleased. I'm going to let myself feel that instead of immediately moving to what's next.", "Grateful", 7),
            ("recording from outside. it's raining lightly. I came out here on purpose because I needed air and noise that wasn't digital. feeling better already. sometimes the fix is embarrassingly simple.", "Peaceful", 6),
            ("I got frustrated with someone today and I didn't hide it well. I don't think I was wrong to be frustrated but I don't love how it came out. thinking about how to handle that better. not punishing myself just noting it.", "Frustrated", 4),
            ("good day. genuinely. I did the things I said I would. I was present for most of it. I had a good laugh. I ate something proper. that's a win. logging it.", "Joyful", 2),
            ("last note of the month. it's been a weird one. a lot happened that I didn't expect and some of it was hard and some of it was better than expected. I feel like I learned some things. I don't know what exactly. but something shifted.", "Hopeful", 1),
        ]

        for (text, mood, days) in entries {
            let entry = Entry(text: "", mood: mood, source: .voice)
            entry.createdAt = daysAgo(days)
            entry.weekIdentifier = DateHelpers.weekIdentifier(for: entry.createdAt)
            let wc = text.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
            let (audio, dur) = syntheticVoiceAudio(words: wc)
            entry.voiceNoteData = audio
            entry.voiceNoteDuration = dur
            entry.voiceNoteTranscript = text
            context.insert(entry)
        }
    }

    // MARK: - Helpers

    static func clearInsights(from context: ModelContext) {
        try? context.delete(model: Insight.self)
    }

    static func clear(from context: ModelContext) {
        try? context.delete(model: Entry.self)
        try? context.delete(model: Insight.self)
    }

    // Generates a minimal valid WAV (PCM 16-bit mono 22050 Hz) playable by AVAudioPlayer.
    // Duration is estimated from word count at ~110 wpm speaking rate.
    private static func syntheticVoiceAudio(words: Int) -> (data: Data, duration: Double) {
        let duration = max(8.0, min(120.0, Double(words) / 110.0 * 60.0))
        let sampleRate = 22050
        let numSamples = Int(Double(sampleRate) * duration)

        var wav = Data()
        wav.reserveCapacity(44 + numSamples * 2)

        func u32le(_ v: UInt32) {
            wav.append(UInt8(v & 0xFF)); wav.append(UInt8((v >> 8) & 0xFF))
            wav.append(UInt8((v >> 16) & 0xFF)); wav.append(UInt8((v >> 24) & 0xFF))
        }
        func u16le(_ v: UInt16) {
            wav.append(UInt8(v & 0xFF)); wav.append(UInt8((v >> 8) & 0xFF))
        }

        // RIFF/WAVE header
        wav.append(contentsOf: [0x52,0x49,0x46,0x46]) // "RIFF"
        u32le(UInt32(36 + numSamples * 2))
        wav.append(contentsOf: [0x57,0x41,0x56,0x45]) // "WAVE"
        wav.append(contentsOf: [0x66,0x6D,0x74,0x20]) // "fmt "
        u32le(16); u16le(1); u16le(1)                 // PCM, mono
        u32le(UInt32(sampleRate))
        u32le(UInt32(sampleRate * 2))
        u16le(2); u16le(16)                            // block align, bits
        wav.append(contentsOf: [0x64,0x61,0x74,0x61]) // "data"
        u32le(UInt32(numSamples * 2))

        // Speech-like audio: 150–250 Hz fundamental with harmonics and slow amplitude variation
        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let f0 = 190.0 + 30.0 * sin(2 * .pi * 0.25 * t)
            let wave = 0.50 * sin(2 * .pi * f0 * t)
                     + 0.25 * sin(2 * .pi * f0 * 2 * t)
                     + 0.15 * sin(2 * .pi * f0 * 3 * t)
                     + 0.10 * sin(2 * .pi * f0 * 4 * t)
            let amp = 0.35 + 0.25 * sin(2 * .pi * 1.7 * t) + 0.15 * sin(2 * .pi * 0.6 * t)
            let sample = Int16(clamping: Int(wave * amp * 9000))
            u16le(UInt16(bitPattern: sample))
        }

        return (wav, duration)
    }
}
#endif
