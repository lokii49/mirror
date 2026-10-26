import Testing
import CloudKit
import Foundation
@testable import mirror

/// The iCloud banner's wording comes from the last upload error (`ExportError`).
struct ExportErrorTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func ck(_ code: CKError.Code) -> ExportError.Code {
        ExportError.Code(domain: CKError.errorDomain, code: code.rawValue)
    }

    /// A partial failure's own code only says "some records failed"; the record's error says why.
    @Test func partialFailureUsesTheRecordError() {
        let inner = NSError(domain: CKError.errorDomain, code: CKError.Code.invalidArguments.rawValue)
        let outer = NSError(domain: CKError.errorDomain, code: CKError.Code.partialFailure.rawValue,
                            userInfo: [CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "x"): inner]])
        #expect(ExportError.Code(outer) == ck(.invalidArguments))
        #expect(ExportError.Code(nil) == nil)
    }

    /// Core Data can wrap the CloudKit error; a full iCloud must still read as full.
    @Test func wrappedCloudKitErrorIsUnwrapped() {
        let quota = NSError(domain: CKError.errorDomain, code: CKError.Code.quotaExceeded.rawValue)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134400, userInfo: [NSUnderlyingErrorKey: quota])
        let code = ExportError.Code(wrapped)
        #expect(code == ck(.quotaExceeded))
        #expect(ExportError(failure: code ?? .unknown, since: start).isQuotaExceeded)
    }

    /// A record that failed only because its batch did isn't the cause.
    @Test func partialFailurePrefersTheCauseOverBatchSideEffects() {
        let records: [AnyHashable: Error] = [
            CKRecord.ID(recordName: "a"): NSError(domain: CKError.errorDomain, code: CKError.Code.batchRequestFailed.rawValue),
            CKRecord.ID(recordName: "b"): NSError(domain: CKError.errorDomain, code: CKError.Code.quotaExceeded.rawValue),
        ]
        let outer = NSError(domain: CKError.errorDomain, code: CKError.Code.partialFailure.rawValue,
                            userInfo: [CKPartialErrorsByItemIDKey: records])
        #expect(ExportError.Code(outer) == ck(.quotaExceeded))
    }

    @Test func sameErrorKeepsItsStartAndBecomesStuck() {
        let first = ExportError.next(after: nil, failure: ck(.invalidArguments), now: start)
        let later = ExportError.next(after: first, failure: ck(.invalidArguments), now: start.addingTimeInterval(3600))
        #expect(later.since == start)
        #expect(!later.isStuck(now: start.addingTimeInterval(ExportError.stuckAfter - 1)))
        #expect(later.isStuck(now: start.addingTimeInterval(ExportError.stuckAfter)))
        #expect(later.label == "CKError 12")
    }

    @Test func aDifferentErrorStartsOver() {
        let first = ExportError.next(after: nil, failure: ck(.invalidArguments), now: start)
        let other = ExportError.next(after: first, failure: ck(.serverRejectedRequest), now: start.addingTimeInterval(7200))
        #expect(other.since == start.addingTimeInterval(7200))
    }

    /// Offline and a full iCloud never read as "waiting won't fix it".
    @Test func networkAndQuotaAreNeverStuck() {
        let later = start.addingTimeInterval(48 * 3600)
        for code in [CKError.Code.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy] {
            #expect(!ExportError(failure: ck(code), since: start).isStuck(now: later))
        }
        let url = ExportError(failure: .init(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), since: start)
        #expect(!url.isStuck(now: later))
        let full = ExportError(failure: ck(.quotaExceeded), since: start)
        #expect(full.isQuotaExceeded)
        #expect(!full.isStuck(now: later))
    }

    @Test func survivesEncoding() throws {
        let error = ExportError(failure: .init(domain: NSCocoaErrorDomain, code: 134400), since: start)
        let decoded = try JSONDecoder().decode(ExportError.self, from: JSONEncoder().encode(error))
        #expect(decoded == error)
        #expect(decoded.label == "CoreData 134400")
    }
}
