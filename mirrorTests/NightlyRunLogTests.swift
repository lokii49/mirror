import Testing
import Foundation
@testable import mirror

// The night job's run record shown in Sentinel's Diagnostics: times and an outcome, never content.
@Suite("Night job run record")
struct NightlyRunLogTests {
    private func defaults() -> UserDefaults {
        let name = "NightlyRunLogTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func neverRanSaysSo() {
        #expect(NightlyRunLog.summary(defaults: defaults()) == "The night job hasn't run on this device yet.")
    }

    @Test func aFinishedRunShowsItsLengthAndCount() {
        let d = defaults()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        NightlyRunLog.recordStart(at: start, defaults: d)
        NightlyRunLog.recordEnd(.finished, at: start.addingTimeInterval(250), defaults: d)
        let text = NightlyRunLog.summary(defaults: d, locale: Locale(identifier: "en_GB"))
        #expect(text.contains("finished after 4 min"), "\(text)")
        #expect(text.hasSuffix("(1 run on this device)."), "\(text)")
    }

    @Test func anExpiredRunAndARunWithNoEndAreTold() {
        let d = defaults()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        NightlyRunLog.recordStart(at: start, defaults: d)
        NightlyRunLog.recordEnd(.expired, at: start.addingTimeInterval(30), defaults: d)
        #expect(NightlyRunLog.summary(defaults: d).contains("cut off by iOS after under a minute"))
        NightlyRunLog.recordStart(at: start.addingTimeInterval(86_400), defaults: d)
        let open = NightlyRunLog.summary(defaults: d)
        #expect(open.contains("no end recorded") && open.contains("2 runs on this device"), "\(open)")
    }
}
