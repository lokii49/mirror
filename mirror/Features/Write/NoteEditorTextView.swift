import SwiftUI
import UIKit
import Photos
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

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
    var panelState: FormattingPanelState
    var onPhotoTapped: ((Int) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.typingAttributes = context.coordinator.bodyAttributes

        let placeholder = UILabel()
        placeholder.text = "What's on your mind?"
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

        textView.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.logicalText(from: textView) != context.coordinator.displayTextEquivalent(for: text) {
            let selectedRange = textView.selectedRange
            context.coordinator.applyStyledText(to: textView, preservingSelection: false)
            textView.selectedRange = context.coordinator.bounded(selectedRange, in: textView.text)
        } else {
            context.coordinator.applyStyledText(to: textView, preservingSelection: true)
        }

        context.coordinator.updatePlaceholder(in: textView)

        if isFocused, !textView.isFirstResponder {
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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
        static let placeholderTag = 701

        var parent: NoteEditorTextView
        private static let paragraphStyleAttribute = NSAttributedString.Key("mirror.paragraphStyle")
        private static let highlightIndexAttribute = NSAttributedString.Key("mirror.highlightIndex")
        private static let indentLevelAttribute = NSAttributedString.Key("mirror.indentLevel")
        private var isApplyingStyledText = false
        private var lastRenderedText: String?
        private var lastRenderedStyleSignature: Int?
        private var lastRenderedInlineSignature: Int?
        private var lastRenderedPhotoSignature: Int?
        private var lastRenderedWidth: CGFloat = 0
        private var lastRenderedFontChoice: WritingFontChoice?
        // Tracks cursor position across focus changes (Menu dismissal resets selectedRange)
        private var lastKnownCursorLocation: Int = 0
        var lastAppliedCommandRevision = 0
        // marker lengths per paragraph index, populated during render for coord mapping
        private var paragraphMarkerLengths: [Int: Int] = [:]
        // formatting panel hosted in UITextView.inputView
        private var formattingPanelHost: UIHostingController<FormattingPanelView>?

        init(parent: NoteEditorTextView) {
            self.parent = parent
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
                if attachCount < sortedTokens.count {
                    parent.onPhotoTapped?(sortedTokens[attachCount].index)
                }
                return
            }

            let paraRange = nsText.paragraphRange(for: NSRange(location: charIndex, length: 0))
            let currentStyle = textStyle(at: paraRange.location, in: textView.attributedText)
            let iLevel = indentLevelValue(at: paraRange.location, in: textView.attributedText)
            let markerStart = textView.textContainerInset.left + CGFloat(iLevel) * 20
            let markerEnd = textView.textContainerInset.left + 44 + CGFloat(iLevel) * 20
            guard location.x >= markerStart && location.x <= markerEnd else { return }
            guard currentStyle == .checklistUnchecked || currentStyle == .checklistChecked else { return }

            let nextStyle: NoteParagraphTextStyle = currentStyle == .checklistUnchecked ? .checklistChecked : .checklistUnchecked
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            mutable.removeAttribute(Self.paragraphStyleAttribute, range: paraRange)
            mutable.addAttributes(attributes(for: nextStyle, level: iLevel), range: paraRange)
            mutable.addAttribute(Self.paragraphStyleAttribute, value: nextStyle.rawValue, range: paraRange)
            if iLevel > 0 { mutable.addAttribute(Self.indentLevelAttribute, value: iLevel, range: paraRange) }

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            textView.selectedRange = bounded(NSRange(location: charIndex, length: 0), in: text)
            isApplyingStyledText = false
            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // MARK: - Photo context menu (UIContextMenuInteractionDelegate)

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let textView = interaction.view as? UITextView,
                  let photoIndex = photoAttachmentIndex(at: location, in: textView),
                  photoIndex < parent.photoDataArray.count else { return nil }
            let data = parent.photoDataArray[photoIndex]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let copy = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                    if let image = UIImage(data: data) { UIPasteboard.general.image = image }
                }
                let save = UIAction(title: "Save to Photos", image: UIImage(systemName: "square.and.arrow.down")) { _ in
                    guard let image = UIImage(data: data) else { return }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }, completionHandler: nil)
                }
                let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    guard let image = UIImage(data: data) else { return }
                    let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                    UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows.first?.rootViewController?
                        .present(vc, animated: true)
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
        // sites — cache the built font, but keyed on the user's choice so switching
        // fonts in the formatting panel takes effect immediately.
        private var _bodyFontCache: (choice: WritingFontChoice, font: UIFont)?
        var serifBodyFont: UIFont {
            let choice = WritingFontChoice.current
            if let cache = _bodyFontCache, cache.choice == choice {
                return cache.font
            }
            let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            let font = UIFont(descriptor: base.withDesign(choice.uiDesign) ?? base, size: 0)
            _bodyFontCache = (choice, font)
            return font
        }

        var bodyAttributes: [NSAttributedString.Key: Any] {
            [
                .font: serifBodyFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle(lineSpacing: 6)
            ]
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingStyledText else { return }
            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            parent.inlineStyleData = extractedInlineStyleData(from: textView)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
            updateTypingAttributes(for: textView)
            refreshActiveInlineStyles(in: textView)
            parent.canUndo = textView.undoManager?.canUndo ?? false
            parent.canRedo = textView.undoManager?.canRedo ?? false
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
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
                let paragraphRange = nsText.paragraphRange(for: NSRange(location: max(0, range.location - 1), length: 0))
                let paragraph = nsText.substring(with: paragraphRange)
                let style = textStyle(at: paragraphRange.location, in: textView.attributedText)
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
            let insertionRange = bounded(NSRange(location: markerEnd, length: 0), in: mutable.string)
            let attributedReplacement = NSAttributedString(
                string: replacement,
                attributes: styledAttributesForTyping(style, numberedIndex: nil, level: paraLevel)
            )
            mutable.replaceCharacters(in: insertionRange, with: attributedReplacement)

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            textView.selectedRange = bounded(
                NSRange(location: insertionRange.location + (replacement as NSString).length, length: 0),
                in: textView.text
            )
            isApplyingStyledText = false

            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            textView.typingAttributes = styledAttributesForTyping(style, numberedIndex: nil, level: paraLevel)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
            refreshActiveParagraphStyle(in: textView)
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

            exitList(at: paragraphRange, in: textView)
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingStyledText, textView.isFirstResponder else { return }
            lastKnownCursorLocation = textView.selectedRange.location
            clampCursorPastListMarker(in: textView)
            refreshActiveParagraphStyle(in: textView)
            refreshActiveInlineStyles(in: textView)
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
            parent.isFocused = true
            lastKnownCursorLocation = textView.selectedRange.location
            refreshActiveParagraphStyle(in: textView)
            refreshActiveInlineStyles(in: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func apply(_ command: NoteTextCommand, to textView: UITextView) {
            // Inline style commands
            switch command {
            case .bold, .italic, .underline, .strikethrough:
                toggleInlineStyle(command, in: textView)
                return
            case .highlight(let index):
                applyHighlight(index, in: textView)
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
            case .photo(let index):
                insertPhotoToken(at: index, in: textView)
                return
            case .undo:
                textView.undoManager?.undo()
                DispatchQueue.main.async {
                    self.parent.canUndo = textView.undoManager?.canUndo ?? false
                    self.parent.canRedo = textView.undoManager?.canRedo ?? false
                }
                return
            case .redo:
                textView.undoManager?.redo()
                DispatchQueue.main.async {
                    self.parent.canUndo = textView.undoManager?.canUndo ?? false
                    self.parent.canRedo = textView.undoManager?.canRedo ?? false
                }
                return
            default: break
            }

            let nsText = (textView.text ?? "") as NSString
            let liveCursorLocation = textView.isFirstResponder ? textView.selectedRange.location : lastKnownCursorLocation
            let cursorLocation = min(liveCursorLocation, max(0, nsText.length))
            lastKnownCursorLocation = cursorLocation

            // Determine target style. List styles toggle off when already active.
            let currentStyle = textStyle(
                at: min(cursorLocation, max(0, (textView.attributedText?.length ?? 1) - 1)),
                in: textView.attributedText
            )
            let targetStyle: NoteParagraphTextStyle
            if command == .checklist {
                targetStyle = isListStyle(currentStyle) ? .body : .checklistUnchecked
            } else if command == .bulletedList {
                targetStyle = currentStyle == .bulletedList ? .body : .bulletedList
            } else if command == .dashedList {
                targetStyle = currentStyle == .dashedList ? .body : .dashedList
            } else if command == .numberedList {
                targetStyle = currentStyle == .numberedList ? .body : .numberedList
            } else {
                targetStyle = paragraphStyle(for: command)
            }

            let cursorLevel = isListStyle(targetStyle) ? indentLevelValue(at: min(cursorLocation, max(0, (textView.attributedText?.length ?? 1) - 1)), in: textView.attributedText) : 0

            if nsText.length == 0 {
                parent.textStyleData = try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [targetStyle]))
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: false)
                if let marker = staticListMarkerPrefix(for: targetStyle) {
                    textView.selectedRange = bounded(NSRange(location: marker.count, length: 0), in: textView.text)
                } else if targetStyle == .numberedList {
                    textView.selectedRange = bounded(NSRange(location: "1.  ".count, length: 0), in: textView.text)
                }
                textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: 1, level: cursorLevel)
                updatePlaceholder(in: textView)
                parent.activeParagraphStyle = targetStyle
                return
            }

            // Strip the visual list marker whenever transitioning from any list style to any non-list style.
            if isListStyle(currentStyle) && !isListStyle(targetStyle) {
                stripListMarkerAndApply(targetStyle, at: cursorLocation, in: textView)
                parent.activeParagraphStyle = targetStyle
                return
            }

            // Cursor is in a virtual empty paragraph past the last character (e.g. "Hello\n", cursor at 6).
            // paragraphRange(for: {length, 0}) returns an empty range that enumerateSubstrings never visits,
            // so the style change silently no-ops. Handle it explicitly.
            if cursorLocation >= nsText.length {
                if isListStyle(targetStyle) {
                    // Extend textStyleData to cover the virtual paragraph, then re-render to insert the marker.
                    var styles = decodedTextStyles()
                    if styles.isEmpty {
                        var count = 0
                        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length),
                                                   options: [.byParagraphs, .substringNotRequired]) { _, _, _, _ in count += 1 }
                        styles = Array(repeating: .body, count: count)
                    }
                    // Only append when cursor is in a true ghost paragraph (text ends with a line break).
                    // When the last paragraph just has no trailing newline (e.g. "○  " clamped to end),
                    // the last styles entry already covers it — update it instead of appending.
                    let lastChar = nsText.length > 0 ? nsText.character(at: nsText.length - 1) : 0
                    let endsWithLineBreak = lastChar == 10 || lastChar == 13
                    if endsWithLineBreak || styles.isEmpty {
                        styles.append(targetStyle)
                    } else {
                        styles[styles.count - 1] = targetStyle
                    }
                    parent.textStyleData = try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: styles))
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
                    textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: nil, level: cursorLevel)
                } else {
                    // Non-list style: typing attributes alone are sufficient; no re-render needed.
                    textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: nil, level: cursorLevel)
                }
                updatePlaceholder(in: textView)
                parent.activeParagraphStyle = targetStyle
                parent.panelState.activeParagraphStyle = targetStyle
                refreshActiveInlineStyles(in: textView)
                return
            }

            let cursorRange = NSRange(location: cursorLocation, length: 0)
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
                textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: nil, level: cursorLevel)
                parent.activeParagraphStyle = targetStyle
                parent.panelState.activeParagraphStyle = targetStyle
                refreshActiveInlineStyles(in: textView)
                return
            }

            nsText.enumerateSubstrings(in: paragraphRange, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                self.setParagraphStyle(targetStyle, range: range, in: textView)
            }
            if staticListMarkerPrefix(for: targetStyle) != nil || targetStyle == .numberedList {
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: false)
                let markerLen: Int
                if targetStyle == .numberedList {
                    // After re-render the displayed marker is "1.  " or similar — measure it
                    let displayText = textView.text ?? ""
                    let nsDisplay = displayText as NSString
                    let safePos = min(cursorLocation, max(0, nsDisplay.length - 1))
                    let pRange = nsDisplay.paragraphRange(for: NSRange(location: safePos, length: 0))
                    let pText = nsDisplay.substring(with: pRange)
                    markerLen = numberedListMarkerLength(in: pText)
                } else {
                    markerLen = (staticListMarkerPrefix(for: targetStyle) as NSString?)?.length ?? 0
                }
                textView.selectedRange = bounded(
                    NSRange(location: cursorLocation + markerLen, length: 0),
                    in: textView.text
                )
            } else {
                textView.selectedRange = bounded(NSRange(location: cursorLocation, length: 0), in: textView.text)
            }
            textView.typingAttributes = styledAttributesForTyping(targetStyle, numberedIndex: nil, level: cursorLevel)
            updatePlaceholder(in: textView)
            parent.activeParagraphStyle = targetStyle
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
                mutable.removeAttribute(Self.paragraphStyleAttribute, range: newParaRange)
                mutable.addAttributes(attributes(for: targetStyle, level: level), range: newParaRange)
                if targetStyle != .body {
                    mutable.addAttribute(Self.paragraphStyleAttribute, value: targetStyle.rawValue, range: newParaRange)
                }
            }

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false

            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            syncRenderedCache(from: textView)

            let newCursor = max(displayParaRange.location, cursorLocation - markerLen)
            textView.selectedRange = bounded(NSRange(location: newCursor, length: 0), in: textView.text)
            textView.typingAttributes = targetStyle == .body
                ? bodyAttributes
                : styledAttributesForTyping(targetStyle, numberedIndex: nil)
            updatePlaceholder(in: textView)
        }

        private func removeListAndApplyBody(at cursorLocation: Int, in textView: UITextView) {
            stripListMarkerAndApply(.body, at: cursorLocation, in: textView)
        }

        func applyStyledText(to textView: UITextView, preservingSelection: Bool) {
            let selectedRange = textView.selectedRange
            let rawText = parent.text
            let styleSignature = parent.textStyleData?.hashValue
            let inlineSignature = parent.inlineStyleData?.hashValue
            let photoSignature = parent.photoDataArray.map(\.count).reduce(0, +)
            let width = textView.bounds.width.rounded()
            let fontChoice = WritingFontChoice.current

            if lastRenderedText == rawText,
               lastRenderedStyleSignature == styleSignature,
               lastRenderedInlineSignature == inlineSignature,
               lastRenderedPhotoSignature == photoSignature,
               lastRenderedWidth == width,
               lastRenderedFontChoice == fontChoice {
                if preservingSelection {
                    textView.selectedRange = bounded(selectedRange, in: textView.text)
                }
                updateTypingAttributes(for: textView)
                return
            }

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
            updateTypingAttributes(for: textView)
        }

        func updatePlaceholder(in textView: UITextView) {
            let placeholder = textView.viewWithTag(Self.placeholderTag) as? UILabel
            placeholder?.isHidden = !parent.text.isEmpty || parent.textStyleData != nil
            placeholder?.font = serifBodyFont
        }

        private func refreshActiveParagraphStyle(in textView: UITextView) {
            guard let attributed = textView.attributedText, attributed.length > 0 else {
                parent.activeParagraphStyle = .body
                return
            }
            if lastKnownCursorLocation >= attributed.length {
                if let raw = textView.typingAttributes[Self.paragraphStyleAttribute] as? String,
                   let style = NoteParagraphTextStyle(rawValue: raw) {
                    parent.activeParagraphStyle = style
                } else {
                    parent.activeParagraphStyle = .body
                }
                return
            }
            let loc = min(lastKnownCursorLocation, attributed.length - 1)
            parent.activeParagraphStyle = textStyle(at: loc, in: attributed)
        }

        func logicalText(from textView: UITextView) -> String {
            let attributed = textView.attributedText ?? NSAttributedString()
            // Replace each attachment char with the correct indexed photo token
            var displayString = attributed.string
            let photoTokensSorted = allPhotoTokens(in: parent.text).sorted {
                parent.text.distance(from: parent.text.startIndex, to: $0.range.lowerBound) <
                parent.text.distance(from: parent.text.startIndex, to: $1.range.lowerBound)
            }
            var tokenIdx = 0
            var rebuilt = ""
            for ch in displayString {
                if ch == "\u{fffc}" {
                    let tok = tokenIdx < photoTokensSorted.count ? inlinePhotoToken(at: photoTokensSorted[tokenIdx].index) : inlinePhotoToken(at: tokenIdx)
                    rebuilt += tok
                    tokenIdx += 1
                } else {
                    rebuilt += String(ch)
                }
            }
            displayString = rebuilt

            let nsRendered = displayString as NSString
            guard nsRendered.length > 0 else { return "" }

            var result = ""
            // Use enclosingRange (3rd param) not substringRange (2nd param) — enclosingRange
            // includes the paragraph separator (\n), substringRange does not.
            nsRendered.enumerateSubstrings(in: NSRange(location: 0, length: nsRendered.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosingRange, _ in
                let paragraph = nsRendered.substring(with: enclosingRange)
                let style = self.textStyle(at: enclosingRange.location, in: attributed)
                let level = self.indentLevelValue(at: enclosingRange.location, in: attributed)
                if let marker = self.staticListMarkerPrefix(for: style, level: level), paragraph.hasPrefix(marker) {
                    result += String(paragraph.dropFirst(marker.count))
                } else if style == .numberedList {
                    let markerLen = self.numberedListMarkerLength(in: paragraph)
                    result += markerLen > 0 ? String(paragraph.dropFirst(markerLen)) : paragraph
                } else {
                    result += paragraph
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

        private func attributes(for style: NoteParagraphTextStyle, level: Int = 0, numberedIndex: Int? = nil) -> [NSAttributedString.Key: Any] {
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
                    .font: UIFont.monospacedSystemFont(ofSize: serifBodyFont.pointSize, weight: .regular),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
                ]
            case .checklistUnchecked:
                return checklistAttributes(checked: false, level: level)
            case .checklistChecked:
                return checklistAttributes(checked: true, level: level)
            case .bulletedList, .dashedList, .numberedList:
                return listAttributes(level: level)
            case .body:
                return bodyAttributes
            }
        }

        private func attributes(for paragraph: String, storedStyle: NoteParagraphTextStyle = .body, level: Int = 0) -> [NSAttributedString.Key: Any] {
            if storedStyle != .body {
                return attributes(for: storedStyle, level: level)
            }
            if paragraph.hasPrefix("### ") { return attributes(for: .subheading) }
            if paragraph.hasPrefix("## ") { return attributes(for: .heading) }
            if paragraph.hasPrefix("# ") { return attributes(for: .title) }
            if paragraph.hasPrefix("    ") { return attributes(for: .monospaced) }
            if paragraph.hasPrefix("○ ") { return checklistAttributes(checked: false, level: level) }
            if paragraph.hasPrefix("✓ ") { return checklistAttributes(checked: true, level: level) }
            return bodyAttributes
        }

        private func checklistAttributes(checked: Bool, level: Int = 0) -> [NSAttributedString.Key: Any] {
            let offset = CGFloat(level) * 20
            let ps = paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
            ps.firstLineHeadIndent = offset
            ps.headIndent = 44 + offset
            var attrs: [NSAttributedString.Key: Any] = [
                .font: serifBodyFont,
                .foregroundColor: checked ? UIColor.tertiaryLabel : UIColor.label,
                .paragraphStyle: ps
            ]
            if checked {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = UIColor.tertiaryLabel
            }
            return attrs
        }

        private func listAttributes(level: Int = 0) -> [NSAttributedString.Key: Any] {
            let offset = CGFloat(level) * 20
            let ps = paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
            ps.firstLineHeadIndent = offset
            ps.headIndent = 28 + offset
            return [
                .font: serifBodyFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: ps
            ]
        }

        private func insertPhotoToken(at photoIndex: Int, in textView: UITextView) {
            let logical = logicalText(from: textView)
            let selectedRange = bounded(textView.selectedRange, in: logical)
            let nsText = logical as NSString
            var insertion = inlinePhotoToken(at: photoIndex)

            if selectedRange.location > 0 {
                let previous = nsText.substring(with: NSRange(location: selectedRange.location - 1, length: 1))
                if previous != "\n" {
                    insertion = "\n" + insertion
                }
            }

            let end = selectedRange.location + selectedRange.length
            if end < nsText.length {
                let next = nsText.substring(with: NSRange(location: end, length: 1))
                if next != "\n" {
                    insertion += "\n"
                }
            } else {
                insertion += "\n"
            }

            let updated = nsText.replacingCharacters(in: selectedRange, with: insertion)
            parent.text = updated
            applyStyledText(to: textView, preservingSelection: false)
            textView.selectedRange = bounded(NSRange(location: selectedRange.location + insertion.count, length: 0), in: textView.text)
            updatePlaceholder(in: textView)
        }

        private func renderedAttributedText(for rawText: String, width: CGFloat) -> NSMutableAttributedString {
            paragraphMarkerLengths.removeAll()
            let attributed = NSMutableAttributedString()

            if rawText.isEmpty,
               let firstStyle = decodedTextStyles().first {
                let marker = staticListMarkerPrefix(for: firstStyle) ?? (firstStyle == .numberedList ? "1.  " : nil)
                if let marker {
                    let paragraph = NSMutableAttributedString(string: marker, attributes: attributes(for: firstStyle))
                    paragraph.addAttribute(Self.paragraphStyleAttribute, value: firstStyle.rawValue, range: NSRange(location: 0, length: paragraph.length))
                    attributed.append(paragraph)
                    paragraphMarkerLengths[0] = (marker as NSString).length
                }
                return attributed
            }

            // Split on all photo tokens, render text segments between them
            let regex = try? NSRegularExpression(pattern: #"\[\[mirror-photo(?:-(\d+))?\]\]"#)
            let nsRaw = rawText as NSString
            let allMatches = regex?.matches(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)) ?? []

            var lastEnd = 0
            var paragraphOffset = 0

            for match in allMatches {
                let textRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let textSegment = nsRaw.substring(with: textRange)
                let rendered = renderedTextWithoutMarkdownMarkers(for: textSegment, startingParagraph: paragraphOffset)
                attributed.append(rendered.value)
                paragraphOffset += rendered.paragraphCount

                let token = nsRaw.substring(with: match.range)
                let photoIdx = inlinePhotoIndex(from: token) ?? 0
                attributed.append(photoAttachmentString(at: photoIdx, width: width))
                lastEnd = NSMaxRange(match.range)
            }

            let tail = nsRaw.substring(from: lastEnd)
            attributed.append(renderedTextWithoutMarkdownMarkers(for: tail, startingParagraph: paragraphOffset).value)
            return attributed
        }

        private func renderedTextWithoutMarkdownMarkers(for rawText: String, startingParagraph: Int) -> (value: NSAttributedString, paragraphCount: Int) {
            let attributed = NSMutableAttributedString()
            let rawParagraphs = rawText.components(separatedBy: "\n")
            guard !rawParagraphs.isEmpty else { return (attributed, 0) }
            let storedStyles = decodedTextStyles()
            let storedIndents = decodedIndentLevels()
            var paragraphIndex = startingParagraph
            var numberedListCounter = 0

            for (offset, rawLine) in rawParagraphs.enumerated() {
                let lineBreak = offset < rawParagraphs.count - 1 ? "\n" : ""
                let rawParagraph = rawLine + lineBreak
                let legacyStyle = self.legacyStyle(in: rawParagraph)
                let storedStyle = storedStyles.indices.contains(paragraphIndex) ? storedStyles[paragraphIndex] : legacyStyle
                let indentLevel = storedIndents.indices.contains(paragraphIndex) ? storedIndents[paragraphIndex] : 0

                // Track numbered list counter for sequential numbering
                if storedStyle == .numberedList {
                    numberedListCounter += 1
                } else {
                    numberedListCounter = 0
                }

                let prefix = self.legacyMarkdownPrefix(in: rawParagraph)
                let legacyChecklistPrefix = self.legacyChecklistPrefix(in: rawParagraph)
                let rawDisplayParagraph = prefix.map { String(rawParagraph.dropFirst($0.count)) }
                    ?? legacyChecklistPrefix.map { String(rawParagraph.dropFirst($0.count)) }
                    ?? rawParagraph

                let listMarker: String
                if storedStyle == .numberedList {
                    listMarker = "\(numberedListCounter).  "
                } else {
                    listMarker = self.staticListMarkerPrefix(for: storedStyle, level: indentLevel) ?? ""
                }
                let displayParagraph = listMarker.isEmpty ? rawDisplayParagraph : listMarker + rawDisplayParagraph

                let markerLen = (listMarker as NSString).length
                if markerLen > 0 { paragraphMarkerLengths[paragraphIndex] = markerLen }

                let paragraph = NSMutableAttributedString(
                    string: displayParagraph,
                    attributes: self.attributes(for: rawParagraph, storedStyle: storedStyle, level: indentLevel)
                )
                if storedStyle != .body, paragraph.length > 0 {
                    paragraph.addAttribute(Self.paragraphStyleAttribute, value: storedStyle.rawValue, range: NSRange(location: 0, length: paragraph.length))
                }
                if indentLevel > 0, paragraph.length > 0 {
                    paragraph.addAttribute(Self.indentLevelAttribute, value: indentLevel, range: NSRange(location: 0, length: paragraph.length))
                }
                attributed.append(paragraph)
                paragraphIndex += 1
            }
            return (attributed, paragraphIndex - startingParagraph)
        }

        private func photoAttachmentString(at photoIndex: Int, width: CGFloat) -> NSAttributedString {
            guard photoIndex < parent.photoDataArray.count,
                  let image = UIImage(data: parent.photoDataArray[photoIndex]) else {
                return NSAttributedString(string: "")
            }

            let maxWidth = max(180, width - 8)
            let scale = min(1, maxWidth / max(image.size.width, 1))
            let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: targetSize)

            let result = NSMutableAttributedString(attachment: attachment)
            result.addAttributes([
                .paragraphStyle: paragraphStyle(lineSpacing: 8, paragraphSpacing: 8)
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
            // Renumber remaining tokens in text
            var updatedText = parent.text
            updatedText = updatedText
                .replacingOccurrences(of: "\n" + tokenStr, with: "")
                .replacingOccurrences(of: tokenStr + "\n", with: "")
                .replacingOccurrences(of: tokenStr, with: "")
            // Renumber subsequent tokens (indices shift down by 1)
            for i in (token.index + 1)..<(parent.photoDataArray.count) {
                updatedText = updatedText.replacingOccurrences(of: inlinePhotoToken(at: i), with: inlinePhotoToken(at: i - 1))
            }
            parent.photoDataArray = photos
            parent.text = updatedText
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
            let nsText = (textView.text ?? "") as NSString
            guard nsText.length > 0 else {
                textView.typingAttributes = bodyAttributes
                return
            }

            let cursorLoc = textView.selectedRange.location
            // Cursor is in a virtual empty paragraph past the last character (e.g. after "Hello\n").
            // Reading attributed text at length-1 would return the \n's style (the *previous* paragraph),
            // which would wrongly overwrite typing attrs the user just set via the format panel.
            if cursorLoc >= nsText.length { return }

            let style = textStyle(at: cursorLoc, in: textView.attributedText)
            let level = indentLevelValue(at: cursorLoc, in: textView.attributedText)
            textView.typingAttributes = styledAttributesForTyping(style, numberedIndex: nil, level: level)
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
            default:            return .body
            }
        }

        private func styledAttributesForTyping(_ style: NoteParagraphTextStyle, numberedIndex: Int?, level: Int = 0) -> [NSAttributedString.Key: Any] {
            var result = attributes(for: style, level: level)
            if style != .body {
                result[Self.paragraphStyleAttribute] = style.rawValue
            }
            if level > 0 {
                result[Self.indentLevelAttribute] = level
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
            mutable.removeAttribute(Self.paragraphStyleAttribute, range: boundedRange)
            mutable.addAttributes(attributes(for: style, level: level), range: boundedRange)
            if style != .body {
                mutable.addAttribute(Self.paragraphStyleAttribute, value: style.rawValue, range: boundedRange)
            }
            // Re-stamp indent level (attributes(for:level:) sets paragraphStyle but not the custom key)
            if level > 0 { mutable.addAttribute(Self.indentLevelAttribute, value: level, range: boundedRange) }

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false
            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            syncRenderedCache(from: textView)
            updateTypingAttributes(for: textView)
        }

        // Insert a new row with the same list style after pressing Return on a non-empty list item
        private func insertListRow(replacing range: NSRange, style: NoteParagraphTextStyle, in textView: UITextView) {
            // For numbered lists, the new row will be numbered after render; just insert unchecked for checklist
            let newStyle: NoteParagraphTextStyle = (style == .checklistChecked) ? .checklistUnchecked : style
            let rowLevel = indentLevelValue(at: max(0, range.location - 1), in: textView.attributedText)
            let marker = staticListMarkerPrefix(for: newStyle, level: rowLevel) ?? (newStyle == .numberedList ? "N.  " : "")
            let insertion = "\n" + marker
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let insertionRange = bounded(range, in: mutable.string)
            let attributedInsertion = NSMutableAttributedString(
                string: insertion,
                attributes: styledAttributesForTyping(newStyle, numberedIndex: nil, level: rowLevel)
            )
            mutable.replaceCharacters(in: insertionRange, with: attributedInsertion)

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            // For numbered lists, cursor goes after the placeholder "N." (will be re-rendered with real number)
            textView.selectedRange = bounded(
                NSRange(location: insertionRange.location + insertion.count, length: 0),
                in: textView.text
            )
            isApplyingStyledText = false
            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            // Re-render to show correct number
            if newStyle == .numberedList { invalidateRenderedCache() }
            applyStyledText(to: textView, preservingSelection: false)
            textView.typingAttributes = styledAttributesForTyping(newStyle, numberedIndex: nil, level: rowLevel)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
        }

        private func exitList(at paragraphRange: NSRange, in textView: UITextView) {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let boundedRange = bounded(paragraphRange, in: mutable.string)
            let paragraph = (mutable.string as NSString).substring(with: boundedRange)
            let lineBreak = trailingLineBreak(from: paragraph)
            mutable.replaceCharacters(
                in: boundedRange,
                with: NSAttributedString(string: lineBreak, attributes: bodyAttributes)
            )

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            textView.selectedRange = bounded(NSRange(location: boundedRange.location + lineBreak.count, length: 0), in: textView.text)
            isApplyingStyledText = false
            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            textView.typingAttributes = bodyAttributes
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
            // Matches "1.  ", "10.  ", "100.  " etc.
            let ns = paragraph as NSString
            var i = 0
            while i < ns.length {
                let c = ns.character(at: i)
                if c >= 48 && c <= 57 { i += 1 } // digit
                else { break }
            }
            // Must have at least one digit, then "." and at least two spaces
            guard i > 0, i < ns.length, ns.character(at: i) == 46 else { return 0 } // "."
            i += 1
            guard i < ns.length, ns.character(at: i) == 32 else { return 0 } // " "
            i += 1
            guard i < ns.length, ns.character(at: i) == 32 else { return 0 } // "  "
            return i + 1
        }

        private func decodedTextStyles() -> [NoteParagraphTextStyle] {
            guard let data = parent.textStyleData,
                  let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data) else {
                return []
            }
            return document.paragraphStyles
        }

        private func decodedIndentLevels() -> [Int] {
            guard let data = parent.textStyleData,
                  let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data),
                  let levels = document.indentLevels else {
                return []
            }
            return levels
        }

        private func indentLevelValue(at location: Int, in attributed: NSAttributedString?) -> Int {
            guard let attributed, attributed.length > 0 else { return 0 }
            let loc = min(max(0, location), attributed.length - 1)
            return attributed.attribute(Self.indentLevelAttribute, at: loc, effectiveRange: nil) as? Int ?? 0
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
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                styles.append(self.textStyle(at: range.location, in: attributed))
                levels.append(self.indentLevelValue(at: range.location, in: attributed))
            }
            guard styles.contains(where: { $0 != .body }) else { return nil }
            let hasIndent = levels.contains(where: { $0 > 0 })
            return try? JSONEncoder().encode(NoteTextStyleDocument(
                paragraphStyles: styles,
                indentLevels: hasIndent ? levels : nil
            ))
        }

        private func invalidateRenderedCache() {
            lastRenderedText = nil
            lastRenderedStyleSignature = nil
            lastRenderedInlineSignature = nil
            lastRenderedPhotoSignature = nil
            lastRenderedWidth = 0
        }

        private func syncRenderedCache(from textView: UITextView) {
            lastRenderedText = parent.text
            lastRenderedStyleSignature = parent.textStyleData?.hashValue
            lastRenderedInlineSignature = parent.inlineStyleData?.hashValue
            lastRenderedPhotoSignature = parent.photoDataArray.map(\.count).reduce(0, +)
            lastRenderedWidth = textView.bounds.width.rounded()
            lastRenderedFontChoice = WritingFontChoice.current
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

            let hasBold       = command == .bold          && isStyleApplied(.bold,          in: effectiveRange, of: attributed)
            let hasItalic     = command == .italic        && isStyleApplied(.italic,        in: effectiveRange, of: attributed)
            let hasUnderline  = command == .underline     && isStyleApplied(.underline,     in: effectiveRange, of: attributed)
            let hasStrike     = command == .strikethrough && isStyleApplied(.strikethrough, in: effectiveRange, of: attributed)
            let shouldRemove = hasBold || hasItalic || hasUnderline || hasStrike

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
                    let uiColor = UIColor(highlightColors[idx])
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
                    typing[.backgroundColor] = UIColor(highlightColors[idx])
                    typing[Self.highlightIndexAttribute] = idx
                }
                textView.typingAttributes = typing
            }

            parent.inlineStyleData = extractedInlineStyleData(from: textView)
            syncRenderedCache(from: textView)
            refreshActiveInlineStyles(in: textView)
        }

        // MARK: - Bulk checklist operations

        func bulkSetChecklist(_ targetStyle: NoteParagraphTextStyle, in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let nsText = attributed.string as NSString
            var styles: [NoteParagraphTextStyle] = []
            var levels: [Int] = []
            var changed = false
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
                let current = self.textStyle(at: enclosing.location, in: attributed)
                let isChecklist = current == .checklistUnchecked || current == .checklistChecked
                let newStyle = isChecklist ? targetStyle : current
                if isChecklist && current != targetStyle { changed = true }
                styles.append(newStyle)
                levels.append(self.indentLevelValue(at: enclosing.location, in: attributed))
            }
            guard changed else { return }
            let hasIndent = levels.contains(where: { $0 > 0 })
            parent.textStyleData = try? JSONEncoder().encode(NoteTextStyleDocument(
                paragraphStyles: styles,
                indentLevels: hasIndent ? levels : nil
            ))
            invalidateRenderedCache()
            applyStyledText(to: textView, preservingSelection: true)
            refreshActiveInlineStyles(in: textView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func sortCheckedToBottom(in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let nsText = attributed.string as NSString
            var paraInfos: [(style: NoteParagraphTextStyle, level: Int)] = []
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
                paraInfos.append((
                    self.textStyle(at: enclosing.location, in: attributed),
                    self.indentLevelValue(at: enclosing.location, in: attributed)
                ))
            }
            let logicalParas = parent.text.components(separatedBy: "\n")
            guard logicalParas.count == paraInfos.count else { return }

            typealias Row = (text: String, style: NoteParagraphTextStyle, level: Int)
            var rows: [Row] = zip(logicalParas, paraInfos).map { ($0, $1.style, $1.level) }
            let isChecklist = { (s: NoteParagraphTextStyle) in s == .checklistUnchecked || s == .checklistChecked }
            var i = 0
            var changed = false
            while i < rows.count {
                guard isChecklist(rows[i].style) else { i += 1; continue }
                var j = i
                while j < rows.count && isChecklist(rows[j].style) { j += 1 }
                let block = Array(rows[i..<j])
                let sorted = block.sorted { a, b in
                    let aChecked = a.style == .checklistChecked
                    let bChecked = b.style == .checklistChecked
                    if aChecked != bChecked { return !aChecked }
                    return false
                }
                if sorted.map({ $0.style }) != block.map({ $0.style }) {
                    changed = true
                    rows.replaceSubrange(i..<j, with: sorted)
                }
                i = j
            }
            guard changed else { return }

            parent.text = rows.map { $0.text }.joined(separator: "\n")
            let styles = rows.map { $0.style }
            let levels = rows.map { $0.level }
            let hasIndent = levels.contains(where: { $0 > 0 })
            parent.textStyleData = styles.allSatisfy({ $0 == .body }) ? nil :
                try? JSONEncoder().encode(NoteTextStyleDocument(
                    paragraphStyles: styles,
                    indentLevels: hasIndent ? levels : nil
                ))
            parent.inlineStyleData = nil  // paragraph positions shifted; inline ranges are now invalid
            invalidateRenderedCache()
            applyStyledText(to: textView, preservingSelection: true)
            refreshActiveInlineStyles(in: textView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func deleteCheckedChecklistItems(in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let nsText = attributed.string as NSString
            var paraInfos: [(style: NoteParagraphTextStyle, level: Int)] = []
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
                paraInfos.append((
                    self.textStyle(at: enclosing.location, in: attributed),
                    self.indentLevelValue(at: enclosing.location, in: attributed)
                ))
            }
            let logicalParas = parent.text.components(separatedBy: "\n")
            guard logicalParas.count == paraInfos.count else { return }

            let kept = zip(logicalParas, paraInfos).filter { $0.1.style != .checklistChecked }
            guard kept.count < logicalParas.count else { return }

            parent.text = kept.map { $0.0 }.joined(separator: "\n")
            let styles = kept.map { $0.1.style }
            let levels = kept.map { $0.1.level }
            let hasIndent = levels.contains(where: { $0 > 0 })
            parent.textStyleData = styles.allSatisfy({ $0 == .body }) ? nil :
                try? JSONEncoder().encode(NoteTextStyleDocument(
                    paragraphStyles: styles,
                    indentLevels: hasIndent ? levels : nil
                ))
            parent.inlineStyleData = nil  // paragraph positions shifted; inline ranges are now invalid
            invalidateRenderedCache()
            applyStyledText(to: textView, preservingSelection: true)
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
            mutable.removeAttribute(Self.indentLevelAttribute, range: paraRange)
            mutable.addAttributes(attributes(for: style, level: newLevel), range: paraRange)
            if style != .body {
                mutable.addAttribute(Self.paragraphStyleAttribute, value: style.rawValue, range: paraRange)
            }
            if newLevel > 0 {
                mutable.addAttribute(Self.indentLevelAttribute, value: newLevel, range: paraRange)
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
            parent.textStyleData = encodedTextStyleData(from: textView)
            syncRenderedCache(from: textView)
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

                // Only store non-default inline attrs (skip heading/title bold — those are paragraph-level)
                let style = self.textStyle(at: range.location, in: attributed)
                let isParaBold = (style == .heading || style == .title)
                let effectiveBold = bold && !isParaBold

                guard effectiveBold || italic || underline || strikethrough || highlightIndex != nil else { return }

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
                    highlightIndex: highlightIndex
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

            for styleRange in doc.ranges {
                let displayStart = logicalToDisplay(logical: styleRange.location, map: logicalOffsets)
                // When a range ends exactly at a paragraph boundary (logicalEnd == paragraph's logicalStart),
                // logicalToDisplay() would add the next paragraph's markerLen and land *inside* the marker.
                // Detect that case and use the paragraph's displayStart instead (before its marker).
                let logicalEnd = styleRange.location + styleRange.length
                let displayEnd: Int
                if let boundary = logicalOffsets.first(where: { $0.logicalStart == logicalEnd && logicalEnd > 0 }) {
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
                    // Don't override checklist's own strikethrough
                    let style = textStyle(at: displayRange.location, in: attributed)
                    if style != .checklistChecked {
                        attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: displayRange)
                    }
                }
                if let idx = styleRange.highlightIndex, idx < highlightColors.count {
                    attributed.addAttribute(.backgroundColor, value: UIColor(highlightColors[idx]), range: displayRange)
                    attributed.addAttribute(Self.highlightIndexAttribute, value: idx, range: displayRange)
                }
            }
        }

        // MARK: - Logical ↔ display coordinate mapping

        private func buildLogicalOffsetMap(from attributed: NSAttributedString) -> [(displayStart: Int, logicalStart: Int, markerLen: Int)] {
            var result: [(Int, Int, Int)] = []
            var displayOff = 0
            var logicalOff = 0
            let nsDisplay = attributed.string as NSString

            nsDisplay.enumerateSubstrings(in: NSRange(location: 0, length: nsDisplay.length), options: [.byParagraphs, .substringNotRequired]) { _, _, enclosingRange, _ in
                let style = self.textStyle(at: enclosingRange.location, in: attributed)
                let markerLen: Int
                if style == .numberedList {
                    let para = nsDisplay.substring(with: enclosingRange)
                    markerLen = self.numberedListMarkerLength(in: para)
                } else {
                    markerLen = (self.staticListMarkerPrefix(for: style) as NSString?)?.length ?? 0
                }
                result.append((displayOff, logicalOff, markerLen))
                logicalOff += enclosingRange.length - markerLen
                displayOff += enclosingRange.length
            }
            return result
        }

        private func displayToLogical(display: Int, map: [(displayStart: Int, logicalStart: Int, markerLen: Int)]) -> Int {
            for (i, entry) in map.enumerated() {
                let nextDisplay = i + 1 < map.count ? map[i + 1].displayStart : Int.max
                if display >= entry.displayStart && display < nextDisplay {
                    let offsetInPara = display - entry.displayStart
                    let logicalOffset = max(0, offsetInPara - entry.markerLen)
                    return entry.logicalStart + logicalOffset
                }
            }
            return display
        }

        private func logicalToDisplay(logical: Int, map: [(displayStart: Int, logicalStart: Int, markerLen: Int)]) -> Int {
            for (i, entry) in map.enumerated() {
                let nextLogical = i + 1 < map.count ? map[i + 1].logicalStart : Int.max
                if logical >= entry.logicalStart && logical < nextLogical {
                    let offsetInPara = logical - entry.logicalStart
                    return entry.displayStart + entry.markerLen + offsetInPara
                }
            }
            return logical
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
                    && range.highlightIndex == last.highlightIndex {
                    result[result.count - 1] = InlineStyleRange(
                        location: last.location,
                        length: max(lastEnd, range.location + range.length) - last.location,
                        bold: last.bold, italic: last.italic,
                        underline: last.underline, strikethrough: last.strikethrough,
                        highlightIndex: last.highlightIndex
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
                parent.activeInlineStyles = InlineStyleSet()
                parent.panelState.activeInlineStyles = InlineStyleSet()
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
            if lastKnownCursorLocation >= attributed.length {
                if let raw = textView.typingAttributes[Self.paragraphStyleAttribute] as? String,
                   let style = NoteParagraphTextStyle(rawValue: raw) {
                    paraStyle = style
                } else {
                    paraStyle = .body
                }
                font = textView.typingAttributes[.font] as? UIFont
                underlineActive = textView.typingAttributes[.underlineStyle] != nil
                strikethroughActive = textView.typingAttributes[.strikethroughStyle] != nil
                highlightIndex = textView.typingAttributes[Self.highlightIndexAttribute] as? Int
            } else {
                paraStyle = textStyle(at: loc, in: attributed)
                font = attributed.attribute(.font, at: loc, effectiveRange: nil) as? UIFont
                underlineActive = attributed.attribute(.underlineStyle, at: loc, effectiveRange: nil) != nil
                strikethroughActive = attributed.attribute(.strikethroughStyle, at: loc, effectiveRange: nil) != nil
                highlightIndex = attributed.attribute(Self.highlightIndexAttribute, at: loc, effectiveRange: nil) as? Int
            }
            let isParaBold = (paraStyle == .heading || paraStyle == .title)
            styles.bold = (font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false) && !isParaBold
            styles.italic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
            styles.underline = underlineActive
            styles.strikethrough = strikethroughActive && paraStyle != .checklistChecked
            parent.activeInlineStyles = styles
            parent.panelState.activeInlineStyles = styles
            parent.panelState.activeParagraphStyle = paraStyle
            parent.panelState.activeHighlightIndex = highlightIndex
        }

        // MARK: - Formatting panel (keyboard replacement)

        func updateFormattingPanel(textView: UITextView, visible: Bool) {
            if visible {
                // Refresh panel state to current cursor position before the panel renders
                refreshActiveInlineStyles(in: textView)
                // Create host controller once only. FormattingPanelState is @Observable so the
                // existing view auto-updates — replacing rootView on every updateUIView call
                // tears down the SwiftUI tree and drops in-flight button taps.
                if formattingPanelHost == nil {
                    let hc = UIHostingController(rootView: FormattingPanelView(state: parent.panelState))
                    hc.view.backgroundColor = .secondarySystemBackground
                    formattingPanelHost = hc
                }
                let panelUIView = formattingPanelHost?.view
                // +56 vs. the original 290 to fit the font-family row added above the
                // paragraph-style row.
                let newFrame = CGRect(x: 0, y: 0, width: textView.frame.width, height: 346)
                if panelUIView?.frame != newFrame { panelUIView?.frame = newFrame }
                if textView.inputView !== panelUIView {
                    textView.inputView = panelUIView
                    textView.reloadInputViews()
                    if !textView.isFirstResponder { textView.becomeFirstResponder() }
                }
            } else {
                if textView.inputView != nil {
                    textView.inputView = nil
                    textView.reloadInputViews()
                }
            }
        }
    }
}

private extension UIFont {
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
    let trimmed = text.trimmingCharacters(in: .newlines)
    return trimmed.isEmpty ? token : "\(trimmed)\n\(token)\n"
}

private nonisolated func isRenderableImageData(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, [
        kCGImageSourceShouldCache: false
    ] as CFDictionary) else {
        return false
    }
    return CGImageSourceGetCount(source) > 0
}
