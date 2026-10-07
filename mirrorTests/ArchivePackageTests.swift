import Foundation
import SwiftData
import Testing
@testable import mirror

/// Synthetic journal text only.
@Suite("Archive package export and import")
@MainActor
struct ArchivePackageTests {
    /// A context is only valid while its container lives; keep them for the test's duration.
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func container() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Entry.self, configurations: config)
        containers.all.append(container)
        return container
    }

    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 7, count: 40))
    private static let m4a = Data([0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70] + Array(repeating: 3, count: 40))

    private func richEntry(in context: ModelContext, text: String = "Café walk — \"quoted\" line\nSecond paragraph") -> Entry {
        let entry = Entry(text: NoteEditorCodec.appendingPhotoTokens(to: text, count: 1), mood: "Calm")
        entry.createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        entry.tags = ["walk", "tag: with \"quotes\""]
        entry.isPinned = true
        entry.fontChoice = "serif"
        entry.textStyleData = Data("{\"paragraphStyles\":[]}".utf8)
        entry.inlineStyleData = Data("{\"ranges\":[]}".utf8)
        entry.photoDataArray = [Self.jpeg, Self.jpeg + Data([1])]
        entry.voiceNoteData = Self.m4a
        entry.voiceNoteDuration = 12
        entry.voiceNoteTranscript = "Synthetisches Transkript"
        entry.voiceNoteLanguageCode = "de"
        entry.voiceNoteLanguageName = "German"
        entry.voiceNoteEnglishTranslation = "Synthetic transcript"
        entry.additionalVoiceNoteData = [Self.m4a + Data([2])]
        entry.additionalVoiceNoteDurations = [4]
        entry.additionalVoiceNoteTranscripts = ["Second note"]
        entry.additionalVoiceNoteLanguageCodes = [""]
        entry.additionalVoiceNoteLanguageNames = [""]
        entry.additionalVoiceNoteEnglishTranslations = [""]
        context.insert(entry)
        return entry
    }

    private func writePackage(_ entries: [ArchivePackage.ArchiveEntry], unreadable: [ArchivePackage.Unreadable] = []) throws -> URL {
        let root = try ArchivePackage.makeStagingDirectory(named: "Test Export")
        var records: [ArchivePackage.Manifest.EntryRecord] = []
        for entry in entries {
            records.append(try ArchivePackage.write(entry, to: root, exportTimeZone: TimeZone(identifier: "Asia/Tokyo")!))
        }
        try ArchivePackage.writeManifest(records: records, unreadable: unreadable, to: root, appVersion: "test",
                                         exportedAt: Date(), timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        return root
    }

    @Test func roundTripPreservesEverything() async throws {
        let source = try container().mainContext
        let original = try #require(richEntry(in: source).archiveSnapshot())
        let root = try writePackage([original])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let read = try ArchivePackage.read(from: root)
        #expect(read.entries == [original])

        let target = try container().mainContext
        let plan = try await ArchiveTransfer.planImport(folder: root, existing: [])
        #expect(plan.new.count == 1)
        _ = try ArchiveTransfer.applyImport(plan, importChangedAsCopies: false, context: target)
        let imported = try #require(try target.fetch(FetchDescriptor<Entry>()).first)
        #expect(imported.archiveSnapshot() == original)
    }

    @Test func markdownHasEscapedFrontMatterAndLinkedMedia() throws {
        let original = try #require(richEntry(in: try container().mainContext).archiveSnapshot())
        let root = try writePackage([original])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let path = root.appendingPathComponent("entries/\(ArchivePackage.fileName(for: original))")
        let markdown = try String(contentsOf: path, encoding: .utf8)
        #expect(markdown.hasPrefix("---\nid: \""))
        #expect(markdown.contains(#"tags: ["walk", "tag: with \"quotes\""]"#))
        #expect(markdown.contains("exported_timezone: \"Asia/Tokyo\""))
        #expect(markdown.contains("![Photo 1](../attachments/"))
        #expect(markdown.contains("photo-2.jpg"))   // photo without an inline token still listed
        #expect(markdown.contains("Transcript (German):\n> Synthetisches Transkript"))
        #expect(markdown.contains("English translation:\n> Synthetic transcript"))
        #expect(!ArchivePackage.fileName(for: original).contains(":"))
    }

    @Test func importingTheSamePackageTwiceAddsNothing() async throws {
        let context = try container().mainContext
        let entry = richEntry(in: context)
        try context.save()
        let root = try writePackage([try #require(entry.archiveSnapshot())])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let plan = try await ArchiveTransfer.planImport(folder: root, existing: try context.fetch(FetchDescriptor<Entry>()))
        #expect(plan.new.isEmpty && plan.changed.isEmpty && plan.identical == 1)
    }

    @Test func changedEntriesAreNeverOverwrittenOnlyCopied() async throws {
        let context = try container().mainContext
        let entry = richEntry(in: context)
        try context.save()
        var packaged = try #require(entry.archiveSnapshot())
        packaged.text = "A different synthetic version."
        let root = try writePackage([packaged])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let plan = try await ArchiveTransfer.planImport(folder: root, existing: try context.fetch(FetchDescriptor<Entry>()))
        #expect(plan.changed.count == 1)

        _ = try ArchiveTransfer.applyImport(plan, importChangedAsCopies: false, context: context)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
        let batch = try ArchiveTransfer.applyImport(plan, importChangedAsCopies: true, context: context)
        let all = try context.fetch(FetchDescriptor<Entry>())
        #expect(all.count == 2)
        #expect(all.contains { $0.id == entry.id && $0.text.hasPrefix("Café walk") })
        #expect(!batch.digests.keys.contains(entry.id))

        // Undo removes only what the import added.
        let undone = try ArchiveTransfer.undoImport(batch, context: context)
        #expect(undone.removed == 1 && undone.kept == 0)
        #expect(try context.fetch(FetchDescriptor<Entry>()).map(\.id) == [entry.id])
    }

    @Test func undoKeepsEntriesEditedAfterImport() async throws {
        let source = try container().mainContext
        let root = try writePackage([try #require(richEntry(in: source).archiveSnapshot())])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let context = try container().mainContext
        let batch = try ArchiveTransfer.applyImport(try await ArchiveTransfer.planImport(folder: root, existing: []),
                                                    importChangedAsCopies: false, context: context)
        try #require(try context.fetch(FetchDescriptor<Entry>()).first).text = "Edited after import."
        try context.save()
        let undone = try ArchiveTransfer.undoImport(batch, context: context)
        #expect(undone.removed == 0 && undone.kept == 1)
    }

    @Test(arguments: ["/etc/passwd", "../outside.jpg", "attachments/../../x", "attachments//x", "./x", "a\\b"])
    func unsafePathsAreRejected(_ path: String) throws {
        let root = try ArchivePackage.makeStagingDirectory(named: "Unsafe")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        #expect(throws: ArchivePackage.PackageError.unsafePath) { try ArchivePackage.resolve(path, in: root) }
    }

    @Test func symlinkedAttachmentIsRejected() throws {
        let original = try #require(richEntry(in: try container().mainContext).archiveSnapshot())
        let root = try writePackage([original])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let photo = root.appendingPathComponent("attachments/\(original.id.uuidString.lowercased())/photo-1.jpg")
        try FileManager.default.removeItem(at: photo)
        try FileManager.default.createSymbolicLink(at: photo, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        #expect(throws: (any Error).self) { try ArchivePackage.read(from: root) }
    }

    @Test func tamperedAndOversizedPackagesFail() throws {
        let original = try #require(richEntry(in: try container().mainContext).archiveSnapshot())
        let root = try writePackage([original])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        var tiny = ArchivePackage.Limits()
        tiny.maxTotalBytes = 10
        #expect(throws: ArchivePackage.PackageError.tooLarge) { try ArchivePackage.read(from: root, limits: tiny) }
        let photo = root.appendingPathComponent("attachments/\(original.id.uuidString.lowercased())/photo-1.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0x00]).write(to: photo)
        #expect(throws: ArchivePackage.PackageError.checksumMismatch) { try ArchivePackage.read(from: root) }
    }

    @Test func unreadableEntriesAreListedNotWritten() async throws {
        let context = try container().mainContext
        let unreadable = Entry(text: "x")
        unreadable.encryptedText = "mirror:v1:" + Data(repeating: 9, count: 40).base64EncodedString()
        context.insert(unreadable)
        #expect(unreadable.archiveSnapshot() == nil)
        let result = try await ArchiveTransfer.exportArchive(entries: [unreadable, richEntry(in: context)], collections: []) { _ in }
        defer { ArchiveTransfer.discardExport(result.zipURL) }
        #expect(result.exported == 1 && result.unreadable == 1)
        #expect(FileManager.default.fileExists(atPath: result.zipURL.path))
        // Synthetic sample kept for inspecting the zip layout from the host.
        #if targetEnvironment(simulator)
        let sample = URL(fileURLWithPath: "/private/tmp/ArchivePackageTests-sample.zip")
        #else
        let sample = FileManager.default.temporaryDirectory.appendingPathComponent("ArchivePackageTests-sample.zip")
        #endif
        try? FileManager.default.removeItem(at: sample)
        try? FileManager.default.copyItem(at: result.zipURL, to: sample)
    }

    @Test func duplicateTimestampsGetDistinctFileNames() throws {
        let context = try container().mainContext
        let first = try #require(richEntry(in: context).archiveSnapshot())
        let second = try #require(richEntry(in: context).archiveSnapshot())
        #expect(first.createdAt == second.createdAt)
        #expect(ArchivePackage.fileName(for: first) != ArchivePackage.fileName(for: second))
    }

    @Test func yamlEscapesControlCharacters() {
        #expect(ArchivePackage.yamlString("a\"b\\c\nd\u{7}") == #""a\"b\\c\nd\u0007""#)
    }
}
