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
}
