import Foundation
import SwiftData
import Testing
@testable import mirror

/// What the Apple Watch app sends, saved on the iPhone. Synthetic text only.
@Suite("Watch inbox", .serialized)
@MainActor
struct WatchInboxTests {
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        containers.all.append(container)
        container.mainContext.autosaveEnabled = false
        return container.mainContext
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "WatchInboxTests.\(UUID().uuidString)")! }

    @Test func payloadsParseAndBadOnesAreDropped() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)   // May 2026, in the past
        let mood = WatchInbox.item(from: ["id": "a", "kind": "mood", "value": "Grateful", "date": date.timeIntervalSince1970])
        #expect(mood == .init(id: "a", kind: .mood, value: "Grateful", date: date))
        #expect(WatchInbox.item(from: ["id": "b", "kind": "mood", "value": "Ecstatic", "date": 0.0]) == nil, "unknown mood")
        #expect(WatchInbox.item(from: ["id": "c", "kind": "note", "value": "   ", "date": 0.0]) == nil, "blank note")
        #expect(WatchInbox.item(from: ["kind": "note", "value": "x", "date": 0.0]) == nil, "no id")
        #expect(WatchInbox.item(from: ["id": "d", "kind": "photo", "value": "x", "date": 0.0]) == nil, "unknown kind")
        let future = WatchInbox.item(from: ["id": "e", "kind": "note", "value": "x", "date": Date().addingTimeInterval(86_400).timeIntervalSince1970])
        #expect((future?.date ?? .distantFuture) <= Date(), "never dated in the future")
    }

    @Test func aMoodBecomesACheckInAndANoteAnEntry() throws {
        let context = try context()
        let d = defaults()
        let when = Date().addingTimeInterval(-3_600)
        #expect(WatchInbox.save(.init(id: "m2", kind: .mood, value: "Grateful", date: when), in: context, defaults: d))
        #expect(WatchInbox.save(.init(id: "n1", kind: .note, value: "Synthetic note from the watch.", date: when), in: context, defaults: d))
        let checkIns = try context.fetch(FetchDescriptor<MoodCheckIn>())
        #expect(checkIns.contains { $0.decryptedMood == "Grateful" && abs($0.createdAt.timeIntervalSince(when)) < 1 })
        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        #expect(entries.first?.text == "Synthetic note from the watch.")
        #expect(entries.first?.collectionID == nil, "Unfiled")
    }

    @Test func aRepeatDeliveryIsSavedOnce() throws {
        let context = try context()
        let d = defaults()
        let item = WatchInbox.Item(id: "same", kind: .note, value: "Synthetic once.", date: Date())
        #expect(WatchInbox.save(item, in: context, defaults: d))
        #expect(WatchInbox.save(item, in: context, defaults: d))
        #expect(try context.fetch(FetchDescriptor<Entry>()).count == 1)
    }

    /// Watch items that come while the journal key can't be read (the phone is locked) wait in
    /// the Keychain and are saved, in order, once it can.
    @Test func itemsWaitForTheKeyAndAreSavedInOrderLater() throws {
        let context = try context()
        let d = defaults()
        WatchInbox.$pendingAccount.withValue("WatchInboxTests.\(UUID().uuidString)") {
            defer { WatchInbox.erasePending() }
            let older = Date().addingTimeInterval(-600)
            MirrorEncryption.$sealFailsForTesting.withValue(true) {
                WatchInbox.receive(["id": "w1", "kind": "note", "value": "Synthetic first.", "date": older.timeIntervalSince1970], in: context, defaults: d)
                WatchInbox.receive(["id": "w2", "kind": "mood", "value": "Peaceful", "date": older.timeIntervalSince1970], in: context, defaults: d)
            }
            #expect(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).isEmpty, "nothing saved without the key")
            #expect(WatchInbox.waiting.map(\.id) == ["w1", "w2"])
            // A new item once the key is back goes after the ones that waited.
            WatchInbox.receive(["id": "w3", "kind": "note", "value": "Synthetic third.", "date": Date().timeIntervalSince1970], in: context, defaults: d)
            #expect(WatchInbox.waiting.isEmpty)
            #expect(d.stringArray(forKey: WatchInbox.handledKey) == ["w1", "w2", "w3"])
            #expect(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).count == 2)
            #expect(((try? context.fetch(FetchDescriptor<MoodCheckIn>())) ?? []).contains { $0.decryptedMood == "Peaceful" })
        }
    }

    @Test func aForegroundRetrySavesWhatWaitedAndEraseClearsIt() throws {
        let context = try context()
        let d = defaults()
        WatchInbox.$pendingAccount.withValue("WatchInboxTests.\(UUID().uuidString)") {
            defer { WatchInbox.erasePending() }
            MirrorEncryption.$sealFailsForTesting.withValue(true) {
                WatchInbox.receive(["id": "r1", "kind": "note", "value": "Synthetic waiting.", "date": Date().timeIntervalSince1970], in: context, defaults: d)
                WatchInbox.retryWaiting(in: context, defaults: d)
            }
            #expect(WatchInbox.waiting.count == 1, "still locked: still waiting")
            WatchInbox.retryWaiting(in: context, defaults: d)
            #expect(WatchInbox.waiting.isEmpty)
            #expect(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).map(\.text) == ["Synthetic waiting."])
            MirrorEncryption.$sealFailsForTesting.withValue(true) {
                WatchInbox.receive(["id": "r2", "kind": "note", "value": "Synthetic erased.", "date": Date().timeIntervalSince1970], in: context, defaults: d)
            }
            WatchInbox.erasePending()
            #expect(WatchInbox.waiting.isEmpty, "Delete Everything clears waiting items")
        }
    }

    // MARK: - Voice notes (build 43)

    /// Synthetic bytes stand in for audio: the inbox stores them; it doesn't decode them.
    private func voiceFile(_ id: String, bytes: [UInt8] = [1, 2, 3, 4, 5]) throws -> URL {
        let url = try #require(WatchInbox.voiceFileURL(id: id))
        try Data(bytes).write(to: url)
        return url
    }

    @Test func aVoiceNoteBecomesAVoiceEntryAndItsFileIsRemoved() throws {
        let context = try context()
        let d = defaults()
        let id = UUID().uuidString
        let file = try voiceFile(id)
        WatchInbox.$pendingAccount.withValue("WatchInboxTests.\(UUID().uuidString)") {
            defer { WatchInbox.erasePending() }
            WatchInbox.receiveVoice(id: id, date: Date().addingTimeInterval(-60), duration: 12.5, in: context, defaults: d)
            let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
            #expect(entries.count == 1)
            #expect(entries.first?.source == .voice)
            #expect(entries.first?.voiceNoteData == Data([1, 2, 3, 4, 5]), "stored encrypted, read back the same")
            #expect(entries.first?.voiceNoteDuration == 12.5)
            #expect(!FileManager.default.fileExists(atPath: file.path), "the waiting copy is deleted once saved")
            // A repeat delivery saves nothing and leaves no file behind.
            let again = try? voiceFile(id)
            WatchInbox.receiveVoice(id: id, date: Date(), duration: 12.5, in: context, defaults: d)
            #expect(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).count == 1)
            #expect(!FileManager.default.fileExists(atPath: again?.path ?? ""))
        }
    }

    @Test func aVoiceNoteWaitsForTheKeyWithItsAudio() throws {
        let context = try context()
        let d = defaults()
        let id = UUID().uuidString
        let file = try voiceFile(id)
        WatchInbox.$pendingAccount.withValue("WatchInboxTests.\(UUID().uuidString)") {
            defer { WatchInbox.erasePending() }
            MirrorEncryption.$sealFailsForTesting.withValue(true) {
                WatchInbox.receiveVoice(id: id, date: Date(), duration: 3, in: context, defaults: d)
            }
            #expect(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).isEmpty)
            #expect(WatchInbox.waiting.map(\.kind) == [.voice])
            #expect(FileManager.default.fileExists(atPath: file.path), "the audio waits with it")
            WatchInbox.retryWaiting(in: context, defaults: d)
            #expect(WatchInbox.waiting.isEmpty)
            #expect(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).first?.source == .voice)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    /// Audio copied in but never queued (the app stopped between the two) is queued again at
    /// start; audio of a note already saved is removed (audit, 2026-11-08).
    @Test func orphanedAudioIsQueuedAgainOrRemoved() throws {
        let d = defaults()
        let orphan = UUID().uuidString
        let saved = UUID().uuidString
        let orphanFile = try voiceFile(orphan)
        let savedFile = try voiceFile(saved)
        d.set([saved], forKey: WatchInbox.handledKey)
        WatchInbox.$pendingAccount.withValue("WatchInboxTests.\(UUID().uuidString)") {
            defer { WatchInbox.erasePending() }
            WatchInbox.adoptOrphanedVoiceFiles(defaults: d)
            #expect(WatchInbox.waiting.map(\.id) == [orphan])
            #expect(FileManager.default.fileExists(atPath: orphanFile.path))
            #expect(!FileManager.default.fileExists(atPath: savedFile.path))
            // Running again doesn't queue it twice.
            WatchInbox.adoptOrphanedVoiceFiles(defaults: d)
            #expect(WatchInbox.waiting.count == 1)
        }
    }

    /// Waiting audio stays out of device backups: it isn't sealed with the journal key yet.
    @Test func waitingAudioIsExcludedFromBackup() throws {
        let dir = try #require(WatchInbox.voiceDirectory)
        #expect(try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func voiceNotesOnlyArriveAsFilesAndEraseRemovesTheirAudio() throws {
        // A message naming a voice note is refused: only a file transfer may bring one.
        #expect(WatchInbox.item(from: ["id": "v1", "kind": "voice", "value": "../../x.m4a", "date": 0.0]) == nil)
        // Only a UUID becomes a file name.
        #expect(WatchInbox.voiceFileURL(id: "../escape") == nil)
        let file = try voiceFile(UUID().uuidString)
        WatchInbox.$pendingAccount.withValue("WatchInboxTests.\(UUID().uuidString)") {
            WatchInbox.erasePending()
        }
        #expect(!FileManager.default.fileExists(atPath: file.path), "Delete Everything removes waiting audio")
    }
}
