import Foundation
import SwiftData

enum EntrySource: String, Codable {
    case typed, voice
}

@Model final class Entry {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var wordCount: Int = 0
    var mood: String? = nil
    var source: EntrySource = EntrySource.typed
    var photoData: Data? = nil  // one photo, stored as data
    var voiceNoteData: Data? = nil
    var voiceNoteDuration: Double = 0
    var weekIdentifier: String = ""

    init(text: String, mood: String? = nil, source: EntrySource = .typed) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.wordCount = text.split(separator: " ").count
        self.mood = mood
        self.source = source
        self.photoData = nil
        self.voiceNoteData = nil
        self.voiceNoteDuration = 0
        self.weekIdentifier = DateHelpers.weekIdentifier(for: Date())
    }
}
