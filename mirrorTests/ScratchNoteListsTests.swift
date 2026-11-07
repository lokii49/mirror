import Foundation
import Testing
import UserNotifications
@testable import mirror

/// Scratch notes with checklists, numbered lists and a reminder (owner, 2026-11-07). Synthetic text.
@Suite("Scratch note lists and reminders")
struct ScratchNoteListsTests {
    private func styles(_ values: [NoteParagraphTextStyle]) throws -> Data {
        try JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: values, indentLevels: nil, fontChoices: nil))
    }
    private func decodedStyles(_ data: Data?) throws -> [NoteParagraphTextStyle]? {
        guard let data else { return nil }
        return try JSONDecoder().decode(NoteTextStyleDocument.self, from: data).paragraphStyles
    }

    @Test func blankLinesAroundAChecklistTakeTheirStylesWithThem() throws {
        let text = "\n\nMilk\nEggs\n1st thing\n\n"
        let data = try styles([.body, .body, .checklistUnchecked, .checklistChecked, .numberedList, .body, .body])
        let r = ScratchNotes.trimmed(text: text, textStyleData: data, inlineStyleData: nil)
        #expect(r.text == "Milk\nEggs\n1st thing")
        #expect(try decodedStyles(r.textStyleData) == [.checklistUnchecked, .checklistChecked, .numberedList])
    }

    @Test func aPlainNoteStaysPlain() throws {
        let r = ScratchNotes.trimmed(text: "  Gate code 4412.  ", textStyleData: try styles([.body]), inlineStyleData: nil)
        #expect(r.text == "Gate code 4412.")
        #expect(r.textStyleData == nil)
        #expect(ScratchNotes.trimmed(text: "\n \n", textStyleData: nil, inlineStyleData: nil).text.isEmpty)
    }

    @Test func inlineRangesMoveWithTheTrimmedFront() throws {
        let text = "\n\nCall Sam\n"
        let bold = InlineStyleRange(location: 2, length: 4, bold: true, italic: false, underline: false, strikethrough: false)
        let inline = try JSONEncoder().encode(InlineStyleDocument(ranges: [bold]))
        let r = ScratchNotes.trimmed(text: text, textStyleData: nil, inlineStyleData: inline)
        let ranges = try JSONDecoder().decode(InlineStyleDocument.self, from: try #require(r.inlineStyleData)).ranges
        #expect(ranges.count == 1)
        #expect((r.text as NSString).substring(with: NSRange(location: ranges[0].location, length: ranges[0].length)) == "Call")
    }

    @Test func theReminderNeverCarriesTheNotesWords() throws {
        let id = UUID()
        let when = Date(timeIntervalSince1970: 2_000_000_000)
        let request = ScratchReminders.request(for: id, at: when)
        #expect(request.identifier == ScratchReminders.identifier(for: id))
        #expect(ScratchReminders.entryID(from: request) == id)
        #expect(!request.content.title.isEmpty && !request.content.body.isEmpty)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(Calendar.current.date(from: trigger.dateComponents) == Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)))
    }

    @Test func otherNotificationsAreNotReminders() {
        let content = UNMutableNotificationContent()
        content.userInfo = [ScratchReminders.entryIDKey: UUID().uuidString]
        let other = UNNotificationRequest(identifier: "mirror.moodCheckIn", content: content, trigger: nil)
        #expect(ScratchReminders.entryID(from: other) == nil)
    }

    @Test func theFirstTimeOfferedIsAWholeHourAtLeastHalfAnHourAway() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 9, minute: 40))!
        let offered = ScratchReminders.defaultTime(after: now, calendar: cal)
        #expect(cal.component(.hour, from: offered) == 11 && cal.component(.minute, from: offered) == 0)
        let early = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 9, minute: 10))!
        #expect(cal.component(.hour, from: ScratchReminders.defaultTime(after: early, calendar: cal)) == 10)
    }
}
