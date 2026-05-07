import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

private let moodLabels = MirrorTheme.moodOptions

enum NoteTextCommand: Equatable {
    case checklist
    case title
    case heading
    case subheading
    case body
    case monospaced
    case photo

    var prefix: String {
        switch self {
        case .checklist: return ""
        case .title, .heading, .subheading: return ""
        case .body: return ""
        case .monospaced: return "    "
        case .photo: return ""
        }
    }
}

enum NoteParagraphTextStyle: String, Codable {
    case body
    case title
    case heading
    case subheading
    case monospaced
    case checklistUnchecked
    case checklistChecked
}

struct NoteTextStyleDocument: Codable {
    var paragraphStyles: [NoteParagraphTextStyle]
}

nonisolated let inlinePhotoToken = "[[mirror-photo]]"

private enum InlinePhotoSegment {
    case before
    case after
}

struct NoteEditorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var textStyleData: Data?
    @Binding var photoData: Data?
    @Binding var command: NoteTextCommand?
    @Binding var commandRevision: Int
    @Binding var isFocused: Bool
    @Binding var activeParagraphStyle: NoteParagraphTextStyle

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
        placeholder.font = UIFont.preferredFont(forTextStyle: .body)
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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        static let placeholderTag = 701

        var parent: NoteEditorTextView
        private static let paragraphStyleAttribute = NSAttributedString.Key("mirror.paragraphStyle")
        private var isApplyingStyledText = false
        private var lastRenderedText: String?
        private var lastRenderedStyleSignature: Int?
        private var lastRenderedPhotoSignature: Int?
        private var lastRenderedWidth: CGFloat = 0
        // Tracks cursor position across focus changes (Menu dismissal resets selectedRange)
        private var lastKnownCursorLocation: Int = 0
        var lastAppliedCommandRevision = 0

        init(parent: NoteEditorTextView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            let location = gesture.location(in: textView)
            let markerWidth = textView.textContainerInset.left + 34
            guard location.x <= markerWidth else { return }
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
            let paraRange = nsText.paragraphRange(for: NSRange(location: charIndex, length: 0))
            let currentStyle = textStyle(at: paraRange.location, in: textView.attributedText)
            guard currentStyle == .checklistUnchecked || currentStyle == .checklistChecked else { return }

            let nextStyle: NoteParagraphTextStyle = currentStyle == .checklistUnchecked ? .checklistChecked : .checklistUnchecked
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            mutable.removeAttribute(Self.paragraphStyleAttribute, range: paraRange)
            mutable.addAttributes(attributes(for: nextStyle), range: paraRange)
            mutable.addAttribute(Self.paragraphStyleAttribute, value: nextStyle.rawValue, range: paraRange)

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            textView.selectedRange = bounded(NSRange(location: charIndex, length: 0), in: text)
            isApplyingStyledText = false
            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
        }

        var bodyAttributes: [NSAttributedString.Key: Any] {
            [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle(lineSpacing: 6)
            ]
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingStyledText else { return }
            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
            updateTypingAttributes(for: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            let rendered = textView.attributedText?.string ?? textView.text ?? ""
            if replacement.isEmpty, deletesInlinePhoto(in: rendered, range: range) {
                removeInlinePhoto(from: textView)
                return false
            }

            if replacement.isEmpty, exitsEmptyChecklistAfterDeletion(in: rendered, range: range, textView: textView) {
                return false
            }

            if !replacement.isEmpty,
               replacement != "\n",
               insertsTextAfterChecklistMarker(replacement, range: range, rendered: rendered, textView: textView) {
                return false
            }

            if replacement == "\n" {
                let nsText = rendered as NSString
                let paragraphRange = nsText.paragraphRange(for: NSRange(location: max(0, range.location - 1), length: 0))
                let paragraph = nsText.substring(with: paragraphRange)
                let style = textStyle(at: paragraphRange.location, in: textView.attributedText)
                if isChecklistStyle(style) {
                    let content = checklistContent(fromDisplayedParagraph: paragraph, style: style)
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        exitChecklist(at: paragraphRange, in: textView)
                    } else {
                        insertChecklistRow(replacing: range, in: textView)
                    }
                    return false
                }
            }

            return true
        }

        private func insertsTextAfterChecklistMarker(
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
            guard isChecklistStyle(style),
                  let marker = checklistMarkerPrefix(for: style) else {
                return false
            }

            let paragraph = nsText.substring(with: paragraphRange)
            let markerLength = (marker as NSString).length
            let markerEnd = paragraphRange.location + markerLength
            guard paragraph.hasPrefix(marker), range.location < markerEnd else {
                return false
            }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let insertionRange = bounded(NSRange(location: markerEnd, length: 0), in: mutable.string)
            let attributedReplacement = NSAttributedString(
                string: replacement,
                attributes: styledAttributesForTyping(style)
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
            textView.typingAttributes = styledAttributesForTyping(style)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
            refreshActiveParagraphStyle(in: textView)
            return true
        }

        private func exitsEmptyChecklistAfterDeletion(in rendered: String, range: NSRange, textView: UITextView) -> Bool {
            let nsText = rendered as NSString
            guard nsText.length > 0, range.location <= nsText.length else { return false }

            let lookupLocation = min(max(0, range.location), max(0, nsText.length - 1))
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: lookupLocation, length: 0))
            let style = textStyle(at: paragraphRange.location, in: textView.attributedText)
            guard isChecklistStyle(style),
                  let marker = checklistMarkerPrefix(for: style) else {
                return false
            }

            let paragraph = nsText.substring(with: paragraphRange)
            guard paragraph.hasPrefix(marker) else { return false }

            let boundedDeletion = bounded(range, in: rendered)
            let updatedRendered = nsText.replacingCharacters(in: boundedDeletion, with: "") as NSString
            let updatedParagraphRange = updatedRendered.paragraphRange(
                for: NSRange(location: min(paragraphRange.location, max(0, updatedRendered.length - 1)), length: 0)
            )
            let updatedParagraph = updatedParagraphRange.location < updatedRendered.length
                ? updatedRendered.substring(with: updatedParagraphRange)
                : ""

            let contentAfterDeletion = checklistContent(fromDisplayedParagraph: updatedParagraph, style: style)
            guard contentAfterDeletion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }

            exitChecklist(at: paragraphRange, in: textView)
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingStyledText, textView.isFirstResponder else { return }
            lastKnownCursorLocation = textView.selectedRange.location
            refreshActiveParagraphStyle(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
            lastKnownCursorLocation = textView.selectedRange.location
            refreshActiveParagraphStyle(in: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func apply(_ command: NoteTextCommand, to textView: UITextView) {
            if command == .photo {
                insertPhotoToken(in: textView)
                return
            }

            let nsText = (textView.text ?? "") as NSString
            let liveCursorLocation = textView.isFirstResponder ? textView.selectedRange.location : lastKnownCursorLocation
            let cursorLocation = min(liveCursorLocation, max(0, nsText.length))
            lastKnownCursorLocation = cursorLocation

            // Determine target style. Checklist toggles off when already active.
            let currentStyle = textStyle(
                at: min(cursorLocation, max(0, (textView.attributedText?.length ?? 1) - 1)),
                in: textView.attributedText
            )
            let targetStyle: NoteParagraphTextStyle
            if command == .checklist {
                targetStyle = isChecklistStyle(currentStyle) ? .body : .checklistUnchecked
            } else {
                targetStyle = paragraphStyle(for: command)
            }

            if nsText.length == 0 {
                parent.textStyleData = try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [targetStyle]))
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: false)
                if let marker = checklistMarkerPrefix(for: targetStyle) {
                    textView.selectedRange = bounded(NSRange(location: marker.count, length: 0), in: textView.text)
                }
                textView.typingAttributes = styledAttributesForTyping(targetStyle)
                updatePlaceholder(in: textView)
                parent.activeParagraphStyle = targetStyle
                return
            }

            // Removing checklist: strip the visual "○  "/" ✓  " marker from display text first.
            if isChecklistStyle(currentStyle) && targetStyle == .body {
                removeChecklistAndApplyBody(at: cursorLocation, in: textView)
                parent.activeParagraphStyle = .body
                return
            }

            let cursorRange = NSRange(location: cursorLocation, length: 0)
            let paragraphRange = nsText.paragraphRange(for: cursorRange)

            nsText.enumerateSubstrings(in: paragraphRange, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                self.setParagraphStyle(targetStyle, range: range, in: textView)
            }
            if checklistMarkerPrefix(for: targetStyle) != nil {
                invalidateRenderedCache()
                applyStyledText(to: textView, preservingSelection: false)
                let marker = checklistMarkerPrefix(for: targetStyle) ?? ""
                textView.selectedRange = bounded(
                    NSRange(location: cursorLocation + marker.count, length: 0),
                    in: textView.text
                )
            } else {
                textView.selectedRange = bounded(NSRange(location: cursorLocation, length: 0), in: textView.text)
            }
            textView.typingAttributes = styledAttributesForTyping(targetStyle)
            updatePlaceholder(in: textView)
            parent.activeParagraphStyle = targetStyle
        }

        // Strips the visual checklist marker ("○  "/"✓  ") from the attributed text and
        // re-applies body style — needed because markers only exist in display, not parent.text.
        private func removeChecklistAndApplyBody(at cursorLocation: Int, in textView: UITextView) {
            guard let attributed = textView.attributedText else { return }
            let nsDisplay = attributed.string as NSString
            let safeLocation = min(cursorLocation, max(0, nsDisplay.length - 1))
            let displayParaRange = nsDisplay.paragraphRange(for: NSRange(location: safeLocation, length: 0))
            let displayPara = nsDisplay.substring(with: displayParaRange)

            let currentStyle = textStyle(at: displayParaRange.location, in: attributed)
            let marker = checklistMarkerPrefix(for: currentStyle) ?? ""
            let markerLen = (marker as NSString).length

            let mutable = NSMutableAttributedString(attributedString: attributed)

            if markerLen > 0 && displayPara.hasPrefix(marker) {
                let markerRange = bounded(NSRange(location: displayParaRange.location, length: markerLen), in: mutable.string)
                mutable.replaceCharacters(in: markerRange, with: "")
            }

            let newParaLen = max(0, displayParaRange.length - markerLen)
            let newParaRange = bounded(NSRange(location: displayParaRange.location, length: newParaLen), in: mutable.string)
            if newParaRange.length > 0 {
                mutable.removeAttribute(Self.paragraphStyleAttribute, range: newParaRange)
                mutable.addAttributes(attributes(for: .body), range: newParaRange)
            }

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false

            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            syncRenderedCache(from: textView)

            let newCursor = max(displayParaRange.location, cursorLocation - markerLen)
            textView.selectedRange = bounded(NSRange(location: newCursor, length: 0), in: textView.text)
            textView.typingAttributes = bodyAttributes
            updatePlaceholder(in: textView)
        }

        func applyStyledText(to textView: UITextView, preservingSelection: Bool) {
            let selectedRange = textView.selectedRange
            let rawText = parent.text
            let styleSignature = parent.textStyleData?.hashValue
            let photoSignature = parent.photoData?.count
            let width = textView.bounds.width.rounded()

            if lastRenderedText == rawText,
               lastRenderedStyleSignature == styleSignature,
               lastRenderedPhotoSignature == photoSignature,
               lastRenderedWidth == width {
                if preservingSelection {
                    textView.selectedRange = bounded(selectedRange, in: textView.text)
                }
                updateTypingAttributes(for: textView)
                return
            }

            let attributed = renderedAttributedText(for: rawText, width: textView.bounds.width)

            isApplyingStyledText = true
            applyAttributedText(attributed, to: textView)
            isApplyingStyledText = false
            lastRenderedText = rawText
            lastRenderedStyleSignature = styleSignature
            lastRenderedPhotoSignature = photoSignature
            lastRenderedWidth = width
            if preservingSelection {
                textView.selectedRange = bounded(selectedRange, in: textView.text)
            }
            updateTypingAttributes(for: textView)
        }

        func updatePlaceholder(in textView: UITextView) {
            textView.viewWithTag(Self.placeholderTag)?.isHidden = !parent.text.isEmpty || parent.textStyleData != nil
        }

        private func refreshActiveParagraphStyle(in textView: UITextView) {
            guard let attributed = textView.attributedText, attributed.length > 0 else {
                parent.activeParagraphStyle = .body
                return
            }
            let loc = min(lastKnownCursorLocation, attributed.length - 1)
            parent.activeParagraphStyle = textStyle(at: loc, in: attributed)
        }

        func logicalText(from textView: UITextView) -> String {
            let attributed = textView.attributedText ?? NSAttributedString()
            let rendered = attributed.string.replacingOccurrences(of: "\u{fffc}", with: inlinePhotoToken)
            let nsRendered = rendered as NSString
            guard nsRendered.length > 0 else { return "" }

            var result = ""
            // Use enclosingRange (3rd param) not substringRange (2nd param) — enclosingRange
            // includes the paragraph separator (\n), substringRange does not. Without this,
            // logicalText strips all newlines and applyStyledText collapses lines into one.
            nsRendered.enumerateSubstrings(in: NSRange(location: 0, length: nsRendered.length), options: [.byParagraphs, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
                let paragraph = nsRendered.substring(with: enclosingRange)
                let style = self.textStyle(at: enclosingRange.location, in: attributed)
                if let marker = self.checklistMarkerPrefix(for: style), paragraph.hasPrefix(marker) {
                    result += String(paragraph.dropFirst(marker.count))
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

        private func attributes(for style: NoteParagraphTextStyle) -> [NSAttributedString.Key: Any] {
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
                    .font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
                ]
            case .checklistUnchecked:
                return checklistAttributes(checked: false)
            case .checklistChecked:
                return checklistAttributes(checked: true)
            case .body:
                return bodyAttributes
            }
        }

        private func attributes(for paragraph: String, storedStyle: NoteParagraphTextStyle = .body) -> [NSAttributedString.Key: Any] {
            if storedStyle != .body {
                return attributes(for: storedStyle)
            }
            if paragraph.hasPrefix("### ") { return attributes(for: .subheading) }
            if paragraph.hasPrefix("## ") { return attributes(for: .heading) }
            if paragraph.hasPrefix("# ") { return attributes(for: .title) }
            if paragraph.hasPrefix("    ") { return attributes(for: .monospaced) }
            if paragraph.hasPrefix("○ ") {
                return checklistAttributes(checked: false)
            }
            if paragraph.hasPrefix("✓ ") {
                return checklistAttributes(checked: true)
            }
            return bodyAttributes
        }

        private func checklistAttributes(checked: Bool) -> [NSAttributedString.Key: Any] {
            let ps = paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
            ps.firstLineHeadIndent = 0
            ps.headIndent = 44
            var attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: checked ? UIColor.tertiaryLabel : UIColor.label,
                .paragraphStyle: ps
            ]
            if checked {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = UIColor.tertiaryLabel
            }
            return attributes
        }

        private func insertPhotoToken(in textView: UITextView) {
            let logical = logicalText(from: textView)
            let selectedRange = bounded(textView.selectedRange, in: logical)
            let nsText = logical as NSString
            var insertion = inlinePhotoToken

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
            let attributed = NSMutableAttributedString()
            if rawText.isEmpty,
               let firstStyle = decodedTextStyles().first,
               let marker = checklistMarkerPrefix(for: firstStyle) {
                let paragraph = NSMutableAttributedString(string: marker, attributes: attributes(for: firstStyle))
                paragraph.addAttribute(Self.paragraphStyleAttribute, value: firstStyle.rawValue, range: NSRange(location: 0, length: paragraph.length))
                attributed.append(paragraph)
                return attributed
            }

            var remaining = rawText[...]
            var paragraphOffset = 0

            while let tokenRange = remaining.range(of: inlinePhotoToken) {
                let before = String(remaining[..<tokenRange.lowerBound])
                let rendered = renderedTextWithoutMarkdownMarkers(for: before, startingParagraph: paragraphOffset)
                attributed.append(rendered.value)
                paragraphOffset += rendered.paragraphCount
                attributed.append(photoAttachmentString(width: width))
                remaining = remaining[tokenRange.upperBound...]
            }

            attributed.append(renderedTextWithoutMarkdownMarkers(for: String(remaining), startingParagraph: paragraphOffset).value)
            return attributed
        }

        private func renderedTextWithoutMarkdownMarkers(for rawText: String, startingParagraph: Int) -> (value: NSAttributedString, paragraphCount: Int) {
            let attributed = NSMutableAttributedString()
            let rawParagraphs = rawText.components(separatedBy: "\n")
            guard !rawParagraphs.isEmpty else { return (attributed, 0) }
            let storedStyles = decodedTextStyles()
            var paragraphIndex = startingParagraph

            for (offset, rawLine) in rawParagraphs.enumerated() {
                let lineBreak = offset < rawParagraphs.count - 1 ? "\n" : ""
                let rawParagraph = rawLine + lineBreak
                let legacyStyle = self.legacyStyle(in: rawParagraph)
                let storedStyle = storedStyles.indices.contains(paragraphIndex) ? storedStyles[paragraphIndex] : legacyStyle
                let prefix = self.legacyMarkdownPrefix(in: rawParagraph)
                let legacyChecklistPrefix = self.legacyChecklistPrefix(in: rawParagraph)
                let rawDisplayParagraph = prefix.map { String(rawParagraph.dropFirst($0.count)) }
                    ?? legacyChecklistPrefix.map { String(rawParagraph.dropFirst($0.count)) }
                    ?? rawParagraph
                let displayParagraph = self.checklistMarkerPrefix(for: storedStyle).map { $0 + rawDisplayParagraph } ?? rawDisplayParagraph
                let paragraph = NSMutableAttributedString(
                    string: displayParagraph,
                    attributes: self.attributes(for: rawParagraph, storedStyle: storedStyle)
                )
                if storedStyle != .body, paragraph.length > 0 {
                    paragraph.addAttribute(Self.paragraphStyleAttribute, value: storedStyle.rawValue, range: NSRange(location: 0, length: paragraph.length))
                }
                attributed.append(paragraph)
                paragraphIndex += 1
            }
            return (attributed, paragraphIndex - startingParagraph)
        }

        private func photoAttachmentString(width: CGFloat) -> NSAttributedString {
            guard let data = parent.photoData,
                  let image = UIImage(data: data) else {
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
            guard parent.photoData != nil, let attachmentRange = rendered.range(of: "\u{fffc}") else { return false }
            let nsRange = NSRange(attachmentRange, in: rendered)
            if range.length > 0 {
                return NSIntersectionRange(range, nsRange).length > 0
            }
            return range.location == nsRange.location || range.location == NSMaxRange(nsRange)
        }

        private func removeInlinePhoto(from textView: UITextView) {
            parent.photoData = nil
            parent.text = parent.text
                .replacingOccurrences(of: "\n\(inlinePhotoToken)", with: "")
                .replacingOccurrences(of: "\(inlinePhotoToken)\n", with: "")
                .replacingOccurrences(of: inlinePhotoToken, with: "")
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

            let location = min(textView.selectedRange.location, max(0, nsText.length - 1))
            let style = textStyle(at: location, in: textView.attributedText)
            textView.typingAttributes = styledAttributesForTyping(style)
        }

        private func paragraphStyle(for command: NoteTextCommand) -> NoteParagraphTextStyle {
            switch command {
            case .checklist: return .checklistUnchecked
            case .title: return .title
            case .heading: return .heading
            case .subheading: return .subheading
            case .monospaced: return .monospaced
            default: return .body
            }
        }

        private func styledAttributesForTyping(_ style: NoteParagraphTextStyle) -> [NSAttributedString.Key: Any] {
            var result = attributes(for: style)
            if style != .body {
                result[Self.paragraphStyleAttribute] = style.rawValue
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
            mutable.removeAttribute(Self.paragraphStyleAttribute, range: boundedRange)
            mutable.addAttributes(attributes(for: style), range: boundedRange)
            if style != .body {
                mutable.addAttribute(Self.paragraphStyleAttribute, value: style.rawValue, range: boundedRange)
            }

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            isApplyingStyledText = false
            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            syncRenderedCache(from: textView)
            updateTypingAttributes(for: textView)
        }

        private func insertChecklistRow(replacing range: NSRange, in textView: UITextView) {
            let marker = checklistMarkerPrefix(for: .checklistUnchecked) ?? ""
            let insertion = "\n" + marker
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
            let insertionRange = bounded(range, in: mutable.string)
            let attributedInsertion = NSMutableAttributedString(
                string: insertion,
                attributes: styledAttributesForTyping(.checklistUnchecked)
            )
            mutable.replaceCharacters(in: insertionRange, with: attributedInsertion)

            isApplyingStyledText = true
            applyAttributedText(mutable, to: textView)
            textView.selectedRange = bounded(
                NSRange(location: insertionRange.location + insertion.count, length: 0),
                in: textView.text
            )
            isApplyingStyledText = false
            parent.text = logicalText(from: textView)
            parent.textStyleData = encodedTextStyleData(from: textView)
            textView.typingAttributes = styledAttributesForTyping(.checklistUnchecked)
            syncRenderedCache(from: textView)
            updatePlaceholder(in: textView)
        }

        private func exitChecklist(at paragraphRange: NSRange, in textView: UITextView) {
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

        private func isChecklistStyle(_ style: NoteParagraphTextStyle) -> Bool {
            style == .checklistUnchecked || style == .checklistChecked
        }

        private func checklistContent(fromDisplayedParagraph paragraph: String, style: NoteParagraphTextStyle) -> String {
            guard let marker = checklistMarkerPrefix(for: style), paragraph.hasPrefix(marker) else {
                return paragraph
            }
            return String(paragraph.dropFirst(marker.count))
        }

        private func checklistMarkerPrefix(for style: NoteParagraphTextStyle) -> String? {
            switch style {
            case .checklistUnchecked: return "○  "
            case .checklistChecked: return "✓  "
            default: return nil
            }
        }

        private func decodedTextStyles() -> [NoteParagraphTextStyle] {
            guard let data = parent.textStyleData,
                  let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: data) else {
                return []
            }
            return document.paragraphStyles
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
            nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                styles.append(self.textStyle(at: range.location, in: attributed))
            }
            guard styles.contains(where: { $0 != .body }) else { return nil }
            return try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: styles))
        }

        private func invalidateRenderedCache() {
            lastRenderedText = nil
            lastRenderedStyleSignature = nil
            lastRenderedPhotoSignature = nil
            lastRenderedWidth = 0
        }

        private func syncRenderedCache(from textView: UITextView) {
            lastRenderedText = parent.text
            lastRenderedStyleSignature = parent.textStyleData?.hashValue
            lastRenderedPhotoSignature = parent.photoData?.count
            lastRenderedWidth = textView.bounds.width.rounded()
        }

        private func paragraphStyle(lineSpacing: CGFloat, paragraphSpacing: CGFloat = 5) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            style.paragraphSpacing = paragraphSpacing
            return style
        }
    }
}

private extension UIFont {
    func bolded() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else {
            return self
        }
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

nonisolated func textWithInlinePhotoToken(_ text: String) -> String {
    guard !text.contains(inlinePhotoToken) else { return text }
    let trimmed = text.trimmingCharacters(in: .newlines)
    return trimmed.isEmpty ? inlinePhotoToken : "\(trimmed)\n\(inlinePhotoToken)\n"
}

private nonisolated func isRenderableImageData(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, [
        kCGImageSourceShouldCache: false
    ] as CFDictionary) else {
        return false
    }
    return CGImageSourceGetCount(source) > 0
}

struct NativePhotoPicker: UIViewControllerRepresentable {
    let onPicked: (Result<URL, Error>) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: (Result<URL, Error>) -> Void

        init(onPicked: @escaping (Result<URL, Error>) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }

            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                if let error {
                    DispatchQueue.main.async {
                        self.onPicked(.failure(error))
                    }
                    return
                }

                guard let url else {
                    DispatchQueue.main.async {
                        self.onPicked(.failure(PhotoAttachError.unreadableImage))
                    }
                    return
                }

                do {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension.isEmpty ? "image" : url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    DispatchQueue.main.async {
                        self.onPicked(.success(tempURL))
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onPicked(.failure(error))
                    }
                }
            }
        }
    }
}

struct WriteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var entry: Entry? = nil
    var autoFocus: Bool = false
    var showsBackButton: Bool = false
    var onSaveComplete: (() -> Void)? = nil

    @State private var viewModel = WriteViewModel()
    @State private var isKeyboardVisible = false
    @State private var showSaved = false
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false
    @State private var showVoiceInput = false
    @State private var showPhotoPicker = false
    @State private var photoAttachError: String? = nil
    @State private var isAttachingPhoto = false
    @State private var photoData: Data? = nil
    @State private var voiceNoteData: Data? = nil
    @State private var voiceNoteDuration: TimeInterval = 0
    @State private var voiceNoteTranscript: String? = nil
    @State private var voiceNoteLanguageCode: String? = nil
    @State private var voiceNoteLanguageName: String? = nil
    @State private var voiceNoteEnglishTranslation: String? = nil
    @State private var additionalVoiceNoteData: [Data] = []
    @State private var additionalVoiceNoteDurations: [TimeInterval] = []
    @State private var additionalVoiceNoteTranscripts: [String] = []
    @State private var additionalVoiceNoteLanguageCodes: [String] = []
    @State private var additionalVoiceNoteLanguageNames: [String] = []
    @State private var additionalVoiceNoteEnglishTranslations: [String] = []
    @State private var transcribingVoiceNoteIndexes: Set<Int> = []
    @State private var isDetectingMood = false
    @State private var pendingTextCommand: NoteTextCommand?
    @State private var textCommandRevision = 0
    @State private var pendingBeforePhotoCommand: NoteTextCommand?
    @State private var pendingAfterPhotoCommand: NoteTextCommand?
    @State private var activePhotoSegment: InlinePhotoSegment = .before
    @State private var beforePhotoFocused = false
    @State private var afterPhotoFocused = false
    @State private var activeParagraphStyle: NoteParagraphTextStyle = .body
    @FocusState private var editorFocused: Bool

    private var noteDate: Date { entry?.createdAt ?? Date() }
    private var hasDraftContent: Bool {
        viewModel.hasContent || photoData != nil || !draftVoiceNotes.isEmpty
    }
    private var hasInlinePhoto: Bool {
        photoData != nil && viewModel.text.contains(inlinePhotoToken)
    }
    private var isTranscribingVoiceNotes: Bool {
        !transcribingVoiceNoteIndexes.isEmpty
    }
    private var draftVoiceNotes: [(data: Data, duration: TimeInterval, transcript: String?, languageName: String?, englishTranslation: String?)] {
        var notes: [(Data, TimeInterval, String?, String?, String?)] = []
        if let voiceNoteData {
            notes.append((
                voiceNoteData,
                voiceNoteDuration,
                voiceNoteTranscript,
                voiceNoteLanguageName,
                voiceNoteEnglishTranslation
            ))
        }
        for (index, data) in additionalVoiceNoteData.enumerated() {
            let duration = index < additionalVoiceNoteDurations.count ? additionalVoiceNoteDurations[index] : 0
            let transcript = index < additionalVoiceNoteTranscripts.count ? additionalVoiceNoteTranscripts[index] : nil
            let languageName = index < additionalVoiceNoteLanguageNames.count ? additionalVoiceNoteLanguageNames[index] : nil
            let translation = index < additionalVoiceNoteEnglishTranslations.count ? additionalVoiceNoteEnglishTranslations[index] : nil
            notes.append((
                data,
                duration,
                transcript,
                languageName,
                translation
            ))
        }
        return notes
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                dateHeader

                if !draftVoiceNotes.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(draftVoiceNotes.indices, id: \.self) { index in
                            VoiceNoteAttachmentView(
                                data: draftVoiceNotes[index].data,
                                duration: draftVoiceNotes[index].duration,
                                title: "Voice note \(index + 1)",
                                transcript: draftVoiceNotes[index].transcript,
                                languageName: draftVoiceNotes[index].languageName,
                                isTranscribing: transcribingVoiceNoteIndexes.contains(index),
                                onDelete: { removeVoiceNote(at: index) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                NoteEditorTextView(
                    text: $viewModel.text,
                    textStyleData: $viewModel.textStyleData,
                    photoData: $photoData,
                    command: $pendingTextCommand,
                    commandRevision: $textCommandRevision,
                    isFocused: Binding(
                        get: { editorFocused },
                        set: { editorFocused = $0 }
                    ),
                    activeParagraphStyle: $activeParagraphStyle
                )
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showSaved {
                Text("Saved")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar, in: Capsule())
                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if isAttachingPhoto {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Attaching photo")
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar, in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteAndDismiss() }
            Button("Cancel", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isKeyboardVisible || editorFocused {
                toolRow
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onAppear {
            viewModel.configure(entry: entry)
            if let entry {
                photoData = entry.photoData
                if entry.photoData != nil, !viewModel.text.contains(inlinePhotoToken) {
                    let trimmed = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.text = trimmed.isEmpty ? inlinePhotoToken : "\(trimmed)\n\(inlinePhotoToken)"
                }
                voiceNoteData = entry.voiceNoteData
                voiceNoteDuration = entry.voiceNoteDuration
                voiceNoteTranscript = entry.voiceNoteTranscript
                voiceNoteLanguageCode = entry.voiceNoteLanguageCode
                voiceNoteLanguageName = entry.voiceNoteLanguageName
                voiceNoteEnglishTranslation = entry.voiceNoteEnglishTranslation
                additionalVoiceNoteData = entry.additionalVoiceNoteData
                additionalVoiceNoteDurations = entry.additionalVoiceNoteDurations
                additionalVoiceNoteTranscripts = entry.additionalVoiceNoteTranscripts
                additionalVoiceNoteLanguageCodes = entry.additionalVoiceNoteLanguageCodes
                additionalVoiceNoteLanguageNames = entry.additionalVoiceNoteLanguageNames
                additionalVoiceNoteEnglishTranslations = entry.additionalVoiceNoteEnglishTranslations
            }
            if autoFocus || entry != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    editorFocused = true
                }
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            NativePhotoPicker { result in
                handlePickedPhoto(result)
            }
            .ignoresSafeArea()
        }
        .alert("Photo not attached", isPresented: Binding(
            get: { photoAttachError != nil },
            set: { if !$0 { photoAttachError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoAttachError ?? "")
        }
        .sheet(isPresented: $showVoiceInput) {
            VoiceInputSheet { data, duration in
                appendVoiceNote(data: data, duration: duration)
            }
        }
    }

    private var dateHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                Text(noteDate, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                if viewModel.wordCount > 0 {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(viewModel.wordCount)w")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            moodMenu
        }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private var moodMenu: some View {
        Menu {
            Button {
                detectMoodWithMirror()
            } label: {
                Label(isDetectingMood ? "Detecting..." : "Mirror suggests", systemImage: "sparkles")
            }
            .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDetectingMood)

            Divider()

            ForEach(moodLabels, id: \.self) { mood in
                Button {
                    viewModel.selectedMood = viewModel.selectedMood == mood ? nil : mood
                } label: {
                    Label {
                        Text(mood)
                    } icon: {
                        Image(uiImage: moodMenuDotImage(for: mood, isSelected: viewModel.selectedMood == mood))
                            .renderingMode(.original)
                    }
                }
            }

            if viewModel.selectedMood != nil {
                Divider()
                Button("Clear Mood", role: .destructive) {
                    viewModel.selectedMood = nil
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isDetectingMood {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 13, height: 13)
                } else {
                    if let selectedMood = viewModel.selectedMood {
                        Circle()
                            .fill(MirrorTheme.moodColor(for: selectedMood))
                            .frame(width: 8, height: 8)
                    }
                    Text(viewModel.selectedMood ?? "Mood")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(viewModel.selectedMood == nil ? .secondary : MirrorTheme.moodColor(for: viewModel.selectedMood ?? ""))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                viewModel.selectedMood == nil && !isDetectingMood
                    ? Color(.secondarySystemFill)
                    : MirrorTheme.moodColor(for: viewModel.selectedMood ?? "").opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mood")
        .accessibilityValue(viewModel.selectedMood ?? "Not selected")
    }

    private nonisolated(unsafe) static var moodImageCache: [String: UIImage] = [:]

    private func moodMenuDotImage(for mood: String, isSelected: Bool) -> UIImage {
        let key = "\(mood)_\(isSelected)"
        if let cached = Self.moodImageCache[key] { return cached }
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(x: 5, y: 5, width: 10, height: 10)
            UIColor(MirrorTheme.moodColor(for: mood)).setFill()
            context.cgContext.fillEllipse(in: rect)
            if isSelected {
                UIColor.white.setStroke()
                context.cgContext.setLineWidth(1.4)
                context.cgContext.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            }
        }
        let result = image.withRenderingMode(.alwaysOriginal)
        Self.moodImageCache[key] = result
        return result
    }

    private func detectMoodWithMirror() {
        let text = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isDetectingMood = true
        Task {
            let detected = try? await InsightService.detectEmotion(text: text, token: "")
            await MainActor.run {
                if let detected, MirrorTheme.moodOptions.contains(detected) {
                    viewModel.selectedMood = detected
                }
                isDetectingMood = false
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if entry != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete entry")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveAndDismiss()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isTranscribingVoiceNotes)
                .accessibilityLabel("Save entry")
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    discardDraft()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(hasDraftContent ? .secondary : .tertiary)
                }
                .buttonStyle(.plain)
                .disabled(!hasDraftContent)
                .accessibilityLabel("Discard draft")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveDraft()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(hasDraftContent ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!hasDraftContent || isTranscribingVoiceNotes)
                .accessibilityLabel("Save entry")
            }
        }
    }

    private var toolRow: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                // Keyboard dismiss
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // Photo button
                Button {
                    presentPhotoPicker()
                } label: {
                    Image(systemName: photoData != nil ? "photo.fill" : "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(photoData != nil ? Color.accentColor : .primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                // Voice button
                Button {
                    presentVoiceNoteSheet()
                } label: {
                    Image(systemName: !draftVoiceNotes.isEmpty ? "waveform.circle.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(!draftVoiceNotes.isEmpty ? Color.accentColor : .primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                // Checklist button — highlighted when cursor is on a checklist line, tap toggles
                Button {
                    applyTextCommand(.checklist)
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            (activeParagraphStyle == .checklistUnchecked || activeParagraphStyle == .checklistChecked)
                                ? Color.accentColor : .primary
                        )
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                formatMenu
            }
            .padding(.horizontal, 8)
        }
        .background(.bar)
    }

    private var formatMenu: some View {
        Menu {
            Button { applyTextCommand(.title) } label: {
                Label("Title", systemImage: activeParagraphStyle == .title ? "checkmark" : "textformat.size.larger")
            }
            Button { applyTextCommand(.heading) } label: {
                Label("Heading", systemImage: activeParagraphStyle == .heading ? "checkmark" : "textformat.size")
            }
            Button { applyTextCommand(.subheading) } label: {
                Label("Subheading", systemImage: activeParagraphStyle == .subheading ? "checkmark" : "textformat")
            }
            Button { applyTextCommand(.body) } label: {
                Label("Body", systemImage: activeParagraphStyle == .body ? "checkmark" : "text.alignleft")
            }
            Button { applyTextCommand(.monospaced) } label: {
                Label("Monostyled", systemImage: activeParagraphStyle == .monospaced ? "checkmark" : "curlybraces")
            }
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 20))
                .foregroundStyle(
                    (activeParagraphStyle != .body && activeParagraphStyle != .checklistUnchecked && activeParagraphStyle != .checklistChecked)
                        ? Color.accentColor : .primary
                )
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Text formatting")
    }

    private var beforePhotoTextBinding: Binding<String> {
        Binding(
            get: { splitInlinePhotoText().before },
            set: { newValue in
                let split = splitInlinePhotoText()
                viewModel.text = composeInlinePhotoText(before: newValue, after: split.after)
            }
        )
    }

    private var afterPhotoTextBinding: Binding<String> {
        Binding(
            get: { splitInlinePhotoText().after },
            set: { newValue in
                let split = splitInlinePhotoText()
                viewModel.text = composeInlinePhotoText(before: split.before, after: newValue)
            }
        )
    }

    private func splitInlinePhotoText() -> (before: String, after: String) {
        guard let tokenRange = viewModel.text.range(of: inlinePhotoToken) else {
            return (viewModel.text, "")
        }
        let before = String(viewModel.text[..<tokenRange.lowerBound])
            .trimmingCharacters(in: CharacterSet.newlines)
        let after = String(viewModel.text[tokenRange.upperBound...])
            .trimmingCharacters(in: CharacterSet.newlines)
        return (before, after)
    }

    private func composeInlinePhotoText(before: String, after: String) -> String {
        let before = before.trimmingCharacters(in: CharacterSet.newlines)
        let after = after.trimmingCharacters(in: CharacterSet.newlines)
        if after.isEmpty {
            return before.isEmpty ? inlinePhotoToken : "\(before)\n\(inlinePhotoToken)"
        }
        if before.isEmpty {
            return "\(inlinePhotoToken)\n\(after)"
        }
        return "\(before)\n\(inlinePhotoToken)\n\(after)"
    }

    private func applyTextCommand(_ command: NoteTextCommand) {
        editorFocused = true
        pendingTextCommand = command
        textCommandRevision += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func saveAndDismiss() {
        guard !isTranscribingVoiceNotes else { return }
        if let entry {
            guard !entry.textDecryptionFailed else {
                dismiss()
                return
            }
            if hasDraftContent {
                update(entry)
                entry.photoData = photoData
                entry.voiceNoteData = voiceNoteData
                entry.voiceNoteDuration = voiceNoteDuration
                entry.voiceNoteTranscript = voiceNoteTranscript
                entry.voiceNoteLanguageCode = voiceNoteLanguageCode
                entry.voiceNoteLanguageName = voiceNoteLanguageName
                entry.voiceNoteEnglishTranslation = voiceNoteEnglishTranslation
                entry.additionalVoiceNoteData = additionalVoiceNoteData
                entry.additionalVoiceNoteDurations = additionalVoiceNoteDurations
                entry.additionalVoiceNoteTranscripts = additionalVoiceNoteTranscripts
                entry.additionalVoiceNoteLanguageCodes = additionalVoiceNoteLanguageCodes
                entry.additionalVoiceNoteLanguageNames = additionalVoiceNoteLanguageNames
                entry.additionalVoiceNoteEnglishTranslations = additionalVoiceNoteEnglishTranslations
                // Defer write past dismiss so SQLite/CloudKit flush doesn't block navigation animation
                let ctx = modelContext
                Task { @MainActor in try? ctx.save() }
            }
        } else {
            if hasDraftContent {
                let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let entry = Entry(text: plain, mood: viewModel.selectedMood, source: !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed)
                entry.textStyleData = viewModel.textStyleData
                entry.photoData = photoData
                entry.voiceNoteData = voiceNoteData
                entry.voiceNoteDuration = voiceNoteDuration
                entry.voiceNoteTranscript = voiceNoteTranscript
                entry.voiceNoteLanguageCode = voiceNoteLanguageCode
                entry.voiceNoteLanguageName = voiceNoteLanguageName
                entry.voiceNoteEnglishTranslation = voiceNoteEnglishTranslation
                entry.additionalVoiceNoteData = additionalVoiceNoteData
                entry.additionalVoiceNoteDurations = additionalVoiceNoteDurations
                entry.additionalVoiceNoteTranscripts = additionalVoiceNoteTranscripts
                entry.additionalVoiceNoteLanguageCodes = additionalVoiceNoteLanguageCodes
                entry.additionalVoiceNoteLanguageNames = additionalVoiceNoteLanguageNames
                entry.additionalVoiceNoteEnglishTranslations = additionalVoiceNoteEnglishTranslations
                modelContext.insert(entry)
                try? modelContext.save()
                withAnimation { showSaved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation { showSaved = false }
                }
            }
        }
        dismiss()
        if entry != nil {
            DispatchQueue.main.async {
                onSaveComplete?()
            }
        }
    }

    private func saveDraft() {
        guard entry == nil, hasDraftContent, !isTranscribingVoiceNotes else { return }
        let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedEntry = Entry(text: plain, mood: viewModel.selectedMood, source: !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed)
        savedEntry.textStyleData = viewModel.textStyleData
        savedEntry.photoData = photoData
        savedEntry.voiceNoteData = voiceNoteData
        savedEntry.voiceNoteDuration = voiceNoteDuration
        savedEntry.voiceNoteTranscript = voiceNoteTranscript
        savedEntry.voiceNoteLanguageCode = voiceNoteLanguageCode
        savedEntry.voiceNoteLanguageName = voiceNoteLanguageName
        savedEntry.voiceNoteEnglishTranslation = voiceNoteEnglishTranslation
        savedEntry.additionalVoiceNoteData = additionalVoiceNoteData
        savedEntry.additionalVoiceNoteDurations = additionalVoiceNoteDurations
        savedEntry.additionalVoiceNoteTranscripts = additionalVoiceNoteTranscripts
        savedEntry.additionalVoiceNoteLanguageCodes = additionalVoiceNoteLanguageCodes
        savedEntry.additionalVoiceNoteLanguageNames = additionalVoiceNoteLanguageNames
        savedEntry.additionalVoiceNoteEnglishTranslations = additionalVoiceNoteEnglishTranslations
        modelContext.insert(savedEntry)
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        clearDraft()
        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { showSaved = false }
        }
        onSaveComplete?()
    }

    private func clearDraft() {
        viewModel.text = ""
        viewModel.textStyleData = nil
        viewModel.selectedMood = nil
        photoData = nil
        voiceNoteData = nil
        voiceNoteDuration = 0
        voiceNoteTranscript = nil
        voiceNoteLanguageCode = nil
        voiceNoteLanguageName = nil
        voiceNoteEnglishTranslation = nil
        additionalVoiceNoteData = []
        additionalVoiceNoteDurations = []
        additionalVoiceNoteTranscripts = []
        additionalVoiceNoteLanguageCodes = []
        additionalVoiceNoteLanguageNames = []
        additionalVoiceNoteEnglishTranslations = []
        transcribingVoiceNoteIndexes = []
    }

    private func update(_ entry: Entry) {
        let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = plain
        entry.textStyleData = viewModel.textStyleData
        entry.wordCount = plain.replacingOccurrences(of: inlinePhotoToken, with: "")
            .split { $0.isWhitespace }
            .filter { !$0.isEmpty }
            .count
        entry.mood = viewModel.selectedMood
        entry.source = !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func appendVoiceNote(data: Data, duration: TimeInterval) {
        let noteIndex: Int
        if voiceNoteData == nil {
            voiceNoteData = data
            voiceNoteDuration = duration
            voiceNoteTranscript = nil
            voiceNoteLanguageCode = nil
            voiceNoteLanguageName = nil
            voiceNoteEnglishTranslation = nil
            noteIndex = 0
        } else {
            additionalVoiceNoteData.append(data)
            additionalVoiceNoteDurations.append(duration)
            additionalVoiceNoteTranscripts.append("")
            additionalVoiceNoteLanguageCodes.append("")
            additionalVoiceNoteLanguageNames.append("")
            additionalVoiceNoteEnglishTranslations.append("")
            noteIndex = additionalVoiceNoteData.count
        }
        transcribeVoiceNote(data: data, index: noteIndex)
    }

    private func transcribeVoiceNote(data: Data, index: Int) {
        transcribingVoiceNoteIndexes.insert(index)
        Task {
            do {
                let result = try await VoiceTranscriptionService.transcribe(audioData: data, token: "")
                await MainActor.run {
                    applyTranscription(result, toVoiceNoteAt: index)
                    transcribingVoiceNoteIndexes.remove(index)
                }
            } catch {
                let _: Void = await MainActor.run {
                    transcribingVoiceNoteIndexes.remove(index)
                }
            }
        }
    }

    private func applyTranscription(_ transcription: VoiceTranscription, toVoiceNoteAt index: Int) {
        if index == 0 {
            voiceNoteTranscript = transcription.transcript
            voiceNoteLanguageCode = transcription.languageCode
            voiceNoteLanguageName = transcription.languageName
            voiceNoteEnglishTranslation = transcription.englishTranslation
        } else {
            let additionalIndex = index - 1
            guard additionalVoiceNoteData.indices.contains(additionalIndex) else { return }
            additionalVoiceNoteTranscripts[additionalIndex] = transcription.transcript
            additionalVoiceNoteLanguageCodes[additionalIndex] = transcription.languageCode
            additionalVoiceNoteLanguageNames[additionalIndex] = transcription.languageName
            additionalVoiceNoteEnglishTranslations[additionalIndex] = transcription.englishTranslation
        }
    }

    private func removeVoiceNote(at index: Int) {
        transcribingVoiceNoteIndexes.remove(index)
        if index == 0 {
            voiceNoteData = nil
            voiceNoteDuration = 0
            voiceNoteTranscript = nil
            voiceNoteLanguageCode = nil
            voiceNoteLanguageName = nil
            voiceNoteEnglishTranslation = nil
            if !additionalVoiceNoteData.isEmpty {
                voiceNoteData = additionalVoiceNoteData.removeFirst()
                voiceNoteDuration = additionalVoiceNoteDurations.isEmpty ? 0 : additionalVoiceNoteDurations.removeFirst()
                voiceNoteTranscript = additionalVoiceNoteTranscripts.isEmpty ? nil : additionalVoiceNoteTranscripts.removeFirst()
                voiceNoteLanguageCode = additionalVoiceNoteLanguageCodes.isEmpty ? nil : additionalVoiceNoteLanguageCodes.removeFirst()
                voiceNoteLanguageName = additionalVoiceNoteLanguageNames.isEmpty ? nil : additionalVoiceNoteLanguageNames.removeFirst()
                voiceNoteEnglishTranslation = additionalVoiceNoteEnglishTranslations.isEmpty ? nil : additionalVoiceNoteEnglishTranslations.removeFirst()
            }
        } else {
            let additionalIndex = index - 1
            if additionalVoiceNoteData.indices.contains(additionalIndex) {
                additionalVoiceNoteData.remove(at: additionalIndex)
            }
            if additionalVoiceNoteDurations.indices.contains(additionalIndex) {
                additionalVoiceNoteDurations.remove(at: additionalIndex)
            }
            if additionalVoiceNoteTranscripts.indices.contains(additionalIndex) {
                additionalVoiceNoteTranscripts.remove(at: additionalIndex)
            }
            if additionalVoiceNoteLanguageCodes.indices.contains(additionalIndex) {
                additionalVoiceNoteLanguageCodes.remove(at: additionalIndex)
            }
            if additionalVoiceNoteLanguageNames.indices.contains(additionalIndex) {
                additionalVoiceNoteLanguageNames.remove(at: additionalIndex)
            }
            if additionalVoiceNoteEnglishTranslations.indices.contains(additionalIndex) {
                additionalVoiceNoteEnglishTranslations.remove(at: additionalIndex)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func presentVoiceNoteSheet() {
        editorFocused = false
        isKeyboardVisible = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showVoiceInput = true
        }
    }

    private func presentPhotoPicker() {
        editorFocused = false
        isKeyboardVisible = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showPhotoPicker = true
        }
    }

    private func handlePickedPhoto(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isAttachingPhoto = true
            Task {
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    let preparedData = try await Task.detached(priority: .userInitiated) {
                        try preparedInlinePhotoData(fromFileAt: url)
                    }.value
                    photoData = preparedData
                    viewModel.text = textWithInlinePhotoToken(viewModel.text)
                    isAttachingPhoto = false
                } catch {
                    isAttachingPhoto = false
                    photoAttachError = "This image could not be attached. Try a different image or export it as JPEG first."
                }
            }
        case .failure:
            photoAttachError = "This image could not be attached. Try a different image or export it as JPEG first."
        }
    }

    private func deleteAndDismiss() {
        if let entry { modelContext.delete(entry) }
        try? modelContext.save()
        dismiss()
        DispatchQueue.main.async {
            onSaveComplete?()
        }
    }

    private func discardDraft() {
        clearDraft()
    }
}

enum PhotoAttachError: Error {
    case unreadableImage
}


#Preview {
    NavigationStack {
        WriteView()
            .modelContainer(for: Entry.self, inMemory: true)
    }
}
