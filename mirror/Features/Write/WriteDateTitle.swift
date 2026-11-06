import SwiftUI

/// The Write screen's date as a title (owner chose option A, 2026-11-06): the weekday large, the
/// day, month and time under it. Sentinel keeps its mono capitals at a smaller size. Its own
/// struct so `WriteView.body` gains no nested opaque types (Debug stack limit on device).
struct WriteDateTitle: View {
    let date: Date
    var isSentinel = false
    /// The chevron says the title opens the date picker; the Mac line beside the text has none.
    var showsChevron = true
    var primary: Color = MirrorTheme.textPrimary
    var secondary: Color = MirrorTheme.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: isSentinel ? 3 : 1) {
            Text(weekday)
                .scaledFont(isSentinel ? 25 : 30, weight: .bold, design: isSentinel ? .monospaced : .default)
                .kerning(isSentinel ? 0.6 : -0.4)
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 5) {
                Text(detail)
                    .scaledFont(isSentinel ? 13 : 15, weight: .medium, design: isSentinel ? .monospaced : .default)
                    .kerning(isSentinel ? 0.4 : 0)
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .scaledFont(isSentinel ? 9 : 10, weight: .semibold)
                        .foregroundStyle(secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var weekday: String {
        let text = date.formatted(.dateTime.weekday(.wide))
        return isSentinel ? text.uppercased() : text
    }

    /// "6 November · 12:08"; the year too when it isn't this year.
    private var detail: String {
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let day = thisYear ? date.formatted(.dateTime.day().month(.wide)) : date.formatted(.dateTime.day().month(.wide).year())
        let text = "\(day) · \(date.formatted(.dateTime.hour().minute()))"
        return isSentinel ? text.uppercased() : text
    }
}
