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

    /// The weekly digest's week: always Monday–Sunday (ISO 8601), whatever the device's first
    /// weekday. The digest is generated on Sunday as a look back at the week ending that day.
    /// With `weekIdentifier`'s locale calendar, Sunday-first regions (US, India, …) put that
    /// Sunday in a brand-new, empty week, so the 3-entry gate never passed on the only day
    /// generation runs — digests silently stopped there. `Entry.weekIdentifier` keeps the locale
    /// week; only digest lookups use this.
    static func digestWeekIdentifier(for date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = Calendar.current.timeZone
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

    /// Earliest date for the weekly digest's background refresh: the next Sunday 7 AM after
    /// `now` (a week on when it's Sunday past 7). Weekday 1 is Sunday whatever `firstWeekday` is.
    static func nextSunday7AM(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 1
        components.hour = 7
        components.minute = 0
        components.second = 0
        guard var next = calendar.date(from: components) else { return now }
        if next <= now {
            next = calendar.date(byAdding: .weekOfYear, value: 1, to: next) ?? next
        }
        return next
    }

    /// Earliest date for the monthly report's background refresh: 9 PM on this month's last day,
    /// or next month's once that has passed.
    static func lastDayOfMonth9PM(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        func lastDay9PM(monthsAhead: Int) -> Date? {
            guard let any = calendar.date(byAdding: .month, value: monthsAhead + 1, to: now),
                  let nextStart = calendar.date(from: calendar.dateComponents([.year, .month], from: any)),
                  let last = calendar.date(byAdding: .day, value: -1, to: nextStart) else { return nil }
            var comps = calendar.dateComponents([.year, .month, .day], from: last)
            comps.hour = 21; comps.minute = 0; comps.second = 0
            return calendar.date(from: comps)
        }
        guard let target = lastDay9PM(monthsAhead: 0) else { return now }
        return target > now ? target : (lastDay9PM(monthsAhead: 1) ?? target)
    }
}
