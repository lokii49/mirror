import Foundation
import Testing
@testable import mirror

/// The one photo-size rule (`PhotoPlacement`): what is drawn, what is ticked, what each choice
/// stores, for every stored value and place a photo can be in (3.1.9 test matrix).
@Suite("Photo placement")
struct PhotoPlacementTests {
    private func p(_ i: Int) -> String { inlinePhotoToken(at: i) }

    /// Inline style data with photo sizes at the inline offsets of the given photo indices.
    private func sizes(_ text: String, _ values: [Int: String]) -> Data? {
        var data: Data?
        for (photo, offset) in PhotoSizes.inlineOffsets(in: text) {
            if let value = values[photo] { data = PhotoSizes.setting(stored: value, atInlineOffset: offset, in: data) }
        }
        return data
    }

    private func place(_ text: String, sized: [Int: String] = [:], landscape: Set<Int> = [], pictures: Int = 99) -> [PhotoPlacement] {
        PhotoPlacement.placements(text: text, inlineStyleData: sizes(text, sized),
                                  hasPicture: { $0 < pictures }, isLandscape: { landscape.contains($0) })
    }

    private func drawn(_ text: String, sized: [Int: String] = [:], landscape: Set<Int> = [], pictures: Int = 99) -> [PhotoDrawn] {
        place(text, sized: sized, landscape: landscape, pictures: pictures).map(\.drawn)
    }

    // MARK: - The rule on its own

    /// Every stored value in every place: drawn, tick and what each choice stores.
    @Test func everyStoredValueInEveryPlace() {
        struct Place { var photoLine: Bool, inRun: Bool, leadsAsMap: Bool }
        let places = [
            Place(photoLine: false, inRun: false, leadsAsMap: false),   // shares its line with words
            Place(photoLine: true, inRun: false, leadsAsMap: false),    // alone
            Place(photoLine: true, inRun: true, leadsAsMap: false),     // row tile
            Place(photoLine: true, inRun: true, leadsAsMap: true),      // row's leading map
        ]
        for place in places {
            for stored in [nil, "thumbnail", "small", "medium", "full"] as [String?] {
                let placement = PhotoPlacement(photoIndex: 0, stored: stored, photoLine: place.photoLine,
                                               inRun: place.inRun, leadsAsMap: place.leadsAsMap)
                let noneIsTile = place.inRun && !place.leadsAsMap
                let expected: PhotoDrawn = switch stored {
                case nil: noneIsTile ? .tile : .width(.full)
                case "thumbnail": place.photoLine ? .tile : .width(.full)
                case "small": .width(.small)
                case "medium": .width(.medium)
                default: .width(.full)
                }
                #expect(placement.drawn == expected, "\(stored ?? "nil") photoLine=\(place.photoLine) inRun=\(place.inRun) map=\(place.leadsAsMap)")
                #expect(placement.isTile == (expected == .tile))
                // Choosing each option draws that option and ticks it.
                for option in placement.options {
                    var chosen = placement
                    chosen.stored = placement.storedValue(for: option)
                    #expect(chosen.tick == option, "\(stored ?? "nil") → \(option)")
                }
                // Nothing is stored when no size already draws the choice.
                #expect(placement.storedValue(for: .thumbnail) == (noneIsTile ? nil : "thumbnail"))
                #expect(placement.storedValue(for: .full) == (noneIsTile ? "full" : nil))
                #expect(placement.storedValue(for: .small) == "small")
                #expect(placement.storedValue(for: .medium) == "medium")
                #expect(placement.options.contains(.thumbnail) == place.photoLine)
            }
        }
    }

    // MARK: - Arrangements

    @Test func onePhoto() {
        #expect(drawn(p(0)) == [.width(.full)])
        #expect(drawn("Walk\n\(p(0))\nThen tea.") == [.width(.full)])
        #expect(drawn(p(0), sized: [0: "thumbnail"]) == [.tile])
        #expect(drawn(p(0), sized: [0: "small"]) == [.width(.small)])
        #expect(drawn(p(0), sized: [0: "full"]) == [.width(.full)], "full on a lone photo is just full width")
    }

    @Test func rowsOfTwoToFive() {
        for count in 2...5 {
            let text = (0..<count).map(p).joined(separator: "\n")
            #expect(drawn(text) == Array(repeating: .tile, count: count))
            #expect(drawn(text + "\n") == Array(repeating: .tile, count: count), "trailing line break")
            #expect(drawn("Title\n" + text + "\nAfter") == Array(repeating: .tile, count: count))
        }
    }

    @Test func aLandscapeFirstPhotoLeadsAtFullWidth() {
        let text = "\(p(0))\n\(p(1))\n\(p(2))"
        #expect(drawn(text, landscape: [0]) == [.width(.full), .tile, .tile])
        #expect(drawn(text, landscape: [1]) == [.tile, .tile, .tile], "landscape not first is a tile")
        #expect(drawn(text, landscape: [0, 1, 2]) == [.width(.full), .tile, .tile])
        #expect(drawn(text, sized: [0: "thumbnail"], landscape: [0]) == [.tile, .tile, .tile])
        // Runs are found before sizes: a sized first photo still counts as the run's first.
        #expect(drawn(text, sized: [0: "full"], landscape: [1]) == [.width(.full), .tile, .tile])
    }

    @Test func whatEndsARun() {
        #expect(drawn("\(p(0))\n\n\(p(1))") == [.width(.full), .width(.full)], "blank line")
        #expect(drawn("\(p(0))\n \n\(p(1))") == [.width(.full), .width(.full)], "line of spaces")
        #expect(drawn("\(p(0))\nwords\n\(p(1))") == [.width(.full), .width(.full)], "words")
        #expect(drawn("\(p(0)) \n  \(p(1))\t") == [.tile, .tile], "spaces around tokens keep it")
        #expect(drawn("look \(p(0))\n\(p(1))") == [.width(.full), .width(.full)], "a photo sharing its line")
        #expect(drawn("\(p(0))\n\(p(1))\n\n\(p(2))\n\(p(3))") == [.tile, .tile, .tile, .tile], "two runs")
    }

    @Test func aPhotoWithoutItsPictureBreaksTheRun() {
        #expect(drawn("\(p(0))\n\(p(1))\n\(p(2))", pictures: 2) == [.tile, .tile, .width(.full)])
        #expect(drawn("\(p(0))\n\(p(5))\n\(p(1))", pictures: 2) == [.width(.full), .width(.full), .width(.full)])
    }

    @Test func aPhotoSharingItsLineWithWords() {
        let placement = place("look \(p(0))", sized: [0: "thumbnail"])[0]
        #expect(placement.drawn == .width(.full))
        #expect(placement.tick == .full)
        #expect(!placement.options.contains(.thumbnail))
        #expect(place("look \(p(0))", sized: [0: "small"])[0].drawn == .width(.small))
    }

    @Test func firstAndLastInTheEntry() {
        #expect(drawn("\(p(0))\n\(p(1))\nwords") == [.tile, .tile])
        #expect(drawn("words\n\(p(0))\n\(p(1))") == [.tile, .tile])
    }

    // MARK: - Size changes in a row

    @Test func sizingFirstMiddleAndLastOfARow() {
        let text = "\(p(0))\n\(p(1))\n\(p(2))"
        for sized in 0..<3 {
            for value in ["small", "medium", "full"] {
                var expected: [PhotoDrawn] = [.tile, .tile, .tile]
                expected[sized] = .width(PhotoSize(stored: value))
                #expect(drawn(text, sized: [sized: value]) == expected, "photo \(sized) \(value)")
            }
            #expect(drawn(text, sized: [sized: "thumbnail"]) == [.tile, .tile, .tile])
        }
    }

    @Test func twoPhotosInARowSizedDifferently() {
        let text = "\(p(0))\n\(p(1))\n\(p(2))"
        #expect(drawn(text, sized: [0: "small", 2: "medium"]) == [.width(.small), .tile, .width(.medium)])
        #expect(drawn(text, sized: [0: "full", 1: "full", 2: "full"]) == [.width(.full), .width(.full), .width(.full)])
    }

    @Test func allSizedThenBackToThumbnail() {
        let text = "\(p(0))\n\(p(1))\n\(p(2))"
        var data = sizes(text, [0: "small", 1: "medium", 2: "full"])
        for placement in PhotoPlacement.placements(text: text, inlineStyleData: data, hasPicture: { _ in true }, isLandscape: { _ in false }) {
            let offset = PhotoSizes.inlineOffsets(in: text).first { $0.photoIndex == placement.photoIndex }!.offset
            data = PhotoSizes.setting(stored: placement.storedValue(for: .thumbnail), atInlineOffset: offset, in: data)
        }
        #expect(data == nil, "a row of tiles stores nothing")
        #expect(PhotoPlacement.placements(text: text, inlineStyleData: data, hasPicture: { _ in true }, isLandscape: { _ in false })
            .map(\.drawn) == [.tile, .tile, .tile])
    }

    // MARK: - Structure changes after sizing

    /// The owner's case (14 Pro, 2026-11-13): a lone photo set to Thumbnail, then a second photo
    /// added with the paperclip, which appends at the end after trimming trailing line breaks.
    /// Right under it (trailing blank lines and lines of spaces trimmed) they make a row of two
    /// tiles; after words the second is a photo of its own, full width.
    @Test func aPhotoAddedUnderAThumbnail() {
        let first = p(0)
        let thumb = sizes(first, [0: "thumbnail"])
        for ending in ["", "\n", "\n\n\n", "\n ", "\n \n", "\n\t\n  \n"] {
            let added = textWithInlinePhotoToken(first + ending, at: 1)
            #expect(PhotoPlacement.placements(text: added, inlineStyleData: thumb, hasPicture: { _ in true }, isLandscape: { _ in false })
                .map(\.drawn) == [.tile, .tile], "\(ending.debugDescription)")
        }
        #expect(textWithInlinePhotoToken("  ", at: 0) == p(0))
        #expect(textWithInlinePhotoToken("words  \n ", at: 0) == "words  \n\(p(0))\n", "spaces on a line of words stay")
        for between in ["words\n", "words \n \n"] {
            let text = textWithInlinePhotoToken(first + "\n" + between, at: 1)
            #expect(PhotoPlacement.placements(text: text, inlineStyleData: thumb, hasPicture: { _ in true }, isLandscape: { _ in false })
                .map(\.drawn) == [.tile, .width(.full)], "\(between.debugDescription)")
        }
    }

    @Test func deletingANeighbourLeavesALonePhoto() {
        let text = "\(p(0))\n\(p(1))"
        let data = sizes(text, [1: "full"])
        #expect(PhotoPlacement.placements(text: text, inlineStyleData: data, hasPicture: { _ in true }, isLandscape: { _ in false })
            .map(\.drawn) == [.tile, .width(.full)])
        // Photo 1 removed: photo 0 is alone, a full-width photo again (no size, nothing stored).
        let after = PhotoSizes.removingPhoto(at: 1, oldText: text, newText: p(0), in: data)
        #expect(after == nil)
        #expect(drawn(p(0)) == [.width(.full)])
        // Photo 0 removed instead: photo 1 keeps "full", which alone is full width.
        let other = PhotoSizes.removingPhoto(at: 0, oldText: text, newText: p(0), in: data)
        let left = PhotoPlacement.placements(text: p(0), inlineStyleData: other, hasPicture: { _ in true }, isLandscape: { _ in false })[0]
        #expect(left.drawn == .width(.full))
        #expect(left.tick == .full)
    }

    @Test func aDuplicateTokenUsesTheFirst() {
        let placements = place("\(p(0))\nwords\n\(p(0))\n\(p(1))")
        #expect(placements.map(\.drawn) == [.width(.full), .tile, .tile])
        #expect(PhotoPlacement.byPhoto(placements)[0]?.drawn == .width(.full))
    }

    // MARK: - Same as before the refactor

    /// The editor's old rule (`OldEditorRule.tileMatches` minus sized photos, plus lone thumbnails)
    /// and the new one agree on random texts where every photo has its picture.
    @Test func matchesTheEditorsOldRule() {
        var rng = SystemRandomNumberGenerator.Seeded(seed: 20261114)
        let pieces = ["\n", "\n", "\n", " ", "words", "\n\n", "\t"]
        let values: [String?] = [nil, nil, "thumbnail", "small", "medium", "full"]
        for _ in 0..<2000 {
            var text = ""
            let count = Int.random(in: 1...5, using: &rng)
            for i in 0..<count {
                text += pieces.randomElement(using: &rng)!
                if Bool.random(using: &rng) { text += pieces.randomElement(using: &rng)! }
                text += p(i)
            }
            if Bool.random(using: &rng) { text += pieces.randomElement(using: &rng)! }
            var sized: [Int: String] = [:]
            for i in 0..<count { if let v = values.randomElement(using: &rng)! { sized[i] = v } }
            let landscape = Set((0..<count).filter { _ in Int.random(in: 0..<4, using: &rng) == 0 })
            let data = sizes(text, sized)

            let ns = text as NSString
            let ranges = allPhotoTokens(in: text).map { (range: NSRange($0.range, in: text), index: $0.index) }
                .sorted { $0.range.location < $1.range.location }
            let stored = PhotoSizes.storedSizes(text: text, inlineStyleData: data)
            let sizedSet = Set(stored.filter { $0.value != PhotoSizes.thumbnail }.keys)
            let thumbs = Set(stored.filter { $0.value == PhotoSizes.thumbnail }.keys)
            let old = OldEditorRule.tileMatches(ranges.map(\.range), in: ns) { r in
                landscape.contains(ranges.first { $0.range == r }!.index)
            }.filter { !sizedSet.contains(ranges[$0].index) }
                .union(ranges.indices.filter { OldEditorRule.aloneOnLine(ranges[$0].range, in: ns) && thumbs.contains(ranges[$0].index) })
            let new = Set(PhotoPlacement.placements(text: text, inlineStyleData: data, hasPicture: { _ in true },
                                                    isLandscape: { landscape.contains($0) }).enumerated().filter { $1.isTile }.map(\.offset))
            #expect(old == new, "\(text.debugDescription) sized=\(sized) landscape=\(landscape)")
            if old != new { return }
        }
    }
}

/// The editor's rule before `PhotoPlacement` (778287f's `PhotoRuns.tileMatches`), kept here as the
/// oracle the new rule must match.
private enum OldEditorRule {
    static func isSpace(_ c: unichar) -> Bool { Unicode.Scalar(c).map { CharacterSet.whitespaces.contains($0) } ?? false }

    static func aloneOnLine(_ r: NSRange, in text: NSString) -> Bool {
        var start = r.location
        while start > 0, isSpace(text.character(at: start - 1)) { start -= 1 }
        var end = NSMaxRange(r)
        while end < text.length, isSpace(text.character(at: end)) { end += 1 }
        return (start == 0 || text.character(at: start - 1) == 10) && (end == text.length || text.character(at: end) == 10)
    }

    static func tileMatches(_ ranges: [NSRange], in text: NSString, isLandscape: (NSRange) -> Bool) -> Set<Int> {
        func onNextLine(_ a: NSRange, _ b: NSRange) -> Bool {
            guard b.location > NSMaxRange(a) else { return false }
            var breaks = 0
            for i in NSMaxRange(a)..<b.location {
                let c = text.character(at: i)
                if c == 10 { breaks += 1 } else if !isSpace(c) { return false }
            }
            return breaks == 1
        }
        var result = Set<Int>()
        var i = 0
        while i < ranges.count {
            guard aloneOnLine(ranges[i], in: text) else { i += 1; continue }
            var j = i
            while j + 1 < ranges.count, aloneOnLine(ranges[j + 1], in: text), onNextLine(ranges[j], ranges[j + 1]) { j += 1 }
            if j > i {
                let first = isLandscape(ranges[i]) ? i + 1 : i
                for k in first...j { result.insert(k) }
            }
            i = j + 1
        }
        return result
    }
}

private extension SystemRandomNumberGenerator {
    /// A small seeded generator (SplitMix64), so a failing text can be found again.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
