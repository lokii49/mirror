import Testing
import Foundation
@testable import mirror

/// What's New picks cards by version; the Mac (1.x) maps to the iOS release whose cards it shows.
struct FeatureCardVersionTests {

    @Test func mac110ShowsThe310Cards() {
        let ids = FeatureCardService.macWhatsNewCards(current: "1.1.0").map(\.id)
        #expect(ids == ["smart-ask-search-310", "privacy-policy-310"])
    }

    @Test func aMacVersionWithoutAMappingShowsNothing() {
        #expect(FeatureCardService.macWhatsNewCards(current: "1.0.2").isEmpty)
        #expect(FeatureCardService.macWhatsNewCards(current: "9.9.9").isEmpty)
    }

    @Test func everyMappedReleaseHasCards() {
        for (mac, ios) in FeatureCardService.macFeatureRelease {
            #expect(!FeatureCardService.macWhatsNewCards(current: mac).isEmpty, "Mac \(mac) -> \(ios) has no cards")
        }
    }
}
