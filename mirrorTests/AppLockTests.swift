import Testing
import Foundation
@testable import mirror

/// The away rule only. Nothing here calls `didLeave` while enabled: that re-arms the automatic
/// prompt, and `didReturn` would then put up a real Face ID / Touch ID / password prompt.
@Suite("AppLock", .serialized)
@MainActor
struct AppLockTests {
    private let lock = AppLock.shared

    private func reset() {
        lock.setStateForTesting(enabled: false, locked: false)
        lock.setAwaySinceForTesting(nil)
        lock.setPrivacyCover(false)
    }

    @Test func locksAfterFiveMinutesAway() {
        defer { reset() }
        lock.setStateForTesting(enabled: true, locked: false)
        lock.setAwaySinceForTesting(Date().addingTimeInterval(-(AppLock.awayLimit + 10)))
        lock.didReturn()
        #expect(lock.isLocked)
    }

    @Test func staysUnlockedAfterAShortAbsence() {
        defer { reset() }
        lock.setStateForTesting(enabled: true, locked: false)
        lock.setAwaySinceForTesting(Date().addingTimeInterval(-(AppLock.awayLimit - 60)))
        lock.didReturn()
        #expect(!lock.isLocked)
        // The absence is used up: a later return doesn't count it again.
        lock.didReturn()
        #expect(!lock.isLocked)
    }

    @Test func neverLocksWhenOff() {
        defer { reset() }
        lock.setStateForTesting(enabled: false, locked: false)
        lock.didLeave()
        lock.setAwaySinceForTesting(Date().addingTimeInterval(-3600))
        lock.didReturn()
        #expect(!lock.isLocked)
        lock.setPrivacyCover(true)
        #expect(!lock.hidesContent)
    }

    @Test func privacyCoverHidesContentOnlyWhenOn() {
        defer { reset() }
        lock.setStateForTesting(enabled: true, locked: false)
        lock.setPrivacyCover(true)
        #expect(lock.hidesContent)
        #expect(!lock.isLocked)
        lock.setPrivacyCover(false)
        #expect(!lock.hidesContent)
    }
}
