import Testing
import SwiftData
import Foundation
@testable import mirror

// Backlog A3: with the content key unreadable, sealing used to fail open (plaintext strings, nil
// data saved as a deleted photo or recording). Writers now check `MirrorEncryption.canEncrypt`
// first, and data setters keep what was stored. `sealFailsForTesting` breaks sealing only, so
// entries still decrypt and the gates are what stops the writes. Synthetic text only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct SealUnavailableTests {
        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: Entry.self, Insight.self, configurations: config)
            return ModelContext(container)
        }

        private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 3, count: 60))
        private static let otherJpeg = Data([0xFF, 0xD8, 0xFF, 0xE1] + Array(repeating: 4, count: 60))

        @Test func canEncryptFollowsTheSeam() {
            _ = Entry(text: "Make sure a key exists in this process.")
            #expect(MirrorEncryption.canEncrypt(creatingIfNeeded: false))
            MirrorEncryption.$sealFailsForTesting.withValue(true) {
                #expect(!MirrorEncryption.canEncrypt(creatingIfNeeded: false))
                #expect(!MirrorEncryption.canEncrypt(creatingIfNeeded: true))
            }
        }

        @Test func dataSettersKeepTheStoredCiphertextWhenSealingFails() {
            let entry = Entry(text: "")
            entry.photoData = Self.jpeg
            entry.voiceNoteData = Self.jpeg
            entry.additionalPhotoData = [Self.jpeg]
            let photo = entry.encryptedPhotoData
            let voice = entry.encryptedVoiceNoteData
            let more = entry.encryptedAdditionalPhotoDataStorage
            #expect(photo != nil && photo != Self.jpeg)

            MirrorEncryption.$sealFailsForTesting.withValue(true) {
                entry.photoData = Self.otherJpeg
                entry.voiceNoteData = Self.otherJpeg
                entry.additionalPhotoData = [Self.otherJpeg]
            }
            // Before: nil (a deleted photo/recording) or the plaintext bytes.
            #expect(entry.encryptedPhotoData == photo)
            #expect(entry.encryptedVoiceNoteData == voice)
            #expect(entry.encryptedAdditionalPhotoDataStorage == more)
            #expect(entry.photoData == Self.jpeg)
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func dailyRunnerWritesNothingWhenSealingFails() async throws {
            let key = mirrorApp.fallbackRetrySignatureKey
            UserDefaults.standard.removeObject(forKey: key); defer { UserDefaults.standard.removeObject(forKey: key) }
            let context = try makeContext()
            let start = Calendar.current.startOfDay(for: Date())
            for (i, text) in [
                "Long walk around the lake with Bruno after work, the light was gold on the water.",
                "Finally fixed the dashboard bug with Omar, it was in the date parsing all along.",
                "Called Anu tonight, first time in weeks, and we talked for almost an hour.",
            ].enumerated() {
                let e = Entry(text: text, mood: "Content")
                e.createdAt = start.addingTimeInterval(Double(i + 1) * 60)
                context.insert(e)
            }
            try context.save()
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in
                calls += 1
                return ("The rain outside feels heavy tonight, doesn't it?", .foundationModels)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            await MirrorEncryption.$sealFailsForTesting.withValue(true) {
                await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            }
            #expect(calls == 0, "no generation when its result couldn't be sealed")
            #expect(try context.fetch(FetchDescriptor<Insight>()).isEmpty)
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func moodDetectionWritesNothingWhenSealingFails() async throws {
            let context = try makeContext()
            let e = Entry(text: "Could not sleep, kept going over the interview questions until three.", mood: nil)
            context.insert(e)
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in ("Anxious", .gemma) }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            let detection = MirrorEncryption.$sealFailsForTesting.withValue(true) {
                MoodAutoDetector.shared.detectIfNeeded(e, context: context)
            }
            #expect(detection == nil)
            #expect(e.encryptedMood == nil)
        }
    }
}
