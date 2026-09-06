import Foundation
import SwiftData
import WidgetKit

/// The one place the app pushes weekly-digest / monthly-report content across the
/// app-group boundary to their home-screen widgets — the counterpart to
/// `mirrorApp.syncNudgeToWidget` for the two insight widgets added in 2.1.0.
///
/// Both functions read straight from SwiftData rather than taking an `Insight`,
/// so they're correct in every case: insight generated this session, served from
/// the 24h cache, or generated in a previous session (the generation paths bail
/// early then and never re-run). Call them right after a digest/report
/// `context.save()` for immediacy, and again on every app-active from
/// `preGenerateInsightsIfNeeded` as the catch-all — same belt-and-braces shape
/// the nudge uses.
///
/// Only ONE section of each multi-section insight crosses the boundary (the one
/// the widget shows), and it's clipped: journal-derived text stays as small as
/// possible in the shared container, and a widget can't reflow what it can't fit.
enum WidgetBridge {
    // Key names live on `WidgetShared` (WidgetTheme.swift) so the widget
    // extension — which can't see this file — can read them.

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetShared.appGroupID)
    }

    /// Push the current week's digest "THIS WEEK'S THEME" line to `MirrorWeeklyDigestWidget`.
    /// No-op (leaves the last value in place) if there's no digest for this week yet.
    @MainActor
    static func syncWeeklyDigest(from context: ModelContext) {
        let week = DateHelpers.weekIdentifier(for: Date())
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == week }
        )
        guard let digest = (try? context.fetch(descriptor))?.first(where: { $0.type == .weeklyDigest }),
              let theme = InsightService.firstSectionBody(
                  of: digest.content, labels: InsightService.weeklyDigestSectionLabels
              )
        else { return }

        defaults?.set(clip(theme, max: 200), forKey: WidgetShared.digestThemeKey)
        defaults?.set(week, forKey: WidgetShared.digestWeekKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "MirrorWeeklyDigestWidget")
    }

    /// Push the current month's "YOUR MONTH IN ONE IMAGE" metaphor to `MirrorMonthlyReportWidget`.
    /// No-op if there's no monthly report for this month yet.
    @MainActor
    static func syncMonthlyReport(from context: ModelContext) {
        let month = DateHelpers.monthIdentifier(for: Date())
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == month }
        )
        guard let report = (try? context.fetch(descriptor))?.first(where: { $0.type == .monthlyReport }),
              let image = InsightService.firstSectionBody(
                  of: report.content, labels: InsightService.monthlyReportSectionLabels
              )
        else { return }

        defaults?.set(clip(image, max: 280), forKey: WidgetShared.monthlyImageKey)
        defaults?.set(month, forKey: WidgetShared.monthlyPeriodKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "MirrorMonthlyReportWidget")
    }

    /// Trim to the last sentence end within `max` characters, else the last word
    /// boundary, so the widget gets a whole thought rather than a mid-word cut.
    private static func clip(_ s: String, max: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        let cut = trimmed.prefix(max)
        if let sentenceEnd = cut.range(of: "[.!?]", options: [.regularExpression, .backwards]) {
            return String(cut[..<sentenceEnd.upperBound])
        }
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace]) + "…"
        }
        return String(cut) + "…"
    }
}
