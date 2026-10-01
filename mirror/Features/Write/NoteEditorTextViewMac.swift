#if os(macOS)
import SwiftUI
import AppKit

// The Mac rich-text editor: an NSTextView whose text is the entry's logical text. Paragraph
// styles, indents and per-paragraph fonts live in custom attributes (see NoteEditorCodec) and
// list markers are drawn by `MirrorLayoutManager` in the left gutter, so the display text,
// the stored text and every stored offset are the same thing. iPhone and iPad read back exactly
// what this editor saves because both go through the same two JSON documents.
//
// Deliberately not supported here yet (entries with these stay read-only on Mac, see
// `NoteEditorCodec.canEditOnMac`): inline photos and the legacy "# " / "○ " prefix entries.
// List behaviors (Return continues or exits a list), indent and the checklist bulk commands
// are the next step.

// MARK: - Visual styling

enum MacEditorStyle {
    static let bodySize: CGFloat = 18
    /// Width reserved left of list text for the marker.
    static func gutter(for style: NoteParagraphTextStyle) -> CGFloat {
        style == .numberedList ? 24 : 28
    }
    static let indentStep: CGFloat = 20

    static func font(style: NoteParagraphTextStyle, choice: WritingFontChoice, bold: Bool, italic: Bool) -> NSFont {
        var size = bodySize
        var paragraphBold = false
        switch style {
        case .title: size = 28; paragraphBold = true
        case .heading: size = 22; paragraphBold = true
        case .subheading: paragraphBold = true
        default: break
        }

        var font: NSFont
        if style == .monospaced {
            font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        } else {
            let base = NSFont.systemFont(ofSize: size)
            if let descriptor = base.fontDescriptor.withDesign(choice.uiDesign), let designed = NSFont(descriptor: descriptor, size: size) {
                font = designed
            } else {
                font = base
            }
        }
        if bold || paragraphBold { font = font.withTrait(.traitBold, add: true) }
        if italic { font = font.withTrait(.traitItalic, add: true) }
        return font
    }

    static func foreground(style: NoteParagraphTextStyle) -> NSColor {
        switch style {
        case .subheading, .blockQuote: return .secondaryLabelColor
        case .checklistChecked: return .tertiaryLabelColor
        default: return .labelColor
        }
    }

    static func paragraphStyle(for model: NoteEditorCodec.ParagraphModel) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        let offset = CGFloat(model.indent) * indentStep
        switch model.style {
        case .title: ps.lineSpacing = 3; ps.paragraphSpacing = 10
        case .heading: ps.lineSpacing = 4; ps.paragraphSpacing = 8
        case .subheading: ps.lineSpacing = 4; ps.paragraphSpacing = 6
        case .monospaced: ps.lineSpacing = 8; ps.paragraphSpacing = 10
        case .blockQuote:
            ps.lineSpacing = 5; ps.paragraphSpacing = 8
            ps.firstLineHeadIndent = 16; ps.headIndent = 16
        case .checklistUnchecked, .checklistChecked, .bulletedList, .dashedList, .numberedList:
            ps.lineSpacing = 10; ps.paragraphSpacing = 8
            // The marker is drawn in the gutter, so first and wrapped lines share one left edge.
            ps.firstLineHeadIndent = offset + gutter(for: model.style)
            ps.headIndent = offset + gutter(for: model.style)
        case .body:
            // The board's 18 pt / 1.78 line height with 20 pt between paragraphs.
            ps.lineSpacing = 10; ps.paragraphSpacing = 20
        }
        return ps
    }

    /// Everything the view needs for one run, derived from the model attributes alone.
    static func visualAttributes(
        model: NoteEditorCodec.ParagraphModel,
        bold: Bool, italic: Bool,
        highlightIndex: Int?, textColorIndex: Int?,
        entryFont: WritingFontChoice, displayMode: DisplayMode
    ) -> [NSAttributedString.Key: Any] {
        let choice = model.fontChoice ?? entryFont
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(style: model.style, choice: choice, bold: bold, italic: italic),
            .foregroundColor: foreground(style: model.style),
            .paragraphStyle: paragraphStyle(for: model),
        ]
        if let idx = textColorIndex {
            let colors = TextColorPalette.colors(for: displayMode)
            if colors.indices.contains(idx) { attrs[.foregroundColor] = NSColor(colors[idx]) }
        }
        if let idx = highlightIndex {
            let colors = HighlightPalette.colors(for: displayMode)
            if colors.indices.contains(idx) { attrs[.backgroundColor] = NSColor(colors[idx]) }
        }
        return attrs
    }

    static func model(from attrs: [NSAttributedString.Key: Any]) -> NoteEditorCodec.ParagraphModel {
        var model = NoteEditorCodec.ParagraphModel()
        if let raw = attrs[NoteEditorCodec.paragraphStyleKey] as? String, let style = NoteParagraphTextStyle(rawValue: raw) {
            model.style = style
        }
        model.indent = attrs[NoteEditorCodec.indentLevelKey] as? Int ?? 0
        if let raw = attrs[NoteEditorCodec.fontChoiceKey] as? String { model.fontChoice = WritingFontChoice(rawValue: raw) }
        return model
    }

    /// Recomputes fonts, colors, paragraph styles and highlights for `range` from the model
    /// attributes. Call after any edit; it never changes the model attributes themselves.
    static func restyle(_ storage: NSMutableAttributedString, in range: NSRange, entryFont: WritingFontChoice, displayMode: DisplayMode) {
        let full = NSRange(location: 0, length: storage.length)
        let target = NSIntersectionRange(range, full)
        guard target.length > 0 else { return }

        var updates: [(NSRange, [NSAttributedString.Key: Any], Bool)] = []
        storage.enumerateAttributes(in: target, options: []) { attrs, run, _ in
            let highlight = attrs[NoteEditorCodec.highlightIndexKey] as? Int
            let visual = visualAttributes(
                model: model(from: attrs),
                bold: attrs[NoteEditorCodec.boldKey] as? Bool ?? false,
                italic: attrs[NoteEditorCodec.italicKey] as? Bool ?? false,
                highlightIndex: highlight,
                textColorIndex: attrs[NoteEditorCodec.textColorIndexKey] as? Int,
                entryFont: entryFont, displayMode: displayMode
            )
            updates.append((run, visual, highlight == nil))
        }
        for (run, visual, clearBackground) in updates {
            storage.addAttributes(visual, range: run)
            if clearBackground { storage.removeAttribute(.backgroundColor, range: run) }
        }
    }
}

// MARK: - Layout manager: list markers

final class MirrorLayoutManager: NSLayoutManager {
    /// Model of the empty paragraph after a final newline (it has no characters to carry one).
    var trailingModel = NoteEditorCodec.ParagraphModel() {
        didSet { if oldValue != trailingModel { invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0)) } }
    }

    private func paragraphModels() -> (starts: [Int], models: [NoteEditorCodec.ParagraphModel]) {
        guard let storage = textStorage else { return ([], []) }
        let text = storage.string as NSString
        let starts = NoteEditorCodec.paragraphStarts(in: text)
        let models = starts.map { start -> NoteEditorCodec.ParagraphModel in
            start >= text.length ? trailingModel : NoteEditorCodec.paragraphModel(at: start, in: storage)
        }
        return (starts, models)
    }

    /// Line rect (container coordinates) of the first line of the paragraph starting at `start`.
    private func firstLineRect(forParagraphAt start: Int) -> NSRect? {
        guard let storage = textStorage else { return nil }
        if start >= storage.length {
            let extra = extraLineFragmentRect
            return extra.isEmpty ? nil : extra
        }
        let glyph = glyphIndexForCharacter(at: start)
        return lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    /// Rect of a checklist box for hit testing and drawing, in container coordinates.
    func markerRect(forParagraphAt start: Int, model: NoteEditorCodec.ParagraphModel) -> NSRect? {
        guard let line = firstLineRect(forParagraphAt: start) else { return nil }
        let x = line.minX + CGFloat(model.indent) * MacEditorStyle.indentStep
        let box: CGFloat = 18
        let textHeight = MacEditorStyle.font(style: model.style, choice: model.fontChoice ?? .system, bold: false, italic: false).boundingRectForFont.height
        return NSRect(x: x + 1, y: line.minY + max(0, (textHeight - box) / 2) + 1, width: box, height: box)
    }

    /// The paragraph start of the checklist box under `point` (container coordinates), if any.
    func checklistParagraphStart(at point: NSPoint) -> Int? {
        let (starts, models) = paragraphModels()
        for (index, start) in starts.enumerated() {
            let model = models[index]
            guard model.style == .checklistUnchecked || model.style == .checklistChecked,
                  let rect = markerRect(forParagraphAt: start, model: model) else { continue }
            if rect.insetBy(dx: -4, dy: -4).contains(point) { return start }
        }
        return nil
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }

        let visibleChars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let (starts, models) = paragraphModels()
        let numbers = NoteEditorCodec.numberedIndices(for: models)

        for (index, start) in starts.enumerated() {
            let model = models[index]
            guard NoteEditorCodec.isListStyle(model.style) else { continue }
            let isTrailing = start >= storage.length
            if !isTrailing && !(NSLocationInRange(start, visibleChars) || start == NSMaxRange(visibleChars)) { continue }
            guard let line = firstLineRect(forParagraphAt: start) else { continue }
            drawMarker(model: model, number: numbers[index], paragraphStart: start, line: line, origin: origin)
        }
    }

    private func drawMarker(model: NoteEditorCodec.ParagraphModel, number: Int?, paragraphStart: Int, line: NSRect, origin: NSPoint) {
        let level = model.indent
        let x = origin.x + line.minX + CGFloat(level) * MacEditorStyle.indentStep
        let font = MacEditorStyle.font(style: model.style, choice: model.fontChoice ?? .system, bold: false, italic: false)
        let textTop = origin.y + line.minY

        switch model.style {
        case .checklistUnchecked, .checklistChecked:
            guard let rect = markerRect(forParagraphAt: paragraphStart, model: model) else { return }
            let symbol = model.style == .checklistChecked ? "checkmark.circle.fill" : "circle"
            let tint: NSColor = model.style == .checklistChecked ? .controlAccentColor : .secondaryLabelColor
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular).applying(.init(paletteColors: [tint]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                image.draw(in: rect.offsetBy(dx: origin.x, dy: origin.y))
            }
        default:
            let marker: String
            switch model.style {
            case .bulletedList: marker = level == 0 ? "•" : (level == 1 ? "◦" : "▸")
            case .dashedList: marker = level == 1 ? "·" : "–"
            case .numberedList: marker = "\(number ?? 1)."
            default: return
            }
            let attributed = NSAttributedString(string: marker, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
            attributed.draw(at: NSPoint(x: x, y: textTop))
        }
    }
}

// MARK: - Text view

final class MirrorNSTextView: NSTextView {
    var placeholder = String(localized: "What's on your mind?")
    var onToggleChecklist: ((Int) -> Void)?
    /// Lets the editor take focus once the view is actually in a window.
    var onAttachToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onAttachToWindow?() }
    }

    /// Anything pasted is plain text: rich pasteboard content would bring fonts, colors and
    /// attachments that bypass the model attributes and would never survive a save.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: .string) == nil,
           let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation {
            NotificationCenter.default.post(name: .mirrorMacPasteImage, object: nil, userInfo: ["data": data])
            return
        }
        pasteAsPlainText(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if let layout = layoutManager as? MirrorLayoutManager {
            let local = convert(event.locationInWindow, from: nil)
            let point = NSPoint(x: local.x - textContainerOrigin.x, y: local.y - textContainerOrigin.y)
            if let start = layout.checklistParagraphStart(at: point) {
                onToggleChecklist?(start)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let origin = textContainerOrigin
        let attributes: [NSAttributedString.Key: Any] = [
            .font: typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: MacEditorStyle.bodySize),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let indent = (typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
        placeholder.draw(at: NSPoint(x: origin.x + textContainer!.lineFragmentPadding + indent, y: origin.y), withAttributes: attributes)
    }
}

// MARK: - SwiftUI wrapper

struct NoteEditorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var textStyleData: Data?
    @Binding var inlineStyleData: Data?
    @Binding var photoDataArray: [Data]
    @Binding var command: NoteTextCommand?
    @Binding var commandRevision: Int
    @Binding var isFocused: Bool
    @Binding var activeParagraphStyle: NoteParagraphTextStyle
    @Binding var activeInlineStyles: InlineStyleSet
    @Binding var showFormattingPanel: Bool
    @Binding var canUndo: Bool
    @Binding var canRedo: Bool
    @Binding var fontChoiceRaw: String
    var panelState: FormattingPanelState
    var displayMode: DisplayMode
    var onPhotoTapped: ((Int) -> Void)?

    private static let minHeight: CGFloat = 60

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> MirrorNSTextView {
        Self.makeConfiguredTextView(coordinator: context.coordinator)
    }

    /// Builds the text view the way the app does; also used by the DEBUG editor self-test.
    static func makeConfiguredTextView(coordinator: Coordinator) -> MirrorNSTextView {
        let storage = NSTextStorage()
        let layout = MirrorLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        // A TextKit 1 text view (explicit layout manager), which the marker drawing relies on.
        let textView = MirrorNSTextView(frame: .zero, textContainer: container)
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        textView.usesRuler = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.allowsImageEditing = false
        textView.isGrammarCheckingEnabled = false
        textView.registerForDraggedTypes([.string])
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        textView.delegate = coordinator
        storage.delegate = coordinator
        textView.onToggleChecklist = { [weak coordinator] start in coordinator?.toggleChecklist(at: start) }
        textView.onAttachToWindow = { [weak coordinator, weak textView] in
            guard let coordinator, let textView, coordinator.parent.isFocused else { return }
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }

        coordinator.textView = textView
        coordinator.load(into: textView)
        return textView
    }

    func updateNSView(_ textView: MirrorNSTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.needsReload(textView) {
            let selection = textView.selectedRange()
            coordinator.load(into: textView)
            textView.setSelectedRange(coordinator.clamped(selection, in: textView))
        }

        if let command, coordinator.lastAppliedCommandRevision != commandRevision {
            coordinator.lastAppliedCommandRevision = commandRevision
            coordinator.apply(command, to: textView)
            DispatchQueue.main.async { self.command = nil }
        }

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    /// The editor grows with its text; WriteView's ScrollView scrolls.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MirrorNSTextView, context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let layout = nsView.layoutManager else { return nil }
        let width = proposal.width ?? 600
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = layout.usedRect(for: container).height + nsView.textContainerInset.height * 2
        return CGSize(width: width, height: max(Self.minHeight, ceil(height)))
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: NoteEditorTextView
        weak var textView: MirrorNSTextView?
        var lastAppliedCommandRevision = 0

        private var isApplying = false
        private var lastStyleData: Data?
        private var lastInlineData: Data?
        private var lastFontChoiceRaw = ""
        private var trailing = NoteEditorCodec.ParagraphModel()

        init(parent: NoteEditorTextView) { self.parent = parent }

        private var entryFont: WritingFontChoice { WritingFontChoice(rawValue: parent.fontChoiceRaw) ?? .system }
        private var displayMode: DisplayMode { parent.displayMode }
        private var layout: MirrorLayoutManager? { textView?.layoutManager as? MirrorLayoutManager }

        func clamped(_ range: NSRange, in textView: NSTextView) -> NSRange {
            let length = (textView.string as NSString).length
            let location = min(max(0, range.location), length)
            return NSRange(location: location, length: min(range.length, length - location))
        }

        // MARK: Loading

        /// True when the bound values differ from what the view shows and from what this editor
        /// last wrote — an outside change (template, Talk it out, a newly opened entry).
        func needsReload(_ textView: NSTextView) -> Bool {
            textView.string != parent.text
                || parent.textStyleData != lastStyleData
                || parent.inlineStyleData != lastInlineData
                || parent.fontChoiceRaw != lastFontChoiceRaw
        }

        func load(into textView: MirrorNSTextView) {
            guard let storage = textView.textStorage else { return }
            let rendered = NoteEditorCodec.render(
                text: parent.text, textStyleData: parent.textStyleData,
                inlineStyleData: parent.inlineStyleData, entryFont: entryFont
            )
            MacEditorStyle.restyle(rendered.attributed, in: NSRange(location: 0, length: rendered.attributed.length),
                                   entryFont: entryFont, displayMode: displayMode)
            isApplying = true
            storage.setAttributedString(rendered.attributed)
            trailing = rendered.trailing
            layout?.trailingModel = rendered.trailing
            isApplying = false
            lastStyleData = parent.textStyleData
            lastInlineData = parent.inlineStyleData
            lastFontChoiceRaw = parent.fontChoiceRaw
            refreshTypingAttributes(in: textView)
            textView.needsDisplay = true
        }

        // MARK: Keeping paragraphs consistent while editing

        /// After a character edit, every paragraph it touched takes the model of its first
        /// character (a merged paragraph keeps the preceding paragraph's style) and is restyled.
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard !isApplying, editedMask.contains(.editedCharacters), textStorage.length > 0 else { return }
            let text = textStorage.string as NSString
            let probe = NSRange(location: min(editedRange.location, text.length), length: min(editedRange.length, max(0, text.length - editedRange.location)))
            let paragraphs = text.paragraphRange(for: probe)
            guard paragraphs.length > 0 else { return }

            var cursor = paragraphs.location
            while cursor < NSMaxRange(paragraphs) {
                let one = text.paragraphRange(for: NSRange(location: cursor, length: 0))
                let model = NoteEditorCodec.paragraphModel(at: one.location, in: textStorage)
                textStorage.removeAttribute(NoteEditorCodec.paragraphStyleKey, range: one)
                textStorage.removeAttribute(NoteEditorCodec.indentLevelKey, range: one)
                textStorage.removeAttribute(NoteEditorCodec.fontChoiceKey, range: one)
                textStorage.addAttributes(model.attributes, range: one)
                MacEditorStyle.restyle(textStorage, in: one, entryFont: entryFont, displayMode: displayMode)
                cursor = max(NSMaxRange(one), cursor + 1)
            }
        }

        // MARK: Emitting changes

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView, let storage = textView.textStorage else { return }
            captureTrailingModel(from: textView)
            emit(storage: storage, textView: textView)
        }

        private func emit(storage: NSTextStorage, textView: NSTextView) {
            let style = NoteEditorCodec.extractTextStyleData(from: storage, trailing: trailing, entryFont: entryFont)
            let inline = NoteEditorCodec.extractInlineStyleData(from: storage)
            lastStyleData = style
            lastInlineData = inline
            parent.text = textView.string
            parent.textStyleData = style
            parent.inlineStyleData = inline
            publishActiveState(in: textView)
            parent.canUndo = textView.undoManager?.canUndo ?? false
            parent.canRedo = textView.undoManager?.canRedo ?? false
            textView.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplying, let textView else { return }
            captureTrailingModel(from: textView)
            publishActiveState(in: textView)
            if textView.window?.firstResponder === textView, !parent.isFocused { parent.isFocused = true }
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused { parent.isFocused = false }
        }

        /// The paragraph after a final newline has no characters; its model is whatever the caret
        /// there would type with. Remember it while the caret sits in it.
        private func captureTrailingModel(from textView: NSTextView) {
            let length = (textView.string as NSString).length
            let atEnd = textView.selectedRange().location >= length
            let endsWithBreak = length == 0 || (textView.string as NSString).character(at: length - 1) == 10
            guard atEnd, endsWithBreak else { return }
            trailing = MacEditorStyle.model(from: textView.typingAttributes)
            layout?.trailingModel = trailing
        }

        private func caretModel(in textView: NSTextView) -> (NoteEditorCodec.ParagraphModel, attrsLocation: Int?) {
            guard let storage = textView.textStorage else { return (NoteEditorCodec.ParagraphModel(), nil) }
            let length = storage.length
            let selection = textView.selectedRange()
            let paragraphIsTrailing = selection.location >= length && (length == 0 || (storage.string as NSString).character(at: length - 1) == 10)
            if paragraphIsTrailing { return (trailing, nil) }
            let location = min(selection.location, max(0, length - 1))
            return (NoteEditorCodec.paragraphModel(at: location, in: storage), location)
        }

        private func publishActiveState(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let (model, location) = caretModel(in: textView)
            var flags = InlineStyleSet()
            let selection = textView.selectedRange()
            let sample: Int? = selection.length > 0 ? selection.location : (selection.location > 0 ? selection.location - 1 : location)
            if let sample, sample < storage.length {
                let attrs = storage.attributes(at: sample, effectiveRange: nil)
                flags.bold = attrs[NoteEditorCodec.boldKey] as? Bool ?? false
                flags.italic = attrs[NoteEditorCodec.italicKey] as? Bool ?? false
                flags.underline = attrs[.underlineStyle] != nil
                flags.strikethrough = attrs[.strikethroughStyle] != nil
            } else {
                let typing = textView.typingAttributes
                flags.bold = typing[NoteEditorCodec.boldKey] as? Bool ?? false
                flags.italic = typing[NoteEditorCodec.italicKey] as? Bool ?? false
                flags.underline = typing[.underlineStyle] != nil
                flags.strikethrough = typing[.strikethroughStyle] != nil
            }
            if parent.activeParagraphStyle != model.style { parent.activeParagraphStyle = model.style }
            if parent.activeInlineStyles != flags { parent.activeInlineStyles = flags }
            let choice = model.fontChoice ?? entryFont
            if parent.panelState.activeFontChoice != choice { parent.panelState.activeFontChoice = choice }
            if parent.panelState.activeParagraphStyle != model.style { parent.panelState.activeParagraphStyle = model.style }
        }

        /// Typing attributes for the caret: the model of its paragraph plus the visual attributes.
        private func refreshTypingAttributes(in textView: NSTextView) {
            let (model, _) = caretModel(in: textView)
            var attrs = MacEditorStyle.visualAttributes(
                model: model, bold: false, italic: false, highlightIndex: nil, textColorIndex: nil,
                entryFont: entryFont, displayMode: displayMode
            )
            for (key, value) in model.attributes { attrs[key] = value }
            textView.typingAttributes = attrs
        }

        // MARK: List behaviors

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard textView.selectedRange().length == 0 else { return false }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return exitEmptyListItem(in: textView)
            case #selector(NSResponder.deleteBackward(_:)):
                return leaveListAtParagraphStart(in: textView)
            case #selector(NSResponder.insertTab(_:)):
                return changeIndent(by: +1, in: textView)
            case #selector(NSResponder.insertBacktab(_:)):
                return changeIndent(by: -1, in: textView)
            default:
                return false
            }
        }

        /// The caret's paragraph: its range, its model and whether it is the empty one after a final newline.
        private func caretParagraph(in textView: NSTextView) -> (range: NSRange, model: NoteEditorCodec.ParagraphModel, isTrailing: Bool)? {
            guard let storage = textView.textStorage else { return nil }
            let text = storage.string as NSString
            let caret = textView.selectedRange().location
            if caret >= text.length, text.length == 0 || text.character(at: text.length - 1) == 10 {
                return (NSRange(location: text.length, length: 0), trailing, true)
            }
            let range = text.paragraphRange(for: NSRange(location: min(caret, text.length), length: 0))
            return (range, NoteEditorCodec.paragraphModel(at: range.location, in: storage), false)
        }

        private func setModel(_ model: NoteEditorCodec.ParagraphModel, forParagraph range: NSRange, isTrailing: Bool, in textView: NSTextView) {
            if isTrailing {
                trailing = model
                layout?.trailingModel = model
                refreshTypingAttributes(in: textView)
                if let storage = textView.textStorage { emit(storage: storage, textView: textView) }
                return
            }
            mutate(textView, range: range) { storage in
                storage.removeAttribute(NoteEditorCodec.paragraphStyleKey, range: range)
                storage.removeAttribute(NoteEditorCodec.indentLevelKey, range: range)
                storage.addAttributes(model.attributes.filter { $0.key != NoteEditorCodec.fontChoiceKey }, range: range)
            }
            refreshTypingAttributes(in: textView)
        }

        /// Return on an empty list item leaves the list instead of adding another empty item.
        private func exitEmptyListItem(in textView: NSTextView) -> Bool {
            guard let (range, model, isTrailing) = caretParagraph(in: textView), NoteEditorCodec.isListStyle(model.style) else { return false }
            let text = textView.string as NSString
            let isEmpty = isTrailing || range.length == 0 || (range.length == 1 && text.character(at: range.location) == 10)
            guard isEmpty else { return false }
            var plain = model
            plain.style = .body
            plain.indent = 0
            setModel(plain, forParagraph: range, isTrailing: isTrailing, in: textView)
            return true
        }

        /// Backspace at the start of a list item turns it into a plain paragraph first.
        private func leaveListAtParagraphStart(in textView: NSTextView) -> Bool {
            guard let (range, model, isTrailing) = caretParagraph(in: textView), NoteEditorCodec.isListStyle(model.style) else { return false }
            guard textView.selectedRange().location == range.location else { return false }
            var plain = model
            plain.style = .body
            plain.indent = 0
            setModel(plain, forParagraph: range, isTrailing: isTrailing, in: textView)
            return true
        }

        /// Tab and Shift-Tab indent and outdent a list item (levels 0 to 4, as on iOS).
        private func changeIndent(by delta: Int, in textView: NSTextView) -> Bool {
            guard let (range, model, isTrailing) = caretParagraph(in: textView), NoteEditorCodec.isListStyle(model.style) else { return false }
            let level = max(0, min(4, model.indent + delta))
            guard level != model.indent else { return true }
            var next = model
            next.indent = level
            setModel(next, forParagraph: range, isTrailing: isTrailing, in: textView)
            return true
        }

        // MARK: Checklist commands (whole document, like the iOS editor)

        /// Every paragraph as text plus model, trailing empty paragraph included.
        private func paragraphRows(in textView: NSTextView) -> [(text: String, model: NoteEditorCodec.ParagraphModel)]? {
            guard let storage = textView.textStorage else { return nil }
            let text = storage.string as NSString
            let starts = NoteEditorCodec.paragraphStarts(in: text)
            var rows: [(String, NoteEditorCodec.ParagraphModel)] = []
            for (index, start) in starts.enumerated() {
                let end = index + 1 < starts.count ? starts[index + 1] - 1 : text.length
                let content = text.substring(with: NSRange(location: start, length: max(0, end - start)))
                let model = start >= text.length ? trailing : NoteEditorCodec.paragraphModel(at: start, in: storage)
                rows.append((content, model))
            }
            return rows
        }

        /// Replaces the document with `rows`. Inline ranges are dropped because paragraph positions
        /// moved (the iOS editor does the same).
        private func replaceDocument(with rows: [(text: String, model: NoteEditorCodec.ParagraphModel)], in textView: MirrorNSTextView) {
            guard !rows.isEmpty else { return }
            parent.text = rows.map(\.text).joined(separator: "\n")
            // The stored document lists the empty last paragraph only when it is a list item.
            var models = rows.map(\.model)
            if let tail = rows.last, tail.text.isEmpty, !NoteEditorCodec.isListStyle(tail.model.style) { models.removeLast() }
            parent.textStyleData = NoteEditorCodec.encodeTextStyleData(models: models, entryFont: entryFont)
            parent.inlineStyleData = nil
            load(into: textView)
            publishActiveState(in: textView)
        }

        private func setAllChecklistItems(checked: Bool, in textView: MirrorNSTextView) {
            guard var rows = paragraphRows(in: textView) else { return }
            var changed = false
            for index in rows.indices {
                let style = rows[index].model.style
                guard style == .checklistChecked || style == .checklistUnchecked else { continue }
                let target: NoteParagraphTextStyle = checked ? .checklistChecked : .checklistUnchecked
                if style != target { rows[index].model.style = target; changed = true }
            }
            guard changed else { return }
            let selection = textView.selectedRange()
            applyRowsKeepingInline(rows, in: textView)
            textView.setSelectedRange(clamped(selection, in: textView))
        }

        /// Style-only changes keep the text and the inline ranges.
        private func applyRowsKeepingInline(_ rows: [(text: String, model: NoteEditorCodec.ParagraphModel)], in textView: MirrorNSTextView) {
            var models = rows.map(\.model)
            if let tail = rows.last, tail.text.isEmpty, !NoteEditorCodec.isListStyle(tail.model.style) { models.removeLast() }
            parent.textStyleData = NoteEditorCodec.encodeTextStyleData(models: models, entryFont: entryFont)
            load(into: textView)
            publishActiveState(in: textView)
        }

        private func deleteCheckedItems(in textView: MirrorNSTextView) {
            guard let rows = paragraphRows(in: textView) else { return }
            let kept = rows.filter { $0.model.style != .checklistChecked }
            guard kept.count < rows.count, !kept.isEmpty else {
                if kept.isEmpty, !rows.isEmpty { replaceDocument(with: [("", NoteEditorCodec.ParagraphModel())], in: textView) }
                return
            }
            replaceDocument(with: kept, in: textView)
        }

        /// Within each run of checklist items, unchecked ones come first (stable).
        private func sortCheckedToBottom(in textView: MirrorNSTextView) {
            guard var rows = paragraphRows(in: textView) else { return }
            func isChecklist(_ style: NoteParagraphTextStyle) -> Bool { style == .checklistChecked || style == .checklistUnchecked }
            var changed = false
            var i = 0
            while i < rows.count {
                guard isChecklist(rows[i].model.style) else { i += 1; continue }
                var j = i
                while j < rows.count, isChecklist(rows[j].model.style) { j += 1 }
                let block = Array(rows[i..<j])
                let sorted = block.filter { $0.model.style != .checklistChecked } + block.filter { $0.model.style == .checklistChecked }
                if sorted.map(\.model.style) != block.map(\.model.style) {
                    changed = true
                    rows.replaceSubrange(i..<j, with: sorted)
                }
                i = j
            }
            if changed { replaceDocument(with: rows, in: textView) }
        }

        // MARK: Commands

        /// Runs a change as one undoable edit and restyles what it touched.
        private func mutate(_ textView: NSTextView, range: NSRange, _ change: (NSTextStorage) -> Void) {
            guard let storage = textView.textStorage, textView.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.beginEditing()
            change(storage)
            MacEditorStyle.restyle(storage, in: range, entryFont: entryFont, displayMode: displayMode)
            storage.endEditing()
            textView.didChangeText()
        }

        private func selectedParagraphRange(in textView: NSTextView) -> NSRange {
            let text = textView.string as NSString
            let sel = textView.selectedRange()
            return text.paragraphRange(for: NSRange(location: min(sel.location, text.length), length: sel.length))
        }

        func apply(_ command: NoteTextCommand, to textView: MirrorNSTextView) {
            switch command {
            case .title, .heading, .subheading, .body, .monospaced, .blockQuote,
                 .checklist, .bulletedList, .dashedList, .numberedList:
                setParagraphStyle(for: command, in: textView)
            case .bold: toggleFlag(NoteEditorCodec.boldKey, in: textView)
            case .italic: toggleFlag(NoteEditorCodec.italicKey, in: textView)
            case .underline: toggleUnderlineLike(.underlineStyle, in: textView)
            case .strikethrough: toggleUnderlineLike(.strikethroughStyle, in: textView)
            case .highlight(let index): setIndexAttribute(NoteEditorCodec.highlightIndexKey, to: index, in: textView)
            case .textColor(let index): setIndexAttribute(NoteEditorCodec.textColorIndexKey, to: index, in: textView)
            case .link(let url): setLink(url, in: textView)
            case .clearFormatting: clearFormatting(in: textView)
            case .fontFamily(let choice): setFont(choice, in: textView)
            case .undo:
                textView.undoManager?.undo()
                DispatchQueue.main.async { self.syncUndoState(textView) }
            case .redo:
                textView.undoManager?.redo()
                DispatchQueue.main.async { self.syncUndoState(textView) }
            case .moveCursor(let location):
                textView.setSelectedRange(clamped(NSRange(location: location, length: 0), in: textView))
                refreshTypingAttributes(in: textView)
            case .indentMore: _ = changeIndent(by: +1, in: textView)
            case .indentLess: _ = changeIndent(by: -1, in: textView)
            case .checkAllItems: setAllChecklistItems(checked: true, in: textView)
            case .uncheckAllItems: setAllChecklistItems(checked: false, in: textView)
            case .deleteCheckedItems: deleteCheckedItems(in: textView)
            case .sortCheckedToBottom: sortCheckedToBottom(in: textView)
            case .photo:
                break  // photos are attached under the editor on Mac
            }
        }

        private func syncUndoState(_ textView: NSTextView) {
            parent.canUndo = textView.undoManager?.canUndo ?? false
            parent.canRedo = textView.undoManager?.canRedo ?? false
        }

        private func targetStyle(for command: NoteTextCommand, current: NoteParagraphTextStyle) -> NoteParagraphTextStyle {
            switch command {
            case .title: return .title
            case .heading: return .heading
            case .subheading: return .subheading
            case .monospaced: return .monospaced
            case .blockQuote: return .blockQuote
            case .checklist:
                return (current == .checklistUnchecked || current == .checklistChecked) ? .body : .checklistUnchecked
            case .bulletedList: return current == .bulletedList ? .body : .bulletedList
            case .dashedList: return current == .dashedList ? .body : .dashedList
            case .numberedList: return current == .numberedList ? .body : .numberedList
            default: return .body
            }
        }

        private func setParagraphStyle(for command: NoteTextCommand, in textView: NSTextView) {
            let (current, _) = caretModel(in: textView)
            let target = targetStyle(for: command, current: current.style)
            let indent = NoteEditorCodec.isListStyle(target) ? current.indent : 0
            let range = selectedParagraphRange(in: textView)

            if range.length == 0 {
                // The empty paragraph after a final newline: only its model changes.
                trailing.style = target
                trailing.indent = indent
                layout?.trailingModel = trailing
                refreshTypingAttributes(in: textView)
                emit(storage: textView.textStorage!, textView: textView)
                return
            }

            mutate(textView, range: range) { storage in
                (storage.string as NSString).enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
                    storage.removeAttribute(NoteEditorCodec.paragraphStyleKey, range: enclosing)
                    storage.removeAttribute(NoteEditorCodec.indentLevelKey, range: enclosing)
                    if target != .body { storage.addAttribute(NoteEditorCodec.paragraphStyleKey, value: target.rawValue, range: enclosing) }
                    if indent > 0 { storage.addAttribute(NoteEditorCodec.indentLevelKey, value: indent, range: enclosing) }
                }
            }
            refreshTypingAttributes(in: textView)
        }

        private func toggleFlag(_ key: NSAttributedString.Key, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let selection = textView.selectedRange()
            if selection.length == 0 {
                var typing = textView.typingAttributes
                let on = !(typing[key] as? Bool ?? false)
                if on { typing[key] = true } else { typing.removeValue(forKey: key) }
                let model = MacEditorStyle.model(from: typing)
                let visual = MacEditorStyle.visualAttributes(
                    model: model, bold: typing[NoteEditorCodec.boldKey] as? Bool ?? false,
                    italic: typing[NoteEditorCodec.italicKey] as? Bool ?? false,
                    highlightIndex: typing[NoteEditorCodec.highlightIndexKey] as? Int,
                    textColorIndex: typing[NoteEditorCodec.textColorIndexKey] as? Int,
                    entryFont: entryFont, displayMode: displayMode)
                for (k, v) in visual { typing[k] = v }
                textView.typingAttributes = typing
                publishActiveState(in: textView)
                return
            }
            var allOn = true
            storage.enumerateAttribute(key, in: selection) { value, _, stop in
                if !(value as? Bool ?? false) { allOn = false; stop.pointee = true }
            }
            mutate(textView, range: selection) { storage in
                if allOn { storage.removeAttribute(key, range: selection) } else { storage.addAttribute(key, value: true, range: selection) }
            }
        }

        private func toggleUnderlineLike(_ key: NSAttributedString.Key, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let selection = textView.selectedRange()
            if selection.length == 0 {
                var typing = textView.typingAttributes
                if typing[key] != nil { typing.removeValue(forKey: key) } else { typing[key] = NSUnderlineStyle.single.rawValue }
                textView.typingAttributes = typing
                publishActiveState(in: textView)
                return
            }
            var allOn = true
            storage.enumerateAttribute(key, in: selection) { value, _, stop in
                if value == nil { allOn = false; stop.pointee = true }
            }
            mutate(textView, range: selection) { storage in
                if allOn { storage.removeAttribute(key, range: selection) } else { storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: selection) }
            }
        }

        private func setIndexAttribute(_ key: NSAttributedString.Key, to index: Int?, in textView: NSTextView) {
            let selection = textView.selectedRange()
            guard selection.length > 0 else {
                var typing = textView.typingAttributes
                if let index { typing[key] = index } else { typing.removeValue(forKey: key) }
                textView.typingAttributes = typing
                return
            }
            mutate(textView, range: selection) { storage in
                if let index { storage.addAttribute(key, value: index, range: selection) } else { storage.removeAttribute(key, range: selection) }
            }
        }

        private func setLink(_ urlString: String?, in textView: NSTextView) {
            let selection = textView.selectedRange()
            guard selection.length > 0 else { return }
            mutate(textView, range: selection) { storage in
                if let url = validatedLinkURL(from: urlString) {
                    storage.addAttribute(.link, value: url, range: selection)
                } else {
                    storage.removeAttribute(.link, range: selection)
                }
            }
        }

        private func clearFormatting(in textView: NSTextView) {
            let selection = textView.selectedRange()
            guard selection.length > 0 else { return }
            mutate(textView, range: selection) { storage in
                for key in [NoteEditorCodec.boldKey, NoteEditorCodec.italicKey, .underlineStyle, .strikethroughStyle,
                            NoteEditorCodec.highlightIndexKey, NoteEditorCodec.textColorIndexKey, .link] {
                    storage.removeAttribute(key, range: selection)
                }
            }
        }

        private func setFont(_ choice: WritingFontChoice, in textView: NSTextView) {
            let range = selectedParagraphRange(in: textView)
            let override: WritingFontChoice? = choice == entryFont ? nil : choice
            if range.length == 0 {
                trailing.fontChoice = override
                layout?.trailingModel = trailing
                refreshTypingAttributes(in: textView)
                emit(storage: textView.textStorage!, textView: textView)
                return
            }
            mutate(textView, range: range) { storage in
                storage.removeAttribute(NoteEditorCodec.fontChoiceKey, range: range)
                if let override { storage.addAttribute(NoteEditorCodec.fontChoiceKey, value: override.rawValue, range: range) }
            }
            refreshTypingAttributes(in: textView)
        }

        /// Clicking a checklist box flips that item between unchecked and checked.
        func toggleChecklist(at paragraphStart: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let text = storage.string as NSString
            if paragraphStart >= text.length {
                trailing.style = trailing.style == .checklistChecked ? .checklistUnchecked : .checklistChecked
                layout?.trailingModel = trailing
                refreshTypingAttributes(in: textView)
                emit(storage: storage, textView: textView)
                return
            }
            let range = text.paragraphRange(for: NSRange(location: paragraphStart, length: 0))
            let current = NoteEditorCodec.paragraphModel(at: paragraphStart, in: storage).style
            let next: NoteParagraphTextStyle = current == .checklistChecked ? .checklistUnchecked : .checklistChecked
            mutate(textView, range: range) { storage in
                storage.addAttribute(NoteEditorCodec.paragraphStyleKey, value: next.rawValue, range: range)
            }
        }
    }
}
#endif
