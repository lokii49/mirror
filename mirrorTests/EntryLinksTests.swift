import Foundation
import SwiftData
import Testing
@testable import mirror

/// Links between entries: mirror://entry/<id> inline links and the backlinks they make.
@Suite("Entry links")
@MainActor
struct EntryLinksTests {
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        containers.all.append(container)
        container.mainContext.autosaveEnabled = false
        return container.mainContext
    }

    private func link(to id: UUID, at location: Int = 0, length: Int = 4) -> Data {
        let range = InlineStyleRange(location: location, length: length, bold: false, italic: false, underline: false,
                                     strikethrough: false, highlightIndex: nil, linkURL: EntryLinks.urlString(for: id))
        return try! JSONEncoder().encode(InlineStyleDocument(ranges: [range]))
    }

    @Test func entryURLsParseAndValidate() {
        let id = UUID()
        let string = EntryLinks.urlString(for: id)
        #expect(EntryLinks.entryID(from: string) == id)
        #expect(validatedLinkURL(from: string)?.absoluteString == string)
        // Only mirror://entry/<uuid> on that scheme; web links still work as before.
        #expect(validatedLinkURL(from: "mirror://entry/not-a-uuid") == nil)
        #expect(validatedLinkURL(from: "mirror://write") == nil)
        #expect(validatedLinkURL(from: "mirror://entry/\(id.uuidString)/extra") == nil)
        #expect(validatedLinkURL(from: "example.com")?.absoluteString == "https://example.com")
        #expect(validatedLinkURL(from: "javascript:alert(1)") == nil)
        #expect(EntryLinks.entryID(from: "https://example.com/entry/\(id.uuidString)") == nil)
    }

    @Test func backlinksAreOnlyAuthoredLinks() throws {
        let context = try context()
        let target = Entry(text: "Synthetic target entry")
        let linking = Entry(text: "See that day for more.")
        linking.inlineStyleData = link(to: target.id)
        let mentioning = Entry(text: "Synthetic target entry mentioned by words, not linked.")
        let elsewhere = Entry(text: "Links somewhere else.")
        elsewhere.inlineStyleData = link(to: UUID())
        [target, linking, mentioning, elsewhere].forEach(context.insert)
        try context.save()
        let links = EntryLinks.cachedBacklinks(to: target.id, in: context)
        #expect(links.map(\.id) == [linking.id])
        #expect(links.first?.title == "See that day for more.")
        #expect(EntryLinks.cachedBacklinks(to: linking.id, in: context).isEmpty, "a link isn't its own backlink")

        // A new link shows once the journal revision moves (the app's saves move it).
        let later = Entry(text: "Another synthetic link.")
        later.createdAt = linking.createdAt.addingTimeInterval(60)
        later.inlineStyleData = link(to: target.id)
        context.insert(later)
        try context.save()
        JournalRevision.shared.bump(settle: false)
        #expect(EntryLinks.cachedBacklinks(to: target.id, in: context).map(\.id) == [later.id, linking.id], "newest first")
    }

    @Test func titleSkipsBlankLinesAndPhotoTokens() {
        let entry = Entry(text: "\n  \n[[mirror-photo-0]]Morning walk\nMore")
        #expect(EntryLinks.title(of: entry) == "Morning walk")
        #expect(EntryLinks.title(of: Entry(text: "   ")) == String(localized: "Untitled entry"))
    }
}
