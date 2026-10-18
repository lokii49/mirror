import Foundation
import SwiftData

/// Entries saved twice: the same text after trimming and collapsing whitespace, on any date.
/// Nothing is merged automatically; the Duplicates screen shows each group with its dates and
/// merges one group at a time.
enum EntryDuplicates {
    /// Shorter texts never count: "Tired." on five different days is five entries, not one.
    static let minimumWords = 5

    struct Candidate: Equatable {
        let id: UUID
        let text: String
        let createdAt: Date
    }

    /// The comparison key, or nil when the text is too short to call a duplicate.
    static func key(for text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= minimumWords else { return nil }
        return words.joined(separator: " ")
    }

    /// Groups of two or more, each oldest first; groups ordered by their newest entry, newest first.
    static func groups(_ candidates: [Candidate]) -> [[Candidate]] {
        var byKey: [String: [Candidate]] = [:]
        for candidate in candidates {
            guard let key = key(for: candidate.text) else { continue }
            byKey[key, default: []].append(candidate)
        }
        return byKey.values
            .filter { $0.count > 1 }
            .map { $0.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } }
            .sorted { ($0.last?.createdAt ?? .distantPast) > ($1.last?.createdAt ?? .distantPast) }
    }

    /// Readable entries only: an entry this device can't decrypt (or voice-only, with no text)
    /// must never match another one.
    @MainActor
    static func candidates(in context: ModelContext) -> [Candidate] {
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        return entries.compactMap { entry in
            guard !entry.textDecryptionFailed, let text = entry.decryptedText,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Candidate(id: entry.id, text: text, createdAt: entry.createdAt)
        }
    }

    /// Whether the group's entries were written on more than one calendar day.
    static func spansSeveralDays(_ group: [Candidate], calendar: Calendar = .current) -> Bool {
        Set(group.map { calendar.startOfDay(for: $0.createdAt) }).count > 1
    }

    /// When a saved entry already has this exact text (5+ words), the oldest one's date. Only
    /// entries with the same stored word count (plaintext, no decrypt) are opened, so a save
    /// decrypts a handful of entries, not the journal.
    @MainActor
    static func existingCopy(of text: String, in context: ModelContext) -> Date? {
        guard let wanted = key(for: text) else { return nil }
        let words = strippedWordCount(text)
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.wordCount == words },
                                                sortBy: [SortDescriptor(\.createdAt)])
        let sameLength = (try? context.fetch(descriptor)) ?? []
        return sameLength.first { entry in
            entry.decryptedText.flatMap(key(for:)) == wanted
        }?.createdAt
    }

    enum MergeError: Error { case unreadable, cannotEncrypt }

    /// Keeps the oldest entry and moves the others to Recently Deleted (restorable for 30 days).
    /// The kept entry gains the others' tags and voice notes it doesn't already have, their mood
    /// if it has none, and their photos if it has none (photos are placed by index in the text,
    /// which is the same in every copy). Nothing is written when any entry can't be read.
    @MainActor
    @discardableResult
    static func merge(_ ids: [UUID], in context: ModelContext) throws -> UUID? {
        let wanted = Set(ids)
        let entries = ((try? context.fetch(FetchDescriptor<Entry>())) ?? [])
            .filter { wanted.contains($0.id) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        guard let keep = entries.first, entries.count > 1 else { return entries.first?.id }
        guard !entries.contains(where: \.contentDecryptionFailed) else { throw MergeError.unreadable }
        guard MirrorEncryption.canEncrypt(creatingIfNeeded: true) else { throw MergeError.cannotEncrypt }
        let others = Array(entries.dropFirst())

        var tags = keep.tags
        for tag in others.flatMap(\.tags) where !tags.contains(tag) { tags.append(tag) }
        if tags != keep.tags { keep.tags = tags }

        if keep.mood == nil, let mood = others.compactMap(\.mood).first { keep.mood = mood }

        if !keep.hasPhoto, let photos = others.map(\.photoDataArray).first(where: { !$0.isEmpty }) {
            keep.photoDataArray = photos
        }

        var notes = keep.voiceNotes
        let missing = others.flatMap(\.voiceNotes).filter { note in !notes.contains { $0.data == note.data } }
        if !missing.isEmpty {
            notes.append(contentsOf: missing)
            if keep.voiceNoteData == nil, let first = notes.first {
                keep.voiceNoteData = first.data
                keep.voiceNoteDuration = first.duration
                keep.voiceNoteTranscript = first.transcript
                keep.voiceNoteLanguageCode = first.languageCode
                keep.voiceNoteLanguageName = first.languageName
                keep.voiceNoteEnglishTranslation = first.englishTranslation
            }
            let rest = notes.dropFirst()
            keep.additionalVoiceNoteData = rest.map(\.data)
            keep.additionalVoiceNoteDurations = rest.map(\.duration)
            keep.additionalVoiceNoteTranscripts = rest.map { $0.transcript ?? "" }
            keep.additionalVoiceNoteLanguageCodes = rest.map { $0.languageCode ?? "" }
            keep.additionalVoiceNoteLanguageNames = rest.map { $0.languageName ?? "" }
            keep.additionalVoiceNoteEnglishTranslations = rest.map { $0.englishTranslation ?? "" }
        }
        if keep.collectionID == nil { keep.collectionID = others.compactMap(\.collectionID).first }
        if !keep.isPinned, others.contains(where: \.isPinned) { keep.isPinned = true }

        // One save for the kept entry's changes and the move to Recently Deleted.
        try EntryTrash.moveToTrash(others, in: context, announce: false)
        return keep.id
    }
}
