import Testing
import Foundation
import SwiftData
@testable import mirror

@Suite("MirrorModelContainer.open")
struct MirrorModelContainerTests {
    @Test @MainActor func failingConfigurationYieldsErrorAndInMemoryStandIn() {
        let bad = ModelConfiguration(
            schema: MirrorModelContainer.schema,
            url: URL(fileURLWithPath: "/nonexistent-dir/mirror-test.store"),
            cloudKitDatabase: .none
        )
        let outcome = MirrorModelContainer.open(bad)
        #expect(outcome.openError != nil)
        // The stand-in works but is empty and not the failed store.
        let count = (try? outcome.container.mainContext.fetchCount(FetchDescriptor<Entry>())) ?? -1
        #expect(count == 0)
    }

    @Test func workingConfigurationHasNoError() {
        let ok = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        #expect(MirrorModelContainer.open(ok).openError == nil)
    }
}
