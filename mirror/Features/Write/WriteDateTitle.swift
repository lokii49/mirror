import SwiftUI

/// The Write screen's date as a title (owner chose option A, 2026-11-06): the weekday large, the
/// day, month and time under it. Its own struct so `WriteView.body` gains no nested opaque types
/// (Debug stack limit on device).
struct WriteDateTitle: View {
    let date: Date
    var isSentinel = false
    /// The chevron says the title opens the date picker; the Mac line beside the text has none.
    var showsChevron = true
    var primary: Color = MirrorTheme.textPrimary
    var secondary: Color = MirrorTheme.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(weekday)
                // Paper & Ink: the day in the reflection's serif.
                .scaledFont(31, weight: .medium, design: .serif)
                .kerning(-0.2)
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 5) {
                Text(detail)
                    .scaledFont(15, weight: .medium, design: .default)
                    .kerning(0)
                    .foregroundStyle(secondary)
                    // Two lines at accessibility sizes, where the Mood pill beside the title
                    // left "7 Novemb…" (UI checklist, AX3 pass 2026-11-07).
                    .lineLimit(1...2)
                    .minimumScaleFactor(0.8)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .scaledFont(10, weight: .semibold)
                        .foregroundStyle(secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        // At AX4–AX5 the title and the Mood pill beside it both truncated ("7 Nove…", "M…");
        // the header stops at AX3, the entry text below keeps growing (2026-11-07 checks).
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    private var weekday: String {
        date.formatted(.dateTime.weekday(.wide))
    }

    /// "6 November · 12:08"; the year too when it isn't this year.
    private var detail: String {
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let day = thisYear ? date.formatted(.dateTime.day().month(.wide)) : date.formatted(.dateTime.day().month(.wide).year())
        return "\(day) · \(date.formatted(.dateTime.hour().minute()))"
    }
}
