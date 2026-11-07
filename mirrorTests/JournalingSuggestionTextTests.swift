import CoreLocation
import Foundation
import Testing
@testable import mirror

/// What a Journaling Suggestion puts into a new entry. Apple's suggestion types can't be built in a
/// test, so the line formats are tested on their inputs. Synthetic names only.
@Suite("Journaling Suggestion text")
struct JournalingSuggestionTextTests {
    @Test func mediaAndPodcastLines() {
        #expect(SuggestionLines.media(title: "Paper Lanterns", artist: "The Quiet Hours") == "🎵 Paper Lanterns · The Quiet Hours")
        #expect(SuggestionLines.media(title: "  Paper Lanterns ", artist: "") == "🎵 Paper Lanterns")
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
        #expect(SuggestionLines.people(["Maya", "Tom"], locale: Locale(identifier: "en_US")) == "👥 With Maya and Tom")
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

    /// Option A (owner 2026-11-07): pictures follow the lines one token per line, the shape 3.1.7's
    /// reader and the Mac codec read, then an empty line for the cursor.
    @Test func picturesFollowTheLinesOnePerLine() {
        let insert = SuggestionInsert(title: "Dinner by the river", lines: ["📍 Blue Door Café, Lisbon"])
        let tokens = [inlinePhotoToken(at: 0), inlinePhotoToken(at: 1)]
        #expect(insert.text(withPhotoTokens: tokens)
                == "Dinner by the river\n📍 Blue Door Café, Lisbon\n[[mirror-photo-0]]\n[[mirror-photo-1]]\n")
        #expect(insert.text(withPhotoTokens: []) == insert.text)
        #expect(SuggestionInsert().text(withPhotoTokens: tokens) == "[[mirror-photo-0]]\n[[mirror-photo-1]]\n")
        #expect(insert.leadsWithTitle)
        var prompted = insert
        prompted.prompt = "What made today feel full?"
        #expect(!prompted.leadsWithTitle, "a reflection prompt is not styled as a heading")
        #expect(!SuggestionInsert(title: "  ").leadsWithTitle)
    }

    /// Tappable lines and map (owner, 2026-11-07): plain https links the entry already stores.
    @Test func linksOpenMapsMusicAndPodcasts() throws {
        let maps = try #require(SuggestionLines.mapsURL(latitude: 38.7077, longitude: -9.1365, name: "Blue Door Café"))
        #expect(maps.host == "maps.apple.com")
        #expect(maps.absoluteString.contains("ll=38.707700,-9.136500"))
        #expect(maps.absoluteString.contains("q=Blue%20Door%20Caf"))
        #expect(SuggestionLines.mapsURL(latitude: 1, longitude: 2, name: " ")?.absoluteString.contains("q=") == false)
        let music = try #require(SuggestionLines.musicSearchURL(title: "Paper Lanterns", artist: "The Quiet Hours"))
        #expect(music.absoluteString == "https://music.apple.com/search?term=Paper%20Lanterns%20The%20Quiet%20Hours")
        #expect(SuggestionLines.podcastSearchURL(episode: "The Long Way Round", show: nil)?.host == "podcasts.apple.com")
        #expect(SuggestionLines.musicSearchURL(title: nil, artist: "  ") == nil)
        #expect(SuggestionLines.mapsSearchURL("Riverside Hall")?.absoluteString == "https://maps.apple.com/?q=Riverside%20Hall")
    }

    @Test func linkRangesCoverTheLinesAndTheMapPicture() throws {
        var insert = SuggestionInsert(title: "Dinner by the river", lines: ["📍 Blue Door Café, Lisbon", "👥 With Maya and Tom"])
        let maps = try #require(SuggestionLines.mapsURL(latitude: 38.7, longitude: -9.1, name: "Blue Door Café"))
        insert.lineLinks["📍 Blue Door Café, Lisbon"] = maps
        insert.mapLink = maps
        let text = insert.text(withPhotoTokens: [inlinePhotoToken(at: 0), inlinePhotoToken(at: 1)])
        let ranges = insert.linkRanges(in: text, mapLeads: true)
        #expect(ranges.count == 2)
        let ns = text as NSString
        #expect(ns.substring(with: NSRange(location: ranges[0].location, length: ranges[0].length)) == "📍 Blue Door Café, Lisbon")
        #expect(ranges[1].location == ns.range(of: "[[mirror-photo-0]]").location && ranges[1].length == 1,
                "the map counts as one character in inline coordinates")
        #expect(ranges.allSatisfy { $0.linkURL == maps.absoluteString })
        #expect(insert.linkRanges(in: text, mapLeads: false).count == 1, "no map picture, no picture link")
    }

    /// From the paperclip menu after writing (2026-11-07): the suggestion goes at the end after a
    /// blank line, existing styles and links stay, new links shift past the existing text.
    @Test func appendingKeepsTheEntryAndShiftsTheNewLinks() throws {
        var insert = SuggestionInsert(title: "Dinner by the river", lines: ["📍 Blue Door Café, Lisbon"])
        let maps = try #require(SuggestionLines.mapsURL(latitude: 38.7, longitude: -9.1, name: "Blue Door Café"))
        insert.lineLinks["📍 Blue Door Café, Lisbon"] = maps
        insert.mapLink = maps
        let existing = "Long day.\n[[mirror-photo-0]]\nStill thinking about it.\n"
        let oldStyles = NoteTextStyleDocument(paragraphStyles: [.title, .body, .body], indentLevels: nil, fontChoices: ["serif", "serif", "serif"])
        let oldLink = InlineStyleRange(location: 0, length: 4, bold: true, italic: false, underline: false, strikethrough: false)
        let r = insert.appended(to: existing, existingStyles: oldStyles, existingInline: [oldLink],
                                tokens: [inlinePhotoToken(at: 1)], mapLeads: true, entryFont: "serif")
        #expect(r.text == "Long day.\n[[mirror-photo-0]]\nStill thinking about it.\n\nDinner by the river\n📍 Blue Door Café, Lisbon\n[[mirror-photo-1]]\n")
        let styles = try #require(r.styles)
        #expect(styles.paragraphStyles == [.title, .body, .body, .body, .heading, .body, .body, .body])
        #expect(styles.fontChoices?.count == styles.paragraphStyles.count)
        #expect(r.inline.first == oldLink, "the entry's own formatting stays")
        // Inline coordinates count the existing photo as one character.
        let logical = (r.text as NSString).replacingOccurrences(of: "[[mirror-photo-0]]", with: "\u{FFFC}")
            .replacingOccurrences(of: "[[mirror-photo-1]]", with: "\u{FFFC}") as NSString
        let place = try #require(r.inline.first { $0.length > 1 && $0.linkURL != nil })
        #expect(logical.substring(with: NSRange(location: place.location, length: place.length)) == "📍 Blue Door Café, Lisbon")
        let map = try #require(r.inline.last)
        #expect(map.length == 1 && logical.character(at: map.location) == 0xFFFC, "the map link sits on the new picture")
    }

    /// From the paperclip menu, the suggestion goes in after the paragraph the cursor is in.
    @Test func insertingAfterTheCursorsParagraph() throws {
        var insert = SuggestionInsert(title: "Songs on the drive home", lines: ["🎵 Low Tide · Marrow & Vine"])
        let music = try #require(SuggestionLines.musicSearchURL(title: "Low Tide", artist: "Marrow & Vine"))
        insert.lineLinks["🎵 Low Tide · Marrow & Vine"] = music
        let existing = "Morning\nWalked to work.\nEvening\nCooked dinner."
        let styles = NoteTextStyleDocument(paragraphStyles: [.heading, .body, .heading, .body], indentLevels: nil, fontChoices: nil)
        // A bold range on "Cooked" (after the insertion point) has to move with its text.
        let cooked = ("Morning\nWalked to work.\nEvening\n" as NSString).length
        let bold = InlineStyleRange(location: cooked, length: 6, bold: true, italic: false, underline: false, strikethrough: false)
        let r = insert.inserted(into: existing, afterParagraph: 1, existingStyles: styles, existingInline: [bold],
                                tokens: [], mapLeads: false, entryFont: "system")
        #expect(r.text == "Morning\nWalked to work.\n\nSongs on the drive home\n🎵 Low Tide · Marrow & Vine\n\nEvening\nCooked dinner.")
        #expect(r.styles?.paragraphStyles == [.heading, .body, .body, .heading, .body, .body, .heading, .body])
        let ns = r.text as NSString
        let moved = try #require(r.inline.first { $0.bold })
        #expect(ns.substring(with: NSRange(location: moved.location, length: moved.length)) == "Cooked")
        let link = try #require(r.inline.first { $0.linkURL != nil })
        #expect(ns.substring(with: NSRange(location: link.location, length: link.length)) == "🎵 Low Tide · Marrow & Vine")
        // The last paragraph (or none given) means the end.
        #expect(insert.inserted(into: existing, afterParagraph: 9, existingStyles: nil, existingInline: [], tokens: [],
                                mapLeads: false, entryFont: "system").text.hasSuffix("Cooked dinner.\n\nSongs on the drive home\n🎵 Low Tide · Marrow & Vine\n"))
    }

    /// A style range over the insertion point is split around the block (code review, 2026-11-07).
    @Test func aRangeAcrossTheInsertionPointIsSplit() throws {
        let insert = SuggestionInsert(title: "Walk", lines: ["👟 8,430 steps"])
        let existing = "Morning\nEvening"
        let both = InlineStyleRange(location: 0, length: 15, bold: true, italic: false, underline: false, strikethrough: false)
        let r = insert.inserted(into: existing, afterParagraph: 0, existingStyles: nil, existingInline: [both],
                                tokens: [], mapLeads: false, entryFont: "system")
        #expect(r.text == "Morning\n\nWalk\n👟 8,430 steps\n\nEvening")
        let ns = r.text as NSString
        let pieces = r.inline.filter(\.bold).map { ns.substring(with: NSRange(location: $0.location, length: $0.length)) }
        #expect(pieces == ["Morning\n", "Evening"])
    }

    /// Mid-entry, the entry keeps the blank lines it ended with, and their paragraph styles.
    @Test func insertingMidEntryKeepsTheTrailingBlankLines() throws {
        let insert = SuggestionInsert(title: "Walk", lines: ["👟 8,430 steps"])
        let existing = "One\nTwo\n\n"
        let styles = NoteTextStyleDocument(paragraphStyles: [.body, .body, .body, .body], indentLevels: nil, fontChoices: nil)
        let r = insert.inserted(into: existing, afterParagraph: 0, existingStyles: styles, existingInline: [],
                                tokens: [], mapLeads: false, entryFont: "system")
        #expect(r.text == "One\n\nWalk\n👟 8,430 steps\n\nTwo\n\n")
        #expect(r.styles?.paragraphStyles.count == r.text.components(separatedBy: "\n").count)
    }

    /// The cursor on a picture puts the block after the whole row; on a blank line, after the
    /// paragraph above it (one blank line before the block, not two).
    @Test func cursorOnAPictureOrABlankLine() {
        let insert = SuggestionInsert(title: "Walk", lines: ["👟 8,430 steps"])
        let photos = "Beach day.\n[[mirror-photo-0]]\n[[mirror-photo-1]]\nSunburnt."
        let onPicture = insert.inserted(into: photos, afterParagraph: 1, existingStyles: nil, existingInline: [],
                                        tokens: [], mapLeads: false, entryFont: "system")
        #expect(onPicture.text == "Beach day.\n[[mirror-photo-0]]\n[[mirror-photo-1]]\n\nWalk\n👟 8,430 steps\n\nSunburnt.")
        let blank = "First.\n\nSecond."
        let onBlank = insert.inserted(into: blank, afterParagraph: 1, existingStyles: nil, existingInline: [],
                                      tokens: [], mapLeads: false, entryFont: "system")
        #expect(onBlank.text == "First.\n\nWalk\n👟 8,430 steps\n\nSecond.")
    }

    @Test func appendingToABlankEntryIsTheSuggestionAlone() {
        let insert = SuggestionInsert(title: "Evening run", lines: ["👟 8,430 steps"])
        let r = insert.appended(to: "\n", existingStyles: nil, existingInline: [], tokens: [], mapLeads: false, entryFont: "system")
        #expect(r.text == insert.text)
        #expect(r.styles?.paragraphStyles.first == .heading)
        #expect(r.inline.isEmpty)
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
