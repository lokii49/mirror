import Testing
@testable import mirror

// Promotional entitlements are granted to this exact string in the RevenueCat dashboard. If the
// format ever changes, every user moves to a new customer and loses what was granted.
@Suite("RevenueCat app user ID from iCloud")
struct RevenueCatIdentityTests {
    @Test func idIsPrefixedSHA256OfRecordName() {
        #expect(RevenueCatIdentity.appUserID(forRecordName: "_abc123recordName")
            == "icloud_2681d4bea6d7c4d267956abdc46877e287eb94c70c9771c170d1e93e11889976")
    }

    @Test func differentAccountsGetDifferentIDs() {
        #expect(RevenueCatIdentity.appUserID(forRecordName: "_a")
            != RevenueCatIdentity.appUserID(forRecordName: "_b"))
    }
}
