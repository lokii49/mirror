import Testing
import Foundation
@testable import mirror

// `InsightService.weeklyDigestIsStale` decides whether a cached weekly digest
// gets regenerated. Both call sites (mirrorApp.runWeeklyDigestIfNeeded, the
// Sunday path; InsightViewModel.loadWeeklyDigest, on-demand) route through it,
// so the AND of the two conditions is pinned here.

@Suite("Weekly digest staleness")
struct WeeklyDigestStalenessTests {
    private let dayAgo = Date().addingTimeInterval(-25 * 60 * 60)
    private let hourAgo = Date().addingTimeInterval(-60 * 60)

    @Test func stale_whenCooldownElapsedAndNewerEntryExists() {
        #expect(InsightService.weeklyDigestIsStale(
            generatedAt: dayAgo,
            newestWeekEntry: Date().addingTimeInterval(-2 * 60 * 60)  // newer than the digest
        ))
    }

    @Test func fresh_whenCooldownNotElapsed() {
        // New material, but generated only an hour ago — cost guard holds it.
        #expect(!InsightService.weeklyDigestIsStale(
            generatedAt: hourAgo,
            newestWeekEntry: Date()
        ))
    }

    @Test func fresh_whenNoNewerEntrySinceGeneration() {
        // Cooldown elapsed, but nothing written since the digest — nothing to fold in.
        #expect(!InsightService.weeklyDigestIsStale(
            generatedAt: dayAgo,
            newestWeekEntry: dayAgo.addingTimeInterval(-60 * 60)
        ))
    }

    @Test func fresh_whenNoWeekEntries() {
        #expect(!InsightService.weeklyDigestIsStale(generatedAt: dayAgo, newestWeekEntry: nil))
    }
}
