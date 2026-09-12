import Foundation

/// Purely local, non-AI: finds entries written on today's month/day in a past year. No
/// generation, no model, no network — zero fabrication risk, unlike every other Insight type.
/// Free for every tier: re-surfacing a user's own past entry isn't a new capability, just a
/// curated view of history CLAUDE.md already promises free users forever.
enum OnThisDayService {
    /// Entries whose `createdAt` shares today's month and day but not today's year, newest
    /// match first. `today`/`calendar` are parameterized for testability, not because callers
    /// need anything but the defaults.
    static func matches(in entries: [Entry], today: Date = Date(), calendar: Calendar = .current) -> [Entry] {
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
        guard let todayYear = todayComponents.year,
              let todayMonth = todayComponents.month,
              let todayDay = todayComponents.day else { return [] }

        return entries
            .filter { entry in
                let c = calendar.dateComponents([.year, .month, .day], from: entry.createdAt)
                guard let year = c.year, let month = c.month, let day = c.day else { return false }
                return year != todayYear && month == todayMonth && day == todayDay
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
