import Testing
import Foundation
import SwiftData
@testable import mirror

@Suite("segmentedWordCount")
struct SegmentedWordCountTests {
    @Test func spacedTextCountsAsBefore() {
        #expect(segmentedWordCount("I don't know, well-known 3.5 times") == 6)
        #expect(segmentedWordCount("Ich fühle mich heute ruhig") == 5)
        #expect(segmentedWordCount("오늘은 기분이 좋아요") == 3)   // Korean uses spaces
        #expect(segmentedWordCount("") == 0)
    }

    @Test func japaneseAndChineseAreSegmented() {
        #expect(segmentedWordCount("今日は天気がいいので散歩に行きました") > 3)
        #expect(segmentedWordCount("今天天气很好所以我去散步了") > 3)
    }

    @Test func detectsOnlyUnspacedScripts() {
        #expect(containsUnspacedScript("今日は"))
        #expect(containsUnspacedScript("カタカナ"))
        #expect(!containsUnspacedScript("한국어"))
        #expect(!containsUnspacedScript("plain english"))
    }

    @Test func photoTokensStillIgnored() {
        #expect(strippedWordCount("one two [[mirror-photo-0]] three") == 3)
    }

    @Test func paragraphCounterMatchesTheWholeTextCount() {
        let texts = [
            "", "\n\n", "one", "one two\nthree", "  spaced   out  \n\n tabs\tand\tmore ",
            "I don't know, well-known 3.5 times\nnext line here",
            "before [[mirror-photo-0]] after\n[[mirror-photo-1]]\nend",
            "word[[mirror-photo-0]]joined",
            "English line with well-known words\n今日は天気がいいので散歩に行きました\nmore English",
            "今天天气很好\n\n所以我去散步了",
        ]
        var counter = ParagraphWordCounter()
        for text in texts {
            #expect(counter.count(text) == strippedWordCount(text), "\(text.debugDescription)")
        }
        // Typing a little at a time, through a switch to segmentation and back.
        var typed = "Hello there\nsecond line"
        for addition in [" more", "\nnew paragraph", " 今日は", " back", "\n"] {
            typed += addition
            #expect(counter.count(typed) == strippedWordCount(typed), "\(typed.debugDescription)")
        }
        typed = "Hello there\nsecond line"
        #expect(counter.count(typed) == strippedWordCount(typed))
    }
}

@Suite("CJKWordCountRecount")
struct CJKWordCountRecountTests {
    @MainActor
    @Test func recountsOnlyCJKEntries() throws {
        let countKey = UngroundedInsightCleanup.backgroundingCountKey
        let savedCount = UserDefaults.standard.integer(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: CJKWordCountRecount.flag)
        defer {
            UserDefaults.standard.removeObject(forKey: CJKWordCountRecount.flag)
            UserDefaults.standard.set(savedCount, forKey: countKey)
        }
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        let context = container.mainContext
        let ja = Entry(text: "今日は天気がいいので散歩に行きました")
        ja.wordCount = 1   // as stored by the old whitespace count
        let en = Entry(text: "a plain english entry")
        en.wordCount = 99  // deliberately off: must not be touched
        context.insert(ja); context.insert(en)
        try context.save()

        CJKWordCountRecount.runIfNeeded(context: context)

        #expect(ja.wordCount > 1)
        #expect(en.wordCount == 99)
        #expect(UserDefaults.standard.bool(forKey: CJKWordCountRecount.flag))
    }

    @MainActor
    @Test func waitsForFirstBackgrounding() throws {
        let countKey = UngroundedInsightCleanup.backgroundingCountKey
        let savedCount = UserDefaults.standard.integer(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: CJKWordCountRecount.flag)
        UserDefaults.standard.set(0, forKey: countKey)
        defer {
            UserDefaults.standard.removeObject(forKey: CJKWordCountRecount.flag)
            UserDefaults.standard.set(savedCount, forKey: countKey)
        }
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        let ja = Entry(text: "今日は天気がいいので散歩に行きました")
        ja.wordCount = 1
        container.mainContext.insert(ja)
        try container.mainContext.save()

        CJKWordCountRecount.runIfNeeded(context: container.mainContext)

        #expect(ja.wordCount == 1)
        #expect(!UserDefaults.standard.bool(forKey: CJKWordCountRecount.flag))
    }
}
