import Testing
import Foundation
@testable import mirror

/// What's New picks cards by version; the Mac (1.x) maps to the iOS release whose cards it shows.
struct FeatureCardVersionTests {

    @Test func mac110ShowsThe310Cards() {
        let ids = FeatureCardService.macWhatsNewCards(lastSeen: "1.0.2", current: "1.1.0").map(\.id)
        #expect(ids == ["smart-ask-search-310", "reflection-styles-310", "writing-310", "privacy-policy-310"])
        #expect(!ids.contains("format-panel-310"), "the Aa panel is iOS only")
    }

    @Test func aMacVersionBeforeAnyMappingShowsNothing() {
        #expect(FeatureCardService.macWhatsNewCards(lastSeen: "1.0.1", current: "1.0.2").isEmpty)
        #expect(!FeatureCardService.macHasUnseenCards(lastSeen: "1.0.1", current: "1.0.2"))
    }

    /// 1.1.1 has no cards of its own: skipping 1.1.0 still brings the 3.1.0 privacy notice, and
    /// a Mac that saw 1.1.0 isn't shown it again.
    @Test func mac111ShowsThe310CardsOnlyToMacsThatSkipped110() {
        #expect(FeatureCardService.macHasUnseenCards(lastSeen: "1.0.2", current: "1.1.1"))
        #expect(FeatureCardService.macWhatsNewCards(lastSeen: "1.0.2", current: "1.1.1").map(\.id).contains("privacy-policy-310"))
        #expect(!FeatureCardService.macHasUnseenCards(lastSeen: "1.1.0", current: "1.1.1"))
        #expect(FeatureCardService.macHasUnseenCards(lastSeen: "0.0.0", current: "1.1.0"))
    }

    @Test func everyMappedReleaseHasCards() {
        for (mac, ios) in FeatureCardService.macFeatureRelease {
            #expect(!FeatureCardService.macWhatsNewCards(lastSeen: "0.0.0", current: mac).isEmpty, "Mac \(mac) -> \(ios) has no cards")
        }
    }

    private let release310 = ["smart-ask-search-310", "reflection-styles-310", "format-panel-310", "writing-310", "privacy-policy-310"]

    /// A reinstall or a restored phone has no last seen version: 3.1.0 showed it all 28 cards.
    @Test func aDeviceWithNoLastSeenVersionGetsOnlyTheNewestRelease() {
        #expect(FeatureCardService.iOSWhatsNewCards(lastSeen: "0.0.0", current: "3.1.0").map(\.id) == release310)
        #expect(FeatureCardService.iOSWhatsNewCards(lastSeen: "0.0.0", current: "3.1.1").map(\.id) == release310)
    }

    @Test func anOldUpgradeGetsOnlyTheNewestRelease() {
        #expect(FeatureCardService.iOSWhatsNewCards(lastSeen: "2.0.3", current: "3.1.0").map(\.id) == release310)
    }

    /// 3.1.1 has no cards of its own; someone who skipped 3.1.0 still gets its privacy notice.
    @Test func skippingAReleaseStillShowsItsPrivacyNotice() {
        let ids = FeatureCardService.iOSWhatsNewCards(lastSeen: "3.0.9", current: "3.1.1").map(\.id)
        #expect(ids == release310)
    }

    @Test func noCardsMeansNoPages() {
        #expect(FeatureCardService.iOSWhatsNewCards(lastSeen: "3.1.0", current: "3.1.1").isEmpty)
    }
}
