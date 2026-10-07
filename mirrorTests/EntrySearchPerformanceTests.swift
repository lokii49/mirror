import XCTest
import Foundation
@testable import mirror

final class EntrySearchPerformanceTests: XCTestCase {
    func testWarmSearchAtArchiveSizes() {
        for count in [500, 2_000, 5_000] {
            let documents = (0..<count).map { index in
                EntrySearchDocument(
                    passages: [.init(String(repeating: "A synthetic afternoon by the river. ", count: 12)
                                     + (index % 5 == 0 ? "Coffee at the library." : "Tea at home."), source: .body)],
                    tags: ["work"], moods: ["content"], createdAt: Date(), hasPhoto: index % 10 == 0,
                    hasAudio: false, isPinned: false, isReadable: true
                )
            }
            let query = EntrySearchQuery.parse("coffee river -meeting tag:work")
            var timings: [Double] = []
            for _ in 0..<10 {
                let start = CFAbsoluteTimeGetCurrent()
                let results = documents.filter { EntrySearch.matches($0, query: query) }
                for document in results { XCTAssertNotNil(EntrySearch.excerpt(document, query: query)) }
                timings.append((CFAbsoluteTimeGetCurrent() - start) * 1_000)
                XCTAssertEqual(results.count, count / 5)
            }
            let p95 = timings.sorted().last!
            print("[Archive search] count=\(count) warm filter+excerpts p95_ms=\(String(format: "%.1f", p95))")
            // This measures the pure search engine, not UI/debounce/CloudKit latency.
            XCTAssertLessThan(p95, 1_000, "Search engine unexpectedly exceeds one second")
        }
    }
}
