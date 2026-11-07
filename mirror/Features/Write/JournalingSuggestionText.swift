import Foundation
import CoreLocation
#if os(iOS) && canImport(JournalingSuggestions)
import JournalingSuggestions
import HealthKit
import AVFoundation
import MapKit
import UIKit
#endif

/// What a picked Journaling Suggestion puts into a new entry (owner, 2026-11-06; mockup approved):
/// its title, one short line per moment (a song, a workout, a place, the people, the steps…), up to
/// four pictures, and, for a State of Mind, the nearest of the app's twelve moods. The lines are
/// ordinary text, so they sync to every version, search finds them and reflections can quote them.
/// Only what the person picked in Apple's sheet is read.
struct SuggestionInsert: Equatable {
    var title: String = ""
    var lines: [String] = []
    /// Local copies the editor may consume (it deletes each file after attaching it).
    var pictures: [URL] = []
    /// A reflection prompt from Apple, used as the starting text.
    var prompt: String?
    /// Lines that open something when tapped (owner, 2026-11-07): a place in Maps, a song or
    /// podcast searched in Music or Podcasts. Stored as ordinary entry links (since 3.1.0).
    var lineLinks: [String: URL] = [:]
    /// Where tapping the leading map picture goes (Maps at the place, or the route's middle).
    var mapLink: URL?
    /// One of `MirrorTheme.moodOptions`, from a State of Mind.
    var mood: String?

    static let maxPictures = 4

    /// The text that starts the entry: the prompt or the title, then the lines, then a blank line
    /// for the cursor.
    var text: String {
        var parts: [String] = []
        let head = (prompt ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        if !head.isEmpty { parts.append(head) }
        if !lines.isEmpty { parts.append(lines.joined(separator: "\n")) }
        guard !parts.isEmpty else { return "" }
        return parts.joined(separator: "\n") + "\n\n"
    }

    /// The text with the pictures' tokens after it, one per line (the shape every version reads),
    /// and an empty last line for the cursor. Without pictures it's `text`.
    func text(withPhotoTokens tokens: [String]) -> String {
        guard !tokens.isEmpty else { return text }
        var head = text
        while head.hasSuffix("\n") { head.removeLast() }
        return ((head.isEmpty ? [] : [head]) + tokens).joined(separator: "\n") + "\n"
    }

    /// Inline link ranges for `text(withPhotoTokens:)`: each linked line where it sits, and the
    /// map's picture when `mapLeads` (the first token is the map). Inline coordinates count a
    /// photo as one character; nothing comes before the first token but text, so up to it they
    /// equal the text's own UTF-16 offsets.
    func linkRanges(in text: String, mapLeads: Bool) -> [InlineStyleRange] {
        let ns = text as NSString
        var ranges: [InlineStyleRange] = []
        func link(_ location: Int, _ length: Int, _ url: URL) {
            ranges.append(InlineStyleRange(location: location, length: length, bold: false, italic: false,
                                           underline: false, strikethrough: false, highlightIndex: nil,
                                           linkURL: url.absoluteString))
        }
        for line in lines {
            guard let url = lineLinks[line] else { continue }
            let found = ns.range(of: line)
            if found.location != NSNotFound { link(found.location, found.length, url) }
        }
        if mapLeads, let mapLink {
            let token = ns.range(of: "[[mirror-photo-")
            if token.location != NSNotFound { link(token.location, 1, mapLink) }
        }
        return ranges.sorted { $0.location < $1.location }
    }

    /// The entry after this suggestion is added at the end (Write, 3.1.8). See `inserted`.
    func appended(to existingText: String, existingStyles: NoteTextStyleDocument?, existingInline: [InlineStyleRange],
                  tokens: [String], mapLeads: Bool, entryFont: String) -> (text: String, styles: NoteTextStyleDocument?, inline: [InlineStyleRange]) {
        inserted(into: existingText, afterParagraph: nil, existingStyles: existingStyles, existingInline: existingInline,
                 tokens: tokens, mapLeads: mapLeads, entryFont: entryFont)
    }

    /// The entry after this suggestion goes in (Write, 3.1.8). On a blank entry the suggestion is the
    /// whole text. Otherwise it goes after paragraph `afterParagraph` (the one the cursor is in; nil
    /// or the last one = the end), with a blank line before it and, when text follows, after it. It
    /// never splits a paragraph. The entry's paragraph styles, fonts, indents and links are kept:
    /// styles are spliced in at that point, ranges after it move by the inserted length, and the
    /// new links land on the new lines (inline coordinates count a photo as one character).
    func inserted(into existingText: String, afterParagraph: Int?, existingStyles: NoteTextStyleDocument?,
                  existingInline: [InlineStyleRange], tokens: [String], mapLeads: Bool,
                  entryFont: String) -> (text: String, styles: NoteTextStyleDocument?, inline: [InlineStyleRange]) {
        let block = text(withPhotoTokens: tokens)
        var blockLines = block.components(separatedBy: "\n")
        while blockLines.last == "" { blockLines.removeLast() }

        var base = existingText
        while let last = base.last, last.isNewline { base.removeLast() }
        let hasBase = !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasBase else {
            // A blank entry: the suggestion is the text, its title a Heading.
            let count = block.components(separatedBy: "\n").count
            let styles = leadsWithTitle
                ? NoteTextStyleDocument(paragraphStyles: [.heading] + Array(repeating: .body, count: max(0, count - 1)),
                                        indentLevels: nil, fontChoices: Array(repeating: entryFont, count: count))
                : nil
            return (block, styles, linkRanges(in: block, mapLeads: mapLeads))
        }
        let lines = base.components(separatedBy: "\n")
        var at = max(0, min(afterParagraph ?? (lines.count - 1), lines.count - 1))   // last paragraph kept before
        // The cursor on a picture: go in after the whole row of pictures, so the row isn't split.
        func isPhotoLine(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("[[mirror-photo") && t.hasSuffix("]]") && allPhotoTokens(in: t).count == 1
        }
        if isPhotoLine(lines[at]) {
            while at + 1 < lines.count, isPhotoLine(lines[at + 1]) { at += 1 }
        }
        // The cursor on a blank line between paragraphs: go in after the paragraph above it, so
        // the block gets one blank line before it, not two.
        while at > 0, lines[at].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
        let before = Array(lines[0...at])
        let after = at + 1 < lines.count ? Array(lines[(at + 1)...]) : []
        let gapAfter = !after.isEmpty && after.first?.trimmingCharacters(in: .whitespaces).isEmpty == false
        // Inserted mid-entry, the entry keeps the blank lines it ended with.
        let trailingNewlines = after.isEmpty ? "" : String(existingText.dropFirst(base.count))

        // prefix (through the paragraph before) + inserted + suffix (the rest).
        let prefix = before.joined(separator: "\n") + "\n"
        let inserted = "\n" + blockLines.map { $0 + "\n" }.joined() + (gapAfter ? "\n" : "")
        let suffix = after.joined(separator: "\n") + trailingNewlines
        let combined = prefix + inserted + suffix

        // Paragraph styles, spliced: [before][blank][block…][blank?][after].
        var styles: NoteTextStyleDocument?
        if leadsWithTitle || existingStyles != nil {
            // Mid-entry, the entry's trailing blank paragraphs stay after the rest of it.
            let oldCount = after.isEmpty ? lines.count : existingText.components(separatedBy: "\n").count
            func padded<T>(_ values: [T]?, _ filler: T) -> [T] {
                let v = Array((values ?? []).prefix(oldCount)); return v + Array(repeating: filler, count: oldCount - v.count)
            }
            let oldStyles = padded(existingStyles?.paragraphStyles, NoteParagraphTextStyle.body)
            let oldFonts = padded(existingStyles?.fontChoices, entryFont)
            let oldIndents: [Int]? = existingStyles?.indentLevels.map { padded($0, 0) }
            let keep = at + 1
            let newCount = 1 + blockLines.count + (gapAfter ? 1 : 0)
            var newStyles = Array(repeating: NoteParagraphTextStyle.body, count: newCount)
            if leadsWithTitle, !blockLines.isEmpty { newStyles[1] = .heading }
            // The text ends with a line break: one more (empty) paragraph after the block when it's last.
            let tail = after.isEmpty ? 1 : 0
            let paragraph = Array(oldStyles.prefix(keep)) + newStyles + Array(oldStyles.dropFirst(keep)) + Array(repeating: .body, count: tail)
            let fonts = Array(oldFonts.prefix(keep)) + Array(repeating: entryFont, count: newCount) + Array(oldFonts.dropFirst(keep)) + Array(repeating: entryFont, count: tail)
            let indents = oldIndents.map { Array($0.prefix(keep)) + Array(repeating: 0, count: newCount) + Array($0.dropFirst(keep)) + Array(repeating: 0, count: tail) }
            styles = NoteTextStyleDocument(paragraphStyles: paragraph, indentLevels: indents, fontChoices: fonts)
        }

        // Inline coordinates: a photo token is one character.
        func logicalLength(_ text: String) -> Int {
            (text as NSString).length - allPhotoTokens(in: text).reduce(0) { $0 + (NSRange($1.range, in: text).length - 1) }
        }
        let insertAt = logicalLength(prefix)
        let insertedLength = logicalLength(inserted)
        // Ranges after the insertion move down; one that spans it is split around the new block,
        // so styling over "Morning\nEvening" stays on both lines and never covers the block.
        let kept = existingInline.flatMap { range -> [InlineStyleRange] in
            var r = range
            if r.location >= insertAt {
                r.location += insertedLength
                return [r]
            }
            guard r.location + r.length > insertAt else { return [r] }
            var head = r, tail = r
            head.length = insertAt - r.location
            tail.location = insertAt + insertedLength
            tail.length = r.location + r.length - insertAt
            return [head, tail]
        }
        let blockStart = insertAt + 1
        let added = linkRanges(in: block, mapLeads: mapLeads).map { range -> InlineStyleRange in
            var r = range; r.location += blockStart; return r
        }
        return (combined, styles, (kept + added).sorted { $0.location < $1.location })
    }

    /// The first line is the suggestion's title (shown as a Heading), not a reflection prompt.
    var leadsWithTitle: Bool {
        prompt == nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The line formats, kept free of Apple's types so they can be tested. Words go through the string
/// catalog; numbers and units follow the reader's region.
enum SuggestionLines {
    static func media(title: String?, artist: String?) -> String? {
        joined("🎵", title, artist)
    }

    static func podcast(episode: String?, show: String?) -> String? {
        joined("🎧", episode, show)
    }

    /// "🏃 Running · 5.2 km · 31 min · 412 kcal"; whatever the workout lacks is left out.
    static func workout(name: String?, meters: Double?, seconds: TimeInterval?, kilocalories: Double?,
                        locale: Locale = .current) -> String {
        var parts = [cleaned(name) ?? String(localized: "Workout", comment: "Journaling Suggestion: a workout without a name")]
        if let meters, meters > 0 {
            let f = MeasurementFormatter()
            f.locale = locale
            f.unitOptions = .providedUnit
            f.numberFormatter.maximumFractionDigits = 1
            let km = Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            let usesMiles = locale.measurementSystem == .us || locale.measurementSystem == .uk
            parts.append(f.string(from: usesMiles ? km.converted(to: .miles) : km))
        }
        if let seconds, seconds >= 60 {
            let f = DateComponentsFormatter()
            f.calendar?.locale = locale
            f.unitsStyle = .short
            f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
            if let s = f.string(from: seconds) { parts.append(s) }
        }
        if let kilocalories, kilocalories >= 1 {
            let f = MeasurementFormatter()
            f.locale = locale
            f.unitOptions = .providedUnit
            f.numberFormatter.maximumFractionDigits = 0
            parts.append(f.string(from: Measurement(value: kilocalories, unit: UnitEnergy.kilocalories)))
        }
        return "🏃 " + parts.joined(separator: " · ")
    }

    static func place(_ place: String?, city: String?) -> String? {
        let bits = [cleaned(place), cleaned(city)].compactMap { $0 }
        guard !bits.isEmpty else { return nil }
        // A place named after its city ("Lisbon, Lisbon") reads once.
        let unique = bits.count == 2 && bits[0].caseInsensitiveCompare(bits[1]) == .orderedSame ? [bits[0]] : bits
        return "📍 " + unique.joined(separator: ", ")
    }

    /// "With Maya and Tom", joined the reader's way.
    static func people(_ names: [String], locale: Locale = .current) -> String? {
        let list = names.compactMap(cleaned)
        guard !list.isEmpty else { return nil }
        let f = ListFormatter()
        f.locale = locale
        let joined = f.string(from: list) ?? list.joined(separator: ", ")
        return "👥 " + String(localized: "With \(joined)", comment: "Journaling Suggestion: the people in a moment, e.g. With Maya and Tom")
    }

    /// Apple Maps at a coordinate, labelled with the place's name when there is one.
    static func mapsURL(latitude: Double, longitude: Double, name: String? = nil) -> URL? {
        var c = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", latitude, longitude))]
        if let name = cleaned(name) { items.append(URLQueryItem(name: "q", value: name)) }
        c?.queryItems = items
        return c?.url
    }

    /// Apple Maps searching a place's name (an event that names its place but has no coordinate).
    static func mapsSearchURL(_ place: String?) -> URL? {
        guard let place = cleaned(place) else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "q", value: place)]
        return c?.url
    }

    /// Apple Music searching a song (or other media) by title and artist.
    static func musicSearchURL(title: String?, artist: String?) -> URL? {
        searchURL("https://music.apple.com/search", [title, artist])
    }

    /// Apple Podcasts searching an episode and its show.
    static func podcastSearchURL(episode: String?, show: String?) -> URL? {
        searchURL("https://podcasts.apple.com/search", [episode, show])
    }

    private static func searchURL(_ base: String, _ parts: [String?]) -> URL? {
        let term = parts.compactMap(cleaned).joined(separator: " ")
        guard !term.isEmpty else { return nil }
        var c = URLComponents(string: base)
        c?.queryItems = [URLQueryItem(name: "term", value: term)]
        return c?.url
    }

    static func steps(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return String(localized: "👟 \(count) steps", comment: "Journaling Suggestion: a step count")
    }

    static func event(title: String?, place: String?) -> String? {
        guard let title = cleaned(title) else { return nil }
        return "📅 " + ([title, cleaned(place)].compactMap { $0 }.joined(separator: " · "))
    }

    /// The nearest of the twelve moods for a State of Mind with no label the app knows.
    static func mood(forValence valence: Double) -> String {
        switch valence {
        case 0.6...: return "Joyful"
        case 0.2..<0.6: return "Content"
        case -0.2..<0.2: return "Numb"
        case -0.6 ..< -0.2: return "Drained"
        default: return "Sad"
        }
    }

    /// A workout route with its first and last `ends` metres cut off, so the map doesn't show
    /// where it starts and ends (usually home). Nil when too little would be left to draw.
    static func trimmedRoute(_ points: [CLLocation], ends: CLLocationDistance = 300) -> [CLLocation]? {
        guard points.count >= 2 else { return nil }
        var fromStart: [CLLocationDistance] = [0]
        for i in 1..<points.count { fromStart.append(fromStart[i - 1] + points[i].distance(from: points[i - 1])) }
        let total = fromStart.last ?? 0
        // Keep at least as much route as is cut, so the map still shows a real stretch.
        guard total >= ends * 3 else { return nil }
        let kept = zip(points, fromStart).filter { $0.1 >= ends && $0.1 <= total - ends }.map(\.0)
        return kept.count >= 2 ? kept : nil
    }

    /// Whether a place gets a map with a pin: any place with a location, home and work included
    /// (owner, 2026-11-06).
    static func placeGetsMap(hasLocation: Bool) -> Bool { hasLocation }

    private static func joined(_ symbol: String, _ first: String?, _ second: String?) -> String? {
        let bits = [cleaned(first), cleaned(second)].compactMap { $0 }
        guard !bits.isEmpty else { return nil }
        return symbol + " " + bits.joined(separator: " · ")
    }

    private static func cleaned(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }
}

#if os(iOS) && canImport(JournalingSuggestions)
@available(iOS 17.2, *)
extension SuggestionInsert {
    /// Reads one picked suggestion. Each item is taken once, as its most useful kind (a Live Photo
    /// that's also offered as a photo comes in once). A video comes in as its first frame (entries don't hold video before 3.1.9).
    /// Contact photos are left out on purpose.
    static func read(_ suggestion: JournalingSuggestion) async -> SuggestionInsert {
        var insert = SuggestionInsert(title: suggestion.title)
        var people: [String] = []
        var route: [CLLocation]?
        var pin: CLLocation?

        func addPicture(_ url: URL?) {
            guard let url, insert.pictures.count < maxPictures, let copy = localCopy(of: url) else { return }
            insert.pictures.append(copy)
        }
        func add(_ line: String?, link: URL? = nil) {
            guard let line, !insert.lines.contains(line) else { return }
            insert.lines.append(line)
            if let link { insert.lineLinks[line] = link }
        }
        func mapsLink(_ location: JournalingSuggestion.Location) -> URL? {
            guard let c = location.location?.coordinate else { return nil }
            return SuggestionLines.mapsURL(latitude: c.latitude, longitude: c.longitude, name: location.place)
        }
        var pinName: String?

        for item in suggestion.items {
            if item.hasContent(ofType: JournalingSuggestion.LivePhoto.self),
               let live = try? await item.content(forType: JournalingSuggestion.LivePhoto.self) {
                addPicture(live.image); continue
            }
            if item.hasContent(ofType: JournalingSuggestion.Photo.self),
               let photo = try? await item.content(forType: JournalingSuggestion.Photo.self) {
                addPicture(photo.photo); continue
            }
            // A video comes in as its first frame (entries don't hold video yet; 3.1.9 plan).
            if item.hasContent(ofType: JournalingSuggestion.Video.self) {
                if insert.pictures.count < maxPictures,
                   let video = try? await item.content(forType: JournalingSuggestion.Video.self),
                   let frame = await firstFrame(of: video.url) {
                    insert.pictures.append(frame)
                }
                continue
            }
            if item.hasContent(ofType: JournalingSuggestion.Song.self),
               let song = try? await item.content(forType: JournalingSuggestion.Song.self) {
                add(SuggestionLines.media(title: song.song, artist: song.artist),
                    link: SuggestionLines.musicSearchURL(title: song.song, artist: song.artist))
                addPicture(song.artwork); continue
            }
            if item.hasContent(ofType: JournalingSuggestion.Podcast.self),
               let pod = try? await item.content(forType: JournalingSuggestion.Podcast.self) {
                add(SuggestionLines.podcast(episode: pod.episode, show: pod.show),
                    link: SuggestionLines.podcastSearchURL(episode: pod.episode, show: pod.show))
                addPicture(pod.artwork); continue
            }
            if #available(iOS 18.0, *), item.hasContent(ofType: JournalingSuggestion.GenericMedia.self),
               let media = try? await item.content(forType: JournalingSuggestion.GenericMedia.self) {
                add(SuggestionLines.media(title: media.title, artist: media.artist),
                    link: SuggestionLines.musicSearchURL(title: media.title, artist: media.artist)); continue
            }
            // A workout's details can come as an item of their own (no route then).
            if item.hasContent(ofType: JournalingSuggestion.Workout.Details.self),
               let details = try? await item.content(forType: JournalingSuggestion.Workout.Details.self) {
                add(detailsLine(details)); continue
            }
            if item.hasContent(ofType: JournalingSuggestion.WorkoutGroup.self),
               let group = try? await item.content(forType: JournalingSuggestion.WorkoutGroup.self) {
                for workout in group.workouts.prefix(3) {
                    add(workoutLine(workout))
                    if route == nil, let points = workout.route { route = SuggestionLines.trimmedRoute(points) }
                }
                continue
            }
            if item.hasContent(ofType: JournalingSuggestion.Workout.self),
               let workout = try? await item.content(forType: JournalingSuggestion.Workout.self) {
                add(workoutLine(workout))
                if route == nil, let points = workout.route { route = SuggestionLines.trimmedRoute(points) }
                continue
            }
            if item.hasContent(ofType: JournalingSuggestion.LocationGroup.self),
               let group = try? await item.content(forType: JournalingSuggestion.LocationGroup.self) {
                for location in group.locations.prefix(3) {
                    add(SuggestionLines.place(location.place, city: location.city), link: mapsLink(location))
                    if pin == nil, mapsPlace(location) { pin = location.location; pinName = location.place }
                }
                continue
            }
            if item.hasContent(ofType: JournalingSuggestion.Location.self),
               let location = try? await item.content(forType: JournalingSuggestion.Location.self) {
                add(SuggestionLines.place(location.place, city: location.city), link: mapsLink(location))
                if pin == nil, mapsPlace(location) { pin = location.location; pinName = location.place }
                continue
            }
            if item.hasContent(ofType: JournalingSuggestion.Contact.self),
               let contact = try? await item.content(forType: JournalingSuggestion.Contact.self) {
                people.append(contact.name); continue
            }
            if item.hasContent(ofType: JournalingSuggestion.MotionActivity.self),
               let motion = try? await item.content(forType: JournalingSuggestion.MotionActivity.self) {
                add(SuggestionLines.steps(motion.steps)); continue
            }
            if #available(iOS 18.0, *), item.hasContent(ofType: JournalingSuggestion.StateOfMind.self),
               let state = try? await item.content(forType: JournalingSuggestion.StateOfMind.self) {
                if insert.mood == nil { insert.mood = mood(for: state.state) }
                continue
            }
            if #available(iOS 18.0, *), item.hasContent(ofType: JournalingSuggestion.Reflection.self),
               let reflection = try? await item.content(forType: JournalingSuggestion.Reflection.self) {
                if insert.prompt == nil { insert.prompt = reflection.prompt }
                continue
            }
            if #available(iOS 26.0, *), item.hasContent(ofType: JournalingSuggestion.EventPoster.self),
               let poster = try? await item.content(forType: JournalingSuggestion.EventPoster.self) {
                add(SuggestionLines.event(title: String(poster.title.characters), place: poster.placeName),
                    link: SuggestionLines.mapsSearchURL(poster.placeName))
                addPicture(poster.image)
                continue
            }
        }
        add(SuggestionLines.people(people))
        // One map leads the pictures (owner, 2026-11-06), within the same limit of four: a
        // workout's route first, else a named place's pin.
        var map: URL?
        if let route, !route.isEmpty {
            let middle = route[route.count / 2]
            map = await routeMap(route)
            // The route's middle, never its (trimmed) ends.
            if map != nil { insert.mapLink = SuggestionLines.mapsURL(latitude: middle.coordinate.latitude, longitude: middle.coordinate.longitude) }
        }
        if map == nil, let pin {
            map = await placeMap(pin)
            if map != nil { insert.mapLink = SuggestionLines.mapsURL(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude, name: pinName) }
        }
        if let map {
            if insert.pictures.count >= maxPictures, let dropped = insert.pictures.popLast() {
                try? FileManager.default.removeItem(at: dropped)
            }
            insert.pictures.insert(map, at: 0)
        }
        return insert
    }

    /// A still map of the (already trimmed) route, drawn in the app's plum on the look the app is
    /// in now. No start or finish marker. Nil if MapKit can't make one (offline, no tiles).
    @MainActor
    static func routeMap(_ points: [CLLocation]) async -> URL? {
        let coords = points.map(\.coordinate)
        let line = MKPolyline(coordinates: coords, count: coords.count)
        let rect = line.boundingMapRect.insetBy(dx: -line.boundingMapRect.width * 0.15 - 200,
                                                dy: -line.boundingMapRect.height * 0.15 - 200)
        return await mapPicture(rect: rect) { snapshot, color in
            let path = UIBezierPath()
            for (i, c) in coords.enumerated() {
                let p = snapshot.point(for: c)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.lineWidth = 8
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            color.setStroke()
            path.stroke()
        }
    }

    /// A still map around a named place with one plum pin, about 800 m across.
    @MainActor
    static func placeMap(_ location: CLLocation) async -> URL? {
        let center = MKMapPoint(location.coordinate)
        let side = MKMapPointsPerMeterAtLatitude(location.coordinate.latitude) * 800
        let rect = MKMapRect(x: center.x - side * 0.75, y: center.y - side / 2, width: side * 1.5, height: side)
        return await mapPicture(rect: rect) { snapshot, color in
            let p = snapshot.point(for: location.coordinate)
            let dot = UIBezierPath(ovalIn: CGRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32))
            UIColor.white.setFill()
            dot.fill()
            let inner = UIBezierPath(ovalIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22))
            color.setFill()
            inner.fill()
        }
    }

    /// The look maps are drawn in: the app's own Appearance setting when it's set, else the screen's.
    @MainActor
    private static var mapStyle: UIUserInterfaceStyle {
        switch UserDefaults.standard.string(forKey: "mirrorAppearanceMode") {
        case "dark": return .dark
        case "light": return .light
        default:
            return UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?
                .traitCollection.userInterfaceStyle ?? UITraitCollection.current.userInterfaceStyle
        }
    }

    @MainActor
    private static func mapPicture(rect: MKMapRect,
                                   draw: @escaping (MKMapSnapshotter.Snapshot, UIColor) -> Void) async -> URL? {
        let style = mapStyle
        let options = MKMapSnapshotter.Options()
        // 16:9, the shape the map leads the entry at (owner, option A, 2026-11-07).
        let size = CGSize(width: 1200, height: 675)
        options.size = size
        options.scale = 1
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)
        options.pointOfInterestFilter = .excludingAll
        options.mapRect = rect
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let color = style == .dark ? UIColor(red: 0.788, green: 0.545, blue: 0.776, alpha: 1)
                                   : UIColor(red: 0.557, green: 0.227, blue: 0.431, alpha: 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snapshot.image.draw(at: .zero)
            draw(snapshot, color)
        }
        return writeJPEG(image)
    }

    /// A video's first frame, as a photo.
    private static func firstFrame(of url: URL) async -> URL? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 2048, height: 2048)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return writeJPEG(UIImage(cgImage: frame))
    }

    private static func writeJPEG(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    private static func mapsPlace(_ location: JournalingSuggestion.Location) -> Bool {
        SuggestionLines.placeGetsMap(hasLocation: location.location != nil)
    }

    private static func workoutLine(_ workout: JournalingSuggestion.Workout) -> String {
        detailsLine(workout.details)
    }

    private static func detailsLine(_ details: JournalingSuggestion.Workout.Details?) -> String {
        var name: String?
        if #available(iOS 26.0, *) { name = details?.localizedName }
        return SuggestionLines.workout(
            name: name,
            meters: details?.distance?.doubleValue(for: .meter()),
            seconds: details?.date?.duration,
            kilocalories: details?.activeEnergyBurned?.doubleValue(for: .kilocalorie()))
    }

    /// The app's mood whose Health label the State of Mind carries, else the nearest by valence.
    @available(iOS 18.0, *)
    private static func mood(for state: HKStateOfMind) -> String {
        for label in state.labels {
            if let match = MirrorTheme.moodOptions.first(where: { HealthMoodWriter.label(for: $0) == label }) { return match }
        }
        return SuggestionLines.mood(forValence: state.valence)
    }

    /// Copied out: the framework owns its files, and the editor deletes what it attaches.
    private static func localCopy(of url: URL) -> URL? {
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
        return (try? FileManager.default.copyItem(at: url, to: copy)) != nil ? copy : nil
    }
}
#endif

#if DEBUG && os(iOS) && canImport(JournalingSuggestions)
@available(iOS 17.2, *)
extension SuggestionInsert {
    /// DEBUG `--demoSuggestion=run|music|place`: a synthetic suggestion, built the way `read` builds
    /// a real one (same line formats, real map pictures), for screenshots and design passes on
    /// devices and simulators that can't show Apple's sheet. Synthetic names and places only.
    @MainActor
    static func demoFromLaunchArguments() async -> SuggestionInsert? {
        guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--demoSuggestion=") }) else { return nil }
        var insert = SuggestionInsert()
        switch arg.dropFirst("--demoSuggestion=".count) {
        case "run":
            insert.title = "Evening run"
            insert.lines = [SuggestionLines.workout(name: "Running", meters: 5200, seconds: 31 * 60, kilocalories: 412),
                            SuggestionLines.steps(8430)].compactMap { $0 }
            insert.mood = "Energized"
            // A loop through a synthetic park, one point every ~60 m.
            let loop = (0..<90).map { i -> CLLocation in
                let t = Double(i) / 90 * 2 * .pi * 0.92
                return CLLocation(latitude: 38.7223 + 0.006 * sin(t), longitude: -9.1500 + 0.008 * cos(t))
            }
            if let kept = SuggestionLines.trimmedRoute(loop), let map = await routeMap(kept) {
                insert.pictures.append(map)
                let middle = kept[kept.count / 2].coordinate
                insert.mapLink = SuggestionLines.mapsURL(latitude: middle.latitude, longitude: middle.longitude)
            }
        case "music":
            insert.title = "Songs on the drive home"
            insert.lines = [SuggestionLines.media(title: "Paper Lanterns", artist: "The Quiet Hours"),
                            SuggestionLines.media(title: "Low Tide", artist: "Marrow & Vine"),
                            SuggestionLines.podcast(episode: "The Long Way Round", show: "Field Notes")].compactMap { $0 }
            insert.pictures = [demoArtwork(0xE8A26A, 0x8E3A6E), demoArtwork(0x6E8FA8, 0x2E3E55), demoArtwork(0xC9B07A, 0x6E5A2E)].compactMap { $0 }
            for (line, url) in zip(insert.lines, [SuggestionLines.musicSearchURL(title: "Paper Lanterns", artist: "The Quiet Hours"),
                                                  SuggestionLines.musicSearchURL(title: "Low Tide", artist: "Marrow & Vine"),
                                                  SuggestionLines.podcastSearchURL(episode: "The Long Way Round", show: "Field Notes")]) {
                insert.lineLinks[line] = url
            }
        case "place":
            insert.title = "Dinner by the river"
            insert.lines = [SuggestionLines.place("Blue Door Café", city: "Lisbon"),
                            SuggestionLines.people(["Maya", "Tom"])].compactMap { $0 }
            if let map = await placeMap(CLLocation(latitude: 38.7077, longitude: -9.1365)) {
                insert.pictures.append(map)
                insert.mapLink = SuggestionLines.mapsURL(latitude: 38.7077, longitude: -9.1365, name: "Blue Door Café")
            }
            if let place = insert.lines.first {
                insert.lineLinks[place] = SuggestionLines.mapsURL(latitude: 38.7077, longitude: -9.1365, name: "Blue Door Café")
            }
            insert.pictures += [demoArtwork(0x7FA88A, 0x2E5540), demoArtwork(0xD9A06A, 0x8A4A2E)].compactMap { $0 }
        default:
            return nil
        }
        return insert
    }

    /// A square two-colour gradient standing in for album art or a photo.
    @MainActor
    private static func demoArtwork(_ from: UInt32, _ to: UInt32) -> URL? {
        func color(_ hex: UInt32) -> CGColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1).cgColor
        }
        let size = CGSize(width: 900, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(from), color(to)] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        return writeJPEG(image)
    }
}
#endif
