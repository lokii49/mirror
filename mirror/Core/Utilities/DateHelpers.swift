import Foundation

extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

enum DateHelpers {
    static func weekIdentifier(for date: Date) -> String {
        let cal = Calendar.current
        let year = cal.component(.yearForWeekOfYear, from: date)
        let week = cal.component(.weekOfYear, from: date)
        return String(format: "%d-W%02d", year, week)
    }

    static func dayIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func monthIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    /// The monthly report's generation window — a report about "this month" written from only
    /// the first two or three weeks isn't actually a look back at the month, so this gates
    /// generation entirely (not just which entry-count threshold applies, which is all the old
    /// isInLastThreeDaysOfMonth version of this controlled).
    static func isInLastWeekOfMonth(_ date: Date = Date()) -> Bool {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: date),
              let day = cal.dateComponents([.day], from: date).day else { return false }
        return day >= range.count - 6
    }

    /// The weekly digest's generation window — matches mirrorApp's own background pre-gen rule
    /// (`Calendar.current.component(.weekday, from: Date()) == 1`), factored out as a testable
    /// predicate so `InsightViewModel.loadWeeklyDigest`'s on-demand path can share the exact
    /// same rule instead of a second inline copy of "1" silently drifting from it over time.
    /// `.weekday == 1` is Sunday regardless of `Calendar.current.firstWeekday` (weekday numbering
    /// is fixed Gregorian, 1...7 = Sun...Sat; only which day a week is considered to *start* on
    /// changes with firstWeekday, not this number).
    static func isSunday(_ date: Date = Date()) -> Bool {
        Calendar.current.component(.weekday, from: date) == 1
    }
}
