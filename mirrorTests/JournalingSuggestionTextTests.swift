import CoreLocation
import Foundation
import Testing
@testable import mirror

/// What a Journaling Suggestion puts into a new entry. Apple's suggestion types can't be built in a
/// test, so the line formats are tested on their inputs. Synthetic names only.
@Suite("Journaling Suggestion text")
struct JournalingSuggestionTextTests {
    @Test func mediaAndPodcastLines() {
        #expect(SuggestionLines.media(title: "Golden Hour", artist: "JVKE") == "♪ Golden Hour · JVKE")
        #expect(SuggestionLines.media(title: "  Golden Hour ", artist: "") == "♪ Golden Hour")
        #expect(SuggestionLines.media(title: nil, artist: nil) == nil)
        #expect(SuggestionLines.podcast(episode: "The Long Way Round", show: "Field Notes") == "🎧 The Long Way Round · Field Notes")
    }

    @Test func workoutLineUsesTheRegionsUnits() {
        let metric = SuggestionLines.workout(name: "Running", meters: 5200, seconds: 31 * 60, kilocalories: 412,
                                             locale: Locale(identifier: "en_IN"))
        #expect(metric.hasPrefix("🏃 Running · "))
        let us = SuggestionLines.workout(name: "Running", meters: 5200, seconds: 31 * 60, kilocalories: 412,
                                         locale: Locale(identifier: "en_US"))
        #expect(us.contains("mi"), "miles in the US: \(us)")
        #expect(us.contains("31 min"))
        let de = SuggestionLines.workout(name: "Laufen", meters: 5200, seconds: nil, kilocalories: nil,
                                         locale: Locale(identifier: "de_DE"))
        #expect(de == "🏃 Laufen · 5,2 km", "German decimal comma, km: \(de)")
        // Whatever the workout lacks is left out; no name falls back to "Workout".
        #expect(SuggestionLines.workout(name: nil, meters: nil, seconds: 20, kilocalories: nil, locale: Locale(identifier: "en_US")) == "🏃 Workout")
        let long = SuggestionLines.workout(name: "Hiking", meters: nil, seconds: 3900, kilocalories: nil, locale: Locale(identifier: "en_US"))
        #expect(long.contains("1 hr"), "an hour reads as hours: \(long)")
    }

    @Test func placePeopleStepsAndEventLines() {
        #expect(SuggestionLines.place("Blue Door Café", city: "Lisbon") == "📍 Blue Door Café, Lisbon")
        #expect(SuggestionLines.place("Lisbon", city: "lisbon") == "📍 Lisbon", "a place named after its city reads once")
        #expect(SuggestionLines.place(nil, city: " ") == nil)
        #expect(SuggestionLines.people(["Maya", "Tom"], locale: Locale(identifier: "en_US")) == "With Maya and Tom")
        #expect(SuggestionLines.people([" "]) == nil)
        #expect(SuggestionLines.steps(1) == "👟 1 step")
        #expect(SuggestionLines.steps(8430) == "👟 8,430 steps" || SuggestionLines.steps(8430) == "👟 8430 steps")
        #expect(SuggestionLines.steps(0) == nil)
        #expect(SuggestionLines.event(title: "Book club", place: "Maya's") == "📅 Book club · Maya's")
        #expect(SuggestionLines.event(title: nil, place: "Somewhere") == nil)
    }

    @Test func stateOfMindFallsBackToTheNearestMoodByValence() {
        #expect(SuggestionLines.mood(forValence: 0.9) == "Joyful")
        #expect(SuggestionLines.mood(forValence: 0.3) == "Content")
        #expect(SuggestionLines.mood(forValence: 0) == "Numb")
        #expect(SuggestionLines.mood(forValence: -0.4) == "Drained")
        #expect(SuggestionLines.mood(forValence: -0.9) == "Sad")
        for v in stride(from: -1.0, through: 1.0, by: 0.1) {
            #expect(MirrorTheme.moodOptions.contains(SuggestionLines.mood(forValence: v)))
        }
    }

    @Test func theStartingTextIsTitleOrPromptThenLines() {
        var insert = SuggestionInsert(title: "Evening run", lines: ["🏃 Running · 5.2 km", "👟 8,430 steps"])
        #expect(insert.text == "Evening run\n🏃 Running · 5.2 km\n👟 8,430 steps\n\n")
        insert.prompt = "What gave you energy today?"
        #expect(insert.text.hasPrefix("What gave you energy today?\n"), "a reflection prompt leads instead of the title")
        #expect(SuggestionInsert(title: "Morning photos").text == "Morning photos\n\n")
        #expect(SuggestionInsert().text.isEmpty)
    }

    /// A route north from a synthetic start, one point every ~111 m.
    private func route(points: Int) -> [CLLocation] {
        (0..<points).map { CLLocation(latitude: 38.7 + Double($0) * 0.001, longitude: -9.1) }
    }

    @Test func routeMapLeavesOutTheStartAndEnd() throws {
        let full = route(points: 19)   // about 2 km
        let kept = try #require(SuggestionLines.trimmedRoute(full))
        #expect(kept.first!.distance(from: full.first!) >= 300, "the first 300 m are cut")
        #expect(kept.last!.distance(from: full.last!) >= 300, "the last 300 m are cut")
        #expect(kept.count < full.count)
        #expect(SuggestionLines.trimmedRoute(route(points: 6)) == nil, "about 600 m: too short to hide the ends, no map")
        #expect(SuggestionLines.trimmedRoute([]) == nil)
    }

    @Test func anyPlaceWithALocationGetsAMap() {
        #expect(SuggestionLines.placeGetsMap(hasLocation: true), "home and work included (owner, 2026-11-06)")
        #expect(!SuggestionLines.placeGetsMap(hasLocation: false))
    }
}
