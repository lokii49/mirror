import Testing
@testable import mirror

// Track C (C1/C2) of the 2.1.0 design plan: the Weekly Digest and Monthly Report
// widgets show ONE section of their multi-section insight, extracted by
// `InsightService.firstSectionBody`. The failure mode if extraction misses is a
// silently blank widget — not a crash — so it's only caught here.
//
// The key case: a `**`-wrapped header. Stored `Insight.content` is already
// `cleaned…Output()` (headers un-wrapped), but the on-screen parsers still
// normalize defensively and so must this, or the widget disagrees with the card
// on exactly the raw outputs the card renders fine.

@Suite("Widget bridge section extraction")
struct WidgetBridgeSectionTests {
    private let weekly = InsightService.weeklyDigestSectionLabels
    private let monthly = InsightService.monthlyReportSectionLabels

    @Test func extractsFirstDigestSection_cleanInput() {
        let content = """
        THIS WEEK'S THEME: You kept steadying yourself against a moving floor.
        YOUR ENERGY: Low but not empty.
        WHAT'S BUILDING: A habit of pausing before you answer.
        WATCH OUT FOR: Saying yes on tired days.
        MOOD BOOST: The walk on Thursday.
        NEXT WEEK: Protect one evening.
        """
        #expect(InsightService.firstSectionBody(of: content, labels: weekly)
                == "You kept steadying yourself against a moving floor.")
    }

    @Test func extractsFirstDigestSection_markdownWrappedHeaders() {
        // The exact shape that would blank the widget if we didn't strip `**`.
        let content = """
        **THIS WEEK'S THEME:** You kept steadying yourself against a moving floor.
        **YOUR ENERGY:** Low but not empty.
        """
        #expect(InsightService.firstSectionBody(of: content, labels: weekly)
                == "You kept steadying yourself against a moving floor.")
    }

    @Test func extractsFirstDigestSection_multilineBody() {
        let content = """
        THIS WEEK'S THEME:
        You kept steadying yourself against a moving floor,
        and mostly you managed it.
        YOUR ENERGY: Low.
        """
        let body = InsightService.firstSectionBody(of: content, labels: weekly)
        #expect(body?.hasPrefix("You kept steadying yourself") == true)
        #expect(body?.contains("mostly you managed it") == true)
        #expect(body?.contains("YOUR ENERGY") == false)
    }

    @Test func extractsMonthlyImageSection() {
        let content = """
        YOUR MONTH IN ONE IMAGE: A harbor at first light, every boat already pointed out to sea.
        THE TENSION AT THE CENTER: Wanting to rest and wanting to move.
        """
        #expect(InsightService.firstSectionBody(of: content, labels: monthly)
                == "A harbor at first light, every boat already pointed out to sea.")
    }

    #if DEBUG
    @Test func extractsFromCanonicalSampleContent() {
        // Not a hand-written fixture — the six-section string the repo ships for
        // the monthly-report capture, with the real header shape.
        let body = InsightService.firstSectionBody(
            of: SampleData.monthlyReportSampleContent, labels: monthly
        )
        #expect(body?.hasPrefix("A desk lamp left on past midnight") == true)
        #expect(body?.contains("swinging between those two") == true)
        #expect(body?.contains("THE TENSION AT THE CENTER") == false)
    }
    #endif

    @Test func returnsNil_whenFirstHeaderMissing() {
        let content = "YOUR ENERGY: Low but not empty.\nNEXT WEEK: Protect one evening."
        #expect(InsightService.firstSectionBody(of: content, labels: weekly) == nil)
    }

    @Test func returnsNil_whenSectionBodyEmpty() {
        let content = "THIS WEEK'S THEME:\n\nYOUR ENERGY: Low."
        #expect(InsightService.firstSectionBody(of: content, labels: weekly) == nil)
    }

    @Test func stopsAtNextSectionHeader() {
        // Body ends at the next section's header, matching WeeklyDigestView.parseDigest —
        // section order is enforced upstream by the validator, so canonical order holds.
        let content = """
        THIS WEEK'S THEME: The floor kept moving.
        YOUR ENERGY: Low.
        NEXT WEEK: Protect one evening.
        """
        #expect(InsightService.firstSectionBody(of: content, labels: weekly)
                == "The floor kept moving.")
    }
}
