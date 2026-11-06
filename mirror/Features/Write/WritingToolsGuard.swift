import Foundation

/// Apple's Writing Tools in the entry editors (3.1.8, item 6). Both editors stored nothing about it
/// before, so iOS 18.2+ and macOS 15.2+ applied their default: full, in-place rewriting. A rewrite
/// that runs over a photo or a list marker can delete the photo or the marker (the iOS editor shows
/// markers as real characters; a photo is one U+FFFC attachment character in both editors).
///
/// So the editors (1) use Writing Tools' panel, where the person confirms Replace, not in-place
/// rewriting; (2) take plain-text results, which pick up the line's own style instead of formatting
/// the editor can't read back; (3) tell Writing Tools to leave every photo and list marker alone
/// (`ignoredRanges`). Checked on this Mac, which has Apple Intelligence (owner, 2026-11-06); the 14 Pro
/// has none, so iOS relies on the same rules.
enum WritingToolsGuard {
    /// The iOS editor's list markers (`staticListMarkerPrefix`), every level and state.
    static let markerPrefixes = ["○  ", "✓  ", "•  ", "◦  ", "▸  ", "–  ", "·  "]

    /// Ranges inside `enclosing` that Writing Tools must not change: each photo attachment character
    /// and, for each paragraph, a leading list marker ("○  ", "1.\t", legacy "1.  " …).
    static func ignoredRanges(in text: String, enclosing: NSRange) -> [NSRange] {
        let ns = text as NSString
        let bounds = NSIntersectionRange(enclosing, NSRange(location: 0, length: ns.length))
        guard bounds.length > 0 else { return [] }
        var ranges: [NSRange] = []

        // Photos.
        var search = bounds
        while search.length > 0 {
            let found = ns.range(of: "\u{fffc}", options: [], range: search)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let next = found.location + found.length
            search = NSRange(location: next, length: NSMaxRange(bounds) - next)
        }

        // List markers at the start of each paragraph that starts inside the range.
        var location = ns.paragraphRange(for: NSRange(location: bounds.location, length: 0)).location
        while location < NSMaxRange(bounds) {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            let line = ns.substring(with: paragraph)
            let markerLength = markerLength(of: line)
            if markerLength > 0 {
                let marker = NSIntersectionRange(NSRange(location: paragraph.location, length: markerLength), bounds)
                if marker.length > 0 { ranges.append(marker) }
            }
            let next = NSMaxRange(paragraph)
            if next <= location { break }
            location = next
        }
        return ranges.sorted { $0.location < $1.location }
    }

    /// UTF-16 length of a leading list marker, or 0.
    static func markerLength(of line: String) -> Int {
        if let prefix = markerPrefixes.first(where: { line.hasPrefix($0) }) { return (prefix as NSString).length }
        let ns = line as NSString
        var i = 0
        while i < ns.length, let scalar = Unicode.Scalar(ns.character(at: i)), ("0"..."9").contains(Character(scalar)) { i += 1 }
        guard i > 0, i < ns.length, ns.character(at: i) == 46 else { return 0 }          // "."
        i += 1
        guard i < ns.length else { return 0 }
        if ns.character(at: i) == 9 { return i + 1 }                                     // "\t"
        guard ns.character(at: i) == 32, i + 1 < ns.length, ns.character(at: i + 1) == 32 else { return 0 }
        return i + 2                                                                     // "  " (before the tab)
    }
}
