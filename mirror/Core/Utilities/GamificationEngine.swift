import Foundation

enum SentinelRank: String {
    case initiate = "Initiate"
    case operative = "Operative"
    case sentinel = "Sentinel"
    case apex = "Apex"

    /// Level thresholds: 1-3 Initiate, 4-8 Operative, 9-15 Sentinel, 16+ Apex.
    init(level: Int) {
        switch level {
        case ..<4: self = .initiate
        case 4..<9: self = .operative
        case 9..<16: self = .sentinel
        default: self = .apex
        }
    }
}

/// XP/level are computed live from entries, the same way CalendarHeatmap
/// computes streak live rather than trusting a stored counter — UserProfile
/// .streakCount is never written anywhere in this codebase and has gone
/// stale as a result. Keeping XP as a pure function of entries avoids
/// repeating that: every entry mutation site (save, edit, delete, import,
/// sample-data loaders) stays correct for free, with nothing to keep in sync.
enum GamificationEngine {

    /// Base points per entry, plus a length bonus (capped) and a mood-tagged
    /// bonus. Deliberately simple — entry text itself is never inspected,
    /// only wordCount, so nothing journal-content-derived gets logged.
    static func xp(for entries: [Entry]) -> Int {
        entries.reduce(0) { total, entry in
            var points = 10
            points += min(entry.wordCount / 20, 15)
            if entry.mood != nil { points += 5 }
            return total + points
        }
    }

    /// 100 XP per level, level 1 floor.
    static func level(forXP xp: Int) -> Int {
        max(1, xp / 100 + 1)
    }

    static func xpIntoLevel(_ xp: Int) -> Int { xp % 100 }
    static func xpForNextLevel() -> Int { 100 }

    static func rank(for entries: [Entry]) -> SentinelRank {
        SentinelRank(level: level(forXP: xp(for: entries)))
    }
}
