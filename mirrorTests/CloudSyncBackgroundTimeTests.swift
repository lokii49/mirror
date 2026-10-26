#if os(iOS)
import Testing
import Foundation
@testable import mirror

// iCloud imports/exports hold a background task from the first start to the last end, so iOS doesn't
// suspend the app mid-write to the App Group store (0xdead10cc).
@MainActor
@Suite("iCloud sync background time")
struct CloudSyncBackgroundTimeTests {
    @Test func holdsBackgroundTimeUntilTheLastSyncEnds() {
        let guardian = CloudSyncBackgroundTime.shared
        let importID = UUID(), exportID = UUID()
        #expect(!guardian.isHoldingBackgroundTime)
        guardian.record(importID, ended: false)
        #expect(guardian.isHoldingBackgroundTime)
        guardian.record(exportID, ended: false)
        guardian.record(importID, ended: true)
        #expect(guardian.isHoldingBackgroundTime, "the export is still running")
        guardian.record(exportID, ended: true)
        #expect(!guardian.isHoldingBackgroundTime)
    }

    @Test func anEndWithoutAStartHoldsNothing() {
        let guardian = CloudSyncBackgroundTime.shared
        guardian.record(UUID(), ended: true)
        #expect(!guardian.isHoldingBackgroundTime)
    }
}
#endif
