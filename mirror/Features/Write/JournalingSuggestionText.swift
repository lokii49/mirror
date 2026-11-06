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
}

/// The line formats, kept free of Apple's types so they can be tested. Words go through the string
/// catalog; numbers and units follow the reader's region.
enum SuggestionLines {
    static func media(title: String?, artist: String?) -> String? {
        joined("♪", title, artist)
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
        return String(localized: "With \(joined)", comment: "Journaling Suggestion: the people in a moment, e.g. With Maya and Tom")
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

    /// Whether a place gets a map with a pin: only a named place (a café, a park), never one Apple
    /// marks as work. A bare city or an unnamed spot keeps its text line only; Apple doesn't mark
    /// home, so needing a name is what keeps a home address off the map (owner, 2026-11-06).
    static func placeGetsMap(name: String?, isWork: Bool?) -> Bool {
        guard isWork != true else { return false }
        return cleaned(name) != nil
    }

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
    /// that's also offered as a photo comes in once). Videos are skipped: entries don't hold video.
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
        func add(_ line: String?) { if let line, !insert.lines.contains(line) { insert.lines.append(line) } }

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
                add(SuggestionLines.media(title: song.song, artist: song.artist)); addPicture(song.artwork); continue
            }
            if item.hasContent(ofType: JournalingSuggestion.Podcast.self),
               let pod = try? await item.content(forType: JournalingSuggestion.Podcast.self) {
                add(SuggestionLines.podcast(episode: pod.episode, show: pod.show)); addPicture(pod.artwork); continue
            }
            if #available(iOS 18.0, *), item.hasContent(ofType: JournalingSuggestion.GenericMedia.self),
               let media = try? await item.content(forType: JournalingSuggestion.GenericMedia.self) {
                add(SuggestionLines.media(title: media.title, artist: media.artist)); continue
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
                    add(SuggestionLines.place(location.place, city: location.city))
                    if pin == nil, mapsPlace(location) { pin = location.location }
                }
                continue
            }
            if item.hasContent(ofType: JournalingSuggestion.Location.self),
               let location = try? await item.content(forType: JournalingSuggestion.Location.self) {
                add(SuggestionLines.place(location.place, city: location.city))
                if pin == nil, mapsPlace(location) { pin = location.location }
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
                add(SuggestionLines.event(title: String(poster.title.characters), place: poster.placeName))
                addPicture(poster.image)
                continue
            }
        }
        add(SuggestionLines.people(people))
        // One map leads the pictures (owner, 2026-11-06), within the same limit of four: a
        // workout's route first, else a named place's pin.
        var map: URL?
        if let route { map = await routeMap(route) }
        if map == nil, let pin { map = await placeMap(pin) }
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
        let size = CGSize(width: 1200, height: 800)
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
        var isWork: Bool?
        if #available(iOS 26.0, *) { isWork = location.isWorkLocation }
        return location.location != nil && SuggestionLines.placeGetsMap(name: location.place, isWork: isWork)
    }

    private static func workoutLine(_ workout: JournalingSuggestion.Workout) -> String {
        let details = workout.details
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
