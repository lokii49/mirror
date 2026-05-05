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
        case .checklist: return "○ "
        case .title: return "# "
        case .heading: return "## "
        case .subheading: return "### "
        case .body: return ""
        case .monospaced: return "    "
        case .photo: return ""
        }
    }
}

let inlinePhotoToken = "[[mirror-photo]]"

private enum InlinePhotoSegment {
    case before
    case after
}

struct NoteEditorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var photoData: Data?
    @Binding var command: NoteTextCommand?
    @Binding var isFocused: Bool

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

        if context.coordinator.logicalText(from: textView) != text {
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

        if let command {
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
        private let stylePrefixes = ["### ", "## ", "# ", "✓ ", "○ ", "    "]
        private var isApplyingStyledText = false
        private var lastRenderedText: String?
        private var lastRenderedPhotoSignature: Int?
        private var lastRenderedWidth: CGFloat = 0

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
            let paragraph = nsText.substring(with: paraRange)
            if paragraph.hasPrefix("○ ") {
                let replacement = "✓ " + paragraph.dropFirst(2)
                let updated = nsText.replacingCharacters(in: paraRange, with: replacement)
                parent.text = updated
                applyStyledText(to: textView, preservingSelection: false)
                textView.selectedRange = bounded(NSRange(location: charIndex, length: 0), in: updated)
                updatePlaceholder(in: textView)
            } else if paragraph.hasPrefix("✓ ") {
                let replacement = "○ " + paragraph.dropFirst(2)
                let updated = nsText.replacingCharacters(in: paraRange, with: replacement)
                parent.text = updated
                applyStyledText(to: textView, preservingSelection: false)
                textView.selectedRange = bounded(NSRange(location: charIndex, length: 0), in: updated)
                updatePlaceholder(in: textView)
            }
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
            updatePlaceholder(in: textView)
            applyStyledText(to: textView, preservingSelection: true)
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

            if replacement == "\n" {
                let nsText = rendered as NSString
                let paragraphRange = nsText.paragraphRange(for: NSRange(location: max(0, range.location - 1), length: 0))
                let paragraph = nsText.substring(with: paragraphRange)
                let editable = paragraph.trimmingCharacters(in: .newlines)
                if editable == "○ " || editable == "✓ " {
                    let updated = nsText.replacingCharacters(in: paragraphRange, with: "")
                    parent.text = updated.replacingOccurrences(of: "\u{fffc}", with: inlinePhotoToken)
                    applyStyledText(to: textView, preservingSelection: false)
                    textView.selectedRange = bounded(NSRange(location: paragraphRange.location, length: 0), in: textView.text)
                    updatePlaceholder(in: textView)
                    return false
                }
                if paragraph.hasPrefix("○ ") || paragraph.hasPrefix("✓ ") {
                    textView.insertText("\n○ ")
                    return false
                }
            }

            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func apply(_ command: NoteTextCommand, to textView: UITextView) {
            if command == .photo {
                insertPhotoToken(in: textView)
                return
            }

            var text = textView.text ?? ""
            let selectedRange = bounded(textView.selectedRange, in: text)
            let paragraphRange = (text as NSString).paragraphRange(for: selectedRange)
            let ranges = paragraphRanges(in: paragraphRange, text: text)

            var cursorOffset = 0
            for range in ranges.reversed() {
                let nsText = text as NSString
                let paragraph = nsText.substring(with: range)
                let lineBreak = trailingLineBreak(from: paragraph)
                let editableLength = paragraph.count - lineBreak.count
                let editable = String(paragraph.prefix(editableLength))
                let stripped = strippedStylePrefix(from: editable)
                let replacement = command.prefix + stripped + lineBreak
                text = nsText.replacingCharacters(in: range, with: replacement)

                if range.location <= selectedRange.location {
                    cursorOffset += replacement.count - range.length
                }
            }

            parent.text = text
            textView.text = text
            applyStyledText(to: textView, preservingSelection: false)
            let newLocation = max(0, selectedRange.location + cursorOffset)
            textView.selectedRange = bounded(NSRange(location: newLocation, length: selectedRange.length), in: text)
            updatePlaceholder(in: textView)
        }

        func applyStyledText(to textView: UITextView, preservingSelection: Bool) {
            let selectedRange = textView.selectedRange
            let rawText = parent.text
            let photoSignature = parent.photoData?.count
            let width = textView.bounds.width.rounded()

            if lastRenderedText == rawText,
               lastRenderedPhotoSignature == photoSignature,
               lastRenderedWidth == width {
                if preservingSelection {
                    textView.selectedRange = bounded(selectedRange, in: textView.text)
                }
                return
            }

            let attributed = renderedAttributedText(for: rawText, width: textView.bounds.width)
            let renderedText = attributed.string
            let nsText = renderedText as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            nsText.enumerateSubstrings(in: fullRange, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                let paragraph = nsText.substring(with: range)
                let attributes = self.attributes(for: paragraph)
                attributed.addAttributes(attributes, range: range)
                if let markerRange = self.hiddenStyleMarkerRange(for: paragraph, paragraphRange: range) {
                    attributed.addAttributes(self.hiddenMarkerAttributes, range: markerRange)
                }
            }

            isApplyingStyledText = true
            textView.attributedText = attributed
            isApplyingStyledText = false
            lastRenderedText = rawText
            lastRenderedPhotoSignature = photoSignature
            lastRenderedWidth = width
            textView.typingAttributes = bodyAttributes
            if preservingSelection {
                textView.selectedRange = bounded(selectedRange, in: textView.text)
            }
        }

        func updatePlaceholder(in textView: UITextView) {
            textView.viewWithTag(Self.placeholderTag)?.isHidden = !parent.text.isEmpty
        }

        func logicalText(from textView: UITextView) -> String {
            textView.attributedText.string.replacingOccurrences(of: "\u{fffc}", with: inlinePhotoToken)
        }

        func bounded(_ range: NSRange, in text: String) -> NSRange {
            let length = (text as NSString).length
            let location = min(max(0, range.location), length)
            let availableLength = max(0, length - location)
            return NSRange(location: location, length: min(range.length, availableLength))
        }

        private func paragraphRanges(in range: NSRange, text: String) -> [NSRange] {
            let nsText = text as NSString
            guard nsText.length > 0 else { return [NSRange(location: 0, length: 0)] }

            var result: [NSRange] = []
            var location = range.location
            let end = min(NSMaxRange(range), nsText.length)

            repeat {
                let paragraphRange = nsText.paragraphRange(for: NSRange(location: min(location, nsText.length), length: 0))
                result.append(paragraphRange)
                let next = NSMaxRange(paragraphRange)
                if next <= location { break }
                location = next
            } while location < end

            return result
        }

        private func strippedStylePrefix(from text: String) -> String {
            for prefix in stylePrefixes where text.hasPrefix(prefix) {
                return String(text.dropFirst(prefix.count))
            }
            return text
        }

        private func trailingLineBreak(from text: String) -> String {
            if text.hasSuffix("\r\n") { return "\r\n" }
            if text.hasSuffix("\n") { return "\n" }
            if text.hasSuffix("\r") { return "\r" }
            return ""
        }

        private func attributes(for paragraph: String) -> [NSAttributedString.Key: Any] {
            if paragraph.hasPrefix("### ") {
                return [
                    .font: UIFont.preferredFont(forTextStyle: .headline),
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: paragraphStyle(lineSpacing: 4, paragraphSpacing: 6)
                ]
            }
            if paragraph.hasPrefix("## ") {
                return [
                    .font: UIFont.preferredFont(forTextStyle: .title2).bolded(),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraphStyle(lineSpacing: 4, paragraphSpacing: 8)
                ]
            }
            if paragraph.hasPrefix("# ") {
                return [
                    .font: UIFont.preferredFont(forTextStyle: .largeTitle).bolded(),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraphStyle(lineSpacing: 3, paragraphSpacing: 10)
                ]
            }
            if paragraph.hasPrefix("    ") {
                return [
                    .font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
                ]
            }
            if paragraph.hasPrefix("○ ") {
                let ps = paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
                ps.headIndent = 34
                ps.firstLineHeadIndent = 0
                return [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: ps
                ]
            }
            if paragraph.hasPrefix("✓ ") {
                let ps = paragraphStyle(lineSpacing: 6, paragraphSpacing: 5)
                ps.headIndent = 34
                ps.firstLineHeadIndent = 0
                return [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.tertiaryLabel,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: UIColor.tertiaryLabel,
                    .paragraphStyle: ps
                ]
            }
            return bodyAttributes
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
            var remaining = rawText[...]

            while let tokenRange = remaining.range(of: inlinePhotoToken) {
                let before = String(remaining[..<tokenRange.lowerBound])
                attributed.append(NSAttributedString(string: before, attributes: bodyAttributes))
                attributed.append(photoAttachmentString(width: width))
                remaining = remaining[tokenRange.upperBound...]
            }

            attributed.append(NSAttributedString(string: String(remaining), attributes: bodyAttributes))
            return attributed
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

        private var hiddenMarkerAttributes: [NSAttributedString.Key: Any] {
            [
                .font: UIFont.systemFont(ofSize: 0.1),
                .foregroundColor: UIColor.clear,
                .kern: -2
            ]
        }

        private func hiddenStyleMarkerRange(for paragraph: String, paragraphRange: NSRange) -> NSRange? {
            let markerLength: Int
            if paragraph.hasPrefix("### ") {
                markerLength = 4
            } else if paragraph.hasPrefix("## ") {
                markerLength = 3
            } else if paragraph.hasPrefix("# ") {
                markerLength = 2
            } else {
                return nil
            }
            return NSRange(location: paragraphRange.location, length: min(markerLength, paragraphRange.length))
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
    @State private var pendingBeforePhotoCommand: NoteTextCommand?
    @State private var pendingAfterPhotoCommand: NoteTextCommand?
    @State private var activePhotoSegment: InlinePhotoSegment = .before
    @State private var beforePhotoFocused = false
    @State private var afterPhotoFocused = false
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
                    photoData: $photoData,
                    command: $pendingTextCommand,
                    isFocused: Binding(
                        get: { editorFocused },
                        set: { editorFocused = $0 }
                    )
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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

    private func moodMenuDotImage(for mood: String, isSelected: Bool) -> UIImage {
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
        return image.withRenderingMode(.alwaysOriginal)
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
        if showsBackButton {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    saveAndDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isTranscribingVoiceNotes)
            }
        }

        if entry != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Done") { saveAndDismiss() }
                        .disabled(isTranscribingVoiceNotes)
                    Button("Delete Entry", systemImage: "trash", role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { deleteAndDismiss() }
                    Button("Cancel", role: .cancel) {}
                }
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

                // Checklist button
                Button {
                    applyTextCommand(.checklist)
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
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
            Button {
                applyTextCommand(.title)
            } label: {
                Label("Title", systemImage: "textformat.size.larger")
            }

            Button {
                applyTextCommand(.heading)
            } label: {
                Label("Heading", systemImage: "textformat.size")
            }

            Button {
                applyTextCommand(.subheading)
            } label: {
                Label("Subheading", systemImage: "textformat")
            }

            Button {
                applyTextCommand(.body)
            } label: {
                Label("Body", systemImage: "text.alignleft")
            }

            Button {
                applyTextCommand(.monospaced)
            } label: {
                Label("Monostyled", systemImage: "curlybraces")
            }
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 20))
                .foregroundStyle(.primary)
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func saveAndDismiss() {
        guard !isTranscribingVoiceNotes else { return }
        if let entry {
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
            }
        } else {
            if hasDraftContent {
                let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let entry = Entry(text: plain, mood: viewModel.selectedMood, source: !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed)
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
                withAnimation { showSaved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation { showSaved = false }
                }
            }
        }
        dismiss()
    }

    private func saveDraft() {
        guard entry == nil, hasDraftContent, !isTranscribingVoiceNotes else { return }
        let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedEntry = Entry(text: plain, mood: viewModel.selectedMood, source: !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed)
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
        dismiss()
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
