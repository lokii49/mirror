import Testing
import SwiftUI
import UIKit
@testable import mirror

/// Random sequences of the things a person does around photos (2026-11-15): add at the caret,
/// Backspace, type, Return, delete or paste over a selection, pick a size, Undo, Redo. After
/// every step the entry must still be well formed. Synthetic text only.
@MainActor
struct PhotoEditSequenceTests {
    private static let portrait: Data = UIGraphicsImageRenderer(size: CGSize(width: 70, height: 100)).image { ctx in
        UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 70, height: 100))
    }.pngData()!
    private static let landscape: Data = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60)).image { ctx in
        UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
    }.pngData()!

    private final class Store {
        var text: String
        var styles: Data?
        var inline: Data?
        var photos: [Data]
        init(text: String, styles: Data?, photos: [Data]) { self.text = text; self.styles = styles; self.photos = photos }
    }

    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private func harness(_ text: String, photos: [Data], styles: NoteTextStyleDocument? = nil) -> (NoteEditorTextView.Coordinator, UITextView, Store) {
        let store = Store(text: text, styles: styles.flatMap { try? JSONEncoder().encode($0) }, photos: photos)
        let editor = NoteEditorTextView(
            text: Binding(get: { store.text }, set: { store.text = $0 }),
            textStyleData: Binding(get: { store.styles }, set: { store.styles = $0 }),
            inlineStyleData: Binding(get: { store.inline }, set: { store.inline = $0 }),
            photoDataArray: Binding(get: { store.photos }, set: { store.photos = $0 }),
            command: .constant(nil), commandRevision: .constant(0), isFocused: .constant(false),
            activeParagraphStyle: .constant(.body), activeInlineStyles: .constant(InlineStyleSet()),
            showFormattingPanel: .constant(false), canUndo: .constant(false), canRedo: .constant(false),
            fontChoiceRaw: .constant(WritingFontChoice.system.rawValue), panelState: FormattingPanelState(),
            displayMode: .classic
        )
        let coordinator = editor.makeCoordinator()
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        textView.delegate = coordinator
        coordinator.applyStyledText(to: textView, preservingSelection: false)
        coordinator.noteOutsideChange(in: textView)
        return (coordinator, textView, store)
    }

    /// The keyboard's way: ask the delegate, apply when allowed.
    private func replace(_ range: NSRange, with replacement: String, in textView: UITextView, _ coordinator: NoteEditorTextView.Coordinator) {
        textView.selectedRange = range.length == 0 ? range : NSRange(location: NSMaxRange(range), length: 0)
        if range.length > 1 { textView.selectedRange = range }
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: replacement) {
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            textView.selectedRange = NSRange(location: range.location + (replacement as NSString).length, length: 0)
            coordinator.textViewDidChange(textView)
        }
    }

    /// A caret can't sit inside a list marker ("○  ", "1.\t"…): a place inside one moves to the
    /// end of it, as a tap does. (Edits inside markers are the list code's, not covered here.)
    private func snapped(_ location: Int, in textView: UITextView) -> Int {
        let ns = textView.text as NSString
        let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        let text = ns.substring(with: line)
        guard let marker = text.range(of: #"^(\s*)(○  |✓  |•  |–  |\d+\.\t)"#, options: .regularExpression) else { return location }
        let end = line.location + NSRange(marker, in: text).length
        return location >= line.location && location < end ? end : location
    }

    private func outsideChange(_ textView: UITextView, _ coordinator: NoteEditorTextView.Coordinator) {
        coordinator.didReceiveParent()
        coordinator.applyStyledText(to: textView, preservingSelection: true)
        coordinator.noteOutsideChange(in: textView)
    }

    private func placements(_ store: Store) -> [PhotoPlacement] {
        let photos = store.photos
        return PhotoPlacement.placements(text: store.text, inlineStyleData: store.inline, hasPicture: { $0 < photos.count },
                                         isLandscape: { $0 < photos.count && PhotoRuns.isLandscape(photos[$0]) })
    }

    private func drawnTiles(_ textView: UITextView) -> [Bool] {
        var result: [Bool] = []
        textView.attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textView.attributedText.length)) { value, _, _ in
            if let photo = value as? PhotoAttachment { result.append(photo.isTile) }
        }
        return result
    }

    /// What must hold after every step. Returns the first thing that doesn't.
    private func problem(_ store: Store, _ textView: UITextView) -> String? {
        let tokens = allPhotoTokens(in: store.text)
        if tokens.count != store.photos.count { return "\(tokens.count) tokens for \(store.photos.count) photos" }
        if Set(tokens.map(\.index)) != Set(0..<store.photos.count) { return "token numbers \(tokens.map(\.index).sorted())" }
        for line in store.text.components(separatedBy: "\n") {
            let inLine = allPhotoTokens(in: line)
            if inLine.count > 1 { return "two photos on one line: \(line)" }
            if let token = inLine.first, line.trimmingCharacters(in: .whitespaces) != String(line[token.range]) {
                return "a photo shares its line: \(line)"
            }
        }
        let rule = placements(store).map(\.isTile)
        let drawn = drawnTiles(textView)
        if rule != drawn { return "drawn \(drawn) but the rule says \(rule)" }
        let sizes = PhotoSizes.storedSizes(text: store.text, inlineStyleData: store.inline)
        if !Set(sizes.keys).isSubset(of: Set(0..<store.photos.count)) { return "a size on no photo: \(sizes)" }
        let known: Set<String> = [PhotoSizes.thumbnail, "small", "medium", "full"]
        if !Set(sizes.values).isSubset(of: known) { return "unknown size \(sizes)" }
        let attachments = (textView.text as NSString).components(separatedBy: "\u{FFFC}").count - 1
        if attachments != store.photos.count { return "\(attachments) attachment characters for \(store.photos.count) photos" }
        return nil
    }

    private func run(seed: UInt64, steps: Int, start: String, photos: [Data], styles: NoteTextStyleDocument? = nil) -> String? {
        var rng = Generator(state: seed)
        let (coordinator, textView, store) = harness(start, photos: photos, styles: styles)
        if let p = problem(store, textView) { return "seed \(seed) at start: \(p)" }
        var log: [String] = []
        var clipboard: PhotoFragment?
        for step in 0..<steps {
            let length = (textView.text as NSString).length
            let at = snapped(Int.random(in: 0...length, using: &rng), in: textView)
            let shownBefore = textView.text.replacingOccurrences(of: "\u{FFFC}", with: "¤").debugDescription
            let textBefore = store.text.debugDescription
            switch Int.random(in: 0..<15, using: &rng) {
            case 12, 13:
                // Copy or Cut a selection with photos in it (the codec, not the system clipboard).
                guard length > 1 else { continue }
                let from = snapped(Int.random(in: 0..<length, using: &rng), in: textView)
                let to = snapped(min(length, from + Int.random(in: 1...8, using: &rng)), in: textView)
                guard to > from, let fragment = coordinator.photoFragment(in: NSRange(location: from, length: to - from), of: textView),
                      let data = fragment.encoded(), let decoded = PhotoFragment.decoded(data) else { continue }
                clipboard = decoded
                if Bool.random(using: &rng) {
                    log.append("cut \(from)+\(to - from)")
                    coordinator.applyAsKeyboardEdit(NSRange(location: from, length: to - from), "", in: textView)
                } else {
                    log.append("copy \(from)+\(to - from)")
                }
            case 14:
                guard let fragment = clipboard, store.photos.count + fragment.photos.count <= 8 else { continue }
                // Paste: a selection gives way, then the lines go in under the caret's paragraph.
                let selection = NSRange(location: at, length: min(Int.random(in: 0...3, using: &rng), length - at))
                if selection.length > 0 { coordinator.applyAsKeyboardEdit(selection, "", in: textView) }
                let shown = textView.text as NSString
                let paragraph = shown.substring(to: min(textView.selectedRange.location, shown.length)).components(separatedBy: "\n").count - 1
                let count = store.photos.count
                let photos = store.photos + fragment.photos
                let result = fragment.inserted(into: store.text, afterParagraph: paragraph, textStyleData: store.styles, inlineStyleData: store.inline,
                                               photoCount: count, entryFont: "system", hasPicture: { $0 < photos.count },
                                               isLandscape: { $0 < photos.count && PhotoRuns.isLandscape(photos[$0]) })
                store.photos = photos
                store.text = result.text; store.styles = result.textStyleData; store.inline = result.inlineStyleData
                log.append("paste \(fragment.lines.count) lines after paragraph \(paragraph)")
                outsideChange(textView, coordinator)
            case 0, 1:
                let letter = ["a", "b", " ", "\n"].randomElement(using: &rng)!
                log.append("type \(letter.debugDescription)@\(at)")
                replace(NSRange(location: at, length: 0), with: letter, in: textView, coordinator)
            case 2, 3, 4:
                guard at > 0 else { continue }
                log.append("backspace@\(at)")
                replace(NSRange(location: at - 1, length: 1), with: "", in: textView, coordinator)
            case 5:
                guard length > 1 else { continue }
                let from = snapped(Int.random(in: 0..<length, using: &rng), in: textView)
                let to = snapped(min(length, from + Int.random(in: 1...4, using: &rng)), in: textView)
                guard to > from else { continue }
                let count = to - from
                let paste = ["", "", "xy", "x\ny", "x\u{FFFC}\ny"].randomElement(using: &rng)!
                log.append("replace \(from)+\(count) with \(paste.debugDescription)")
                replace(NSRange(location: from, length: count), with: paste, in: textView, coordinator)
            case 6, 7:
                guard store.photos.count < 8 else { continue }
                // The paperclip: the photo is appended, then its token goes in at the caret's paragraph.
                let paragraph = (textView.text as NSString).substring(to: at).components(separatedBy: "\n").count - 1
                let index = store.photos.count
                store.photos.append(Bool.random(using: &rng) ? Self.portrait : Self.landscape)
                let styles = store.styles.flatMap { try? JSONDecoder().decode(NoteTextStyleDocument.self, from: $0) }
                let inline = store.inline.flatMap { try? JSONDecoder().decode(InlineStyleDocument.self, from: $0) }?.ranges ?? []
                let result = SuggestionInsert().inserted(into: store.text, afterParagraph: paragraph, existingStyles: styles,
                                                         existingInline: inline, tokens: [inlinePhotoToken(at: index)], mapLeads: false, entryFont: "system")
                store.text = result.text
                if let styles = result.styles { store.styles = try? JSONEncoder().encode(styles) }
                store.inline = result.inline.isEmpty ? nil : try? JSONEncoder().encode(InlineStyleDocument(ranges: result.inline))
                log.append("add photo \(index) after paragraph \(paragraph)")
                outsideChange(textView, coordinator)
            case 8, 9:
                let all = placements(store)
                guard !all.isEmpty else { continue }
                let k = Int.random(in: 0..<all.count, using: &rng)
                let option = all[k].options.randomElement(using: &rng)!
                let offsets = PhotoSizes.inlineOffsets(in: store.text)
                store.inline = PhotoSizes.setting(stored: all[k].storedValue(for: option), atInlineOffset: offsets[k].offset, in: store.inline)
                log.append("size \(option.rawValue) on photo #\(k)")
                outsideChange(textView, coordinator)
            case 10:
                guard coordinator.canUndoEdit else { continue }
                log.append("undo")
                coordinator.undoEdit(in: textView)
                coordinator.noteOutsideChange(in: textView)
            default:
                guard coordinator.canRedoEdit else { continue }
                log.append("redo")
                coordinator.redoEdit(in: textView)
                coordinator.noteOutsideChange(in: textView)
            }
            // What `updateUIView` does after every change.
            coordinator.didReceiveParent()
            coordinator.noteOutsideChange(in: textView)
            if let p = problem(store, textView) {
                return "seed \(seed) step \(step): \(p)\n  text: \(store.text.debugDescription)\n  before the last step: \(textBefore) shown as \(shownBefore)\n  last steps: \(log.suffix(8).joined(separator: "; "))"
            }
        }
        return nil
    }

    private let p0 = inlinePhotoToken(at: 0), p1 = inlinePhotoToken(at: 1), p2 = inlinePhotoToken(at: 2)

    @Test func randomEditsKeepTheEntryWellFormed() {
        var failures: [String] = []
        for seed in 1...150 {
            if let failure = run(seed: UInt64(seed), steps: 60, start: "Day\n\(p0)\n\(p1)\n\nWords here\n\(p2)",
                                 photos: [Self.portrait, Self.portrait, Self.landscape]) {
                failures.append(failure)
                if failures.count == 3 { break }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func randomEditsFromAnEmptyEntry() {
        var failures: [String] = []
        for seed in 1000...1100 {
            if let failure = run(seed: UInt64(seed), steps: 60, start: "", photos: []) {
                failures.append(failure)
                if failures.count == 3 { break }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func randomEditsBesideListsAndHeadings() {
        let styles = NoteTextStyleDocument(
            paragraphStyles: [.heading, .body, .checklistUnchecked, .body, .numberedList, .numberedList, .body],
            indentLevels: nil, fontChoices: nil)
        var failures: [String] = []
        for seed in 5000...5100 {
            if let failure = run(seed: UInt64(seed), steps: 60, start: "Title\n\(p0)\nTask\n\(p1)\nOne\nTwo\n\(p2)",
                                 photos: [Self.portrait, Self.portrait, Self.portrait], styles: styles) {
                failures.append(failure)
                if failures.count == 3 { break }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // MARK: - Typing beside a photo next to a list or heading line

    private func styles(_ store: Store) -> [NoteParagraphTextStyle] {
        store.styles.flatMap { try? JSONDecoder().decode(NoteTextStyleDocument.self, from: $0) }?.paragraphStyles ?? []
    }

    private func photoIndex(_ textView: UITextView) -> Int { (textView.text as NSString).range(of: "\u{FFFC}").location }

    @Test func typingAfterAPhotoUnderAChecklistLineIsBody() {
        let (coordinator, textView, store) = harness("Task\n\(p0)", photos: [Self.portrait],
            styles: NoteTextStyleDocument(paragraphStyles: [.checklistUnchecked, .body], indentLevels: nil, fontChoices: nil))
        replace(NSRange(location: photoIndex(textView) + 1, length: 0), with: "a", in: textView, coordinator)
        #expect(store.text == "Task\n\(p0)\na")
        #expect(Array(styles(store).prefix(3)) == [.checklistUnchecked, .body, .body])
        #expect(problem(store, textView) == nil)
    }

    @Test func typingBeforeAPhotoUnderAHeadingIsBody() {
        let (coordinator, textView, store) = harness("Title\n\(p0)", photos: [Self.portrait],
            styles: NoteTextStyleDocument(paragraphStyles: [.heading, .body], indentLevels: nil, fontChoices: nil))
        replace(NSRange(location: photoIndex(textView), length: 0), with: "a", in: textView, coordinator)
        #expect(store.text == "Title\na\n\(p0)")
        #expect(Array(styles(store).prefix(3)) == [.heading, .body, .body])
        #expect(problem(store, textView) == nil)
    }

    @Test func typingAfterAPhotoAboveANumberedLineKeepsTheList() {
        let (coordinator, textView, store) = harness("\(p0)\nOne\nTwo", photos: [Self.portrait],
            styles: NoteTextStyleDocument(paragraphStyles: [.body, .numberedList, .numberedList], indentLevels: nil, fontChoices: nil))
        replace(NSRange(location: photoIndex(textView) + 1, length: 0), with: "a", in: textView, coordinator)
        #expect(store.text == "\(p0)\na\nOne\nTwo")
        #expect(Array(styles(store).prefix(4)) == [.body, .body, .numberedList, .numberedList])
        #expect(problem(store, textView) == nil)
    }
    /// Deleting a photo takes its paragraph's style with it: the lines under it keep theirs.
    @Test func deletingAPhotoKeepsTheStylesOfTheLinesUnderIt() {
        let (coordinator, textView, store) = harness("\(p0)\nTask\nPlain\n\(p1)\nOne", photos: [Self.portrait, Self.portrait],
            styles: NoteTextStyleDocument(paragraphStyles: [.body, .checklistUnchecked, .body, .body, .numberedList], indentLevels: nil, fontChoices: nil))
        replace(NSRange(location: 0, length: 1), with: "", in: textView, coordinator)   // photo 0
        #expect(store.text == "Task\nPlain\n\(p0)\nOne")
        #expect(Array(styles(store).prefix(4)) == [.checklistUnchecked, .body, .body, .numberedList])
        let second = (textView.text as NSString).range(of: "\u{FFFC}").location
        replace(NSRange(location: second, length: 1), with: "", in: textView, coordinator)   // the other photo
        #expect(store.text == "Task\nPlain\nOne")
        #expect(Array(styles(store).prefix(3)) == [.checklistUnchecked, .body, .numberedList])
    }
    /// Text copied together with a photo pastes the photo's placeholder character: it's dropped,
    /// so every such character in the editor is still a photo.
    @Test func pastedTextCarryingAPhotoCharacterDropsIt() {
        let (coordinator, textView, store) = harness("Day\n\(p0)\nEnd", photos: [Self.portrait])
        let end = (textView.text as NSString).length
        replace(NSRange(location: end, length: 0), with: " more\n\u{FFFC}\nwords", in: textView, coordinator)
        #expect(store.text == "Day\n\(p0)\nEnd more\n\nwords")
        #expect(problem(store, textView) == nil)
        replace(NSRange(location: 0, length: 3), with: "\u{FFFC}", in: textView, coordinator)   // over "Day"
        #expect(store.text == "\n\(p0)\nEnd more\n\nwords")
        #expect(problem(store, textView) == nil)
    }
}
