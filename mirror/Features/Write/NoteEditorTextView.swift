import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Photos
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

#if os(iOS)
struct NoteEditorTextView: UIViewRepresentable {
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
    // Per-entry, not global — owned by WriteView, mirrored into panelState so the
    // formatting panel (presented by WriteView, a separate SwiftUI tree) can
    // read/mutate it. Declaring it as a @Binding here is what makes SwiftUI
    // re-invoke updateUIView when it changes.
    @Binding var fontChoiceRaw: String
    var panelState: FormattingPanelState
    var displayMode: DisplayMode
    /// WriteView's `usesPopoverPanel`: a popover off the Aa button where there's room,
    /// otherwise the panel replaces the keyboard.
    var panelAsPopover = false
    var onPhotoTapped: ((Int) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        // An explicit TextKit 1 stack: the editor reads `layoutManager` throughout, and the
        // checklist circles are drawn by ChecklistLayoutManager.
        let storage = NSTextStorage()
        let layoutManager = ChecklistLayoutManager()
        layoutManager.setAccentColor(UIColor(displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor), traits: .current)
        storage.addLayoutManager(layoutManager)
        storage.delegate = layoutManager.markerSpacing
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = MirrorEditorTextView(frame: .zero, textContainer: container)
        context.coordinator.textView = textView
        textView.caretAccessibilityActions = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return [] }
            return coordinator.checklistAccessibilityActions(in: textView)
        }
        textView.editorUndo = context.coordinator.editorUndoManager
        context.coordinator.editorUndoManager.textView = textView
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        // The editor doesn't scroll itself — it lives in WriteView's ScrollView and
        // grows to fit its content (see sizeThatFits). A non-scrolling text view
        // can't keep the caret above the keyboard, so scrollCaretToVisible nudges
        // the enclosing scroll view instead.
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.typingAttributes = context.coordinator.bodyAttributes

        let placeholder = UILabel()
        placeholder.text = String(localized: "What's on your mind?")
        placeholder.textColor = .tertiaryLabel
        placeholder.font = context.coordinator.serifBodyFont
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.tag = Coordinator.placeholderTag
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8)
        ])

        context.coordinator.applyStyledText(to: textView, preservingSelection: false)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = context.coordinator
        textView.addGestureRecognizer(tapGesture)
        // Notes' list gestures: swipe an item right or left to indent it, touch and hold its circle
        // to drag it to another place in the list.
        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleListSwipe(_:)))
        swipeRight.direction = .right
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleListSwipe(_:)))
        swipeLeft.direction = .left
        let drag = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleChecklistDrag(_:)))
        drag.minimumPressDuration = 0.3
        for recognizer in [swipeRight, swipeLeft, drag] as [UIGestureRecognizer] {
            recognizer.delegate = context.coordinator
            textView.addGestureRecognizer(recognizer)
        }
        textView.checklistGestureRecognizers = [tapGesture, swipeRight, swipeLeft, drag]
        textView.isChecklistMarker = { [weak coordinator = context.coordinator, weak textView] point in
            guard let coordinator, let textView else { return false }
            return coordinator.checklistMarkerParagraph(at: point, in: textView) != nil
        }

        textView.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if let layoutManager = textView.layoutManager as? ChecklistLayoutManager {
            let accent = UIColor(displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor)
            if layoutManager.setAccentColor(accent, traits: textView.traitCollection) {
                textView.setNeedsDisplay()
                layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textView.textStorage.length))
            }
        }
        context.coordinator.parent = self
        context.coordinator.didReceiveParent()
        context.coordinator.noteOutsideChange(in: textView)

        // The full comparison rebuilds the logical text (several ms at 50k characters). When the
        // text is exactly what the editor last showed or synced, it can't differ.
        let logicalMismatch = !context.coordinator.isShowing(text)
            && context.coordinator.logicalText(from: textView) != context.coordinator.displayTextEquivalent(for: text)
        if logicalMismatch {
            let selectedRange = textView.selectedRange
            context.coordinator.applyStyledText(to: textView, preservingSelection: false)
            textView.selectedRange = context.coordinator.bounded(selectedRange, in: textView.text)
        } else {
            context.coordinator.applyStyledText(to: textView, preservingSelection: true)
        }

        context.coordinator.updatePlaceholder(in: textView)

        if isFocused, !textView.isFirstResponder, Self.isCoveredBySheet(textView) {
            // Write's launch focus can land after What's New (or another sheet) is already up,
            // and the keyboard would sit on top of that sheet (3.1.4, 2026-10-20). Give the
            // focus up instead; a tap brings it back.
            DispatchQueue.main.async { isFocused = false }
        } else if isFocused, !textView.isFirstResponder {
            // The first focus this editor didn't get from a tap (autoFocus on Write, Edit, a
            // restored draft) starts at the end of the text, like Notes; it used to start at
            // the beginning. Later programmatic refocus keeps the caret where it was.
            if !context.coordinator.placedInitialCaret {
                context.coordinator.placedInitialCaret = true
                textView.selectedRange = NSRange(location: (textView.text as NSString? ?? "").length, length: 0)
            }
            textView.becomeFirstResponder()
        }

        if let command, context.coordinator.lastAppliedCommandRevision != commandRevision {
            context.coordinator.lastAppliedCommandRevision = commandRevision
            context.coordinator.apply(command, to: textView)
            DispatchQueue.main.async {
                self.command = nil
            }
        }

        context.coordinator.updateFormattingPanel(textView: textView, visible: showFormattingPanel)
    }

    /// The editor grows to fit its text — it doesn't scroll (WriteView's
    /// ScrollView does). Never reports shorter than this so an empty note still
    /// has a comfortable tap target.
    private static let minEditorHeight: CGFloat = 240

    /// True when a sheet the editor isn't inside is presented on its window.
    static func isCoveredBySheet(_ view: UIView) -> Bool {
        guard var top = view.window?.rootViewController else { return false }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return !view.isDescendant(of: top.view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let rawWidth = proposal.width, rawWidth > 0, rawWidth != .infinity else { return nil }
        // Rounded, not the raw proposal: dateHeader/tagsBar now sit as siblings of this
        // ScrollView instead of scrolling away above it, so their own relayout (the animated
        // word-count badge springing in at a word boundary, most visibly right on Return)
        // can hand this view a proposal a fraction of a point off from the last pass. An
        // exact != comparison treated that as a real width change and zeroed the floor right
        // when a transient short sizeThatFits reading was most likely — reopening the same
        // collapse-to-top this floor exists to prevent, just retriggered by header jitter
        // instead of a line un-wrap.
        let width = rawWidth.rounded()
        // A height floor only makes sense at the width it was measured at (rotation, Split
        // View resize) — carry it over across widths and the editor could get pinned taller
        // than it needs to be at the new width.
        if context.coordinator.sessionMaxEditorHeightWidth != width {
            context.coordinator.sessionMaxEditorHeight = 0
            context.coordinator.sessionMaxEditorHeightWidth = width
        }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height.rounded(.up)
        // SwiftUI can query this mid-edit, sometimes catching the layout manager between a
        // text change landing and its glyphs being laid out — most visibly right when an
        // edit un-wraps a line, where it can transiently answer with a much shorter height
        // for that one pass. The enclosing SwiftUI ScrollView reads that as the content
        // genuinely shrinking and snaps its contentOffset toward zero — on-device that showed
        // up as one backspace teleporting an 850-word entry to the top instead of nudging the
        // scroll to follow the caret. Floor against the tallest height seen this editing
        // session so a transient short read can't shrink the scroll content out from under
        // the user. Reset when the coordinator is torn down (a new entry gets a fresh
        // NoteEditorTextView/Coordinator) — an intentional select-all-delete mid-entry won't
        // reclaim the freed scroll space until then, which is the right side to err on for a
        // journaling editor: never yank the view out from under someone who's still typing.
        context.coordinator.sessionMaxEditorHeight = max(context.coordinator.sessionMaxEditorHeight, fitting)
        return CGSize(width: width, height: max(context.coordinator.sessionMaxEditorHeight, Self.minEditorHeight))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
        /// The paragraph styles as the editor last wrote them, until SwiftUI's next update. In the app
        /// a write through `parent.textStyleData` (WriteViewModel via a binding) does not read back
        /// until then, so a re-render right after a style change drew the old styles: a list button
        /// on a line between two lists added its marker one update late and the caret landed in the
        /// next row. Every read and write in the coordinator goes through here.
        private var writtenTextStyleData: Data??
        var textStyleData: Data? {
            get {
                if case .some(let written) = writtenTextStyleData { return written }
                return parent.textStyleData
            }
            set {
                writtenTextStyleData = .some(newValue)
                parent.textStyleData = newValue
            }
        }

        /// Called with each new `parent`: the binding now reflects what was written (and any change
        /// made outside the editor wins).
        func didReceiveParent() { writtenTextStyleData = nil }

        static let placeholderTag = 701

        var parent: NoteEditorTextView
        fileprivate static let paragraphStyleAttribute = NSAttributedString.Key("mirror.paragraphStyle")
        private static let highlightIndexAttribute = NSAttributedString.Key("mirror.highlightIndex")
        private static let textColorIndexAttribute = NSAttributedString.Key("mirror.textColorIndex")
        private static let indentLevelAttribute = NSAttributedString.Key("mirror.indentLevel")
        private static let fontChoiceAttribute = NSAttributedString.Key("mirror.fontChoice")
        private var isApplyingStyledText = false
        private var lastRenderedText: String?
        private var lastRenderedStyleSignature: Int?
        private var lastRenderedInlineSignature: Int?
        private var lastRenderedPhotoSignature: Int?
        private var lastRenderedWidth: CGFloat = 0
        private var lastRenderedFontChoice: WritingFontChoice?
        // Tracks cursor position across focus changes (Menu dismissal resets selectedRange)
        var lastKnownCursorLocation: Int = 0  // internal for tests
        /// Inline formatting chosen with nothing selected (B/I/U/S, highlight, colour, clear),
        /// kept for as long as the caret stays where it was chosen. Without it the next render pass
        /// rebuilt typing attributes from the paragraph style and the choice was lost.
        private var pendingTypingInline: (location: Int, inline: TypingInline)?
        /// A re-render was skipped because an input method was composing (setting
        /// `attributedText` ends the composition); it runs once the composition ends.
        private var renderDeferredForComposition = false
        /// Several lines were pasted into a list item (display range of the pasted text, the item's
        /// style and level). Lines after the first came in as body with no marker; textViewDidChange
        /// gives them the item's style and redraws.
        private var pastedIntoList: (range: NSRange, style: NoteParagraphTextStyle, level: Int)?

        /// The inline formatting the next typed character gets (links are never extended).
        struct TypingInline: Equatable {
            var bold = false
            var italic = false
            var underline = false
            var strikethrough = false
            var highlightIndex: Int? = nil
            var textColorIndex: Int? = nil
        }
        // textViewDidChange and textViewDidChangeSelection both fire per keystroke, each
        // scheduling an async scrollCaretToVisible. Under fast typing/auto-repeat backspace,
        // several of these land before the previous animated scroll finishes; each restarts
        // an animation toward its own target, and UIScrollView's animation can overshoot when
        // repeatedly interrupted this way — observed on-device as the whole document rubber-
        // banding to the top instead of following the caret. Only the most recent request
        // matters, so cancel any in-flight one before scheduling the next.
        private var pendingCaretScroll: DispatchWorkItem?
        // See sizeThatFits — floors the editor's reported height against the tallest it has
        // measured this session, so a transient short measurement can't shrink the scroll
        // content and reset the ScrollView's offset out from under the caret.
        var sessionMaxEditorHeight: CGFloat = 0
        var sessionMaxEditorHeightWidth: CGFloat = 0
        // See scrollCaretToVisible — the last contentOffset captured while the caret rect
        // looked trustworthy, restored when iOS's predictive-text engine faults and resets
        // the scroll view's offset out from under us.
        var lastGoodContentOffset: CGPoint?
        var lastAppliedCommandRevision = 0
        /// Set once the first programmatic focus placed the caret at the end (or the person
        /// focused the editor themselves, which keeps their caret).
        var placedInitialCaret = false
        // marker lengths per paragraph index, populated during render for coord mapping
        private var paragraphMarkerLengths: [Int: Int] = [:]

        init(parent: NoteEditorTextView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange),
                                                   name: UIContentSizeCategory.didChangeNotification, object: nil)
        }

        /// The text view this coordinator draws into (for redraws it starts itself).
        weak var textView: UITextView?

        /// The system text size the body font follows. A function so tests can change it.
        var contentSizeCategory: () -> UIContentSizeCategory = { UIApplication.shared.preferredContentSizeCategory }

        /// Text size changed in Settings while writing: body text is built from a cached font and
        /// attributed runs don't follow `adjustsFontForContentSizeCategory`, so redraw (headings
        /// already rebuild their fonts on each render).
        @objc func contentSizeCategoryDidChange() {
            guard let textView else { return }
            invalidateRenderedCache()
            applyStyledText(to: textView, preservingSelection: true)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            let location = gesture.location(in: textView)
            let textLayout = textView.layoutManager
            let containerOrigin = textView.textContainerInset
            let adjustedPoint = CGPoint(x: location.x - containerOrigin.left, y: location.y - containerOrigin.top)
            let charIndex = textLayout.characterIndex(
                for: adjustedPoint,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            let text = textView.text ?? ""
            let nsText = text as NSString
            guard charIndex < nsText.length else { return }

            // Photo attachment tap
            let char = nsText.character(at: charIndex)
            if char == 0xFFFC {
                // Find which photo token this corresponds to
                let displayed = textView.attributedText?.string ?? ""
                let photoTokens = allPhotoTokens(in: parent.text)
                // Match by object replacement char count (position among multiple attachments)
                var attachCount = 0
                for i in 0..<charIndex {
                    if (displayed as NSString).character(at: i) == 0xFFFC { attachCount += 1 }
                }
                let sortedTokens = photoTokens.sorted { parent.text.distance(from: parent.text.startIndex, to: $0.range.lowerBound) < parent.text.distance(from: parent.text.startIndex, to: $1.range.lowerBound) }
                if attachCount < sortedTokens.count, isPhotoReadable(sortedTokens[attachCount].index) {
                    parent.onPhotoTapped?(sortedTokens[attachCount].index)
                }
                return
            }

            guard let paraRange = checklistMarkerParagraph(at: location, in: textView) else { return }
            // Notes: checking an item leaves the caret where you were typing and doesn't raise the
            // keyboard (MirrorEditorTextView keeps UIKit's own tap from moving it).
            toggleChecklistItem(paragraphRange: paraRange, caret: textView.selectedRange.location, in: textView)
        }

        /// The circle of an item just checked springs in, as Notes' does: the drawn one is hidden for
        /// a moment and an image of it scales up in its place.
        private func popCheckedCircle(at marker: Int, in textView: UITextView) {
            guard UIView.areAnimationsEnabled, let lm = textView.layoutManager as? ChecklistLayoutManager,
                  let circle = lm.circle(forMarkerAt: marker, checked: true) else { return }
            let view = UIImageView(image: circle.image)
            view.frame = circle.rect.offsetBy(dx: textView.textContainerInset.left, dy: textView.textContainerInset.top)
            view.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            textView.addSubview(view)
            lm.hiddenCharacterRanges.append(NSRange(location: marker, length: 1))
            lm.invalidateDisplay(forCharacterRange: NSRange(location: marker, length: 1))
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8, options: [.allowUserInteraction]) {
                view.transform = .identity
            } completion: { _ in
                view.removeFromSuperview()
                lm.hiddenCharacterRanges.removeAll { $0 == NSRange(location: marker, length: 1) }
                lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textView.textStorage.length))
            }
        }

        /// The checklist item whose circle is under `location` (text view coordinates): the marker
        /// plus a margin, as wide as the item's text indent.
        func checklistMarkerParagraph(at location: CGPoint, in textView: UITextView) -> NSRange? {
            let nsText = (textView.text ?? "") as NSString
            guard nsText.length > 0 else { return nil }
            let inset = textView.textContainerInset
            let charIndex = textView.layoutManager.characterIndex(
                for: CGPoint(x: location.x - inset.left, y: location.y - inset.top),
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            guard charIndex < nsText.length else { return nil }
            let paraRange = nsText.paragraphRange(for: NSRange(location: charIndex, length: 0))
            let style = textStyle(at: paraRange.location, in: textView.attributedText)
            guard style == .checklistUnchecked || style == .checklistChecked else { return nil }
            // The tap must be on the item's first line, where the circle is.
            let glyph = textView.layoutManager.glyphIndexForCharacter(at: paraRange.location)
            let line = textView.layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            guard location.y - inset.top >= line.minY - 4, location.y - inset.top <= line.maxY + 4 else { return nil }
            let level = indentLevelValue(at: paraRange.location, in: textView.attributedText)
            let markerStart = inset.left + CGFloat(level) * 20
            let markerEnd = markerStart + ChecklistLayoutManager.textIndent + 4
            guard location.x >= markerStart - 8, location.x <= markerEnd else { return nil }
            return paraRange
        }

        /// Checks or unchecks the checklist item in `paraRange` (a tap on its marker, or the
        /// VoiceOver action). The caret ends at `caret`.
        func toggleChecklistItem(paragraphRange paraRange: NSRange, caret charIndex: Int, in textView: UITextView) {
            let currentStyle = textStyle(at: paraRange.location, in: textView.attributedText)
            guard currentStyle == .checklistUnchecked || currentStyle == .checklistChecked else { return }
            let iLevel = indentLevelValue(at: paraRange.location, in: textView.attributedText)
            let iFontChoice = fontChoiceValue(at: paraRange.location, in: textView.attributedText)

            let nextStyle: NoteParagraphTextStyle = currentStyle == .checklistUnchecked ? .checklistChecked : .checklistUnchecked
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())

            // Attribute changes alone re-color the row but never touch the ○/✓
            // character itself — swap the marker glyph in place so the tick shows
            // immediately instead of waiting for the next full re-render (e.g. Enter).
            let oldMarker = staticListMarkerPrefix(for: currentStyle, level: iLevel) ?? ""
            let newMarker = staticListMarkerPrefix(for: nextStyle, level: iLevel) ?? ""
            let markerRange = bounded(NSRange(location: paraRange.location, length: (oldMarker as NSString).length), in: mutable.string)
            if markerRange.length > 0 {
                mutable.replaceCharacters(in: markerRange, with: newMarker)
            }
            let styledRange = bounded(NSRange(
                location: paraRange.location,
                length: paraRange.length - markerRange.length + (newMarker as NSString).length
            ), in: mutable.string)

            mutable.removeAttribute(Self.paragraphStyleAttribute, range: styledRange)
            mutable.addAttributes(attributes(for: nextStyle, level: iLevel, fontChoice: iFontChoice), range: styledRange)
            mutable.addAttribute(Self.paragraphStyleAttribute, value: nextStyle.rawValue, range: styledRange)
            if iLevel > 0 { mutable.addAttribute(Self.indentLevelAttribute, value: iLevel, range: styledRange) }
            if iFontChoice != entryDefaultFontChoice { mutable.addAttribute(Self.fontChoiceAttribute, value: iFontChoice.rawValue, range: styledRange) }

            isApplyingStyledText = true
            // A hard `attributedText` swap reads as an instant, jarring cut when
            // toggling a checkbox — crossfade the marker glyph and the text dimming
            // together so it reads as one smooth transition, à la Notes.
            UIView.transition(with: textView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                // The paragraph font was just replaced, which drops inline bold/italic; put the stored ranges back.
                self.applyInlineStyles(to: mutable, from: self.parent.inlineStyleData)
                self.applyAttributedText(mutable, to: textView)
                textView.selectedRange = self.bounded(NSRange(location: charIndex, length: 0), in: textView.text)
            }
            isApplyingStyledText = false
            storeDocuments(from: textView)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Moving checked items to the bottom is the person's choice, asked on the first check
            // as Notes asks (WriteView owns the prompt and the setting, then sends Sort Done).
            if nextStyle == .checklistChecked {
                checkedItemCaret = (textView.selectedRange.location, Date())
                popCheckedCircle(at: paraRange.location, in: textView)
                parent.panelState.onChecklistItemChecked?()
            }
            commitUndoPoint(in: textView)
        }

        // MARK: - Photo context menu (UIContextMenuInteractionDelegate)

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let textView = interaction.view as? UITextView,
                  let photoIndex = photoAttachmentIndex(at: location, in: textView),
                  isPhotoReadable(photoIndex) else { return nil }
            let data = parent.photoDataArray[photoIndex]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let copy = UIAction(title: String(localized: "Copy"), image: UIImage(systemName: "doc.on.doc")) { _ in
                    if let image = UIImage(data: data) { UIPasteboard.general.image = image }
                }
                let save = UIAction(title: String(localized: "Save to Photos"), image: UIImage(systemName: "square.and.arrow.down")) { _ in
                    guard let image = UIImage(data: data) else { return }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }, completionHandler: nil)
                }
                let share = UIAction(title: String(localized: "Share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak textView] _ in
                    guard let image = UIImage(data: data) else { return }
                    presentShareSheet(items: [image], from: textView, rect: CGRect(origin: location, size: CGSize(width: 1, height: 1)))
                }
                return UIMenu(title: "", children: [copy, save, share])
            }
        }

        private func photoAttachmentIndex(at location: CGPoint, in textView: UITextView) -> Int? {
            let origin = textView.textContainerInset
            let adjusted = CGPoint(x: location.x - origin.left, y: location.y - origin.top)
            let charIndex = textView.layoutManager.characterIndex(
                for: adjusted, in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            let nsText = (textView.text ?? "") as NSString
            guard charIndex < nsText.length, nsText.character(at: charIndex) == 0xFFFC else { return nil }
            let displayed = textView.attributedText?.string ?? ""
            let tokens = allPhotoTokens(in: parent.text).sorted {
                parent.text.distance(from: parent.text.startIndex, to: $0.range.lowerBound) <
                parent.text.distance(from: parent.text.startIndex, to: $1.range.lowerBound)
            }
            var attachCount = 0
            for i in 0..<charIndex {
                if (displayed as NSString).character(at: i) == 0xFFFC { attachCount += 1 }
            }
            guard attachCount < tokens.count else { return nil }
            return tokens[attachCount].index
        }

        // UIFontDescriptor.preferredFontDescriptor + withDesign + UIFont init are not
        // free, and this is called on every keystroke/cursor movement across 13+ call
        // sites — cache the built font, keyed on the user's choice (so switching fonts in
        // the formatting panel takes effect immediately) and on the text size (so a text
        // size change in Settings does; it used to keep the old size until the editor closed).
        private var _bodyFontCache: (choice: WritingFontChoice, category: UIContentSizeCategory, font: UIFont)?
        func bodyFont(for choice: WritingFontChoice) -> UIFont {
            let category = contentSizeCategory()
            if let cache = _bodyFontCache, cache.choice == choice, cache.category == category {
                return cache.font
            }
            let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body,
                                                                compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
            let font = UIFont(descriptor: base.withDesign(choice.uiDesign) ?? base, size: 0)
            _bodyFontCache = (choice, category, font)
            return font
        }

        // Entry-wide default font — legitimate for contexts with no specific paragraph
        // in play (placeholder text, an empty document's typing attributes, etc).
        var serifBodyFont: UIFont { bodyFont(for: entryDefaultFontChoice) }

        func bodyAttributes(fontChoice: WritingFontChoice) -> [NSAttributedString.Key: Any] {
            [
                .font: bodyFont(for: fontChoice),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle(lineSpacing: 6)
            ]
        }

        var bodyAttributes: [NSAttributedString.Key: Any] { bodyAttributes(fontChoice: entryDefaultFontChoice) }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingStyledText else { return }
            if let paste = pastedIntoList {
                let nsText = (textView.text ?? "") as NSString
                let pasted = NSIntersectionRange(paste.range, NSRange(location: 0, length: nsText.length))
                if pasted.length > 0 {
                    let paragraphs = nsText.paragraphRange(for: pasted)
                    textView.textStorage.addAttribute(Self.paragraphStyleAttribute, value: paste.style.rawValue, range: paragraphs)
                    if paste.level > 0 { textView.textStorage.addAttribute(Self.indentLevelAttribute, value: paste.level, range: paragraphs) }
                }
            }
            if renderDeferredForComposition {
                // Stored styles changed while an input method was composing and the view hasn't
                // shown them yet: reading styles back from it would undo that change. Keep the
                // text in sync; once the composition ends, render the stored styles onto the
                // current text, then carry on as usual.
                parent.text = logicalText(from: textView)
                guard textView.markedTextRange == nil else {
                    if !changeWasGrouped { groupTypedChange(range: nil, replacement: nil) }
                    changeWasGrouped = false
                    committedSnapshot = currentSnapshot(of: textView)
                    return
                }
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: true)
            }
            parent.text = logicalText(from: textView)
            textStyleData = encodedTextStyleData(from: textView)
            parent.inlineStyleData = extractedInlineStyleData(from: textView)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
            updateTypingAttributes(for: textView)
            refreshActiveInlineStyles(in: textView)
            if !changeWasGrouped { groupTypedChange(range: nil, replacement: nil) }
            changeWasGrouped = false
            if pastedIntoList != nil {
                // Draw the markers for the pasted lines, keeping the caret at the same place in
                // the text (each new marker shifts display offsets after it).
                pastedIntoList = nil
                let logicalCaret = displayToLogical(display: textView.selectedRange.location,
                                                    map: buildLogicalOffsetMap(from: textView.attributedText ?? NSAttributedString()))
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: false)
                let map = buildLogicalOffsetMap(from: textView.attributedText ?? NSAttributedString())
                isApplyingStyledText = true
                textView.selectedRange = bounded(NSRange(location: logicalToDisplay(logical: logicalCaret, map: map), length: 0), in: textView.text)
                isApplyingStyledText = false
                updateTypingAttributes(for: textView)
            }
            committedSnapshot = currentSnapshot(of: textView)
            scrollCaretToVisible(in: textView)
        }

        /// The text view doesn't scroll (WriteView's ScrollView owns scrolling), so
        /// keep the caret above the keyboard by nudging the enclosing scroll view.
        /// A no-op when the caret rect is already fully visible.
        private func scrollCaretToVisible(in textView: UITextView) {
            // Reading caretRect/convert here, synchronously on every keystroke, was the bug:
            // this fires mid-edit, sometimes before UIKit's layoutManager has regenerated
            // glyphs for a text change that just landed (e.g. right when a wrapped line
            // un-wraps and the editor's height shrinks), and caretRect(for:) can answer with
            // a stale/degenerate rect from before that relayout — observed on-device as a
            // single keystroke snapping the whole scroll view to the very top of a long
            // entry instead of nudging it to follow the caret. Deferring the read itself
            // into the dispatched block, not just the scroll call, means it runs after
            // layout has settled on the final state.
            guard let ancestor = { () -> UIScrollView? in
                var view = textView.superview
                while let v = view, !(v is UIScrollView) { view = v.superview }
                return view as? UIScrollView
            }() else { return }

            pendingCaretScroll?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView, weak ancestor] in
                guard let textView, let scrollView = ancestor,
                      let selection = textView.selectedTextRange else { return }
                // Force the layout manager to finish flowing glyphs for the text container's
                // CURRENT size before asking it where the caret is. Without this, caretRect(for:)
                // can answer from stale layout right when the container's height just changed.
                textView.layoutManager.ensureLayout(for: textView.textContainer)
                let caret = textView.caretRect(for: selection.end)
                // iOS's own predictive-text engine intermittently faults — on-device logs show
                // it throwing internal TextInputUI/CandidateGeneration errors ("variant
                // selector cell index number could not be found", "Attempted to update
                // accumulator... after completion has already been called") — and as a side
                // effect of that fault it resets this UIScrollView's contentOffset to near-zero
                // itself, entirely outside this code, then hands the next caretRect(for:) call a
                // bogus answer too (observed: y = -1, impossible mid-document). isFinite alone
                // doesn't catch that — -1 is finite — so check plausibility against the laid-out
                // content instead. Confirmed on-device: caretRect stays poisoned until the next
                // real keystroke, not just for a moment, so retrying the read shortly after gets
                // nothing — restore the offset we already know was correct instead.
                let maxPlausibleY = textView.layoutManager.usedRect(for: textView.textContainer).maxY + textView.textContainerInset.top + textView.textContainerInset.bottom
                guard !caret.isNull, caret.origin.y.isFinite, caret.height.isFinite,
                      caret.origin.y >= 0, caret.origin.y <= maxPlausibleY + 1 else {
                    // Rare (only the OS fault above triggers it) and geometry-only — left in
                    // as a signal that the mitigation actually fired, not left over from
                    // debugging. Debug builds only.
                    #if DEBUG
                    print("[scrollDiag] rejected bad caret rect y=\(caret.origin.y) maxPlausibleY=\(maxPlausibleY)")
                    #endif
                    if let lastGood = self?.lastGoodContentOffset {
                        scrollView.setContentOffset(lastGood, animated: false)
                    }
                    return
                }
                let target = textView.convert(caret, to: scrollView).insetBy(dx: 0, dy: -48)
                // scrollRectToVisible(animated: true) doesn't offer a completion handler, and
                // reading scrollView.contentOffset back right after calling it (even one
                // runloop hop later) can catch it mid-animation, not settled — confirmed
                // against on-device logs where that read landed on an in-flight value nowhere
                // near the actual target. Driving the same move through an explicit UIView
                // animation gets a completion callback that fires once it's actually done, so
                // what gets saved as "last known good" is the real resting position.
                UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction], animations: {
                    scrollView.scrollRectToVisible(target, animated: false)
                }, completion: { finished in
                    // At typing speed a keystroke's animation is routinely superseded by the
                    // next one within ~100ms — completion still fires, but with finished=false
                    // and contentOffset at whatever the interrupted animation reached, not a
                    // resting position. Saving that would reintroduce the exact "read a
                    // mid-flight value" problem this completion-handler approach exists to avoid.
                    guard finished else { return }
                    self?.lastGoodContentOffset = scrollView.contentOffset
                })
            }
            pendingCaretScroll = work
            DispatchQueue.main.async(execute: work)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            if textView.markedTextRange != nil {
                if replacement == "\n" {
                    // Return while composing (Korean): commit the composed text first, so the
                    // list handling below works on finished text instead of ending the
                    // composition halfway through rebuilding the row.
                    textView.unmarkText()
                } else {
                    // Every other change while composing belongs to the input method; list and
                    // marker handling would rebuild the text and end the composition.
                    groupTypedChange(range: nil, replacement: replacement)
                    changeWasGrouped = true
                    return true
                }
            }
            let allowed = handleChange(textView, range: range, replacement: replacement)
            if allowed {
                // UIKit applies it; textViewDidChange records the result.
                groupTypedChange(range: range, replacement: replacement)
                changeWasGrouped = true
                if replacement.count > 1, replacement.contains("\n"), let attributed = textView.attributedText, attributed.length > 0 {
                    let at = min(range.location, attributed.length - 1)
                    let style = textStyle(at: at, in: attributed)
                    if isListStyle(style) {
                        pastedIntoList = (NSRange(location: range.location, length: (replacement as NSString).length), style,
                                          indentLevelValue(at: at, in: attributed))
                    }
                }
            } else {
                commitUndoPoint(in: textView)
            }
            return allowed
        }

        private func handleChange(_ textView: UITextView, range: NSRange, replacement: String) -> Bool {
            let rendered = textView.attributedText?.string ?? textView.text ?? ""
            if replacement.isEmpty, deletesInlinePhoto(in: rendered, range: range) {
                // Find which attachment char is being deleted
                let deleteTarget = range.length > 0 ? range.location : range.location - 1
                if deleteTarget >= 0 {
                    removeInlinePhoto(at: deleteTarget, from: textView)
                }
                return false
            }

            if replacement.isEmpty, exitsEmptyListAfterDeletion(in: rendered, range: range, textView: textView) {
                return false
            }

            if replacement.isEmpty, leavesListFromMarker(in: rendered, range: range, textView: textView) {
                return false
            }

            if replacement.isEmpty, mergesParagraphsOfDifferentStyle(in: rendered, range: range, textView: textView) {
                return false
            }

            // Notes-style shortcut: "1. " at the head of a body paragraph starts a
            // numbered list. Must run BEFORE insertsTextAfterListMarker (which only
            // fires on existing list paragraphs) — the guard here is style == .body.
            if replacement == " ",
               autoStartNumberedList(range: range, rendered: rendered, textView: textView) {
                return false
            }

            if !replacement.isEmpty,
               replacement != "\n",
               insertsTextAfterListMarker(replacement, range: range, rendered: rendered, textView: textView) {
                return false
            }

            if replacement == "\t" {
                let nsText = rendered as NSString
                let lookupLoc = min(max(0, range.location), max(0, nsText.length - 1))
                let paraRange = nsText.paragraphRange(for: NSRange(location: lookupLoc, length: 0))
                let style = textStyle(at: paraRange.location, in: textView.attributedText)
                if isListStyle(style) {
                    applyIndent(delta: +1, in: textView)
                    return false
                }
            }

            if replacement == "\n" {
                let nsText = rendered as NSString
                // Resolve the paragraph the caret is *in*.
                //
                // When the caret sits at the very end of the text AND the text ends
                // with a line break, the caret is in a virtual EMPTY trailing
                // paragraph — no characters, no style attribute of its own yet, and
                // always .body by convention. paragraphRange(for: {length, 0})
                // correctly isolates that empty paragraph.
                //
                // The old code always substituted `length - 1` here to get a valid,
                // in-bounds character index to sample a style from. That's still
                // right for a caret at the START of a line with real content after
                // it (e.g. a freshly created empty list item, where UIKit parks the
                // caret before the render-only marker — see below) — but when the
                // trailing paragraph is genuinely empty, `length - 1` instead lands
                // on the *previous* paragraph's own closing "\n" (a paragraph's
                // attributed run includes its trailing newline), misreading that
                // paragraph's real style AND content: a Return that had just exited
                // a list (leaving this empty virtual body paragraph behind) could
                // then be misread as "Return mid-content in the previous list
                // item," spawning a bogus new row instead of just continuing as
                // plain body text. Mirrors the fix already applied to
                // `apply(_:to:)`'s `currentStyle` lookup for the identical reason.
                let paragraphRange: NSRange
                let style: NoteParagraphTextStyle
                let endsWithLineBreak = nsText.length > 0 && {
                    let last = nsText.character(at: nsText.length - 1)
                    return last == 10 || last == 13
                }()
                if range.location >= nsText.length, endsWithLineBreak {
                    paragraphRange = NSRange(location: nsText.length, length: 0)
                    style = .body
                } else {
                    let lookupLoc = range.location >= nsText.length
                        ? max(0, nsText.length - 1)
                        : range.location
                    paragraphRange = nsText.paragraphRange(for: NSRange(location: max(0, lookupLoc), length: 0))
                    style = textStyle(at: paragraphRange.location, in: textView.attributedText)
                }
                let paragraph = nsText.substring(with: paragraphRange)
                if isListStyle(style) {
                    let level = indentLevelValue(at: paragraphRange.location, in: textView.attributedText)
                    let content = listContent(fromDisplayedParagraph: paragraph, style: style, level: level)
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        exitList(at: paragraphRange, in: textView)
                    } else {
                        insertListRow(replacing: range, style: style, in: textView)
                    }
                    return false
                }
                if style == .title || style == .heading || style == .subheading || style == .monospaced || style == .blockQuote {
                    // Headings/titles/mono/quote are one-line blocks by convention — continuing
                    // to type after Return should drop back to body text, not keep
                    // growing as another heading. Only affects what's typed *after* the
                    // break; text split off mid-paragraph keeps its own attributes.
                    // Font family is a separate, sticky property though — it survives
                    // the block-style reset, matching Notes/Docs/Notion.
                    let returnFontChoice = fontChoiceValue(at: paragraphRange.location, in: textView.attributedText)
                    textView.typingAttributes = styledAttributesForTyping(.body, numberedIndex: nil, level: 0, fontChoice: returnFontChoice)
                }
            }

            return true
        }

        private func insertsTextAfterListMarker(
            _ replacement: String,
            range: NSRange,
            rendered: String,
            textView: UITextView
        ) -> Bool {
            let nsText = rendered as NSString
            guard nsText.length > 0, range.location <= nsText.length else { return false }

            let lookupLocation = min(max(0, range.location), max(0, nsText.length - 1))
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: lookupLocation, length: 0))
            let style = textStyle(at: paragraphRange.location, in: textView.attributedText)
            guard isListStyle(style) else { return false }

            let paragraph = nsText.substring(with: paragraphRange)
            let markerLength: Int
            if style == .numberedList {
                markerLength = numberedListMarkerLength(in: paragraph)
            } else {
                markerLength = (staticListMarkerPrefix(for: style) as NSString?)?.length ?? 0
            }
            let markerEnd = paragraphRange.location + markerLength
            guard markerLength > 0, range.location < markerEnd else { return false }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let paraLevel = indentLevelValue(at: paragraphRange.location, in: mutable)
            let paraFontChoice = fontChoiceValue(at: paragraphRange.location, in: mutable)
            let insertionRange = bounded(NSRange(location: markerEnd, length: 0), in: mutable.string)
            let attributedReplacement = NSAttributedString(
                string: replacement,
                attributes: styledAttributesForTyping(style, numberedIndex: nil, level: paraLevel, fontChoice: paraFontChoice)
            )
            mutable.replaceCharacters(in: insertionRange, with: attributedReplacement)

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            textView.selectedRange = bounded(
                NSRange(location: insertionRange.location + (replacement as NSString).length, length: 0),
                in: textView.text
            )
            isApplyingStyledText = false

            storeDocuments(from: textView)
            textView.typingAttributes = styledAttributesForTyping(style, numberedIndex: nil, level: paraLevel, fontChoice: paraFontChoice)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
            refreshActiveParagraphStyle(in: textView)
            refreshActiveFontChoice(in: textView)
            return true
        }

        /// Typing a space right after "<digits>." at the start of a `.body`
        /// paragraph converts it to a numbered-list item, consuming the typed
        /// "<digits>." prefix. The renderer renumbers the block from 1, so "5. "
        /// still becomes item 1 — same as the Aa-panel toggle.
        private func autoStartNumberedList(range: NSRange, rendered: String, textView: UITextView) -> Bool {
            let nsText = rendered as NSString
            guard range.length == 0, range.location <= nsText.length else { return false }

            let lookup = min(range.location, max(0, nsText.length - 1))
            let paraRange = nsText.paragraphRange(for: NSRange(location: lookup, length: 0))
            guard range.location >= paraRange.location else { return false }
            guard textStyle(at: paraRange.location, in: textView.attributedText) == .body else { return false }

            let headLen = range.location - paraRange.location
            guard headLen >= 2 else { return false }
            let head = nsText.substring(with: NSRange(location: paraRange.location, length: headLen))
            guard head.hasSuffix("."), head.dropLast().allSatisfy({ $0.isNumber }) else { return false }

            // Drop the typed "<digits>." — keep the paragraph body for now.
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let prefixRange = bounded(NSRange(location: paraRange.location, length: headLen), in: mutable.string)
            mutable.replaceCharacters(in: prefixRange, with: "")

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false
            storeDocuments(from: textView)
            syncRenderedCache(from: textView)

            // Hand off to the shared command path — it covers the empty-doc,
            // ghost-paragraph, encode, marker-insert, cursor and panel-state cases
            // that a hand-rolled conversion here would each have to re-solve
            // (an empty paragraph after the prefix removal is exactly one of them).
            let caret = bounded(NSRange(location: paraRange.location, length: 0), in: textView.text)
            textView.selectedRange = caret
            lastKnownCursorLocation = caret.location
            apply(.numberedList, to: textView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return true
        }

        /// Backspace at the start of a list item's text (the caret sits just after the marker)
        /// turns the item into a body paragraph, as on Mac and in Notes. Without this the
        /// delete ate one marker character, and the half-marker was then saved as text.
        private func leavesListFromMarker(in rendered: String, range: NSRange, textView: UITextView) -> Bool {
            let nsText = rendered as NSString
            guard nsText.length > 0, range.location < nsText.length else { return false }
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: range.location, length: 0))
            let style = textStyle(at: paragraphRange.location, in: textView.attributedText)
            guard isListStyle(style) else { return false }
            let paragraph = nsText.substring(with: paragraphRange)
            let markerLength = style == .numberedList
                ? numberedListMarkerLength(in: paragraph)
                : ((staticListMarkerPrefix(for: style) as NSString?)?.length ?? 0)
            let markerEnd = paragraphRange.location + markerLength
            // Only a delete that starts inside the marker and stays inside it; a longer
            // selection that reaches into the text keeps its normal behavior.
            guard markerLength > 0, range.location < markerEnd, NSMaxRange(range) <= markerEnd else { return false }
            stripListMarkerAndApply(.body, at: markerEnd, in: textView)
            return true
        }

        private func exitsEmptyListAfterDeletion(in rendered: String, range: NSRange, textView: UITextView) -> Bool {
            let nsText = rendered as NSString
            guard nsText.length > 0, range.location <= nsText.length else { return false }

            let lookupLocation = min(max(0, range.location), max(0, nsText.length - 1))
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: lookupLocation, length: 0))
            let style = textStyle(at: paragraphRange.location, in: textView.attributedText)
            guard isListStyle(style) else { return false }

            let paragraph = nsText.substring(with: paragraphRange)
            let markerLength: Int
            if style == .numberedList {
                markerLength = numberedListMarkerLength(in: paragraph)
            } else {
                markerLength = (staticListMarkerPrefix(for: style) as NSString?)?.length ?? 0
            }
            guard markerLength > 0 else { return false }

            let boundedDeletion = bounded(range, in: rendered)
            let updatedRendered = nsText.replacingCharacters(in: boundedDeletion, with: "") as NSString
            let updatedParagraphRange = updatedRendered.paragraphRange(
                for: NSRange(location: min(paragraphRange.location, max(0, updatedRendered.length - 1)), length: 0)
            )
            let updatedParagraph = updatedParagraphRange.location < updatedRendered.length
                ? updatedRendered.substring(with: updatedParagraphRange)
                : ""

            let paraLevel = indentLevelValue(at: paragraphRange.location, in: textView.attributedText)
            let content = listContent(fromDisplayedParagraph: updatedParagraph, style: style, level: paraLevel)
            guard content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            // As in Notes: deleting an item's last letter leaves an empty item; only a Backspace on an
            // item that is already empty takes its circle away.
            let before = listContent(fromDisplayedParagraph: paragraph, style: style, level: paraLevel)
            guard before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

            exitList(at: paragraphRange, in: textView)
            return true
        }

        // Backspacing the "\n" that separates two differently-styled paragraphs (e.g. a
        // Heading line into the Body line below it) would otherwise fall through to
        // default UIKit deletion: the two character runs just get glued together, each
        // keeping its own attributes for now. But only one style is ever recorded per
        // paragraph — read from the merged paragraph's *first* character — so the next
        // full re-render (backgrounding, reopening the entry) silently promotes the
        // whole merged paragraph to that style. Handle the merge explicitly instead:
        // the preceding paragraph's style wins immediately, same convention as
        // Notion/Docs/Notes, so there's no delayed surprise.
        private func mergesParagraphsOfDifferentStyle(in rendered: String, range: NSRange, textView: UITextView) -> Bool {
            guard range.length == 1 else { return false }
            let nsText = rendered as NSString
            guard range.location >= 0, range.location < nsText.length,
                  nsText.character(at: range.location) == 10 else { return false }

            let prevStyle = textStyle(at: range.location, in: textView.attributedText)
            let nextLocation = range.location + 1
            guard nextLocation < nsText.length else { return false }
            let nextStyle = textStyle(at: nextLocation, in: textView.attributedText)
            guard !isListStyle(prevStyle), !isListStyle(nextStyle), prevStyle != nextStyle else { return false }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            mutable.deleteCharacters(in: NSRange(location: range.location, length: 1))

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            textView.selectedRange = bounded(NSRange(location: range.location, length: 0), in: textView.text)
            isApplyingStyledText = false
            parent.text = logicalText(from: textView)
            // textStyleData naturally records prevStyle for the merged paragraph (its
            // first character is untouched), and inline ranges are captured fresh here
            // — before the structural rebuild below touches paragraph-level font/color —
            // so bold/italic/highlight on either half survive the merge.
            textStyleData = encodedTextStyleData(from: textView)
            parent.inlineStyleData = extractedInlineStyleData(from: textView)
            invalidateRenderedCache()
            applyStyledText(to: textView, preservingSelection: true)
            syncRenderedCache(from: textView)
            updateTypingAttributes(for: textView)
            updatePlaceholder(in: textView)
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // A drag owns the touch; the others share it as before.
            !(gestureRecognizer is UILongPressGestureRecognizer && gestureRecognizer.view is MirrorEditorTextView)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let textView = gestureRecognizer.view as? UITextView else { return true }
            let point = gestureRecognizer.location(in: textView)
            if gestureRecognizer is UISwipeGestureRecognizer { return listParagraph(at: point, in: textView) != nil }
            if gestureRecognizer is UILongPressGestureRecognizer { return checklistMarkerParagraph(at: point, in: textView) != nil }
            return true
        }

        /// The list paragraph (any list style) under `point`, anywhere on its row.
        private func listParagraph(at point: CGPoint, in textView: UITextView) -> NSRange? {
            let text = (textView.text ?? "") as NSString
            guard text.length > 0 else { return nil }
            let inset = textView.textContainerInset
            let index = textView.layoutManager.characterIndex(for: CGPoint(x: point.x - inset.left, y: point.y - inset.top),
                                                              in: textView.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            guard index < text.length else { return nil }
            let para = text.paragraphRange(for: NSRange(location: index, length: 0))
            return isListStyle(textStyle(at: para.location, in: textView.attributedText)) ? para : nil
        }

        /// Swipe right on a list item indents it, left outdents it; the caret stays where it was.
        @objc func handleListSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard let textView = gesture.view as? UITextView,
                  let para = listParagraph(at: gesture.location(in: textView), in: textView) else { return }
            let text = (textView.text ?? "") as NSString
            let caret = paragraphCaretAnchor(textView.selectedRange.location, in: text)
            let marker = displayedMarkerLength(of: para, in: textView.attributedText ?? NSAttributedString())
            isApplyingStyledText = true
            textView.selectedRange = NSRange(location: para.location + marker, length: 0)
            isApplyingStyledText = false
            applyIndent(delta: gesture.direction == .right ? 1 : -1, in: textView)
            pendingParagraphCaret = caret
            applyPendingParagraphCaret(in: textView)
            pendingParagraphCaret = nil
            // Its own undo step, as a toolbar command makes in apply(_:to:).
            commitUndoPoint(in: textView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // MARK: Drag to reorder

        private struct ChecklistDrag {
            var row: Int
            var target: Int
            var block: Range<Int>
            var frames: [(chars: NSRange, rect: CGRect)]
            var snapshot: UIView
            var grabOffset: CGFloat
            var indicator: UIView
        }
        private var checklistDrag: ChecklistDrag?

        /// Touch and hold a circle, then drag: the item lifts and moves within its list, as in Notes.
        @objc func handleChecklistDrag(_ gesture: UILongPressGestureRecognizer) {
            guard let textView = gesture.view as? UITextView, let lm = textView.layoutManager as? ChecklistLayoutManager else { return }
            let point = gesture.location(in: textView)
            switch gesture.state {
            case .began:
                guard let para = checklistMarkerParagraph(at: point, in: textView) else { return }
                let frames = rowFrames(in: textView)
                guard let row = frames.firstIndex(where: { $0.chars.location == para.location }), frames[row].rect.height > 0,
                      let snapshot = textView.resizableSnapshotView(from: frames[row].rect, afterScreenUpdates: false, withCapInsets: .zero) else { return }
                let attributed = textView.attributedText ?? NSAttributedString()
                let isItem = { (i: Int) -> Bool in
                    let style = self.textStyle(at: frames[i].chars.location, in: attributed)
                    return style == .checklistUnchecked || style == .checklistChecked
                }
                var lower = row, upper = row + 1
                while lower > 0 && isItem(lower - 1) { lower -= 1 }
                while upper < frames.count && isItem(upper) { upper += 1 }
                snapshot.frame = frames[row].rect
                snapshot.layer.shadowColor = UIColor.black.cgColor
                snapshot.layer.shadowOpacity = 0.18
                snapshot.layer.shadowRadius = 10
                snapshot.layer.shadowOffset = CGSize(width: 0, height: 4)
                textView.addSubview(snapshot)
                let indicator = UIView(frame: CGRect(x: textView.textContainerInset.left, y: 0, width: textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right, height: 2))
                indicator.backgroundColor = lm.accentColor
                indicator.layer.cornerRadius = 1
                indicator.isHidden = true
                textView.addSubview(indicator)
                lm.hiddenCharacterRanges = [frames[row].chars]
                lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textView.textStorage.length))
                UIView.animate(withDuration: 0.15) { snapshot.transform = CGAffineTransform(scaleX: 1.02, y: 1.02) }
                checklistDrag = ChecklistDrag(row: row, target: row, block: lower..<upper, frames: frames, snapshot: snapshot,
                                              grabOffset: point.y - frames[row].rect.midY, indicator: indicator)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .changed:
                guard var drag = checklistDrag else { return }
                let top = drag.frames[drag.block.lowerBound].rect.midY
                let bottom = drag.frames[drag.block.upperBound - 1].rect.midY
                let centerY = min(max(point.y - drag.grabOffset, top), bottom)
                drag.snapshot.center.y = centerY
                // The other rows of the list, in order: the drop goes before the first whose middle
                // is below the dragged row's middle.
                let others = drag.block.filter { $0 != drag.row }
                let before = others.filter { drag.frames[$0].rect.midY < centerY }.count
                let target = drag.block.lowerBound + before
                if target != drag.target {
                    drag.target = target
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                // The line shows where it will land (nothing when it would stay put).
                if target == drag.row {
                    drag.indicator.isHidden = true
                } else {
                    let y = before < others.count ? drag.frames[others[before]].rect.minY : drag.frames[others[before - 1]].rect.maxY
                    drag.indicator.frame.origin.y = y - 1
                    drag.indicator.isHidden = false
                }
                checklistDrag = drag
            case .ended:
                guard let drag = checklistDrag else { return }
                checklistDrag = nil
                drag.indicator.removeFromSuperview()
                guard drag.target != drag.row, var rows = editorRows(in: textView) else { return settleDrag(drag, to: drag.frames[drag.row].rect, in: textView) }
                let moved = rows.remove(at: drag.row)
                rows.insert(moved, at: drag.target)
                commitRowOrder(rows, caret: textView.selectedRange.location, in: textView, slide: false)
                commitUndoPoint(in: textView)
                let after = rowFrames(in: textView)
                guard drag.target < after.count else { return settleDrag(drag, to: drag.frames[drag.row].rect, in: textView) }
                lm.hiddenCharacterRanges = [after[drag.target].chars]
                lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textView.textStorage.length))
                settleDrag(drag, to: after[drag.target].rect, in: textView)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .cancelled, .failed:
                guard let drag = checklistDrag else { return }
                checklistDrag = nil
                drag.indicator.removeFromSuperview()
                settleDrag(drag, to: drag.frames[drag.row].rect, in: textView)
            default:
                break
            }
        }

        private func settleDrag(_ drag: ChecklistDrag, to frame: CGRect, in textView: UITextView) {
            let lm = textView.layoutManager as? ChecklistLayoutManager
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                drag.snapshot.transform = .identity
                drag.snapshot.frame = frame
                drag.snapshot.layer.shadowOpacity = 0
            } completion: { _ in
                drag.snapshot.removeFromSuperview()
                lm?.hiddenCharacterRanges = []
                lm?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textView.textStorage.length))
            }
        }

        // MARK: Edit menu: check or uncheck selected items

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let attributed = textView.attributedText else { return nil }
            let text = attributed.string as NSString
            let covered = text.paragraphRange(for: bounded(range, in: attributed.string))
            var items = 0, checked = 0
            text.enumerateSubstrings(in: covered, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
                let style = self.textStyle(at: enclosing.location, in: attributed)
                if style == .checklistUnchecked || style == .checklistChecked { items += 1 }
                if style == .checklistChecked { checked += 1 }
            }
            guard items > 0 else { return nil }
            let allChecked = checked == items
            let action = UIAction(title: allChecked ? String(localized: "Uncheck") : String(localized: "Check"),
                                  image: UIImage(systemName: allChecked ? "circle" : "checkmark.circle")) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.bulkSetChecklist(allChecked ? .checklistUnchecked : .checklistChecked, in: textView, within: covered)
                self.commitUndoPoint(in: textView)
            }
            return UIMenu(children: [action] + suggestedActions)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingStyledText, textView.isFirstResponder else { return }
            lastKnownCursorLocation = textView.selectedRange.location
            // The caret moves inside the composition; clamping it or rewriting typing attributes
            // there would break the input method.
            guard textView.markedTextRange == nil else { return }
            clampCursorPastListMarker(in: textView)
            updateTypingAttributes(for: textView)
            refreshActiveParagraphStyle(in: textView)
            refreshActiveFontChoice(in: textView)
            refreshActiveInlineStyles(in: textView)
            scrollCaretToVisible(in: textView)
        }

        // Moves cursor to after the list marker when it lands inside the glyph prefix.
        // Async dispatch avoids re-entrancy; the follow-up textViewDidChangeSelection
        // will see the corrected position and hit the early-return guard.
        private func clampCursorPastListMarker(in textView: UITextView) {
            let selRange = textView.selectedRange
            guard selRange.length == 0 else { return }
            let nsText = (textView.text ?? "") as NSString
            guard nsText.length > 0, selRange.location < nsText.length else { return }

            let paraRange = nsText.paragraphRange(for: NSRange(location: selRange.location, length: 0))
            let style = textStyle(at: paraRange.location, in: textView.attributedText)
            guard isListStyle(style) else { return }

            let level = indentLevelValue(at: paraRange.location, in: textView.attributedText)
            let markerLen: Int
            if style == .numberedList {
                markerLen = numberedListMarkerLength(in: nsText.substring(with: paraRange))
            } else {
                markerLen = (staticListMarkerPrefix(for: style, level: level) as NSString?)?.length ?? 0
            }
            let markerEnd = paraRange.location + markerLen
            guard selRange.location < markerEnd else { return }

            DispatchQueue.main.async {
                guard textView.isFirstResponder else { return }
                textView.selectedRange = self.bounded(NSRange(location: markerEnd, length: 0), in: textView.text)
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            placedInitialCaret = true   // a tap placed the caret; never move it to the end later
            parent.isFocused = true
            // A sort that ran while the editor was unfocused (behind the sorting prompt): iOS
            // resets the caret when editing resumes, so put it back in the row it followed.
            if let pending = pendingCaretLocation {
                pendingCaretLocation = nil
                textView.selectedRange = bounded(NSRange(location: pending, length: 0), in: textView.text)
            }
            lastKnownCursorLocation = textView.selectedRange.location
            refreshActiveParagraphStyle(in: textView)
            refreshActiveFontChoice(in: textView)
            refreshActiveInlineStyles(in: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func apply(_ command: NoteTextCommand, to textView: UITextView) {
            switch command {
            case .undo:
                undoEdit(in: textView)
            case .redo:
                redoEdit(in: textView)
            case .moveCursor:
                performCommand(command, to: textView)
            default:
                performCommand(command, to: textView)
                commitUndoPoint(in: textView)
            }
        }

        private func performCommand(_ command: NoteTextCommand, to textView: UITextView) {
            // Inline style commands
            switch command {
            case .bold, .italic, .underline, .strikethrough:
                toggleInlineStyle(command, in: textView)
                return
            case .highlight(let index):
                applyHighlight(index, in: textView)
                return
            case .textColor(let index):
                applyTextColor(index, in: textView)
                return
            case .link(let url):
                applyLink(urlString: url, in: textView)
                return
            case .clearFormatting:
                applyClearFormatting(in: textView)
                return
            case .fontFamily(let choice):
                applyFontFamily(choice, in: textView)
                return
            case .checkAllItems:
                bulkSetChecklist(.checklistChecked, in: textView)
                return
            case .uncheckAllItems:
                bulkSetChecklist(.checklistUnchecked, in: textView)
                return
            case .deleteCheckedItems:
                deleteCheckedChecklistItems(in: textView)
                return
            case .sortCheckedToBottom:
                sortCheckedToBottom(in: textView)
                return
            case .indentMore:
                applyIndent(delta: +1, in: textView)
                return
            case .indentLess:
                applyIndent(delta: -1, in: textView)
                return
            case .undo, .redo:
                return   // handled in apply(_:to:)
            case .moveCursor(let location):
                // Runs in the same updateUIView pass as the text-diff branch above (lines
                // 75-81), which has already applied the new text to textView by the time any
                // command reaches here — so this clamps against the *new* text, not stale state.
                let newRange = bounded(NSRange(location: location, length: 0), in: textView.text)
                textView.selectedRange = newRange
                // Every other selectedRange-setting call site in this file also refreshes
                // typingAttributes to match the paragraph at the new location — skipping it here
                // left the caret rendering with whatever typingAttributes were last active
                // (from the editor's *previous* content/font, before the template/append), which
                // showed up on-device as an oversized caret glyph, not just a wrong-looking one.
                let sampleLocation = max(0, newRange.location - 1)
                let style = textStyle(at: sampleLocation, in: textView.attributedText)
                let level = indentLevelValue(at: sampleLocation, in: textView.attributedText)
                let fontChoice = fontChoiceValue(at: sampleLocation, in: textView.attributedText)
                textView.typingAttributes = styledAttributesForTyping(style, numberedIndex: nil, level: level, fontChoice: fontChoice)
                return
            default: break
            }

            let nsText = (textView.text ?? "") as NSString
            let liveCursorLocation = textView.isFirstResponder ? textView.selectedRange.location : lastKnownCursorLocation
            let cursorLocation = min(liveCursorLocation, max(0, nsText.length))
            lastKnownCursorLocation = cursorLocation

            // Determine target style. List styles toggle off when already active.
            //
            // When the cursor sits at the very end of the text AND that end is a virtual
            // empty paragraph (text ends with a line break), it has no style of its own yet
            // — sampling `length - 1` would read the *preceding* paragraph's own attribute
            // off its closing "\n" (paragraph runs include their own trailing newline), not
            // this new paragraph's true .body state. That misread flips `targetStyle` below
            // (e.g. .body→.numberedList reads as an active-list toggle-off) and routes into
            // the "strip list marker" branch instead of the dedicated virtual-empty-paragraph
            // branch further down — which then strips the *preceding* real paragraph's marker.
            let paragraphStart = nsText.length > 0
                ? nsText.paragraphRange(for: NSRange(location: min(cursorLocation, nsText.length - 1), length: 0)).location
                : 0
            let currentStyle: NoteParagraphTextStyle
            if cursorLocation >= nsText.length, nsText.length > 0, nsText.character(at: nsText.length - 1) == 10 {
                currentStyle = .body
            } else {
                // Read the paragraph's style where it starts: with the caret at the end of a row,
                // the character under it is the row's line break, which can still carry the style
                // of the row Return made it from (a body line typed after leaving a checklist
                // read as a checklist, so the button turned the list off instead of on).
                currentStyle = textStyle(at: paragraphStart, in: textView.attributedText)
            }
            let targetStyle: NoteParagraphTextStyle
            if command == .checklist {
                // Matches bulleted/dashed/numbered below: only clears to .body when
                // a checklist is already active — was clearing on ANY active list
                // type (isListStyle), so tapping Checklist on a bulleted/dashed/
                // numbered row deleted the list instead of converting it, unlike
                // every other list-type button which converts in place.
                let isChecklist = currentStyle == .checklistUnchecked || currentStyle == .checklistChecked
                targetStyle = isChecklist ? .body : .checklistUnchecked
            } else if command == .bulletedList {
                targetStyle = currentStyle == .bulletedList ? .body : .bulletedList
            } else if command == .dashedList {
                targetStyle = currentStyle == .dashedList ? .body : .dashedList
            } else if command == .numberedList {
                targetStyle = currentStyle == .numberedList ? .body : .numberedList
            } else {
                targetStyle = paragraphStyle(for: command)
            }

            let cursorLevel = isListStyle(targetStyle) ? indentLevelValue(at: paragraphStart, in: textView.attributedText) : 0
            // A paragraph-STYLE command (Heading/Body/list toggle) must never silently
            // reset the cursor's current font — resolve and carry it through every
            // branch below, same as cursorLevel already does for indent.
            let cursorFontChoice = fontChoiceValue(at: min(cursorLocation, max(0, (textView.attributedText?.length ?? 1) - 1)), in: textView.attributedText)

            if nsText.length == 0 {
                let emptyFontChoice = emptyDocumentStyle().1
                storeEmptyDocumentStyle(targetStyle, fontChoice: emptyFontChoice)
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: false)
                if let marker = staticListMarkerPrefix(for: targetStyle) {
                    textView.selectedRange = bounded(NSRange(location: marker.count, length: 0), in: textView.text)
                } else if targetStyle == .numberedList {
                    textView.selectedRange = bounded(NSRange(location: "1.\t".count, length: 0), in: textView.text)
                }
                var typing = styledAttributesForTyping(targetStyle, numberedIndex: 1, level: cursorLevel, fontChoice: emptyFontChoice)
                // An empty entry: keep a B / I / U / S picked before the style, at the caret's new
                // place past any list marker.
                if let pending = pendingTypingInline {
                    overlay(pending.inline, onto: &typing)
                    textView.typingAttributes = typing
                    rememberTypingInline(in: textView)
                } else {
                    textView.typingAttributes = typing
                }
                updatePlaceholder(in: textView)
                setActiveParagraphStyle(targetStyle)
                refreshActiveInlineStyles(in: textView)
                return
            }

            // Strip the visual list marker whenever transitioning from any list style to any non-list style.
            if isListStyle(currentStyle) && !isListStyle(targetStyle) {
                stripListMarkerAndApply(targetStyle, at: cursorLocation, in: textView)
                setActiveParagraphStyle(targetStyle)
                return
            }

            // Cursor is in a virtual empty paragraph past the last character (e.g. "Hello\n", cursor at 6).
            // paragraphRange(for: {length, 0}) returns an empty range that enumerateSubstrings never visits,
            // so the style change silently no-ops. Handle it explicitly.
            if cursorLocation >= nsText.length {
                if isListStyle(targetStyle) {
                    // Extend textStyleData to cover the virtual paragraph, then re-render to insert the marker.
                    var styles = decodedTextStyles()
                    var indentLevels = decodedIndentLevels()
                    var fontChoices = decodedFontChoices()
                    if styles.isEmpty {
                        var count = 0
                        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length),
                                                   options: [.byParagraphs, .substringNotRequired]) { _, _, _, _ in count += 1 }
                        styles = Array(repeating: .body, count: count)
                    }
                    // Preserve existing paragraphs' indent/font before appending or overwriting the
                    // virtual one below — rebuilding the document from `styles` alone would silently
                    // drop every other paragraph's font/indent override.
                    while indentLevels.count < styles.count { indentLevels.append(0) }
                    while fontChoices.count < styles.count { fontChoices.append(entryDefaultFontChoice.rawValue) }
                    // Only append when cursor is in a true ghost paragraph (text ends with a line break).
                    // When the last paragraph just has no trailing newline (e.g. "○  " clamped to end),
                    // the last styles entry already covers it — update it instead of appending.
                    let lastChar = nsText.length > 0 ? nsText.character(at: nsText.length - 1) : 0
                    let endsWithLineBreak = lastChar == 10 || lastChar == 13
                    if endsWithLineBreak || styles.isEmpty {
                        styles.append(targetStyle)
                        indentLevels.append(cursorLevel)
                        fontChoices.append(cursorFontChoice.rawValue)
                    } else {
                        styles[styles.count - 1] = targetStyle
                        indentLevels[indentLevels.count - 1] = cursorLevel
                        fontChoices[fontChoices.count - 1] = cursorFontChoice.rawValue
                    }
                    let hasIndent = indentLevels.contains { $0 != 0 }
                    let hasFontOverride = fontChoices.contains { WritingFontChoice(rawValue: $0) != entryDefaultFontChoice }
                    textStyleData = try? JSONEncoder().encode(NoteTextStyleDocument(
                        paragraphStyles: styles,
                        indentLevels: hasIndent ? indentLevels : nil,
                        fontChoices: hasFontOverride ? fontChoices : nil
                    ))
                    invalidateRenderedCache()
                    applyStyledText(to: textView, preservingSelection: false)
                    let markerLen: Int
                    if targetStyle == .numberedList {
                        let nsDisplay = (textView.text ?? "") as NSString
                        let safePos = max(0, nsDisplay.length - 1)
                        let pRange = nsDisplay.paragraphRange(for: NSRange(location: safePos, length: 0))
                        markerLen = numberedListMarkerLength(in: nsDisplay.substring(with: pRange))
                    } else {
                        markerLen = (staticListMarkerPrefix(for: targetStyle) as NSString?)?.length ?? 0
                    }
                    textView.selectedRange = bounded(
                        NSRange(location: cursorLocation + markerLen, length: 0),
                        in: textView.text
                    )
                    textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: nil, level: cursorLevel, fontChoice: cursorFontChoice)
                } else {
                    // Non-list style: typing attributes alone are sufficient; no re-render needed.
                    textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: nil, level: cursorLevel, fontChoice: cursorFontChoice)
                }
                updatePlaceholder(in: textView)
                setActiveParagraphStyle(targetStyle)
                refreshActiveInlineStyles(in: textView)
                return
            }

            // A real (non-zero-length) selection can span multiple paragraphs — widen to
            // the full selection so every paragraph it touches gets restyled, not just
            // the one at the selection's start.
            let selectionRange = textView.isFirstResponder ? textView.selectedRange : NSRange(location: cursorLocation, length: 0)
            let cursorRange = bounded(selectionRange, in: nsText as String)
            let paragraphRange = nsText.paragraphRange(for: cursorRange)

            // List A → different List B: setParagraphStyle changes the attribute first, then calls
            // logicalText which can no longer match the old marker prefix → parent.text gets the old
            // marker baked in → re-render double-prefixes (e.g. "1.  ○  hello"). Strip the old marker
            // explicitly before applying the new style.
            if isListStyle(currentStyle) && isListStyle(targetStyle) && currentStyle != targetStyle {
                stripListMarkerAndApply(targetStyle, at: cursorLocation, in: textView)
                if staticListMarkerPrefix(for: targetStyle, level: cursorLevel) != nil || targetStyle == .numberedList {
                    invalidateRenderedCache()
                    applyStyledText(to: textView, preservingSelection: false)
                    let nsPost = (textView.text ?? "") as NSString
                    let safeLoc = min(cursorLocation, max(0, nsPost.length - 1))
                    let postPara = nsPost.paragraphRange(for: NSRange(location: safeLoc, length: 0))
                    let newMarkerLen: Int
                    if targetStyle == .numberedList {
                        newMarkerLen = numberedListMarkerLength(in: nsPost.substring(with: postPara))
                    } else {
                        newMarkerLen = (staticListMarkerPrefix(for: targetStyle, level: cursorLevel) as NSString?)?.length ?? 0
                    }
                    textView.selectedRange = bounded(
                        NSRange(location: postPara.location + newMarkerLen, length: 0),
                        in: textView.text
                    )
                }
                textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: nil, level: cursorLevel, fontChoice: cursorFontChoice)
                setActiveParagraphStyle(targetStyle)
                refreshActiveInlineStyles(in: textView)
                return
            }

            // The caret as a row and a distance from that row's end, so it lands in the same place
            // whether the re-render that adds the marker happens now or on the next update.
            let anchor = paragraphCaretAnchor(cursorLocation, in: nsText)
            nsText.enumerateSubstrings(in: paragraphRange, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                self.setParagraphStyle(targetStyle, range: range, in: textView)
            }
            if staticListMarkerPrefix(for: targetStyle) != nil || targetStyle == .numberedList {
                pendingParagraphCaret = anchor
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: false)
                applyPendingParagraphCaret(in: textView)
            } else {
                textView.selectedRange = bounded(NSRange(location: cursorLocation, length: 0), in: textView.text)
            }
            textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: nil, level: cursorLevel, fontChoice: cursorFontChoice)
            updatePlaceholder(in: textView)
            setActiveParagraphStyle(targetStyle)
        }

        // Strips the list marker from the current paragraph and applies targetStyle.
        // Handles all transitions: list → body, list → heading, list → title, list → monospaced, etc.
        private func stripListMarkerAndApply(_ targetStyle: NoteParagraphTextStyle, at cursorLocation: Int, in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let nsDisplay = attributed.string as NSString
            let safeLocation = min(cursorLocation, max(0, nsDisplay.length - 1))
            let displayParaRange = nsDisplay.paragraphRange(for: NSRange(location: safeLocation, length: 0))
            let displayPara = nsDisplay.substring(with: displayParaRange)

            let currentStyle = textStyle(at: displayParaRange.location, in: attributed)
            let markerLen: Int
            if currentStyle == .numberedList {
                markerLen = numberedListMarkerLength(in: displayPara)
            } else {
                markerLen = (staticListMarkerPrefix(for: currentStyle) as NSString?)?.length ?? 0
            }

            let mutable = NSMutableAttributedString(attributedString: attributed)

            if markerLen > 0 {
                let markerRange = bounded(NSRange(location: displayParaRange.location, length: markerLen), in: mutable.string)
                mutable.replaceCharacters(in: markerRange, with: "")
            }

            let newParaLen = max(0, displayParaRange.length - markerLen)
            let newParaRange = bounded(NSRange(location: displayParaRange.location, length: newParaLen), in: mutable.string)
            if newParaRange.length > 0 {
                let level = indentLevelValue(at: displayParaRange.location, in: attributed)
                let fontChoice = fontChoiceValue(at: displayParaRange.location, in: attributed)
                mutable.removeAttribute(Self.paragraphStyleAttribute, range: newParaRange)
                mutable.addAttributes(attributes(for: targetStyle, level: level, fontChoice: fontChoice), range: newParaRange)
                if targetStyle != .body {
                    mutable.addAttribute(Self.paragraphStyleAttribute, value: targetStyle.rawValue, range: newParaRange)
                }
                if fontChoice != entryDefaultFontChoice {
                    mutable.addAttribute(Self.fontChoiceAttribute, value: fontChoice.rawValue, range: newParaRange)
                }
            }

            isApplyingStyledText = true
            // The paragraph font was just replaced, which drops inline bold/italic; put the stored ranges back.
            applyInlineStyles(to: mutable, from: parent.inlineStyleData)
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false

            storeDocuments(from: textView)
            syncRenderedCache(from: textView)

            let newCursor = max(displayParaRange.location, cursorLocation - markerLen)
            textView.selectedRange = bounded(NSRange(location: newCursor, length: 0), in: textView.text)
            let typingFontChoice = fontChoiceValue(at: displayParaRange.location, in: attributed)
            textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: nil, level: 0, fontChoice: typingFontChoice)
            updatePlaceholder(in: textView)
        }

        private func removeListAndApplyBody(at cursorLocation: Int, in textView: UITextView) {
            stripListMarkerAndApply(.body, at: cursorLocation, in: textView)
        }

        func applyStyledText(to textView: UITextView, preservingSelection: Bool) {
            let selectedRange = textView.selectedRange
            let rawText = parent.text
            let styleSignature = textStyleData?.hashValue
            let inlineSignature = parent.inlineStyleData?.hashValue
            let photoSignature = parent.photoDataArray.map(\.count).reduce(0, +)
            let width = textView.bounds.width.rounded()
            let fontChoice = WritingFontChoice(rawValue: parent.fontChoiceRaw) ?? .system

            let isComposing = textView.markedTextRange != nil
            if lastRenderedText == rawText,
               lastRenderedStyleSignature == styleSignature,
               lastRenderedInlineSignature == inlineSignature,
               lastRenderedPhotoSignature == photoSignature,
               lastRenderedWidth == width,
               lastRenderedFontChoice == fontChoice {
                // While an input method composes (Japanese, Chinese, Korean), the selection and
                // typing attributes belong to it.
                guard !isComposing else { return }
                if preservingSelection {
                    textView.selectedRange = bounded(selectedRange, in: textView.text)
                }
                updateTypingAttributes(for: textView)
                return
            }
            // Setting attributedText would end the composition mid-word; render when it ends.
            if isComposing {
                renderDeferredForComposition = true
                return
            }
            renderDeferredForComposition = false

            let attributed = renderedAttributedText(for: rawText, width: textView.bounds.width)
            applyInlineStyles(to: attributed, from: parent.inlineStyleData)

            isApplyingStyledText = true
            applyAttributedText(attributed, to: textView)
            isApplyingStyledText = false
            lastRenderedText = rawText
            lastRenderedStyleSignature = styleSignature
            lastRenderedInlineSignature = inlineSignature
            lastRenderedPhotoSignature = photoSignature
            lastRenderedWidth = width
            lastRenderedFontChoice = fontChoice
            if preservingSelection {
                textView.selectedRange = bounded(selectedRange, in: textView.text)
            }
            applyPendingParagraphCaret(in: textView)
            updateTypingAttributes(for: textView)
            // The first render is the undo baseline (before any updateUIView has run).
            if committedSnapshot == nil { committedSnapshot = currentSnapshot(of: textView) }
        }

        func updatePlaceholder(in textView: UITextView) {
            let placeholder = textView.viewWithTag(Self.placeholderTag) as? UILabel
            placeholder?.isHidden = !parent.text.isEmpty || textStyleData != nil
            placeholder?.font = serifBodyFont
        }

        private func refreshActiveParagraphStyle(in textView: UITextView) {
            guard let attributed = textView.attributedText, attributed.length > 0 else {
                setActiveParagraphStyle(emptyDocumentStyle().0)
                return
            }
            if lastKnownCursorLocation >= attributed.length {
                if let raw = textView.typingAttributes[Self.paragraphStyleAttribute] as? String,
                   let style = NoteParagraphTextStyle(rawValue: raw) {
                    setActiveParagraphStyle(style)
                } else {
                    setActiveParagraphStyle(.body)
                }
                return
            }
            let loc = min(lastKnownCursorLocation, attributed.length - 1)
            setActiveParagraphStyle(textStyle(at: loc, in: attributed))
        }

        private func refreshActiveFontChoice(in textView: UITextView) {
            guard let attributed = textView.attributedText, attributed.length > 0 else {
                parent.panelState.activeFontChoice = emptyDocumentStyle().1
                return
            }
            if lastKnownCursorLocation >= attributed.length {
                if let raw = textView.typingAttributes[Self.fontChoiceAttribute] as? String,
                   let choice = WritingFontChoice(rawValue: raw) {
                    parent.panelState.activeFontChoice = choice
                } else {
                    parent.panelState.activeFontChoice = entryDefaultFontChoice
                }
                return
            }
            let loc = min(lastKnownCursorLocation, attributed.length - 1)
            parent.panelState.activeFontChoice = fontChoiceValue(at: loc, in: attributed)
        }

        func logicalText(from textView: UITextView) -> String {
            let attributed = textView.attributedText ?? NSAttributedString()
            let nsDisplay = attributed.string as NSString
            guard nsDisplay.length > 0 else { return "" }
            // Each attachment character becomes its photo's token, in text order.
            let photoTokensSorted = allPhotoTokens(in: parent.text).sorted {
                parent.text.distance(from: parent.text.startIndex, to: $0.range.lowerBound) <
                parent.text.distance(from: parent.text.startIndex, to: $1.range.lowerBound)
            }
            var tokenIdx = 0

            var result = ""
            // Paragraphs and their attributes are read in display offsets. Swapping the tokens in
            // first (as this used to) inflated every offset after a photo, so styles were read from
            // the wrong paragraph and list markers were saved into the text.
            // enclosingRange (3rd param) includes the paragraph separator (\n).
            nsDisplay.enumerateSubstrings(in: NSRange(location: 0, length: nsDisplay.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosingRange, _ in
                let markerLen = self.displayedMarkerLength(of: enclosingRange, in: attributed)
                let content = nsDisplay.substring(with: NSRange(location: enclosingRange.location + markerLen, length: enclosingRange.length - markerLen))
                guard content.contains("\u{fffc}") else { result += content; return }
                for ch in content {
                    if ch == "\u{fffc}" {
                        result += tokenIdx < photoTokensSorted.count ? inlinePhotoToken(at: photoTokensSorted[tokenIdx].index) : inlinePhotoToken(at: tokenIdx)
                        tokenIdx += 1
                    } else {
                        result.append(ch)
                    }
                }
            }
            return result
        }

        func displayTextEquivalent(for rawText: String) -> String {
            let nsText = rawText as NSString
            guard nsText.length > 0 else { return rawText }
            var result = ""
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosingRange, _ in
                let paragraph = nsText.substring(with: enclosingRange)
                if let prefix = self.legacyMarkdownPrefix(in: paragraph) {
                    result += String(paragraph.dropFirst(prefix.count))
                } else if let prefix = self.legacyChecklistPrefix(in: paragraph) {
                    result += String(paragraph.dropFirst(prefix.count))
                } else {
                    result += paragraph
                }
            }
            return result
        }

        func bounded(_ range: NSRange, in text: String) -> NSRange {
            let length = (text as NSString).length
            let location = min(max(0, range.location), length)
            let availableLength = max(0, length - location)
            return NSRange(location: location, length: min(range.length, availableLength))
        }

        private func trailingLineBreak(from text: String) -> String {
            if text.hasSuffix("\r\n") { return "\r\n" }
            if text.hasSuffix("\n") { return "\n" }
            if text.hasSuffix("\r") { return "\r" }
            return ""
        }

        // fontChoice is required, not defaulted — callers changing an EXISTING
        // paragraph's style must explicitly read and preserve its current font via
        // fontChoiceValue(at:in:) (same pattern already used for `level`), so a style
        // change (e.g. checking a checklist item) never silently resets that
        // paragraph's font back to the entry default.
        private func attributes(for style: NoteParagraphTextStyle, level: Int = 0, numberedIndex: Int? = nil, fontChoice: WritingFontChoice) -> [NSAttributedString.Key: Any] {
            switch style {
            case .subheading:
                return [
                    .font: UIFont.preferredFont(forTextStyle: .headline),
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: paragraphStyle(lineSpacing: 4, paragraphSpacing: 6)
                ]
            case .heading:
                return [
                    .font: UIFont.preferredFont(forTextStyle: .title2).bolded(),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraphStyle(lineSpacing: 4, paragraphSpacing: 8)
                ]
            case .title:
                return [
                    .font: UIFont.preferredFont(forTextStyle: .largeTitle).bolded(),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraphStyle(lineSpacing: 3, paragraphSpacing: 10)
                ]
            case .monospaced:
                return [
                    .font: UIFont.monospacedSystemFont(ofSize: bodyFont(for: fontChoice).pointSize, weight: .regular),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
                ]
            case .blockQuote:
                let ps = paragraphStyle(lineSpacing: 5, paragraphSpacing: 8)
                // A single, non-wrapping indent — quotes here are a body-text
                // treatment (muted, set in), not a list, so there's no
                // marker/tab-stop machinery to keep first-line and wrapped-line
                // indents in sync the way listAttributes/checklistAttributes do.
                // Deliberately not italic: the Italic inline toggle manages
                // .traitItalic on the rendered font directly (applyInlineStyles /
                // isStyleApplied), so baking italic into the paragraph style's
                // own base font would make the "I" button read as falsely
                // selected on every quote, and toggling it off would silently
                // strip the quote's font trait. Indent + secondaryLabel alone
                // reads clearly as a quote without touching that toggle's
                // territory (secondaryLabel also matches .subheading's choice).
                ps.headIndent = 16
                ps.firstLineHeadIndent = 16
                return [
                    .font: bodyFont(for: fontChoice),
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: ps
                ]
            case .checklistUnchecked:
                return checklistAttributes(checked: false, level: level, fontChoice: fontChoice)
            case .checklistChecked:
                return checklistAttributes(checked: true, level: level, fontChoice: fontChoice)
            case .bulletedList, .dashedList:
                return listAttributes(level: level, fontChoice: fontChoice)
            case .numberedList:
                return listAttributes(level: level, fontChoice: fontChoice, numbered: true)
            case .body:
                return bodyAttributes(fontChoice: fontChoice)
            }
        }

        private func attributes(for paragraph: String, storedStyle: NoteParagraphTextStyle = .body, allowLegacyDetection: Bool = true, level: Int = 0, fontChoice: WritingFontChoice) -> [NSAttributedString.Key: Any] {
            if storedStyle != .body {
                return attributes(for: storedStyle, level: level, fontChoice: fontChoice)
            }
            // Only infer block style from a leading "# " / "○ " / 4-space on true
            // legacy entries. New-schema content stores its style explicitly, so
            // such a prefix there is literal text the user typed, not a marker.
            guard allowLegacyDetection else {
                return bodyAttributes(fontChoice: fontChoice)
            }
            if paragraph.hasPrefix("### ") { return attributes(for: .subheading, fontChoice: fontChoice) }
            if paragraph.hasPrefix("## ") { return attributes(for: .heading, fontChoice: fontChoice) }
            if paragraph.hasPrefix("# ") { return attributes(for: .title, fontChoice: fontChoice) }
            if paragraph.hasPrefix("    ") { return attributes(for: .monospaced, fontChoice: fontChoice) }
            if paragraph.hasPrefix("○ ") { return checklistAttributes(checked: false, level: level, fontChoice: fontChoice) }
            if paragraph.hasPrefix("✓ ") { return checklistAttributes(checked: true, level: level, fontChoice: fontChoice) }
            return bodyAttributes(fontChoice: fontChoice)
        }

        private func checklistAttributes(checked: Bool, level: Int = 0, fontChoice: WritingFontChoice) -> [NSAttributedString.Key: Any] {
            let offset = CGFloat(level) * 20
            // Rows 35pt apart at body size, as in Notes (5 left them about 32pt apart).
            let ps = paragraphStyle(lineSpacing: 6, paragraphSpacing: 8)
            ps.firstLineHeadIndent = offset
            // Text starts 36pt in, past the circle (ChecklistLayoutManager), as in Notes; the
            // marker is kerned out to the same edge, so wrapped lines line up with the first.
            ps.headIndent = ChecklistLayoutManager.textIndent + offset
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont(for: fontChoice),
                // Notes keeps a checked item's text at full ink; only the circle changes.
                .foregroundColor: UIColor.label,
                .paragraphStyle: ps
            ]
            return attrs
        }

        private func listAttributes(level: Int = 0, fontChoice: WritingFontChoice, numbered: Bool = false) -> [NSAttributedString.Key: Any] {
            let offset = CGFloat(level) * 20
            let ps = paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
            ps.firstLineHeadIndent = offset
            if numbered {
                // Marker is "N.\t". The tab stop == headIndent, so the text after
                // the tab and the wrapped lines share one left edge. 20pt is a
                // tight, Notes-like gap that still clears a single digit; a
                // two-digit "10." overruns it and falls to the 38pt stop (its
                // wrapped lines still align at 20 — acceptable past 10 items).
                ps.headIndent = 20 + offset
                ps.tabStops = [
                    NSTextTab(textAlignment: .left, location: 20 + offset),
                    NSTextTab(textAlignment: .left, location: 38 + offset),
                ]
            } else {
                ps.headIndent = 28 + offset
            }
            return [
                .font: bodyFont(for: fontChoice),
                .foregroundColor: UIColor.label,
                .paragraphStyle: ps
            ]
        }

        private func renderedAttributedText(for rawText: String, width: CGFloat) -> NSMutableAttributedString {
            paragraphMarkerLengths.removeAll()
            let attributed = NSMutableAttributedString()

            if rawText.isEmpty,
               let firstStyle = decodedTextStyles().first {
                let marker = staticListMarkerPrefix(for: firstStyle) ?? (firstStyle == .numberedList ? "1.\t" : nil)
                if let marker {
                    let firstFontChoice = decodedFontChoices().first.flatMap(WritingFontChoice.init(rawValue:)) ?? entryDefaultFontChoice
                    let paragraph = NSMutableAttributedString(string: marker, attributes: attributes(for: firstStyle, fontChoice: firstFontChoice))
                    paragraph.addAttribute(Self.paragraphStyleAttribute, value: firstStyle.rawValue, range: NSRange(location: 0, length: paragraph.length))
                    if firstFontChoice != entryDefaultFontChoice {
                        paragraph.addAttribute(Self.fontChoiceAttribute, value: firstFontChoice.rawValue, range: NSRange(location: 0, length: paragraph.length))
                    }
                    attributed.append(paragraph)
                    paragraphMarkerLengths[0] = (marker as NSString).length
                }
                return attributed
            }

            // Split on all photo tokens, render text segments between them
            let regex = try? NSRegularExpression(pattern: #"\[\[mirror-photo(?:-(\d+))?\]\]"#)
            let nsRaw = rawText as NSString
            let allMatches = regex?.matches(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)) ?? []

            // A segment's first paragraph index is the number of line breaks before it, so the
            // text on either side of a photo token shares the photo line's one slot. Counting each
            // segment's pieces gave a photo line two slots, while the encoder and the Mac codec
            // store one: every style below a mid-text photo read the next paragraph's entry.
            func paragraphIndex(at location: Int) -> Int {
                var count = 0
                var i = 0
                while i < location {
                    if nsRaw.character(at: i) == 10 { count += 1 }
                    i += 1
                }
                return count
            }

            var lastEnd = 0

            for match in allMatches {
                let textRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let textSegment = nsRaw.substring(with: textRange)
                let rendered = renderedTextWithoutMarkdownMarkers(for: textSegment, startingParagraph: paragraphIndex(at: lastEnd), continuesLine: lastEnd > 0)
                attributed.append(rendered.value)

                let token = nsRaw.substring(with: match.range)
                let photoIdx = inlinePhotoIndex(from: token) ?? 0
                attributed.append(photoAttachmentString(at: photoIdx, width: width))
                lastEnd = NSMaxRange(match.range)
            }

            let tail = nsRaw.substring(from: lastEnd)
            attributed.append(renderedTextWithoutMarkdownMarkers(for: tail, startingParagraph: paragraphIndex(at: lastEnd), continuesLine: lastEnd > 0).value)
            return attributed
        }

        /// `continuesLine`: the segment starts right after a photo token, so its first piece is the
        /// rest of the photo's line. That line's marker was already drawn before the photo; drawing
        /// it again after the photo put a second one there, which was then saved into the text.
        private func renderedTextWithoutMarkdownMarkers(for rawText: String, startingParagraph: Int, continuesLine: Bool = false) -> (value: NSAttributedString, paragraphCount: Int) {
            let attributed = NSMutableAttributedString()
            let rawParagraphs = rawText.components(separatedBy: "\n")
            guard !rawParagraphs.isEmpty else { return (attributed, 0) }
            let storedStyles = decodedTextStyles()
            let storedIndents = decodedIndentLevels()
            let storedFontChoices = decodedFontChoices()
            var paragraphIndex = startingParagraph
            // Keyed by indent level so a nested numbered sub-list restarts at 1
            // instead of continuing the parent's sequence (StoryPad/flutter_quill
            // doesn't nest numbered lists at all; Notes and Notion both restart
            // per level, which is what this matches). A level's counter is
            // dropped once a shallower-or-equal-level paragraph is seen, so
            // returning to the outer list resumes its own count rather than the
            // nested one.
            var numberedListCounters: [Int: Int] = [:]

            for (offset, rawLine) in rawParagraphs.enumerated() {
                let lineBreak = offset < rawParagraphs.count - 1 ? "\n" : ""
                let rawParagraph = rawLine + lineBreak
                let legacyStyle = self.legacyStyle(in: rawParagraph)
                // A stored style entry means new-schema content: block style is
                // authoritative and legacy markdown/checklist prefix parsing
                // ("# ", "○ ", 4-space) must NOT run — otherwise a paragraph the
                // user literally typed starting with "# " has that prefix
                // stripped from display (and gets title attributes) on every
                // full re-render, silently mangling their text.
                let hasStoredStyle = storedStyles.indices.contains(paragraphIndex)
                let storedStyle = hasStoredStyle ? storedStyles[paragraphIndex] : legacyStyle
                let indentLevel = storedIndents.indices.contains(paragraphIndex) ? storedIndents[paragraphIndex] : 0
                let hasFontOverride = storedFontChoices.indices.contains(paragraphIndex)
                let fontChoice = hasFontOverride
                    ? (WritingFontChoice(rawValue: storedFontChoices[paragraphIndex]) ?? entryDefaultFontChoice)
                    : entryDefaultFontChoice

                // Track numbered list counter per indent level for sequential
                // numbering that restarts on nesting (see comment at declaration).
                let isLineContinuation = continuesLine && offset == 0
                var numberedListCounter = 0
                if isLineContinuation {
                    // Same line as the photo: no marker, no new number.
                } else if storedStyle == .numberedList {
                    numberedListCounters = numberedListCounters.filter { $0.key <= indentLevel }
                    numberedListCounter = (numberedListCounters[indentLevel] ?? 0) + 1
                    numberedListCounters[indentLevel] = numberedListCounter
                } else {
                    numberedListCounters.removeAll()
                }

                let rawDisplayParagraph: String
                if hasStoredStyle {
                    rawDisplayParagraph = rawParagraph
                } else {
                    let prefix = self.legacyMarkdownPrefix(in: rawParagraph)
                    let legacyChecklistPrefix = self.legacyChecklistPrefix(in: rawParagraph)
                    rawDisplayParagraph = prefix.map { String(rawParagraph.dropFirst($0.count)) }
                        ?? legacyChecklistPrefix.map { String(rawParagraph.dropFirst($0.count)) }
                        ?? rawParagraph
                }

                let listMarker: String
                if isLineContinuation {
                    listMarker = ""
                } else if storedStyle == .numberedList {
                    listMarker = "\(numberedListCounter).\t"
                } else {
                    listMarker = self.staticListMarkerPrefix(for: storedStyle, level: indentLevel) ?? ""
                }
                let displayParagraph = listMarker.isEmpty ? rawDisplayParagraph : listMarker + rawDisplayParagraph

                let markerLen = (listMarker as NSString).length
                if markerLen > 0 { paragraphMarkerLengths[paragraphIndex] = markerLen }

                let paragraph = NSMutableAttributedString(
                    string: displayParagraph,
                    attributes: self.attributes(for: rawParagraph, storedStyle: storedStyle, allowLegacyDetection: !hasStoredStyle, level: indentLevel, fontChoice: fontChoice)
                )
                if storedStyle != .body, paragraph.length > 0 {
                    paragraph.addAttribute(Self.paragraphStyleAttribute, value: storedStyle.rawValue, range: NSRange(location: 0, length: paragraph.length))
                }
                if indentLevel > 0, paragraph.length > 0 {
                    paragraph.addAttribute(Self.indentLevelAttribute, value: indentLevel, range: NSRange(location: 0, length: paragraph.length))
                }
                // Tag only when it actually differs from the entry default — same rule
                // used at every live-edit site, so a later edit that re-resolves this
                // paragraph's font (e.g. a checklist toggle) can't silently strip an
                // explicit tag by disagreeing on what "explicit" means.
                if fontChoice != entryDefaultFontChoice, paragraph.length > 0 {
                    paragraph.addAttribute(Self.fontChoiceAttribute, value: fontChoice.rawValue, range: NSRange(location: 0, length: paragraph.length))
                }
                attributed.append(paragraph)
                paragraphIndex += 1
            }
            return (attributed, paragraphIndex - startingParagraph)
        }

        /// VoiceOver can't tap a checkbox: the checklist item at the caret gets a custom action,
        /// named for what it does, so it also says whether the item is done.
        func checklistAccessibilityActions(in textView: UITextView) -> [UIAccessibilityCustomAction] {
            let nsText = (textView.text ?? "") as NSString
            guard nsText.length > 0, let attributed = textView.attributedText else { return [] }
            let location = min(textView.selectedRange.location, nsText.length - 1)
            let paragraph = nsText.paragraphRange(for: NSRange(location: location, length: 0))
            let style = textStyle(at: paragraph.location, in: attributed)
            guard style == .checklistUnchecked || style == .checklistChecked else { return [] }
            let name = style == .checklistChecked ? String(localized: "Mark as not done") : String(localized: "Mark as done")
            return [UIAccessibilityCustomAction(name: name) { [weak self, weak textView] _ in
                guard let self, let textView else { return false }
                self.toggleChecklistItem(paragraphRange: paragraph, caret: textView.selectedRange.location, in: textView)
                return true
            }]
        }

        /// Whether photo `index` has data that decodes to an image (tap and context menu ignore the rest).
        private func isPhotoReadable(_ index: Int) -> Bool {
            index < parent.photoDataArray.count && photoCache.isReadable(parent.photoDataArray[index], at: index)
        }

        /// Decoded, downsampled photo images for the attachments, kept across re-renders. Every
        /// re-render (list Return, checklist tap, a paragraph style) used to make a fresh
        /// `UIImage(data:)` per photo, which decodes the full-size JPEG again on the main thread
        /// when drawn: ~31 ms per re-render with three 12 MP photos on an iPhone 14 Pro.
        private var photoCache = PhotoAttachmentCache()

        /// Drawn for a token whose photo is missing or won't decode. It must be a real attachment
        /// character: `logicalText` turns each one back into its token, and photo lookups count
        /// them. Rendering nothing (as this used to) dropped the token on the next keystroke and
        /// matched every later photo to the wrong token.
        private func unreadablePhotoAttachmentString() -> NSAttributedString {
            let config = UIImage.SymbolConfiguration(pointSize: 34, weight: .light)
            let symbol = UIImage(systemName: "photo.badge.exclamationmark", withConfiguration: config)?
                .withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal)
            let attachment = NSTextAttachment()
            attachment.image = symbol
            attachment.accessibilityLabel = String(localized: "Photo unavailable")
            if let size = symbol?.size { attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: size) }
            let result = NSMutableAttributedString(attachment: attachment)
            result.addAttributes([
                .paragraphStyle: paragraphStyle(lineSpacing: 8, paragraphSpacing: 8),
                .font: bodyFont(for: entryDefaultFontChoice),
                .foregroundColor: UIColor.label
            ], range: NSRange(location: 0, length: result.length))
            return result
        }

        private func photoAttachmentString(at photoIndex: Int, width: CGFloat) -> NSAttributedString {
            let maxWidth = max(180, width - 8)
            guard photoIndex < parent.photoDataArray.count,
                  let photo = photoCache.image(for: parent.photoDataArray[photoIndex], at: photoIndex, maxWidth: maxWidth,
                                               displayScale: max(UITraitCollection.current.displayScale, 2)) else {
                return unreadablePhotoAttachmentString()
            }

            let attachment = NSTextAttachment()
            attachment.image = photo.image
            attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: photo.displaySize)

            let result = NSMutableAttributedString(attachment: attachment)
            // Font/color matter here even though nothing visible renders them on the
            // attachment glyph itself: when a photo lands as the last character with
            // nothing typed after it (e.g. attaching to a blank entry — see
            // textWithInlinePhotoToken's no-trailing-newline case), there's no real
            // text run left for UIKit's own typing-attributes-on-selection-change
            // inheritance (or our updateTypingAttributes) to read from. Without them
            // here, a cursor placed right after the photo inherits nothing and UIKit
            // falls back to its own tiny default font/black text for whatever gets
            // typed next.
            result.addAttributes([
                .paragraphStyle: paragraphStyle(lineSpacing: 8, paragraphSpacing: 8),
                .font: bodyFont(for: entryDefaultFontChoice),
                .foregroundColor: UIColor.label
            ], range: NSRange(location: 0, length: result.length))
            return result
        }

        private func deletesInlinePhoto(in rendered: String, range: NSRange) -> Bool {
            guard !parent.photoDataArray.isEmpty else { return false }
            // Find all attachment chars in rendered
            let nsRendered = rendered as NSString
            var attachRanges: [NSRange] = []
            for i in 0..<nsRendered.length {
                if nsRendered.character(at: i) == 0xFFFC {
                    attachRanges.append(NSRange(location: i, length: 1))
                }
            }
            guard !attachRanges.isEmpty else { return false }
            if range.length > 0 {
                return attachRanges.contains { NSIntersectionRange(range, $0).length > 0 }
            }
            return attachRanges.contains { range.location == $0.location || range.location == NSMaxRange($0) }
        }

        private func removeInlinePhoto(at displayCharIndex: Int, from textView: UITextView) {
            // Determine which photo token this corresponds to
            let displayed = textView.text ?? ""
            var attachCount = 0
            let nsDisplayed = displayed as NSString
            for i in 0..<displayCharIndex {
                if nsDisplayed.character(at: i) == 0xFFFC { attachCount += 1 }
            }

            let photoTokensSorted = allPhotoTokens(in: parent.text).sorted {
                parent.text.distance(from: parent.text.startIndex, to: $0.range.lowerBound) <
                parent.text.distance(from: parent.text.startIndex, to: $1.range.lowerBound)
            }
            guard attachCount < photoTokensSorted.count else { return }
            let token = photoTokensSorted[attachCount]
            let tokenStr = inlinePhotoToken(at: token.index)

            // Remove from photoDataArray
            var photos = parent.photoDataArray
            if token.index < photos.count { photos.remove(at: token.index) }
            // Remove the token line from the text: the line break before it, else the one after.
            var updatedText = parent.text as NSString
            var removedBreakBefore = false
            var removedBreakAfter = false
            let tokenRange = updatedText.range(of: tokenStr)
            if tokenRange.location != NSNotFound {
                let tokenEnd = NSMaxRange(tokenRange)
                var removal = tokenRange
                if tokenRange.location > 0, updatedText.character(at: tokenRange.location - 1) == 10 {
                    removal = NSRange(location: tokenRange.location - 1, length: tokenRange.length + 1)
                    removedBreakBefore = true
                } else if tokenEnd < updatedText.length, updatedText.character(at: tokenEnd) == 10 {
                    removal.length += 1
                    removedBreakAfter = true
                }
                updatedText = updatedText.replacingCharacters(in: removal, with: "") as NSString
            }
            // Renumber subsequent tokens (indices shift down by 1)
            // A token past the end (a photo that failed to decode or save) has nothing after it to renumber.
            for i in stride(from: token.index + 1, to: parent.photoDataArray.count, by: 1) {
                updatedText = updatedText.replacingOccurrences(of: inlinePhotoToken(at: i), with: inlinePhotoToken(at: i - 1)) as NSString
            }
            // Inline ranges count the photo as its one attachment character, so make the same
            // removal there (renumbering a token changes nothing in those coordinates); otherwise
            // formatting below the photo shifts by one or two characters.
            if tokenRange.location != NSNotFound, let attributed = textView.attributedText {
                let map = buildLogicalOffsetMap(from: attributed)
                var location = displayToLogical(display: displayCharIndex, map: map)
                var length = 1
                if removedBreakBefore { location -= 1; length += 1 } else if removedBreakAfter { length += 1 }
                parent.inlineStyleData = NoteEditorCodec.adjustInlineStyles(parent.inlineStyleData,
                                                                            replacing: NSRange(location: max(0, location), length: length), withLength: 0)
            }
            parent.photoDataArray = photos
            parent.text = updatedText as String
            applyStyledText(to: textView, preservingSelection: false)
            textView.selectedRange = bounded(textView.selectedRange, in: textView.text)
            updatePlaceholder(in: textView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        private func legacyMarkdownPrefix(in paragraph: String) -> String? {
            if paragraph.hasPrefix("### ") { return "### " }
            if paragraph.hasPrefix("## ") { return "## " }
            if paragraph.hasPrefix("# ") { return "# " }
            return nil
        }

        private func legacyChecklistPrefix(in paragraph: String) -> String? {
            if paragraph.hasPrefix("○ ") { return "○ " }
            if paragraph.hasPrefix("✓ ") { return "✓ " }
            return nil
        }

        private func legacyStyle(in paragraph: String) -> NoteParagraphTextStyle {
            if paragraph.hasPrefix("### ") { return .subheading }
            if paragraph.hasPrefix("## ") { return .heading }
            if paragraph.hasPrefix("# ") { return .title }
            if paragraph.hasPrefix("    ") { return .monospaced }
            if paragraph.hasPrefix("✓ ") { return .checklistChecked }
            if paragraph.hasPrefix("○ ") { return .checklistUnchecked }
            return .body
        }

        private func updateTypingAttributes(for textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            // A checklist marker's spacer is kerned (ChecklistMarkerSpacing); typed text must not be.
            if textView.typingAttributes[.kern] != nil { textView.typingAttributes.removeValue(forKey: .kern) }
            let nsText = (textView.text ?? "") as NSString
            guard nsText.length > 0 else {
                // An empty entry's style lives in the stored style data (Title or a font picked
                // in Aa before typing). Every SwiftUI update re-runs this, so resetting to body
                // here made the first word typed after picking Title come out as body.
                let (style, fontChoice) = emptyDocumentStyle()
                var typing = styledAttributesForTyping(style, numberedIndex: 1, level: 0, fontChoice: fontChoice)
                // B / I / U / S or a color picked before the first character lives only in the
                // typing attributes; rebuilding them here dropped it, so the first word came out
                // plain and the bar and panel showed the style off.
                if let pending = pendingTypingInline, pending.location == 0 {
                    overlay(pending.inline, onto: &typing)
                }
                textView.typingAttributes = typing
                return
            }

            let cursorLoc = textView.selectedRange.location
            // Cursor is in a virtual empty paragraph past the last character (e.g. after "Hello\n").
            // Reading attributed text at length-1 would return the \n's style (the *previous* paragraph),
            // which would wrongly overwrite typing attrs the user just set via the format panel.
            if cursorLoc >= nsText.length {
                restoreInlineIndexKeys(in: textView, at: cursorLoc)
                return
            }

            let style = textStyle(at: cursorLoc, in: textView.attributedText)
            let level = indentLevelValue(at: cursorLoc, in: textView.attributedText)
            let fontChoice = fontChoiceValue(at: cursorLoc, in: textView.attributedText)
            var typing = styledAttributesForTyping(style, numberedIndex: nil, level: level, fontChoice: fontChoice)
            // Inline formatting: what was just chosen at this caret, else the character before the
            // caret in the same paragraph (as in Notes: typing after a bold word stays bold).
            let selection = textView.selectedRange
            if let pending = pendingTypingInline, pending.location == selection.location, selection.length == 0 {
                overlay(pending.inline, onto: &typing)
            } else {
                pendingTypingInline = nil
                if let attributed = textView.attributedText, let inline = inheritedTypingInline(before: cursorLoc, in: attributed) {
                    overlay(inline, onto: &typing)
                }
            }
            textView.typingAttributes = typing
        }

        /// After each keystroke UIKit rebuilds the typing attributes from the text it just inserted.
        /// The highlight and text colors survive, but the index keys don't, so at the end of the
        /// text only the first character typed carried them: the rest showed the color but were
        /// saved without it, and the bar's highlight toggle read as off. Puts the keys back when the
        /// character before the caret has them and its color is still being typed.
        private func restoreInlineIndexKeys(in textView: UITextView, at location: Int) {
            guard let attributed = textView.attributedText,
                  let previous = inheritedTypingInline(before: location, in: attributed) else { return }
            var typing = textView.typingAttributes
            var changed = false
            if typing[Self.highlightIndexAttribute] == nil, let idx = previous.highlightIndex,
               typingColor(typing[.backgroundColor], matches: HighlightPalette.colors(for: parent.displayMode), at: idx, traits: textView.traitCollection) {
                typing[Self.highlightIndexAttribute] = idx
                changed = true
            }
            if typing[Self.textColorIndexAttribute] == nil, let idx = previous.textColorIndex,
               typingColor(typing[.foregroundColor], matches: TextColorPalette.colors(for: parent.displayMode), at: idx, traits: textView.traitCollection) {
                typing[Self.textColorIndexAttribute] = idx
                changed = true
            }
            if changed { textView.typingAttributes = typing }
        }

        /// Compares resolved components: two `UIColor(Color)` conversions of the same adaptive
        /// palette entry are separate objects that `isEqual` doesn't match.
        private func typingColor(_ value: Any?, matches palette: [Color], at index: Int, traits: UITraitCollection) -> Bool {
            guard let color = value as? UIColor, palette.indices.contains(index) else { return false }
            var a: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var b: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            guard color.resolvedColor(with: traits).getRed(&a.0, green: &a.1, blue: &a.2, alpha: &a.3),
                  UIColor(palette[index]).resolvedColor(with: traits).getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3)
            else { return false }
            return abs(a.0 - b.0) < 0.01 && abs(a.1 - b.1) < 0.01 && abs(a.2 - b.2) < 0.01 && abs(a.3 - b.3) < 0.01
        }

        /// The inline formatting of the character before `location`, if it is in the same paragraph
        /// and is text (not a list marker, a photo or the paragraph break).
        private func inheritedTypingInline(before location: Int, in attributed: NSAttributedString) -> TypingInline? {
            let nsText = attributed.string as NSString
            guard location > 0, location <= nsText.length else { return nil }
            let paragraph = nsText.paragraphRange(for: NSRange(location: location - 1, length: 0))
            let contentStart = paragraph.location + displayedMarkerLength(of: paragraph, in: attributed)
            guard location - 1 >= contentStart else { return nil }
            let previous = nsText.character(at: location - 1)
            guard previous != 10, previous != 0xFFFC else { return nil }
            return typingInline(from: attributed.attributes(at: location - 1, effectiveRange: nil),
                                style: textStyle(at: location - 1, in: attributed))
        }

        private func typingInline(from attributes: [NSAttributedString.Key: Any], style: NoteParagraphTextStyle) -> TypingInline {
            let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            let paragraphBold = style == .heading || style == .title || style == .subheading
            return TypingInline(
                bold: traits.contains(.traitBold) && !paragraphBold,
                italic: traits.contains(.traitItalic),
                underline: attributes[.underlineStyle] != nil,
                strikethrough: attributes[.strikethroughStyle] != nil,
                highlightIndex: attributes[Self.highlightIndexAttribute] as? Int,
                textColorIndex: attributes[Self.textColorIndexAttribute] as? Int
            )
        }

        private func overlay(_ inline: TypingInline, onto typing: inout [NSAttributedString.Key: Any]) {
            if let font = typing[.font] as? UIFont {
                var styled = font
                if inline.bold { styled = styled.withTrait(.traitBold, add: true) }
                if inline.italic { styled = styled.withTrait(.traitItalic, add: true) }
                typing[.font] = styled
            }
            if inline.underline { typing[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if inline.strikethrough { typing[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            let highlights = HighlightPalette.colors(for: parent.displayMode)
            if let index = inline.highlightIndex, highlights.indices.contains(index) {
                typing[.backgroundColor] = UIColor(highlights[index])
                typing[Self.highlightIndexAttribute] = index
            }
            let textColors = TextColorPalette.colors(for: parent.displayMode)
            if let index = inline.textColorIndex, textColors.indices.contains(index) {
                typing[.foregroundColor] = UIColor(textColors[index])
                typing[Self.textColorIndexAttribute] = index
            }
        }

        /// Records the typing attributes a no-selection formatting choice just set.
        private func rememberTypingInline(in textView: UITextView) {
            guard textView.selectedRange.length == 0 else { pendingTypingInline = nil; return }
            let location = textView.selectedRange.location
            let style = textView.attributedText.map { textStyle(at: min(location, max(0, $0.length - 1)), in: $0) } ?? .body
            pendingTypingInline = (location, typingInline(from: textView.typingAttributes, style: style))
        }

        private func paragraphStyle(for command: NoteTextCommand) -> NoteParagraphTextStyle {
            switch command {
            case .checklist:    return .checklistUnchecked
            case .bulletedList: return .bulletedList
            case .dashedList:   return .dashedList
            case .numberedList: return .numberedList
            case .title:        return .title
            case .heading:      return .heading
            case .subheading:   return .subheading
            case .monospaced:   return .monospaced
            case .blockQuote:   return .blockQuote
            default:            return .body
            }
        }

        private func styledAttributesForTyping(_ style: NoteParagraphTextStyle, numberedIndex: Int?, level: Int = 0, fontChoice: WritingFontChoice) -> [NSAttributedString.Key: Any] {
            var result = attributes(for: style, level: level, fontChoice: fontChoice)
            if style != .body {
                result[Self.paragraphStyleAttribute] = style.rawValue
            }
            if level > 0 {
                result[Self.indentLevelAttribute] = level
            }
            if fontChoice != entryDefaultFontChoice {
                result[Self.fontChoiceAttribute] = fontChoice.rawValue
            }
            return result
        }

        private func textStyle(at location: Int, in attributed: NSAttributedString?) -> NoteParagraphTextStyle {
            guard let attributed, attributed.length > 0 else { return .body }
            let location = min(max(0, location), attributed.length - 1)
            if let rawValue = attributed.attribute(Self.paragraphStyleAttribute, at: location, effectiveRange: nil) as? String,
               let style = NoteParagraphTextStyle(rawValue: rawValue) {
                return style
            }
            return .body
        }

        private func setParagraphStyle(_ style: NoteParagraphTextStyle, range: NSRange, in textView: UITextView) {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let boundedRange = bounded(range, in: mutable.string)
            let level = indentLevelValue(at: boundedRange.location, in: mutable)
            let fontChoice = fontChoiceValue(at: boundedRange.location, in: mutable)
            // Entries saved before extraction skipped subheading bold carry it as an inline range;
            // drop it with the style, or the stored ranges re-applied below keep the paragraph bold.
            if textStyle(at: boundedRange.location, in: mutable) == .subheading, style != .subheading {
                let map = buildLogicalOffsetMap(from: mutable)
                let start = displayToLogical(display: boundedRange.location, map: map)
                parent.inlineStyleData = NoteEditorCodec.clearingBold(parent.inlineStyleData,
                                                                      in: NSRange(location: start, length: boundedRange.length))
            }
            mutable.removeAttribute(Self.paragraphStyleAttribute, range: boundedRange)
            mutable.addAttributes(attributes(for: style, level: level, fontChoice: fontChoice), range: boundedRange)
            if style != .body {
                mutable.addAttribute(Self.paragraphStyleAttribute, value: style.rawValue, range: boundedRange)
            }
            // Re-stamp indent level (attributes(for:level:) sets paragraphStyle but not the custom key)
            if level > 0 { mutable.addAttribute(Self.indentLevelAttribute, value: level, range: boundedRange) }
            if fontChoice != entryDefaultFontChoice {
                mutable.addAttribute(Self.fontChoiceAttribute, value: fontChoice.rawValue, range: boundedRange)
            }

            isApplyingStyledText = true
            // The paragraph font was just replaced, which drops inline bold/italic; put the stored ranges back.
            applyInlineStyles(to: mutable, from: parent.inlineStyleData)
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false
            storeDocuments(from: textView)
            syncRenderedCache(from: textView)
            updateTypingAttributes(for: textView)
        }

        // Same shape as setParagraphStyle, but changes only the font — paragraph style
        // and indent are read from the existing paragraph and re-applied unchanged, so
        // a font-family command never disturbs block style or list nesting.
        private func setParagraphFontChoice(_ choice: WritingFontChoice, range: NSRange, in textView: UITextView) {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let boundedRange = bounded(range, in: mutable.string)
            guard boundedRange.length > 0 else { return }
            let style = textStyle(at: boundedRange.location, in: mutable)
            let level = indentLevelValue(at: boundedRange.location, in: mutable)
            mutable.removeAttribute(Self.fontChoiceAttribute, range: boundedRange)
            mutable.addAttributes(attributes(for: style, level: level, fontChoice: choice), range: boundedRange)
            if style != .body {
                mutable.addAttribute(Self.paragraphStyleAttribute, value: style.rawValue, range: boundedRange)
            }
            if level > 0 { mutable.addAttribute(Self.indentLevelAttribute, value: level, range: boundedRange) }
            if choice != entryDefaultFontChoice {
                mutable.addAttribute(Self.fontChoiceAttribute, value: choice.rawValue, range: boundedRange)
            }

            isApplyingStyledText = true
            // The paragraph font was just replaced, which drops inline bold/italic; put the stored ranges back.
            applyInlineStyles(to: mutable, from: parent.inlineStyleData)
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false
            storeDocuments(from: textView)
            syncRenderedCache(from: textView)
        }

        func applyFontFamily(_ choice: WritingFontChoice, in textView: UITextView) {
            let nsText = (textView.text ?? "") as NSString
            let liveCursorLocation = textView.isFirstResponder ? textView.selectedRange.location : lastKnownCursorLocation
            let cursorLocation = min(liveCursorLocation, max(0, nsText.length))
            lastKnownCursorLocation = cursorLocation

            if nsText.length == 0 || cursorLocation >= nsText.length {
                // Nothing to restyle yet (empty document, or cursor past the last
                // character in a virtual trailing paragraph) — typing attributes alone
                // carry the choice to whatever gets typed next, same as the general
                // paragraph-style apply() path handles this exact ambiguity.
                let anchor = max(0, nsText.length - 1)
                let style = nsText.length == 0 ? emptyDocumentStyle().0 : textStyle(at: anchor, in: textView.attributedText)
                let level = nsText.length == 0 ? 0 : indentLevelValue(at: anchor, in: textView.attributedText)
                if nsText.length == 0 {
                    storeEmptyDocumentStyle(style, fontChoice: choice)
                    invalidateRenderedCache()
                }
                textView.typingAttributes = styledAttributesForTyping(style, numberedIndex: nil, level: level, fontChoice: choice)
                parent.panelState.activeFontChoice = choice
                return
            }

            // A real selection can span multiple paragraphs — same widening as the
            // general paragraph-style apply() path, so selecting 3 paragraphs and
            // tapping a font restyles all 3, not just the one at the selection's start.
            let selectionRange = textView.isFirstResponder ? textView.selectedRange : NSRange(location: cursorLocation, length: 0)
            let cursorRange = bounded(selectionRange, in: nsText as String)
            let paragraphRange = nsText.paragraphRange(for: cursorRange)

            nsText.enumerateSubstrings(in: paragraphRange, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                self.setParagraphFontChoice(choice, range: range, in: textView)
            }

            textView.selectedRange = bounded(NSRange(location: cursorLocation, length: 0), in: textView.text)
            let level = indentLevelValue(at: cursorLocation, in: textView.attributedText)
            let style = textStyle(at: cursorLocation, in: textView.attributedText)
            textView.typingAttributes = styledAttributesForTyping(style, numberedIndex: nil, level: level, fontChoice: choice)
            updatePlaceholder(in: textView)
            parent.panelState.activeFontChoice = choice
        }

        // Insert a new row with the same list style after pressing Return on a non-empty list item
        private func insertListRow(replacing range: NSRange, style: NoteParagraphTextStyle, in textView: UITextView) {
            // For numbered lists, the new row will be numbered after render; just insert unchecked for checklist
            let newStyle: NoteParagraphTextStyle = (style == .checklistChecked) ? .checklistUnchecked : style
            if range.length == 0, insertListRowAbove(at: range.location, style: style, newStyle: newStyle, in: textView) { return }
            let rowLevel = indentLevelValue(at: max(0, range.location - 1), in: textView.attributedText)
            let rowFontChoice = fontChoiceValue(at: max(0, range.location - 1), in: textView.attributedText)
            // Numbered placeholder must be digit-shaped ("1.\t", not "N.\t"): the
            // logical-text pass (`logicalText` / `renderedString`) strips a numbered
            // marker via `numberedListMarkerLength`, which only matches digits. A
            // "N.\t" placeholder survives into the paragraph's stored content and
            // the re-render then prepends the real number on top of it → "2.\tN.\t".
            // Matches the placeholder used by the paste path.
            let marker = staticListMarkerPrefix(for: newStyle, level: rowLevel) ?? (newStyle == .numberedList ? "1.\t" : "")
            let insertion = "\n" + marker
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let insertionRange = bounded(range, in: mutable.string)
            let attributedInsertion = NSMutableAttributedString(
                string: insertion,
                attributes: styledAttributesForTyping(newStyle, numberedIndex: nil, level: rowLevel, fontChoice: rowFontChoice)
            )
            mutable.replaceCharacters(in: insertionRange, with: attributedInsertion)

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false
            storeDocuments(from: textView)
            // Re-render to show correct number
            if newStyle == .numberedList { invalidateRenderedCache() }
            applyStyledText(to: textView, preservingSelection: false)

            // Place the cursor AFTER the re-render (applyStyledText clears the
            // selection) at the end of the new row's marker. Setting it before the
            // re-render, as this used to, left it wherever UIKit dropped it — so
            // the next Return read the *previous* row's paragraph, saw content,
            // and kept spawning rows instead of exiting the list.
            let display = (textView.text ?? "") as NSString
            let newRowLoc = min(insertionRange.location + 1, max(0, display.length))
            let newRowRange = display.paragraphRange(for: NSRange(location: min(newRowLoc, max(0, display.length - 1)), length: 0))
            let newRowMarkerLen = newStyle == .numberedList
                ? numberedListMarkerLength(in: display.substring(with: newRowRange))
                : ((staticListMarkerPrefix(for: newStyle, level: rowLevel) as NSString?)?.length ?? 0)
            // Guard the assignment like exitList does, so it doesn't re-enter
            // textViewDidChangeSelection's panel/font refresh on every list Return.
            isApplyingStyledText = true
            textView.selectedRange = bounded(
                NSRange(location: newRowRange.location + newRowMarkerLen, length: 0),
                in: textView.text
            )
            isApplyingStyledText = false
            textView.typingAttributes = styledAttributesForTyping(newStyle, numberedIndex: nil, level: rowLevel, fontChoice: rowFontChoice)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
        }

        /// Return with the caret at the start of an item's text, as Notes does it: an empty item goes
        /// in above and the item keeps its text and its check (splitting there handed the check to
        /// the empty half). The caret stays at the start of the item's text. false when the caret is
        /// not at the start of the text.
        private func insertListRowAbove(at location: Int, style: NoteParagraphTextStyle, newStyle: NoteParagraphTextStyle, in textView: UITextView) -> Bool {
            guard style == .checklistUnchecked || style == .checklistChecked,
                  let attributed = textView.attributedText, attributed.length > 0 else { return false }
            let text = attributed.string as NSString
            let para = text.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))
            let level = indentLevelValue(at: para.location, in: attributed)
            let marker = staticListMarkerPrefix(for: style, level: level) ?? ""
            let markerLen = (marker as NSString).length
            guard markerLen > 0, displayedMarkerLength(of: para, in: attributed) == markerLen,
                  location == para.location + markerLen else { return false }
            var contentEnd = NSMaxRange(para)
            if contentEnd > para.location, text.character(at: contentEnd - 1) == 10 { contentEnd -= 1 }
            let contentLength = contentEnd - location
            guard contentLength > 0 else { return false }   // an empty item: Return ends the list instead

            let fontChoice = fontChoiceValue(at: para.location, in: attributed)
            let newMarker = staticListMarkerPrefix(for: newStyle, level: level) ?? ""
            let mutable = NSMutableAttributedString(attributedString: attributed)
            mutable.insert(NSAttributedString(string: newMarker + "\n",
                                              attributes: styledAttributesForTyping(newStyle, numberedIndex: nil, level: level, fontChoice: fontChoice)),
                           at: para.location)
            let row = text.substring(to: para.location).components(separatedBy: "\n").count - 1
            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false
            storeDocuments(from: textView)
            pendingParagraphCaret = (row + 1, contentLength)
            invalidateRenderedCache()
            applyStyledText(to: textView, preservingSelection: false)
            applyPendingParagraphCaret(in: textView)
            textView.typingAttributes = styledAttributesForTyping(style, numberedIndex: nil, level: level, fontChoice: fontChoice)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
            return true
        }

        private func exitList(at paragraphRange: NSRange, in textView: UITextView) {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let boundedRange = bounded(paragraphRange, in: mutable.string)
            let paragraph = (mutable.string as NSString).substring(with: boundedRange)
            let lineBreak = trailingLineBreak(from: paragraph)
            let exitFontChoice = fontChoiceValue(at: boundedRange.location, in: mutable)
            mutable.replaceCharacters(
                in: boundedRange,
                with: NSAttributedString(
                    string: lineBreak,
                    attributes: styledAttributesForTyping(.body, numberedIndex: nil, level: 0, fontChoice: exitFontChoice)
                )
            )

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            // The caret stays on the line that left the list (it used to land on the row below
            // when the empty item had rows after it).
            textView.selectedRange = bounded(NSRange(location: boundedRange.location, length: 0), in: textView.text)
            isApplyingStyledText = false
            storeDocuments(from: textView)
            // A numbered list below now starts a new list: redraw so it counts from 1.
            let afterExit = boundedRange.location + (lineBreak as NSString).length
            if afterExit < (textView.text as NSString).length, textStyle(at: afterExit, in: textView.attributedText) == .numberedList {
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: true)
            }
            textView.typingAttributes = styledAttributesForTyping(.body, numberedIndex: nil, level: 0, fontChoice: exitFontChoice)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
        }

        private func isListStyle(_ style: NoteParagraphTextStyle) -> Bool {
            switch style {
            case .checklistUnchecked, .checklistChecked, .bulletedList, .dashedList, .numberedList: return true
            default: return false
            }
        }

        private func listContent(fromDisplayedParagraph paragraph: String, style: NoteParagraphTextStyle, level: Int = 0) -> String {
            if style == .numberedList {
                let markerLen = numberedListMarkerLength(in: paragraph)
                return markerLen > 0 ? String(paragraph.dropFirst(markerLen)) : paragraph
            }
            guard let marker = staticListMarkerPrefix(for: style, level: level), paragraph.hasPrefix(marker) else {
                return paragraph
            }
            return String(paragraph.dropFirst(marker.count))
        }

        // Returns static (non-numbered) marker prefix for a list style, nil for numbered/non-list.
        // Bullet/dash markers use nested visual hierarchy per indent level (all variants are 3 chars).
        private func staticListMarkerPrefix(for style: NoteParagraphTextStyle, level: Int = 0) -> String? {
            switch style {
            case .checklistUnchecked: return "○  "
            case .checklistChecked:   return "✓  "
            case .bulletedList:
                switch level {
                case 0:  return "•  "
                case 1:  return "◦  "
                default: return "▸  "
                }
            case .dashedList:
                switch level {
                case 0:  return "–  "
                case 1:  return "·  "
                default: return "–  "
                }
            default: return nil
            }
        }

        private func numberedListMarkerLength(in paragraph: String) -> Int {
            // Current markers use a tab ("1.\t"); entries saved before that used two
            // spaces ("1.  "). Both must parse — `logicalText` strips whatever a
            // stored entry baked in on load.
            let ns = paragraph as NSString
            var i = 0
            while i < ns.length {
                let c = ns.character(at: i)
                if c >= 48 && c <= 57 { i += 1 } // digit
                else { break }
            }
            // At least one digit, then "."
            guard i > 0, i < ns.length, ns.character(at: i) == 46 else { return 0 } // "."
            i += 1
            guard i < ns.length else { return 0 }
            if ns.character(at: i) == 9 { return i + 1 } // "\t"
            guard ns.character(at: i) == 32 else { return 0 } // " "
            i += 1
            guard i < ns.length, ns.character(at: i) == 32 else { return 0 } // "  "
            return i + 1
        }

        private func decodedTextStyles() -> [NoteParagraphTextStyle] {
            guard let data = textStyleData,
                  let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data) else {
                return []
            }
            return document.paragraphStyles
        }

        private func decodedIndentLevels() -> [Int] {
            guard let data = textStyleData,
                  let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data),
                  let levels = document.indentLevels else {
                return []
            }
            return levels
        }

        private func decodedFontChoices() -> [String] {
            guard let data = textStyleData,
                  let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data),
                  let choices = document.fontChoices else {
                return []
            }
            return choices
        }

        /// The paragraph style and font an empty entry will type in, from the stored style data.
        private func emptyDocumentStyle() -> (NoteParagraphTextStyle, WritingFontChoice) {
            let style = decodedTextStyles().first ?? .body
            let fontChoice = decodedFontChoices().first.flatMap(WritingFontChoice.init(rawValue:)) ?? entryDefaultFontChoice
            return (style, fontChoice)
        }

        /// Stores an empty entry's paragraph style and font, so they survive re-renders until the
        /// first character takes them on. Plain body in the entry's font stores nothing.
        private func storeEmptyDocumentStyle(_ style: NoteParagraphTextStyle, fontChoice: WritingFontChoice) {
            guard style != .body || fontChoice != entryDefaultFontChoice else {
                textStyleData = nil
                return
            }
            textStyleData = try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [style], fontChoices: [fontChoice.rawValue]))
        }

        private var entryDefaultFontChoice: WritingFontChoice {
            WritingFontChoice(rawValue: parent.fontChoiceRaw) ?? .system
        }

        private func indentLevelValue(at location: Int, in attributed: NSAttributedString?) -> Int {
            guard let attributed, attributed.length > 0 else { return 0 }
            let loc = min(max(0, location), attributed.length - 1)
            return attributed.attribute(Self.indentLevelAttribute, at: loc, effectiveRange: nil) as? Int ?? 0
        }

        // No per-paragraph tag means "no override" — falls back to the entry's own
        // default font choice, not a hardcoded one, so untouched paragraphs keep
        // following the entry-wide setting exactly like before this feature existed.
        private func fontChoiceValue(at location: Int, in attributed: NSAttributedString?) -> WritingFontChoice {
            guard let attributed, attributed.length > 0 else { return entryDefaultFontChoice }
            let loc = min(max(0, location), attributed.length - 1)
            if let raw = attributed.attribute(Self.fontChoiceAttribute, at: loc, effectiveRange: nil) as? String,
               let choice = WritingFontChoice(rawValue: raw) {
                return choice
            }
            return entryDefaultFontChoice
        }

        private func applyAttributedText(_ attr: NSAttributedString, to textView: UITextView) {
            let um = textView.undoManager
            um?.disableUndoRegistration()
            textView.attributedText = attr
            // UIKit may internally re-enable undo registration when attributedText is set;
            // only balance if still disabled to avoid the NSInternalInconsistencyException crash.
            if um?.isUndoRegistrationEnabled == false {
                um?.enableUndoRegistration()
            }
        }

        private func encodedTextStyleData(from textView: UITextView) -> Data? {
            let attributed = textView.attributedText ?? NSAttributedString()
            let nsText = attributed.string as NSString
            guard nsText.length > 0 else { return nil }

            var styles: [NoteParagraphTextStyle] = []
            var levels: [Int] = []
            var fontChoices: [String] = []
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                styles.append(self.textStyle(at: range.location, in: attributed))
                levels.append(self.indentLevelValue(at: range.location, in: attributed))
                fontChoices.append(self.fontChoiceValue(at: range.location, in: attributed).rawValue)
            }
            let hasIndent = levels.contains(where: { $0 > 0 })
            // A plain-body, non-indented paragraph can still carry a font override —
            // don't let the old "all body, nothing to persist" shortcut silently drop it.
            let hasFontOverride = fontChoices.contains { WritingFontChoice(rawValue: $0) != entryDefaultFontChoice }
            guard styles.contains(where: { $0 != .body }) || hasIndent || hasFontOverride else { return nil }
            return try? JSONEncoder().encode(NoteTextStyleDocument(
                paragraphStyles: styles,
                indentLevels: hasIndent ? levels : nil,
                fontChoices: fontChoices
            ))
        }

        /// Reads the text and paragraph styles back from the view after an edit, and the inline
        /// ranges too when the logical text moved (list Return, typing into a marker, "1. "):
        /// otherwise the next re-render applies them at stale offsets and the next keystroke
        /// saves the shifted result. When the text did not move the stored ranges stay: a style
        /// change replaces the paragraph's font, so reading bold/italic back from it would lose them.
        private func storeDocuments(from textView: UITextView) {
            let text = logicalText(from: textView)
            let moved = text != parent.text
            parent.text = text
            textStyleData = encodedTextStyleData(from: textView)
            if moved { parent.inlineStyleData = extractedInlineStyleData(from: textView) }
        }

        /// The text in the coordinates inline ranges use: the displayed text without list markers
        /// (same rule as `buildLogicalOffsetMap`). A photo is its one attachment character here (a
        /// placeholder when it can't be decoded), never its `[[mirror-photo-N]]` token, so these
        /// offsets differ from `parent.text` after a photo.
        func inlineCoordinateText(from attributed: NSAttributedString) -> String {
            let nsDisplay = attributed.string as NSString
            var result = ""
            nsDisplay.enumerateSubstrings(in: NSRange(location: 0, length: nsDisplay.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosingRange, _ in
                let markerLen = self.displayedMarkerLength(of: enclosingRange, in: attributed)
                result += nsDisplay.substring(with: NSRange(location: enclosingRange.location + markerLen, length: enclosingRange.length - markerLen))
            }
            return result
        }

        // MARK: - Undo
        //
        // UITextView's own undo manager loses its whole stack whenever `attributedText` is set,
        // which every list Return, re-render, formatting command and checkbox tap does. So the
        // editor keeps its own history of whole-document snapshots, and the text view's undo
        // manager (Undo button, Cmd-Z, shake, three-finger swipe) is pointed at it.

        struct EditorSnapshot {
            var text: String
            var textStyleData: Data?
            var inlineStyleData: Data?
            var photos: [Data]
            var selection: NSRange

            func hasSameContent(as other: EditorSnapshot) -> Bool {
                text == other.text && textStyleData == other.textStyleData && inlineStyleData == other.inlineStyleData
                    && photos.count == other.photos.count && photos.map(\.count) == other.photos.map(\.count)
            }
        }

        private struct TypingGroup {
            var isDeletion: Bool
            var nextLocation: Int
            var lastEdit: Date
        }

        private static let undoLimit = 200
        private static let typingGroupPause: TimeInterval = 2

        private var undoStack: [EditorSnapshot] = []
        private var redoStack: [EditorSnapshot] = []
        /// The document as of the last change the editor knows about: what an undo point records.
        private var committedSnapshot: EditorSnapshot?
        private var typingGroup: TypingGroup?
        /// Set by `shouldChangeTextIn` when it has already grouped the change `textViewDidChange` reports.
        private var changeWasGrouped = false
        /// Outside changes (loading the entry, restoring a draft) are not undoable until the
        /// person has edited, so Undo can never empty an entry that was just opened.
        private var hasUserEdited = false

        var canUndoEdit: Bool { !undoStack.isEmpty }
        var canRedoEdit: Bool { !redoStack.isEmpty }

        lazy var editorUndoManager = EditorUndoManager(coordinator: self)

        func currentSnapshot(of textView: UITextView) -> EditorSnapshot {
            EditorSnapshot(text: parent.text, textStyleData: textStyleData, inlineStyleData: parent.inlineStyleData,
                           photos: parent.photoDataArray, selection: textView.selectedRange)
        }

        private func pushUndo(_ snapshot: EditorSnapshot) {
            undoStack.append(snapshot)
            if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
            redoStack.removeAll()
            hasUserEdited = true
            publishUndoState()
        }

        /// After a structural edit or command: one undo step if the document changed.
        private func commitUndoPoint(in textView: UITextView) {
            let current = currentSnapshot(of: textView)
            typingGroup = nil
            guard let committed = committedSnapshot else { committedSnapshot = current; return }
            if !committed.hasSameContent(as: current) { pushUndo(committed) }
            committedSnapshot = current
        }

        /// Before UIKit applies a typed change: start a new undo step unless it continues the
        /// current run (same kind, at the caret, within a short pause, no line break).
        private func groupTypedChange(range: NSRange?, replacement: String?) {
            let now = Date()
            let isDeletion = replacement?.isEmpty ?? false
            var continues = false
            if let group = typingGroup, now.timeIntervalSince(group.lastEdit) < Self.typingGroupPause, group.isDeletion == isDeletion {
                if let range {
                    continues = isDeletion ? NSMaxRange(range) == group.nextLocation : range.location == group.nextLocation
                } else {
                    continues = true   // marked (IME) text has no range here; group it by time
                }
            }
            if replacement?.contains("\n") == true { continues = false }
            if !continues, let committed = committedSnapshot { pushUndo(committed) }
            let next: Int
            if let range { next = isDeletion ? range.location : range.location + ((replacement ?? "") as NSString).length } else { next = typingGroup?.nextLocation ?? 0 }
            typingGroup = replacement?.contains("\n") == true ? nil : TypingGroup(isDeletion: isDeletion, nextLocation: next, lastEdit: now)
        }

        /// Called at the start of every `updateUIView`: a document change the editor did not make
        /// (an append, a scan, a photo attached) becomes an undo step once the person has edited.
        func noteOutsideChange(in textView: UITextView) {
            let current = currentSnapshot(of: textView)
            guard let committed = committedSnapshot else { committedSnapshot = current; return }
            guard !committed.hasSameContent(as: current) else { return }
            if hasUserEdited { pushUndo(committed) }
            committedSnapshot = current
            typingGroup = nil
        }

        func undoEdit(in textView: UITextView) {
            guard let snapshot = undoStack.popLast() else { return }
            redoStack.append(currentSnapshot(of: textView))
            restore(snapshot, in: textView)
        }

        func redoEdit(in textView: UITextView) {
            guard let snapshot = redoStack.popLast() else { return }
            undoStack.append(currentSnapshot(of: textView))
            restore(snapshot, in: textView)
        }

        private func restore(_ snapshot: EditorSnapshot, in textView: UITextView) {
            parent.text = snapshot.text
            textStyleData = snapshot.textStyleData
            parent.inlineStyleData = snapshot.inlineStyleData
            if parent.photoDataArray.map(\.count) != snapshot.photos.map(\.count) { parent.photoDataArray = snapshot.photos }
            pendingTypingInline = nil
            typingGroup = nil
            invalidateRenderedCache()
            applyStyledText(to: textView, preservingSelection: false)
            isApplyingStyledText = true
            textView.selectedRange = bounded(snapshot.selection, in: textView.text)
            isApplyingStyledText = false
            lastKnownCursorLocation = textView.selectedRange.location
            updateTypingAttributes(for: textView)
            updatePlaceholder(in: textView)
            refreshActiveParagraphStyle(in: textView)
            refreshActiveInlineStyles(in: textView)
            committedSnapshot = currentSnapshot(of: textView)
            publishUndoState()
        }

        /// The toolbar buttons read these. Deferred: this can run inside `updateUIView`.
        private func publishUndoState() {
            let canUndo = canUndoEdit, canRedo = canRedoEdit
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.canUndo != canUndo { self.parent.canUndo = canUndo }
                if self.parent.canRedo != canRedo { self.parent.canRedo = canRedo }
            }
        }

        /// Whether `text` is what the editor last rendered or read back from the view.
        func isShowing(_ text: String) -> Bool { lastRenderedText == text }

        private func invalidateRenderedCache() {
            lastRenderedText = nil
            lastRenderedStyleSignature = nil
            lastRenderedInlineSignature = nil
            lastRenderedPhotoSignature = nil
            lastRenderedWidth = 0
        }

        private func syncRenderedCache(from textView: UITextView) {
            lastRenderedText = parent.text
            lastRenderedStyleSignature = textStyleData?.hashValue
            lastRenderedInlineSignature = parent.inlineStyleData?.hashValue
            lastRenderedPhotoSignature = parent.photoDataArray.map(\.count).reduce(0, +)
            lastRenderedWidth = textView.bounds.width.rounded()
            lastRenderedFontChoice = WritingFontChoice(rawValue: parent.fontChoiceRaw) ?? .system
        }

        private func paragraphStyle(lineSpacing: CGFloat, paragraphSpacing: CGFloat = 5) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            style.paragraphSpacing = paragraphSpacing
            return style
        }

        // MARK: - Inline style toggle

        func toggleInlineStyle(_ command: NoteTextCommand, in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let selRange = textView.selectedRange
            let effectiveRange = selRange.length > 0
                ? selRange
                : NSRange(location: min(selRange.location, max(0, attributed.length - 1)), length: min(1, attributed.length))

            let shouldRemove: Bool
            if selRange.length == 0 {
                // With nothing selected, toggle what the next typed character would get (the
                // typing attributes), not the character after the caret: at the end of a bold word
                // that is a plain space, so B used to add bold instead of turning it off.
                let style = attributed.length > 0 ? textStyle(at: effectiveRange.location, in: attributed) : .body
                let typing = typingInline(from: textView.typingAttributes, style: style)
                switch command {
                case .bold: shouldRemove = typing.bold
                case .italic: shouldRemove = typing.italic
                case .underline: shouldRemove = typing.underline
                case .strikethrough: shouldRemove = typing.strikethrough
                default: shouldRemove = false
                }
            } else {
                let hasBold       = command == .bold          && isStyleApplied(.bold,          in: effectiveRange, of: attributed)
                let hasItalic     = command == .italic        && isStyleApplied(.italic,        in: effectiveRange, of: attributed)
                let hasUnderline  = command == .underline     && isStyleApplied(.underline,     in: effectiveRange, of: attributed)
                let hasStrike     = command == .strikethrough && isStyleApplied(.strikethrough, in: effectiveRange, of: attributed)
                shouldRemove = hasBold || hasItalic || hasUnderline || hasStrike
            }

            let mutable = NSMutableAttributedString(attributedString: attributed)

            if selRange.length > 0 {
                let applyRange = bounded(selRange, in: mutable.string)
                switch command {
                case .bold:
                    mutable.enumerateAttribute(.font, in: applyRange) { value, range, _ in
                        let font = (value as? UIFont) ?? serifBodyFont
                        mutable.addAttribute(.font, value: font.withTrait(.traitBold, add: !shouldRemove), range: range)
                    }
                case .italic:
                    mutable.enumerateAttribute(.font, in: applyRange) { value, range, _ in
                        let font = (value as? UIFont) ?? serifBodyFont
                        mutable.addAttribute(.font, value: font.withTrait(.traitItalic, add: !shouldRemove), range: range)
                    }
                case .underline:
                    if shouldRemove {
                        mutable.removeAttribute(.underlineStyle, range: applyRange)
                    } else {
                        mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: applyRange)
                    }
                case .strikethrough:
                    if shouldRemove {
                        mutable.removeAttribute(.strikethroughStyle, range: applyRange)
                    } else {
                        mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: applyRange)
                    }
                default: break
                }

                isApplyingStyledText = true
                applyAttributedText(mutable, to: textView)
                textView.selectedRange = bounded(selRange, in: textView.text)
                isApplyingStyledText = false
            } else {
                // No selection — toggle typing attributes
                var typing = textView.typingAttributes
                switch command {
                case .bold:
                    let font = (typing[.font] as? UIFont) ?? serifBodyFont
                    typing[.font] = font.withTrait(.traitBold, add: !shouldRemove)
                case .italic:
                    let font = (typing[.font] as? UIFont) ?? serifBodyFont
                    typing[.font] = font.withTrait(.traitItalic, add: !shouldRemove)
                case .underline:
                    if shouldRemove { typing.removeValue(forKey: .underlineStyle) }
                    else { typing[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                case .strikethrough:
                    if shouldRemove { typing.removeValue(forKey: .strikethroughStyle) }
                    else { typing[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                default: break
                }
                textView.typingAttributes = typing
                rememberTypingInline(in: textView)
            }

            parent.inlineStyleData = extractedInlineStyleData(from: textView)
            syncRenderedCache(from: textView)
            refreshActiveInlineStyles(in: textView)
        }

        func applyHighlight(_ index: Int?, in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let selRange = textView.selectedRange
            let mutable = NSMutableAttributedString(attributedString: attributed)

            if selRange.length > 0 {
                let applyRange = bounded(selRange, in: mutable.string)
                mutable.removeAttribute(Self.highlightIndexAttribute, range: applyRange)
                mutable.removeAttribute(.backgroundColor, range: applyRange)
                if let idx = index {
                    let uiColor = UIColor(HighlightPalette.colors(for: parent.displayMode)[idx])
                    mutable.addAttribute(.backgroundColor, value: uiColor, range: applyRange)
                    mutable.addAttribute(Self.highlightIndexAttribute, value: idx, range: applyRange)
                }
                isApplyingStyledText = true
                applyAttributedText(mutable, to: textView)
                textView.selectedRange = bounded(selRange, in: textView.text)
                isApplyingStyledText = false
            } else {
                var typing = textView.typingAttributes
                typing.removeValue(forKey: Self.highlightIndexAttribute)
                typing.removeValue(forKey: .backgroundColor)
                if let idx = index {
                    typing[.backgroundColor] = UIColor(HighlightPalette.colors(for: parent.displayMode)[idx])
                    typing[Self.highlightIndexAttribute] = idx
                }
                textView.typingAttributes = typing
                rememberTypingInline(in: textView)
            }

            parent.inlineStyleData = extractedInlineStyleData(from: textView)
            syncRenderedCache(from: textView)
            refreshActiveInlineStyles(in: textView)
        }

        /// `.foregroundColor` is never absent on this text — every paragraph
        /// style bakes in an explicit base color (`.label`/`.secondaryLabel`/
        /// `.tertiaryLabel`, see `attributes(for:)`), unlike `.backgroundColor`
        /// where "unset" is itself the valid default. Removing the attribute
        /// outright (like `applyHighlight` does for `.backgroundColor`) would
        /// leave the run with no explicit color at all, falling back to
        /// whatever `textView.textColor`/UIKit default applies — wrong, and
        /// potentially invisible in Sentinel/dark mode. Must restore the
        /// style's own base color, not just delete the key.
        private func baseForegroundColor(for style: NoteParagraphTextStyle) -> UIColor {
            switch style {
            case .subheading, .blockQuote: return .secondaryLabel
            default: return .label
            }
        }

        func applyTextColor(_ index: Int?, in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let selRange = textView.selectedRange
            let mutable = NSMutableAttributedString(attributedString: attributed)

            if selRange.length > 0 {
                let applyRange = bounded(selRange, in: mutable.string)
                mutable.removeAttribute(Self.textColorIndexAttribute, range: applyRange)
                if let idx = index {
                    let uiColor = UIColor(TextColorPalette.colors(for: parent.displayMode)[idx])
                    mutable.addAttribute(.foregroundColor, value: uiColor, range: applyRange)
                    mutable.addAttribute(Self.textColorIndexAttribute, value: idx, range: applyRange)
                } else {
                    // Restore each paragraph's own base color — a selection can
                    // span paragraphs with different base colors (e.g. a
                    // subheading into a body line), so one flat color is wrong.
                    (mutable.string as NSString).enumerateSubstrings(in: applyRange, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosingRange, _ in
                        let style = self.textStyle(at: enclosingRange.location, in: mutable)
                        let base = self.baseForegroundColor(for: style)
                        let intersected = NSIntersectionRange(enclosingRange, applyRange)
                        if intersected.length > 0 {
                            mutable.addAttribute(.foregroundColor, value: base, range: intersected)
                        }
                    }
                }
                isApplyingStyledText = true
                applyAttributedText(mutable, to: textView)
                textView.selectedRange = bounded(selRange, in: textView.text)
                isApplyingStyledText = false
            } else {
                var typing = textView.typingAttributes
                typing.removeValue(forKey: Self.textColorIndexAttribute)
                if let idx = index {
                    typing[.foregroundColor] = UIColor(TextColorPalette.colors(for: parent.displayMode)[idx])
                    typing[Self.textColorIndexAttribute] = idx
                } else {
                    let cursorLoc = min(textView.selectedRange.location, max(0, attributed.length - 1))
                    let style = attributed.length > 0 ? textStyle(at: cursorLoc, in: attributed) : .body
                    typing[.foregroundColor] = baseForegroundColor(for: style)
                }
                textView.typingAttributes = typing
                rememberTypingInline(in: textView)
            }

            parent.inlineStyleData = extractedInlineStyleData(from: textView)
            syncRenderedCache(from: textView)
            refreshActiveInlineStyles(in: textView)
        }

        /// Unlike highlight, a link can't apply to an empty typing-attributes
        /// cursor — it needs text to wrap. With no selection, falls back to the
        /// existing link run under the cursor (if any) so editing/removing a
        /// link doesn't require re-selecting its exact text; otherwise no-ops.
        func applyLink(urlString: String?, in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let selRange = textView.selectedRange
            let targetRange: NSRange
            if selRange.length > 0 {
                targetRange = bounded(selRange, in: attributed.string)
            } else if let existing = existingLinkRange(at: selRange.location, in: attributed) {
                targetRange = existing
            } else {
                return
            }

            let mutable = NSMutableAttributedString(attributedString: attributed)
            if let url = validatedLinkURL(from: urlString) {
                mutable.addAttribute(.link, value: url, range: targetRange)
            } else {
                mutable.removeAttribute(.link, range: targetRange)
            }

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            textView.selectedRange = bounded(targetRange, in: textView.text)
            isApplyingStyledText = false

            parent.inlineStyleData = extractedInlineStyleData(from: textView)
            syncRenderedCache(from: textView)
            refreshActiveInlineStyles(in: textView)
        }

        /// Clears character-level formatting only (bold/italic/underline/
        /// strikethrough/highlight/link) — mirrors the scope of Notes' equivalent.
        /// Paragraph style (heading/list/etc) is untouched; that's a separate
        /// concern with its own toolbar row.
        func applyClearFormatting(in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let selRange = textView.selectedRange

            if selRange.length > 0 {
                let applyRange = bounded(selRange, in: attributed.string)
                let mutable = NSMutableAttributedString(attributedString: attributed)
                mutable.enumerateAttribute(.font, in: applyRange) { value, range, _ in
                    let font = (value as? UIFont) ?? self.serifBodyFont
                    let plain = font.withTrait(.traitBold, add: false).withTrait(.traitItalic, add: false)
                    mutable.addAttribute(.font, value: plain, range: range)
                }
                mutable.removeAttribute(.underlineStyle, range: applyRange)
                mutable.removeAttribute(.strikethroughStyle, range: applyRange)
                mutable.removeAttribute(.backgroundColor, range: applyRange)
                mutable.removeAttribute(Self.highlightIndexAttribute, range: applyRange)
                mutable.removeAttribute(Self.textColorIndexAttribute, range: applyRange)
                mutable.removeAttribute(.link, range: applyRange)
                // .foregroundColor has no "unset" default (every paragraph style
                // bakes one in) — restore each paragraph's own base color rather
                // than deleting the key, same reasoning as applyTextColor(nil,...).
                (mutable.string as NSString).enumerateSubstrings(in: applyRange, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosingRange, _ in
                    let style = self.textStyle(at: enclosingRange.location, in: mutable)
                    let base = self.baseForegroundColor(for: style)
                    let intersected = NSIntersectionRange(enclosingRange, applyRange)
                    if intersected.length > 0 {
                        mutable.addAttribute(.foregroundColor, value: base, range: intersected)
                    }
                }

                isApplyingStyledText = true
                applyAttributedText(mutable, to: textView)
                textView.selectedRange = bounded(selRange, in: textView.text)
                isApplyingStyledText = false
            } else {
                var typing = textView.typingAttributes
                if let font = typing[.font] as? UIFont {
                    typing[.font] = font.withTrait(.traitBold, add: false).withTrait(.traitItalic, add: false)
                }
                typing.removeValue(forKey: .underlineStyle)
                typing.removeValue(forKey: .strikethroughStyle)
                typing.removeValue(forKey: .backgroundColor)
                typing.removeValue(forKey: Self.highlightIndexAttribute)
                typing.removeValue(forKey: Self.textColorIndexAttribute)
                typing.removeValue(forKey: .link)
                let cursorLoc = min(textView.selectedRange.location, max(0, attributed.length - 1))
                let style = attributed.length > 0 ? textStyle(at: cursorLoc, in: attributed) : .body
                typing[.foregroundColor] = baseForegroundColor(for: style)
                textView.typingAttributes = typing
                rememberTypingInline(in: textView)
            }

            parent.inlineStyleData = extractedInlineStyleData(from: textView)
            syncRenderedCache(from: textView)
            refreshActiveInlineStyles(in: textView)
        }

        private func existingLinkRange(at location: Int, in attributed: NSAttributedString) -> NSRange? {
            guard attributed.length > 0 else { return nil }
            let loc = min(max(0, location), attributed.length - 1)
            var range = NSRange(location: NSNotFound, length: 0)
            guard attributed.attribute(.link, at: loc, effectiveRange: &range) != nil else { return nil }
            return range
        }

        // MARK: - Bulk checklist operations

        func bulkSetChecklist(_ targetStyle: NoteParagraphTextStyle, in textView: UITextView, within scope: NSRange? = nil) {
            guard let attributed = textView.attributedText else { return }
            let nsText = attributed.string as NSString
            var styles: [NoteParagraphTextStyle] = []
            var levels: [Int] = []
            var fontChoices: [String] = []
            var changed = false
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
                let current = self.textStyle(at: enclosing.location, in: attributed)
                let inScope = scope.map { NSLocationInRange(enclosing.location, $0) } ?? true
                let isChecklist = (current == .checklistUnchecked || current == .checklistChecked) && inScope
                let newStyle = isChecklist ? targetStyle : current
                if isChecklist && current != targetStyle { changed = true }
                styles.append(newStyle)
                levels.append(self.indentLevelValue(at: enclosing.location, in: attributed))
                fontChoices.append(self.fontChoiceValue(at: enclosing.location, in: attributed).rawValue)
            }
            guard changed else { return }
            let hasIndent = levels.contains(where: { $0 > 0 })
            textStyleData = try? JSONEncoder().encode(NoteTextStyleDocument(
                paragraphStyles: styles,
                indentLevels: hasIndent ? levels : nil,
                fontChoices: fontChoices
            ))
            invalidateRenderedCache()
            applyStyledText(to: textView, preservingSelection: true)
            refreshActiveInlineStyles(in: textView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func sortCheckedToBottom(in textView: UITextView) {
            guard var rows = editorRows(in: textView) else { return }
            let isChecklist = { (s: NoteParagraphTextStyle) in s == .checklistUnchecked || s == .checklistChecked }
            var i = 0
            var changed = false
            while i < rows.count {
                guard isChecklist(rows[i].style) else { i += 1; continue }
                var j = i
                while j < rows.count && isChecklist(rows[j].style) { j += 1 }
                let block = Array(rows[i..<j])
                // Stable: an item just checked goes to the top of the checked ones, as in Notes.
                let sorted = block.filter { $0.style != .checklistChecked } + block.filter { $0.style == .checklistChecked }
                if sorted.map({ $0.source }) != block.map({ $0.source }) {
                    changed = true
                    rows.replaceSubrange(i..<j, with: sorted)
                }
                i = j
            }
            guard changed else { return }
            // Right after a checkbox tap, the caret it set wins: closing the sorting prompt refocuses
            // the editor with the caret reset to the start (iPhone 14 Pro, iOS 27).
            var caret = textView.selectedRange.location
            if let checked = checkedItemCaret, Date().timeIntervalSince(checked.at) < 10 { caret = checked.location }
            checkedItemCaret = nil
            commitRowOrder(rows, caret: caret, in: textView, slide: true)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // MARK: - Rows (sort, drag)

        /// One paragraph as the reordering code moves it: its stored text and per-paragraph style
        /// data, and its index before the move. fontChoice is index-based like level (one entry per
        /// paragraph), not offset-based like inlineStyleData, so it moves with its row.
        typealias EditorRow = (text: String, style: NoteParagraphTextStyle, level: Int, fontChoice: String, source: Int)

        func editorRows(in textView: UITextView) -> [EditorRow]? {
            guard let attributed = textView.attributedText, let rows = logicalRows(in: attributed) else { return nil }
            return zip(rows.lines, rows.infos).enumerated().map { ($1.0, $1.1.style, $1.1.level, $1.1.fontChoice, $0) }
        }

        typealias RowInfo = (style: NoteParagraphTextStyle, level: Int, fontChoice: String)

        /// `parent.text`'s lines and each one's paragraph style, level and font choice, or nil when
        /// the shown paragraphs don't line up with them. Paragraph enumeration skips the empty line
        /// after a final line break, which `components(separatedBy:)` keeps; that line gets its
        /// stored style and stays last (it has no marker, so it is never a checklist item). Without
        /// it, sorting and dragging did nothing whenever the entry ended with a line break.
        private func logicalRows(in attributed: NSAttributedString) -> (lines: [String], infos: [RowInfo])? {
            let nsText = attributed.string as NSString
            var infos: [RowInfo] = []
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
                infos.append((self.textStyle(at: enclosing.location, in: attributed),
                              self.indentLevelValue(at: enclosing.location, in: attributed),
                              self.fontChoiceValue(at: enclosing.location, in: attributed).rawValue))
            }
            let logical = parent.text.components(separatedBy: "\n")
            if logical.count == infos.count + 1, nsText.length == 0 || nsText.hasSuffix("\n") {
                let index = infos.count
                let styles = decodedTextStyles(), levels = decodedIndentLevels(), fonts = decodedFontChoices()
                infos.append((styles.indices.contains(index) ? styles[index] : .body,
                              levels.indices.contains(index) ? levels[index] : 0,
                              fonts.indices.contains(index) ? fonts[index] : entryDefaultFontChoice.rawValue))
            }
            guard logical.count == infos.count else { return nil }
            return (logical, infos)
        }

        /// Each paragraph's character range (without its line break) and its rect in text view
        /// coordinates, full width.
        func rowFrames(in textView: UITextView) -> [(chars: NSRange, rect: CGRect)] {
            let text = (textView.text ?? "") as NSString
            let lm = textView.layoutManager
            let inset = textView.textContainerInset
            var out: [(NSRange, CGRect)] = []
            text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
                let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: enclosing.location, length: max(1, range.length)), actualCharacterRange: nil)
                guard glyphs.length > 0 else { out.append((range, .zero)); return }
                var rect = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                rect = rect.union(lm.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil))
                out.append((range, CGRect(x: 0, y: rect.minY + inset.top, width: textView.bounds.width, height: rect.height)))
            }
            return out
        }

        /// Writes `rows` in their new order (text, styles, inline ranges), keeps the caret in the
        /// row it was in, and, with `slide`, moves each row that changed place from where it was to
        /// where it lands, as Notes' list does.
        func commitRowOrder(_ rows: [EditorRow], caret: Int, in textView: UITextView, slide: Bool) {
            guard let attributed = textView.attributedText else { return }
            let nsText = attributed.string as NSString
            var caretRow = 0
            var caretOffset = 0
            var rowIndex = 0
            // On the empty line after a final line break: that line, which is last and never moves.
            let caretOnTrailingLine = caret >= nsText.length && nsText.hasSuffix("\n")
            if caretOnTrailingLine { caretRow = rows.count - 1 }
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, stop in
                if caretOnTrailingLine { stop.pointee = true; return }
                if caret >= enclosing.location && (caret < NSMaxRange(enclosing) || NSMaxRange(enclosing) == nsText.length) {
                    caretRow = rowIndex
                    caretOffset = min(caret - range.location, range.length)
                    stop.pointee = true
                }
                rowIndex += 1
            }
            let moving = rows.enumerated().filter { $0.offset != $0.element.source }.map(\.element.source)
            let before = slide && UIView.areAnimationsEnabled ? rowFrames(in: textView) : []
            var snapshots: [Int: UIView] = [:]
            for source in moving where source < before.count && before[source].rect.height > 0 {
                if let view = textView.resizableSnapshotView(from: before[source].rect, afterScreenUpdates: false, withCapInsets: .zero) {
                    snapshots[source] = view
                }
            }

            // Inline ranges move with their rows (they used to be dropped, wiping every bold,
            // link and highlight in the entry).
            parent.inlineStyleData = remappedInlineStyles(rowOrder: rows.map { $0.source }, rowCount: rows.count, displayed: attributed)
            parent.text = rows.map { $0.text }.joined(separator: "\n")
            let styles = rows.map { $0.style }
            let levels = rows.map { $0.level }
            let fontChoices = rows.map { $0.fontChoice }
            let hasIndent = levels.contains(where: { $0 > 0 })
            let hasFontOverride = fontChoices.contains { WritingFontChoice(rawValue: $0) != entryDefaultFontChoice }
            textStyleData = (styles.allSatisfy({ $0 == .body }) && !hasIndent && !hasFontOverride) ? nil :
                try? JSONEncoder().encode(NoteTextStyleDocument(
                    paragraphStyles: styles,
                    indentLevels: hasIndent ? levels : nil,
                    fontChoices: fontChoices
                ))
            invalidateRenderedCache()
            let movedRow = rows.firstIndex { $0.source == caretRow } ?? caretRow
            if snapshots.isEmpty {
                UIView.transition(with: textView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                    self.applyStyledText(to: textView, preservingSelection: true)
                }
            } else {
                applyStyledText(to: textView, preservingSelection: true)
                slideRows(snapshots, from: before, rows: rows, in: textView)
            }
            // Keep the caret in the row it was in, not at the same offset (which now points into
            // whichever row moved there); again once the re-render that follows has run.
            placeCaret(inRow: movedRow, offset: caretOffset, in: textView)
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.placeCaret(inRow: movedRow, offset: caretOffset, in: textView)
            }
            refreshActiveInlineStyles(in: textView)
        }

        private func placeCaret(inRow row: Int, offset: Int, in textView: UITextView) {
            let shown = (textView.text ?? "") as NSString
            var index = 0
            var placed = false
            shown.enumerateSubstrings(in: NSRange(location: 0, length: shown.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, stop in
                if index == row {
                    self.placeCaret(at: range.location + min(offset, range.length), in: textView)
                    placed = true
                    stop.pointee = true
                }
                index += 1
            }
            if !placed, row == index, shown.hasSuffix("\n") {
                placeCaret(at: shown.length, in: textView)   // the empty line after a final line break
            }
        }

        /// Hides the moved rows in their new places and slides snapshots of them there.
        private func slideRows(_ snapshots: [Int: UIView], from before: [(chars: NSRange, rect: CGRect)], rows: [EditorRow], in textView: UITextView) {
            guard let lm = textView.layoutManager as? ChecklistLayoutManager else { return }
            let after = rowFrames(in: textView)
            var hidden: [NSRange] = []
            var moves: [(UIView, CGRect)] = []
            for (newIndex, row) in rows.enumerated() {
                guard let view = snapshots[row.source], newIndex < after.count else { continue }
                hidden.append(after[newIndex].chars)
                view.frame = before[row.source].rect
                textView.addSubview(view)
                moves.append((view, CGRect(origin: CGPoint(x: 0, y: after[newIndex].rect.minY), size: before[row.source].rect.size)))
            }
            lm.hiddenCharacterRanges = hidden
            lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textView.textStorage.length))
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                for (view, frame) in moves { view.frame = frame }
            } completion: { _ in
                for (view, _) in moves { view.removeFromSuperview() }
                lm.hiddenCharacterRanges = []
                lm.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textView.textStorage.length))
            }
        }

        /// A caret to restore as (row, characters before the row's end), until a render shows the
        /// row's list marker. See `apply(_:to:)`'s list toggle.
        private var pendingParagraphCaret: (row: Int, fromEnd: Int)?

        private func paragraphCaretAnchor(_ location: Int, in text: NSString) -> (row: Int, fromEnd: Int) {
            let clamped = min(max(0, location), text.length)
            let row = text.substring(to: clamped).components(separatedBy: "\n").count - 1
            let para = text.paragraphRange(for: NSRange(location: min(clamped, max(0, text.length - 1)), length: 0))
            var contentEnd = NSMaxRange(para)
            if contentEnd > para.location, contentEnd <= text.length, text.character(at: contentEnd - 1) == 10 { contentEnd -= 1 }
            return (row, max(0, contentEnd - clamped))
        }

        /// Puts a pending row-anchored caret back; done once the row shows its marker.
        func applyPendingParagraphCaret(in textView: UITextView) {
            guard let pending = pendingParagraphCaret, let attributed = textView.attributedText else { return }
            let text = attributed.string as NSString
            var row = 0
            var target: (location: Int, hasMarker: Bool)?
            text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, stop in
                if row == pending.row {
                    let marker = self.displayedMarkerLength(of: enclosing, in: attributed)
                    target = (max(range.location + marker, NSMaxRange(range) - pending.fromEnd), marker > 0)
                    stop.pointee = true
                }
                row += 1
            }
            if target == nil, pending.row == row, text.length > 0, text.character(at: text.length - 1) == 10 {
                target = (text.length, false)   // the empty row after a final line break
            }
            guard let target else { pendingParagraphCaret = nil; return }
            isApplyingStyledText = true
            textView.selectedRange = bounded(NSRange(location: target.location, length: 0), in: textView.text)
            isApplyingStyledText = false
            lastKnownCursorLocation = textView.selectedRange.location
            if target.hasMarker { pendingParagraphCaret = nil }
        }

        /// Where the caret goes when editing resumes, if it was placed while the editor was unfocused.
        private var pendingCaretLocation: Int?
        /// The caret a checkbox tap just left, for the sort that may follow it.
        private var checkedItemCaret: (location: Int, at: Date)?

        private func placeCaret(at location: Int, in textView: UITextView) {
            pendingCaretLocation = textView.isFirstResponder ? nil : location
            isApplyingStyledText = true
            textView.selectedRange = bounded(NSRange(location: location, length: 0), in: textView.text)
            isApplyingStyledText = false
            clampCursorPastListMarker(in: textView)
            lastKnownCursorLocation = textView.selectedRange.location
        }

        /// Inline ranges after rows are reordered or dropped. Rows are cut from the inline
        /// coordinate text (a photo is one character there), not `parent.text`. If its rows don't
        /// line up with the stored text's, the ranges are dropped rather than put on the wrong words.
        private func remappedInlineStyles(rowOrder: [Int], rowCount: Int, displayed: NSAttributedString) -> Data? {
            let text = inlineCoordinateText(from: displayed)
            guard text.components(separatedBy: "\n").count == rowCount else { return nil }
            return NoteEditorCodec.remapInlineStyles(parent.inlineStyleData, in: text, rowOrder: rowOrder)
        }

        func deleteCheckedChecklistItems(in textView: UITextView) {
            guard let attributed = textView.attributedText, let rows = logicalRows(in: attributed) else { return }
            let logicalParas = rows.lines
            let paraInfos = rows.infos

            let keptRows = paraInfos.indices.filter { paraInfos[$0].style != .checklistChecked }
            let kept = keptRows.map { (logicalParas[$0], paraInfos[$0]) }
            guard kept.count < logicalParas.count else { return }

            // Formatting on the kept rows moves with them (it used to be dropped for the whole entry).
            parent.inlineStyleData = remappedInlineStyles(rowOrder: keptRows, rowCount: logicalParas.count, displayed: attributed)
            parent.text = kept.map { $0.0 }.joined(separator: "\n")
            let styles = kept.map { $0.1.style }
            let levels = kept.map { $0.1.level }
            let fontChoices = kept.map { $0.1.fontChoice }
            let hasIndent = levels.contains(where: { $0 > 0 })
            let hasFontOverride = fontChoices.contains { WritingFontChoice(rawValue: $0) != entryDefaultFontChoice }
            textStyleData = (styles.allSatisfy({ $0 == .body }) && !hasIndent && !hasFontOverride) ? nil :
                try? JSONEncoder().encode(NoteTextStyleDocument(
                    paragraphStyles: styles,
                    indentLevels: hasIndent ? levels : nil,
                    fontChoices: fontChoices
                ))
            invalidateRenderedCache()
            UIView.transition(with: textView, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.applyStyledText(to: textView, preservingSelection: true)
            }
            refreshActiveInlineStyles(in: textView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func applyIndent(delta: Int, in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let mutable = NSMutableAttributedString(attributedString: attributed)
            let cursorLocation = min(textView.selectedRange.location, max(0, attributed.length - 1))
            let nsText = mutable.string as NSString
            let paraRange = nsText.paragraphRange(for: NSRange(location: cursorLocation, length: 0))

            let style = textStyle(at: paraRange.location, in: mutable)
            guard isListStyle(style) else { return }

            let currentLevel = indentLevelValue(at: paraRange.location, in: mutable)
            let newLevel = max(0, min(4, currentLevel + delta))
            guard newLevel != currentLevel else { return }
            let indentFontChoice = fontChoiceValue(at: paraRange.location, in: mutable)
            mutable.removeAttribute(Self.indentLevelAttribute, range: paraRange)
            mutable.addAttributes(attributes(for: style, level: newLevel, fontChoice: indentFontChoice), range: paraRange)
            if style != .body {
                mutable.addAttribute(Self.paragraphStyleAttribute, value: style.rawValue, range: paraRange)
            }
            if newLevel > 0 {
                mutable.addAttribute(Self.indentLevelAttribute, value: newLevel, range: paraRange)
            }
            if indentFontChoice != entryDefaultFontChoice {
                mutable.addAttribute(Self.fontChoiceAttribute, value: indentFontChoice.rawValue, range: paraRange)
            }

            // Swap bullet/dash marker glyph to match new indent level.
            // Attributes are updated above but the marker character in the string is still the old glyph.
            // syncRenderedCache below produces a cache hit on the next updateUIView, so without this swap
            // the new glyph (◦, ▸, etc.) would never appear until the next text edit triggers a cache miss.
            if (style == .bulletedList || style == .dashedList),
               let oldMarker = staticListMarkerPrefix(for: style, level: currentLevel),
               let newMarker = staticListMarkerPrefix(for: style, level: newLevel) {
                let oldNS = oldMarker as NSString
                let markerRange = bounded(NSRange(location: paraRange.location, length: oldNS.length), in: mutable.string)
                if markerRange.length == oldNS.length,
                   (mutable.string as NSString).substring(with: markerRange) == oldMarker {
                    let existingAttrs = mutable.attributes(at: markerRange.location, effectiveRange: nil)
                    mutable.replaceCharacters(in: markerRange, with: NSAttributedString(string: newMarker, attributes: existingAttrs))
                }
            }

            invalidateRenderedCache()
            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            textView.selectedRange = bounded(textView.selectedRange, in: textView.text)
            isApplyingStyledText = false
            textStyleData = encodedTextStyleData(from: textView)
            if style == .numberedList {
                // Unlike bullet/dash, a numbered marker's digits depend on every
                // sibling paragraph's level, not just this row's own level —
                // syncRenderedCache would stamp the stale digits (still whatever
                // they were pre-indent) as canonical, and they'd never renumber
                // until an unrelated cache miss (e.g. a width change) happened to
                // force one. Re-render for real so the whole block renumbers now.
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: true)
            } else {
                syncRenderedCache(from: textView)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        private func isStyleApplied(_ style: InlineTextStyle, in range: NSRange, of attributed: NSAttributedString) -> Bool {
            guard range.length > 0, attributed.length > 0 else {
                // cursor: check typing attrs via current attributed position
                return false
            }
            var allApplied = true
            let checkRange = bounded(range, in: attributed.string)
            attributed.enumerateAttributes(in: checkRange) { attrs, _, stop in
                switch style {
                case .bold:
                    let font = attrs[.font] as? UIFont ?? serifBodyFont
                    if !font.fontDescriptor.symbolicTraits.contains(.traitBold) { allApplied = false; stop.pointee = true }
                case .italic:
                    let font = attrs[.font] as? UIFont ?? serifBodyFont
                    if !font.fontDescriptor.symbolicTraits.contains(.traitItalic) { allApplied = false; stop.pointee = true }
                case .underline:
                    if attrs[.underlineStyle] == nil { allApplied = false; stop.pointee = true }
                case .strikethrough:
                    if attrs[.strikethroughStyle] == nil { allApplied = false; stop.pointee = true }
                }
            }
            return allApplied
        }

        // MARK: - Inline style extraction / application

        func extractedInlineStyleData(from textView: UITextView) -> Data? {
            guard let attributed = textView.attributedText, attributed.length > 0 else { return nil }
            var ranges: [InlineStyleRange] = []

            // Build logical offset map for display→logical coordinate mapping
            let logicalOffsets = buildLogicalOffsetMap(from: attributed)

            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
                let font = attrs[.font] as? UIFont
                let bold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
                let italic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
                let underline = attrs[.underlineStyle] != nil
                let strikethrough = attrs[.strikethroughStyle] != nil
                let highlightIndex = attrs[Self.highlightIndexAttribute] as? Int
                let textColorIndex = attrs[Self.textColorIndexAttribute] as? Int
                let linkURL = (attrs[.link] as? URL)?.absoluteString

                // Only store non-default inline attrs (skip title/heading/subheading bold — those are
                // paragraph-level; the subheading font is semibold, which reads as bold)
                let style = self.textStyle(at: range.location, in: attributed)
                let isParaBold = (style == .heading || style == .title || style == .subheading)
                let effectiveBold = bold && !isParaBold

                guard effectiveBold || italic || underline || strikethrough || highlightIndex != nil || linkURL != nil || textColorIndex != nil else { return }

                let logicalStart = displayToLogical(display: range.location, map: logicalOffsets)
                let logicalEnd = displayToLogical(display: NSMaxRange(range), map: logicalOffsets)
                let logicalLen = logicalEnd - logicalStart
                guard logicalLen > 0 else { return }

                ranges.append(InlineStyleRange(
                    location: logicalStart,
                    length: logicalLen,
                    bold: effectiveBold,
                    italic: italic,
                    underline: underline,
                    strikethrough: strikethrough,
                    highlightIndex: highlightIndex,
                    linkURL: linkURL,
                    textColorIndex: textColorIndex
                ))
            }

            // Merge adjacent/overlapping ranges with same attrs
            let merged = mergeInlineRanges(ranges)
            guard !merged.isEmpty else { return nil }
            return try? JSONEncoder().encode(InlineStyleDocument(ranges: merged))
        }

        func applyInlineStyles(to attributed: NSMutableAttributedString, from data: Data?) {
            guard let data,
                  let doc = try? JSONDecoder().decode(InlineStyleDocument.self, from: data),
                  !doc.ranges.isEmpty else { return }

            let logicalOffsets = buildLogicalOffsetMap(from: attributed)
            let highlightColors = HighlightPalette.colors(for: parent.displayMode)
            let textColors = TextColorPalette.colors(for: parent.displayMode)

            for styleRange in doc.ranges {
                let displayStart = logicalToDisplay(logical: styleRange.location, map: logicalOffsets)
                // When a range ends exactly at a paragraph boundary (logicalEnd == paragraph's logicalStart),
                // logicalToDisplay() would add the next paragraph's markerLen and land *inside* the marker.
                // Detect that case and use the paragraph's displayStart instead (before its marker).
                let logicalEnd = styleRange.location + styleRange.length
                let displayEnd: Int
                if logicalEnd > 0, let boundary = firstParagraph(startingAt: logicalEnd, in: logicalOffsets) {
                    displayEnd = boundary.displayStart
                } else {
                    displayEnd = logicalToDisplay(logical: logicalEnd, map: logicalOffsets)
                }
                let displayRange = bounded(NSRange(location: displayStart, length: max(0, displayEnd - displayStart)), in: attributed.string)
                guard displayRange.length > 0 else { continue }

                if styleRange.bold || styleRange.italic {
                    attributed.enumerateAttribute(.font, in: displayRange) { value, range, _ in
                        let font = (value as? UIFont) ?? serifBodyFont
                        var modified = font
                        if styleRange.bold   { modified = modified.withTrait(.traitBold, add: true) }
                        if styleRange.italic { modified = modified.withTrait(.traitItalic, add: true) }
                        attributed.addAttribute(.font, value: modified, range: range)
                    }
                }
                if styleRange.underline {
                    attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: displayRange)
                }
                if styleRange.strikethrough {
                    // Checked checklist rows no longer auto-strike (Notes just dims them),
                    // so a user's explicit strikethrough always applies here now.
                    attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: displayRange)
                }
                if let idx = styleRange.highlightIndex, idx < highlightColors.count {
                    attributed.addAttribute(.backgroundColor, value: UIColor(highlightColors[idx]), range: displayRange)
                    attributed.addAttribute(Self.highlightIndexAttribute, value: idx, range: displayRange)
                }
                if let idx = styleRange.textColorIndex, idx < textColors.count {
                    attributed.addAttribute(.foregroundColor, value: UIColor(textColors[idx]), range: displayRange)
                    attributed.addAttribute(Self.textColorIndexAttribute, value: idx, range: displayRange)
                }
                if let url = validatedLinkURL(from: styleRange.linkURL) {
                    attributed.addAttribute(.link, value: url, range: displayRange)
                }
            }
        }

        // MARK: - Logical ↔ display coordinate mapping

        /// Length of the list marker the paragraph really starts with. Same rule as `logicalText`:
        /// right after a style change, before the re-render inserts the marker, a list paragraph
        /// has none, and counting one shifted every inline range after it.
        private func displayedMarkerLength(of paragraphRange: NSRange, in attributed: NSAttributedString) -> Int {
            let style = textStyle(at: paragraphRange.location, in: attributed)
            let level = indentLevelValue(at: paragraphRange.location, in: attributed)
            let paragraph = (attributed.string as NSString).substring(with: paragraphRange)
            if let marker = staticListMarkerPrefix(for: style, level: level) {
                return paragraph.hasPrefix(marker) ? (marker as NSString).length : 0
            }
            return style == .numberedList ? numberedListMarkerLength(in: paragraph) : 0
        }

        private func buildLogicalOffsetMap(from attributed: NSAttributedString) -> [(displayStart: Int, logicalStart: Int, markerLen: Int)] {
            var result: [(Int, Int, Int)] = []
            var displayOff = 0
            var logicalOff = 0
            let nsDisplay = attributed.string as NSString

            nsDisplay.enumerateSubstrings(in: NSRange(location: 0, length: nsDisplay.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosingRange, _ in
                let markerLen = self.displayedMarkerLength(of: enclosingRange, in: attributed)
                result.append((displayOff, logicalOff, markerLen))
                logicalOff += enclosingRange.length - markerLen
                displayOff += enclosingRange.length
            }
            return result
        }

        /// Index of the last paragraph whose start (by `key`) is at or before `offset`; nil before
        /// the first. Binary search: inline extraction maps every attribute run, and a linear scan
        /// per run made it quadratic (30 ms a keystroke at 50k characters).
        private func paragraphIndex(atOrBefore offset: Int, in map: [(displayStart: Int, logicalStart: Int, markerLen: Int)],
                                    key: KeyPath<(displayStart: Int, logicalStart: Int, markerLen: Int), Int>) -> Int? {
            var low = 0, high = map.count - 1, found: Int?
            while low <= high {
                let mid = (low + high) / 2
                if map[mid][keyPath: key] <= offset { found = mid; low = mid + 1 } else { high = mid - 1 }
            }
            return found
        }

        /// The first paragraph whose logical start is exactly `logical` (binary search).
        private func firstParagraph(startingAt logical: Int, in map: [(displayStart: Int, logicalStart: Int, markerLen: Int)])
            -> (displayStart: Int, logicalStart: Int, markerLen: Int)? {
            var low = 0, high = map.count
            while low < high {
                let mid = (low + high) / 2
                if map[mid].logicalStart < logical { low = mid + 1 } else { high = mid }
            }
            return low < map.count && map[low].logicalStart == logical ? map[low] : nil
        }

        private func displayToLogical(display: Int, map: [(displayStart: Int, logicalStart: Int, markerLen: Int)]) -> Int {
            guard let i = paragraphIndex(atOrBefore: display, in: map, key: \.displayStart) else { return display }
            let entry = map[i]
            return entry.logicalStart + max(0, display - entry.displayStart - entry.markerLen)
        }

        private func logicalToDisplay(logical: Int, map: [(displayStart: Int, logicalStart: Int, markerLen: Int)]) -> Int {
            guard let i = paragraphIndex(atOrBefore: logical, in: map, key: \.logicalStart) else { return logical }
            let entry = map[i]
            return entry.displayStart + entry.markerLen + (logical - entry.logicalStart)
        }

        private func mergeInlineRanges(_ ranges: [InlineStyleRange]) -> [InlineStyleRange] {
            guard !ranges.isEmpty else { return [] }
            let sorted = ranges.sorted { $0.location < $1.location }
            var result: [InlineStyleRange] = [sorted[0]]
            for range in sorted.dropFirst() {
                let last = result[result.count - 1]
                let lastEnd = last.location + last.length
                if range.location <= lastEnd
                    && range.bold == last.bold
                    && range.italic == last.italic
                    && range.underline == last.underline
                    && range.strikethrough == last.strikethrough
                    && range.highlightIndex == last.highlightIndex
                    && range.linkURL == last.linkURL
                    && range.textColorIndex == last.textColorIndex {
                    result[result.count - 1] = InlineStyleRange(
                        location: last.location,
                        length: max(lastEnd, range.location + range.length) - last.location,
                        bold: last.bold, italic: last.italic,
                        underline: last.underline, strikethrough: last.strikethrough,
                        highlightIndex: last.highlightIndex,
                        linkURL: last.linkURL,
                        textColorIndex: last.textColorIndex
                    )
                } else {
                    result.append(range)
                }
            }
            return result
        }

        // MARK: - Active inline style refresh

        private func refreshActiveInlineStyles(in textView: UITextView) {
            guard let attributed = textView.attributedText, attributed.length > 0 else {
                // An empty entry: what the first character will get is all there is to show.
                let style = emptyDocumentStyle().0
                let typing = typingInline(from: textView.typingAttributes, style: style)
                var styles = InlineStyleSet()
                styles.bold = typing.bold
                styles.italic = typing.italic
                styles.underline = typing.underline
                styles.strikethrough = typing.strikethrough
                publishActiveStyles(styles, paragraph: style, highlightIndex: typing.highlightIndex,
                                    textColorIndex: typing.textColorIndex, linkURL: nil)
                return
            }
            let loc = min(lastKnownCursorLocation, attributed.length - 1)
            var styles = InlineStyleSet()
            // When cursor is in the virtual empty paragraph past the last character, the attributed
            // text position (length-1) belongs to the *previous* paragraph's \n. Read ALL inline
            // attributes from typing attrs so the panel reflects the style the user just selected.
            let paraStyle: NoteParagraphTextStyle
            let font: UIFont?
            let underlineActive: Bool
            let strikethroughActive: Bool
            let highlightIndex: Int?
            let textColorIndex: Int?
            let linkURL: String?
            // With nothing selected the panel shows what the next typed character gets, which is
            // the typing attributes (a B pressed with no selection showed as off before).
            if lastKnownCursorLocation >= attributed.length || textView.selectedRange.length == 0 {
                if lastKnownCursorLocation < attributed.length {
                    paraStyle = textStyle(at: loc, in: attributed)
                } else if let raw = textView.typingAttributes[Self.paragraphStyleAttribute] as? String,
                   let style = NoteParagraphTextStyle(rawValue: raw) {
                    paraStyle = style
                } else {
                    paraStyle = .body
                }
                font = textView.typingAttributes[.font] as? UIFont
                underlineActive = textView.typingAttributes[.underlineStyle] != nil
                strikethroughActive = textView.typingAttributes[.strikethroughStyle] != nil
                highlightIndex = textView.typingAttributes[Self.highlightIndexAttribute] as? Int
                textColorIndex = textView.typingAttributes[Self.textColorIndexAttribute] as? Int
                linkURL = (textView.typingAttributes[.link] as? URL)?.absoluteString
            } else {
                paraStyle = textStyle(at: loc, in: attributed)
                font = attributed.attribute(.font, at: loc, effectiveRange: nil) as? UIFont
                underlineActive = attributed.attribute(.underlineStyle, at: loc, effectiveRange: nil) != nil
                strikethroughActive = attributed.attribute(.strikethroughStyle, at: loc, effectiveRange: nil) != nil
                highlightIndex = attributed.attribute(Self.highlightIndexAttribute, at: loc, effectiveRange: nil) as? Int
                textColorIndex = attributed.attribute(Self.textColorIndexAttribute, at: loc, effectiveRange: nil) as? Int
                linkURL = (attributed.attribute(.link, at: loc, effectiveRange: nil) as? URL)?.absoluteString
            }
            let isParaBold = (paraStyle == .heading || paraStyle == .title)
            styles.bold = (font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false) && !isParaBold
            styles.italic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
            styles.underline = underlineActive
            styles.strikethrough = strikethroughActive
            publishActiveStyles(styles, paragraph: paraStyle, highlightIndex: highlightIndex,
                                textColorIndex: textColorIndex, linkURL: linkURL)
        }

        /// The one place the caret's inline styles are published, to the binding the bar reads and
        /// to the Aa panel's state, so the two can't disagree.
        private func publishActiveStyles(_ styles: InlineStyleSet, paragraph: NoteParagraphTextStyle,
                                         highlightIndex: Int?, textColorIndex: Int?, linkURL: String?) {
            parent.activeInlineStyles = styles
            parent.panelState.activeInlineStyles = styles
            setActiveParagraphStyle(paragraph)
            parent.panelState.activeHighlightIndex = highlightIndex
            parent.panelState.activeTextColorIndex = textColorIndex
            parent.panelState.activeLinkURL = linkURL
        }

        /// Sets the caret's paragraph style for both the bar's binding and the Aa panel; several
        /// paths used to set only the binding, leaving the panel's style pill behind.
        private func setActiveParagraphStyle(_ style: NoteParagraphTextStyle) {
            parent.activeParagraphStyle = style
            parent.panelState.activeParagraphStyle = style
        }

        // MARK: - Formatting panel

        private var formattingPanelHost: UIHostingController<AnyView>?

        /// With room (iPad, an opened iPhone Duo) the panel is a SwiftUI `.popover` off the Aa button, so
        /// the keyboard is never touched. iPhone swaps the panel in as the text
        /// view's `inputView`: the keyboard is visually replaced but the text
        /// view keeps first responder, so the selection survives and typing
        /// resumes the moment the panel closes — the Apple Notes model. (A panel
        /// stacked above a live keyboard leaves no room for the editor on a phone.)
        func updateFormattingPanel(textView: UITextView, visible: Bool) {
            let usesInputView = !parent.panelAsPopover

            guard usesInputView else {
                if textView.inputView != nil {
                    textView.inputView = nil
                    textView.reloadInputViews()
                }
                if visible { refreshActiveInlineStyles(in: textView) }
                return
            }

            if visible {
                refreshActiveInlineStyles(in: textView)
                if formattingPanelHost == nil {
                    let hc = UIHostingController(rootView: AnyView(
                        FormattingPanelView(state: parent.panelState, presentation: .sheet,
                                            onClose: { [weak self] in self?.parent.showFormattingPanel = false })
                            .environment(\.appDisplayMode, parent.displayMode)
                    ))
                    hc.view.backgroundColor = .clear
                    // The card sits 8pt above the screen edge like Notes' does, over the home
                    // indicator area, so the host must not inset it by the safe area.
                    hc.safeAreaRegions = []
                    formattingPanelHost = hc
                }
                if let panel = formattingPanelHost?.view {
                    // As tall as the card's content, as in Notes (FormattingPanelSizingTests pins
                    // the default size), capped so large Dynamic Type sizes scroll inside the card
                    // instead of pushing it off screen (audit 2.5).
                    let width = textView.frame.width
                    let fitted = formattingPanelHost?.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height ?? 300
                    let frame = CGRect(x: 0, y: 0, width: width, height: min(fitted, FormattingPanelView.maximumInputHeight))
                    if panel.frame != frame { panel.frame = frame }
                    if textView.inputView !== panel {
                        textView.inputView = panel
                        textView.reloadInputViews()
                        if !textView.isFirstResponder { textView.becomeFirstResponder() }
                    }
                }
            } else if textView.inputView != nil {
                textView.inputView = nil
                textView.reloadInputViews()
            }
        }
    }
}

#endif

#if os(iOS)
extension UIFont {
    func bolded() -> UIFont {
        return withTrait(.traitBold, add: true)
    }

    func withTrait(_ trait: UIFontDescriptor.SymbolicTraits, add: Bool) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if add { traits.insert(trait) } else { traits.remove(trait) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif

nonisolated func preparedInlinePhotoData(from data: Data) -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, [
        kCGImageSourceShouldCache: false
    ] as CFDictionary) else {
        return data
    }

    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: 1600
    ] as CFDictionary

    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        return data
    }

    let imageForEncoding = opaqueRGBImage(from: thumbnail) ?? thumbnail

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
        return data
    }

    CGImageDestinationAddImage(destination, imageForEncoding, [
        kCGImageDestinationLossyCompressionQuality: 0.84
    ] as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
        return data
    }

    return output as Data
}

private nonisolated func opaqueRGBImage(from image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

nonisolated func preparedInlinePhotoData(fromFileAt url: URL) throws -> Data {
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    let prepared = preparedInlinePhotoData(from: data)
    guard isRenderableImageData(prepared) else {
        throw PhotoAttachError.unreadableImage
    }
    return prepared
}

nonisolated func textWithInlinePhotoToken(_ text: String, at index: Int) -> String {
    let token = inlinePhotoToken(at: index)
    guard !text.contains(token) else { return text }
    let trimmed = trimmingTrailingNewlines(text)
    return trimmed.isEmpty ? token : "\(trimmed)\n\(token)\n"
}

/// `text` without its trailing line breaks, for appending a block (photo, scan, Talk It Out).
/// Leading line breaks stay: paragraph styles are stored by paragraph index and inline ranges by
/// offset from the start, so trimming the front shifted every style in the entry.
nonisolated func trimmingTrailingNewlines(_ text: String) -> String {
    var trimmed = text
    while let last = trimmed.last, last.isNewline { trimmed.removeLast() }
    return trimmed
}

private nonisolated func isRenderableImageData(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, [
        kCGImageSourceShouldCache: false
    ] as CFDictionary) else {
        return false
    }
    return CGImageSourceGetCount(source) > 0
}

#if os(iOS)
/// The editor text view. Its undo manager is the editor's own history (see the coordinator's
/// "Undo" section), so Cmd-Z, shake and the three-finger gesture use the same steps as the
/// toolbar's Undo button.
/// Draws a checklist item's marker as Notes does: a light grey circle, or a filled accent circle
/// with a white check. The stored marker characters ("○  " / "✓  ") stay in the text, so every
/// edit, parse and older version reads them unchanged; only their glyph isn't drawn. Measured from
/// Notes on an iPhone (2026-10-15): about 22pt across at body size, text starting past it.
final class ChecklistLayoutManager: NSLayoutManager {
    private(set) var accentColor: UIColor = .tintColor
    /// The accent as last set: resolved components and the light/dark style they were resolved in.
    private var accentKey: [CGFloat]?

    /// Sets the circles' accent; true when it changed and they need redrawing. Compares resolved
    /// components: each `UIColor(Color.accentColor)` is a new adaptive color that `isEqual` never
    /// matches, so comparing the colors themselves redrew the whole text on every update.
    @discardableResult
    func setAccentColor(_ color: UIColor, traits: UITraitCollection) -> Bool {
        var c: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        let resolved = color.resolvedColor(with: traits).getRed(&c.0, green: &c.1, blue: &c.2, alpha: &c.3)
        let key = resolved ? [c.0, c.1, c.2, c.3, CGFloat(traits.userInterfaceStyle.rawValue)] : nil
        if let key, key == accentKey { return false }
        accentKey = key
        accentColor = color
        return true
    }
    /// Where a checklist item's text starts, from the paragraph's leading edge.
    static let textIndent: CGFloat = 36
    let markerSpacing = ChecklistMarkerSpacing()

    private static let unchecked = NoteParagraphTextStyle.checklistUnchecked.rawValue
    private static let checked = NoteParagraphTextStyle.checklistChecked.rawValue

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage, storage.length > 0 else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let text = storage.string as NSString
        var markers: [(glyph: Int, char: Int, checked: Bool)] = []
        var paragraph = text.paragraphRange(for: NSRange(location: chars.location, length: 0))
        while paragraph.location < NSMaxRange(chars), paragraph.location < text.length {
            let at = paragraph.location
            if let raw = storage.attribute(NoteEditorTextView.Coordinator.paragraphStyleAttribute, at: at, effectiveRange: nil) as? String,
               raw == Self.unchecked || raw == Self.checked {
                let ch = text.character(at: at)
                if ch == 0x25CB || ch == 0x2713 {   // ○ ✓
                    markers.append((glyphIndexForCharacter(at: at), at, raw == Self.checked))
                }
            }
            let next = NSMaxRange(paragraph)
            guard next > paragraph.location, next < text.length else { break }
            paragraph = text.paragraphRange(for: NSRange(location: next, length: 0))
        }
        guard !markers.isEmpty || !hiddenCharacterRanges.isEmpty else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        // Everything but the marker glyphs, then the circles.
        drawSkipping(glyphsToShow, markers: markers.map(\.glyph), at: origin)
        for marker in markers where NSLocationInRange(marker.glyph, glyphsToShow) && !isHidden(character: marker.char) {
            drawCircle(for: marker, storage: storage, origin: origin)
        }
    }

    /// Characters not drawn for now: rows a slide or drag animates as snapshots, or a circle that
    /// is popping in.
    var hiddenCharacterRanges: [NSRange] = []

    /// Text added or deleted while a row or circle animates (the animations allow interaction)
    /// shifts what the hidden ranges point at, so they are dropped and everything draws.
    override func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorage.EditActions,
                                 range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
        if delta != 0, !hiddenCharacterRanges.isEmpty { hiddenCharacterRanges = [] }
    }

    private func isHidden(character index: Int) -> Bool {
        hiddenCharacterRanges.contains { NSLocationInRange(index, $0) }
    }

    /// Draws `range` except the marker glyphs and any hidden characters.
    private func drawSkipping(_ range: NSRange, markers: [Int], at origin: CGPoint) {
        var skip = Set(markers.filter { NSLocationInRange($0, range) })
        let length = textStorage?.length ?? 0
        for hidden in hiddenCharacterRanges {
            // A range set before an edit can run past the text's end now.
            let hidden = NSIntersectionRange(hidden, NSRange(location: 0, length: length))
            guard hidden.length > 0 else { continue }
            let glyphs = glyphRange(forCharacterRange: hidden, actualCharacterRange: nil)
            for g in glyphs.location..<NSMaxRange(glyphs) where NSLocationInRange(g, range) { skip.insert(g) }
        }
        guard !skip.isEmpty else {
            super.drawGlyphs(forGlyphRange: range, at: origin)
            return
        }
        var start = range.location
        for g in skip.sorted() {
            if g > start { super.drawGlyphs(forGlyphRange: NSRange(location: start, length: g - start), at: origin) }
            start = g + 1
        }
        if start < NSMaxRange(range) {
            super.drawGlyphs(forGlyphRange: NSRange(location: start, length: NSMaxRange(range) - start), at: origin)
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        // A hidden row's highlight goes with it (the snapshot carries it).
        guard !hiddenCharacterRanges.isEmpty else { return super.drawBackground(forGlyphRange: glyphsToShow, at: origin) }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        if hiddenCharacterRanges.contains(where: { NSIntersectionRange($0, chars).length == chars.length }) { return }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawCircle(for marker: (glyph: Int, char: Int, checked: Bool), storage: NSTextStorage, origin: CGPoint) {
        guard let circle = circle(forMarkerAt: marker.char, checked: marker.checked) else { return }
        circle.image.draw(in: circle.rect.offsetBy(dx: origin.x, dy: origin.y))
    }

    /// The circle image for the marker at `char` and where it goes, in text container coordinates.
    func circle(forMarkerAt char: Int, checked: Bool) -> (image: UIImage, rect: CGRect)? {
        guard let storage = textStorage, char < storage.length else { return nil }
        let glyph = glyphIndexForCharacter(at: char)
        let marker = (glyph: glyph, char: char, checked: checked)
        let origin = CGPoint.zero
        let font = (storage.attribute(.font, at: marker.char, effectiveRange: nil) as? UIFont) ?? .preferredFont(forTextStyle: .body)
        let line = lineFragmentRect(forGlyphAt: marker.glyph, effectiveRange: nil)
        let glyphX = location(forGlyphAt: marker.glyph).x
        let baseline = line.minY + location(forGlyphAt: marker.glyph).y
        // Notes' circle is about 22pt across at body size, a light grey ring when open.
        let diameter = (font.pointSize * 1.3).rounded()
        // Centred on the text's x-height band, so the circle sits level with lowercase letters.
        let centerY = origin.y + baseline - font.xHeight / 2 - font.descender * 0.15
        let config = UIImage.SymbolConfiguration(pointSize: diameter, weight: .regular)
        let image: UIImage?
        if marker.checked {
            image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config.applying(
                UIImage.SymbolConfiguration(paletteColors: [.white, accentColor])))
        } else {
            image = UIImage(systemName: "circle", withConfiguration: config)?
                .withTintColor(.systemGray3, renderingMode: .alwaysOriginal)
        }
        guard let image, image.size.width > 0 else { return nil }
        // A symbol image carries padding around its glyph; scale it so the circle itself is
        // `diameter` across (it used to come out near 19pt instead of 22).
        let scale = diameter / (image.size.width * 0.84)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let x = origin.x + line.minX + glyphX - (size.width - diameter) / 2
        return (image, CGRect(x: x, y: centerY - size.height / 2, width: size.width, height: size.height))
    }
}

/// Kerns each checklist marker ("○  " / "✓  ") out to `ChecklistLayoutManager.textIndent`, so the
/// item's text clears the drawn circle and its first line starts where wrapped lines do. Runs after
/// every edit of the text storage, so every path that writes a marker gets it.
final class ChecklistMarkerSpacing: NSObject, NSTextStorageDelegate {
    private static let checklistStyles: Set<String> = [
        NoteParagraphTextStyle.checklistUnchecked.rawValue,
        NoteParagraphTextStyle.checklistChecked.rawValue
    ]

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        let text = textStorage.string as NSString
        guard text.length > 0 else { return }
        let scope = text.paragraphRange(for: NSRange(location: min(editedRange.location, text.length - 1),
                                                     length: min(editedRange.length, text.length - min(editedRange.location, text.length - 1))))
        // Only a marker's spacer is kerned. Text typed after it inherits the kern from the typing
        // attributes ("t e s t"), and a marker removed by a style change leaves it on its row.
        var wanted: [(location: Int, kern: CGFloat)] = []
        text.enumerateSubstrings(in: scope, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let at = range.location
            guard range.length >= 3,
                  let raw = textStorage.attribute(NoteEditorTextView.Coordinator.paragraphStyleAttribute, at: at, effectiveRange: nil) as? String,
                  Self.checklistStyles.contains(raw) else { return }
            let first = text.character(at: at)
            guard first == 0x25CB || first == 0x2713, text.character(at: at + 1) == 0x20, text.character(at: at + 2) == 0x20 else { return }
            let font = (textStorage.attribute(.font, at: at, effectiveRange: nil) as? UIFont) ?? .preferredFont(forTextStyle: .body)
            let width = text.substring(with: NSRange(location: at, length: 3)).size(withAttributes: [.font: font]).width
            wanted.append((at + 2, max(0, ChecklistLayoutManager.textIndent - width)))
        }
        // Most edits (every keystroke outside a checklist, and input-method composing) leave the
        // kerning as it is; rewriting it anyway re-marks the scope as edited.
        var present: [(location: Int, length: Int, kern: CGFloat)] = []
        textStorage.enumerateAttribute(.kern, in: scope) { value, range, _ in
            if let kern = (value as? NSNumber).map({ CGFloat($0.doubleValue) }) { present.append((range.location, range.length, kern)) }
        }
        let unchanged = present.count == wanted.count && zip(present, wanted).allSatisfy {
            $0.location == $1.location && $0.length == 1 && abs($0.kern - $1.kern) < 0.01
        }
        guard !unchanged else { return }
        textStorage.removeAttribute(.kern, range: scope)
        for spacer in wanted {
            textStorage.addAttribute(.kern, value: spacer.kern, range: NSRange(location: spacer.location, length: 1))
        }
    }
}

final class MirrorEditorTextView: UITextView {
    weak var editorUndo: UndoManager?
    /// The editor's own list gestures (circle tap, swipe to indent, drag to reorder).
    var checklistGestureRecognizers: [UIGestureRecognizer] = []
    /// Whether a point (text view coordinates) is on a checklist item's circle.
    var isChecklistMarker: ((CGPoint) -> Bool)?

    /// A tap on a checklist circle only toggles the item, as in Notes: UIKit's own text gestures
    /// would also move the caret there and raise the keyboard.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if !checklistGestureRecognizers.contains(where: { $0 === gestureRecognizer }), gestureRecognizer.view === self,
           let isChecklistMarker, isChecklistMarker(gestureRecognizer.location(in: self)) {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    override var undoManager: UndoManager? { editorUndo ?? super.undoManager }

    /// Extra VoiceOver actions for the caret's paragraph (checking a checklist item).
    var caretAccessibilityActions: (() -> [UIAccessibilityCustomAction])?
    private var assignedAccessibilityActions: [UIAccessibilityCustomAction]?
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get { (assignedAccessibilityActions ?? []) + (caretAccessibilityActions?() ?? []) }
        set { assignedAccessibilityActions = newValue }
    }
}

/// Answers UIKit's undo questions from the editor's snapshot history. Registrations UIKit makes
/// while typing are accepted and never used.
final class EditorUndoManager: UndoManager {
    private weak var coordinator: NoteEditorTextView.Coordinator?
    weak var textView: UITextView?

    init(coordinator: NoteEditorTextView.Coordinator) {
        self.coordinator = coordinator
        super.init()
        levelsOfUndo = 1   // only UIKit's unused typing registrations land here
    }

    override var canUndo: Bool { coordinator?.canUndoEdit ?? false }
    override var canRedo: Bool { coordinator?.canRedoEdit ?? false }
    override func undo() {
        guard let coordinator, let textView else { return }
        coordinator.undoEdit(in: textView)
    }
    override func redo() {
        guard let coordinator, let textView else { return }
        coordinator.redoEdit(in: textView)
    }
    override func undoNestedGroup() { undo() }
}
#endif
