import SwiftUI
import UIKit
import PhotosUI
import PencilKit
import UniformTypeIdentifiers
import VisionKit

func decodeRichText(from data: Data) -> NSAttributedString? {
    let allowedClasses: [AnyClass] = [
        NSAttributedString.self,
        NSMutableAttributedString.self,
        NSTextAttachment.self,
        UIImage.self,
        UIFont.self,
        UIColor.self,
        NSMutableParagraphStyle.self,
        NSParagraphStyle.self,
        NSData.self,
        FileWrapper.self,
        NSURL.self,
    ]

    return try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data) as? NSAttributedString
}

enum NoteTextStyle: String, CaseIterable {
    case title
    case heading
    case subheading
    case body
    case monospaced
}

struct FormatState: Equatable {
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var isHighlighted = false
    var alignment: NSTextAlignment = .left
    var textStyle: NoteTextStyle = .body
    var canUndo = false
    var canRedo = false
}

private struct NoteFont {
    let title: UIFont
    let heading: UIFont
    let subheading: UIFont
    let body: UIFont
    let mono: UIFont
    let bold: UIFont
    let italic: UIFont
    let boldItalic: UIFont

    init() {
        let bodyDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        let serifDescriptor = bodyDescriptor.withDesign(.serif) ?? bodyDescriptor
        let size = UIFont(descriptor: serifDescriptor, size: 0).pointSize

        body = UIFont(descriptor: serifDescriptor, size: 0)
        bold = UIFont(
            descriptor: serifDescriptor.withSymbolicTraits(.traitBold) ?? serifDescriptor,
            size: size
        )
        italic = UIFont(
            descriptor: serifDescriptor.withSymbolicTraits(.traitItalic) ?? serifDescriptor,
            size: size
        )
        boldItalic = UIFont(
            descriptor: serifDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) ?? serifDescriptor,
            size: size
        )

        let titleDescriptor = serifDescriptor.withSymbolicTraits(.traitBold) ?? serifDescriptor
        title = UIFont(descriptor: titleDescriptor, size: size + 14)
        heading = UIFont(descriptor: titleDescriptor, size: size + 6)
        subheading = UIFont(
            descriptor: serifDescriptor.withSymbolicTraits(.traitBold) ?? serifDescriptor,
            size: size + 3
        )
        mono = .monospacedSystemFont(ofSize: size - 1, weight: .regular)
    }

    func font(for style: NoteTextStyle) -> UIFont {
        switch style {
        case .title:
            return title
        case .heading:
            return heading
        case .subheading:
            return subheading
        case .body:
            return body
        case .monospaced:
            return mono
        }
    }

    func style(for font: UIFont) -> NoteTextStyle {
        let size = font.pointSize
        let traits = font.fontDescriptor.symbolicTraits
        let isBold = traits.contains(.traitBold)
        let bodySize = body.pointSize

        if font.fontName.lowercased().contains("mono") {
            return .monospaced
        }
        if size >= bodySize + 12 && isBold {
            return .title
        }
        if size >= bodySize + 5 && isBold {
            return .heading
        }
        if size >= bodySize + 2 && isBold {
            return .subheading
        }

        return .body
    }
}

final class RichTextCoordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, VNDocumentCameraViewControllerDelegate, UIDocumentPickerDelegate {
    weak var textView: UITextView?

    var onChange: ((NSAttributedString) -> Void)?
    var onFormatStateChange: ((FormatState) -> Void)?

    private let fonts = NoteFont()
    private(set) var formatState = FormatState()

    func focus() {
        textView?.becomeFirstResponder()
    }

    func clear() {
        guard let textView else { return }
        textView.attributedText = NSAttributedString()
        textView.typingAttributes = defaultAttrs()
        onChange?(NSAttributedString())
        refreshFormatState()
    }

    func defaultAttrs() -> [NSAttributedString.Key: Any] {
        [
            .font: fonts.body,
            .foregroundColor: UIColor.label,
            .paragraphStyle: baseParagraphStyle(),
        ]
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard text == "\n" else { return true }
        return !handleReturnInList(textView, at: range)
    }

    func textViewDidChange(_ textView: UITextView) {
        onChange?(textView.attributedText)
        refreshFormatState()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        refreshFormatState()
    }

    func toggleBold() {
        toggleTrait(
            .traitBold,
            boldFont: fonts.bold,
            italicFont: fonts.italic,
            boldItalicFont: fonts.boldItalic,
            baseFont: fonts.body
        )
    }

    func toggleItalic() {
        toggleTrait(
            .traitItalic,
            boldFont: fonts.bold,
            italicFont: fonts.italic,
            boldItalicFont: fonts.boldItalic,
            baseFont: fonts.body
        )
    }

    func toggleUnderline() {
        guard let textView else { return }
        let selection = textView.selectedRange
        let current = currentAttributeValue(
            for: .underlineStyle,
            in: textView,
            selection: selection
        ) as? Int ?? 0
        let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        applyAttribute(.underlineStyle, value: newValue, in: textView, selection: selection)
    }

    func toggleStrikethrough() {
        guard let textView else { return }
        let selection = textView.selectedRange
        let current = currentAttributeValue(
            for: .strikethroughStyle,
            in: textView,
            selection: selection
        ) as? Int ?? 0
        let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        applyAttribute(.strikethroughStyle, value: newValue, in: textView, selection: selection)
    }

    func setTextStyle(_ style: NoteTextStyle) {
        guard let textView else { return }

        let font = fonts.font(for: style)
        let nsText = textView.text as NSString
        let selection = textView.selectedRange
        let paragraphRange: NSRange

        if selection.length > 0 {
            paragraphRange = nsText.paragraphRange(for: selection)
        } else {
            paragraphRange = nsText.lineRange(
                for: NSRange(location: min(selection.location, nsText.length), length: 0)
            )
        }

        textView.textStorage.beginEditing()
        if paragraphRange.length > 0 {
            textView.textStorage.addAttribute(.font, value: font, range: paragraphRange)
            textView.textStorage.addAttribute(.paragraphStyle, value: baseParagraphStyle(), range: paragraphRange)
        }
        textView.textStorage.endEditing()

        var attrs = textView.typingAttributes
        attrs[.font] = font
        attrs[.paragraphStyle] = baseParagraphStyle()
        textView.typingAttributes = attrs

        notifyChange()
    }

    func insertChecklist() {
        guard let textView else { return }
        insertListPrefix(textView, prefix: "○\t")
    }

    func insertBullet() {
        guard let textView else { return }
        insertListPrefix(textView, prefix: "•\t")
    }

    func insertNumberedList() {
        guard let textView else { return }

        let nsText = textView.text as NSString
        let cursor = min(textView.selectedRange.location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let previousLineEnd = lineRange.location > 0 ? lineRange.location - 1 : 0

        var nextNumber = 1
        if previousLineEnd > 0 {
            let previousLineRange = nsText.lineRange(for: NSRange(location: previousLineEnd, length: 0))
            let previousLine = nsText.substring(with: previousLineRange)
            if let (number, _) = numberedListPrefix(previousLine) {
                nextNumber = number + 1
            }
        }

        insertListPrefix(textView, prefix: "\(nextNumber).\t")
    }

    func indent() {
        guard let textView else { return }
        adjustIndent(textView, delta: 22)
    }

    func outdent() {
        guard let textView else { return }
        adjustIndent(textView, delta: -22)
    }

    func presentPhotoPicker() {
        presentPhotoVideoPicker()
    }

    @objc func presentPhotoVideoPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker)
    }

    @objc func presentCameraCapture() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.delegate = self
        picker.videoQuality = .typeHigh
        present(picker)
    }

    func presentDocumentScanner() {
        guard VNDocumentCameraViewController.isSupported else { return }

        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        present(scanner)
    }

    func presentFilePicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker)
    }

    func insertMarkupDrawing(_ image: UIImage) {
        insertImageAttachment(image)
    }

    @objc func presentDrawingCanvas() {
        let drawingController = DrawingCanvasViewController()
        drawingController.onInsertDrawing = { [weak self] image in
            self?.insertMarkupDrawing(image)
            self?.focus()
        }
        let navigationController = UINavigationController(rootViewController: drawingController)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController)
    }

    func presentShareSheet() {
        guard let textView else { return }
        let text = textView.attributedText?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }

        let activityController = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = textView
            popover.sourceRect = CGRect(x: textView.bounds.midX, y: 0, width: 1, height: 1)
        }
        present(activityController)
    }

    func insertTable() {
        guard let textView else { return }
        let tableText = "\n\t\n\t\n"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: fonts.body,
            .foregroundColor: UIColor.label,
            .paragraphStyle: tableParagraphStyle(in: textView),
            .backgroundColor: UIColor.secondarySystemGroupedBackground,
        ]
        let content = NSMutableAttributedString(string: tableText, attributes: attrs)
        replaceSelection(in: textView, with: content)
        let firstCellLocation = max(0, textView.selectedRange.location - tableText.utf16.count + 1)
        textView.selectedRange = NSRange(location: firstCellLocation, length: 0)
        textView.typingAttributes = attrs
    }

    func setEditingLocked(_ isLocked: Bool) {
        textView?.isEditable = !isLocked
        textView?.isSelectable = true
        refreshFormatState()
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else { return }

        for result in results {
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                    guard let self, let image = image as? UIImage else { return }
                    DispatchQueue.main.async {
                        self.insertImageAttachment(image)
                    }
                }
                continue
            }

            guard result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { continue }
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
                guard let self, let url else { return }
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)

                do {
                    if FileManager.default.fileExists(atPath: temporaryURL.path) {
                        try FileManager.default.removeItem(at: temporaryURL)
                    }
                    try FileManager.default.copyItem(at: url, to: temporaryURL)
                    DispatchQueue.main.async {
                        self.insertFileCardAttachment(for: temporaryURL)
                    }
                } catch { }
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)

        if let image = info[.originalImage] as? UIImage {
            insertImageAttachment(image)
            return
        }

        if let videoURL = info[.mediaURL] as? URL {
            insertFileCardAttachment(for: videoURL)
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        controller.dismiss(animated: true)
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true)

        for pageIndex in 0..<scan.pageCount {
            insertImageAttachment(scan.imageOfPage(at: pageIndex))
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        urls.forEach { insertFileCardAttachment(for: $0) }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc func handleCheckboxTap(_ gesture: UITapGestureRecognizer) {
        guard let textView, gesture.state == .ended else { return }

        let point = gesture.location(in: textView)
        guard point.x < textView.textContainerInset.left + 44 else { return }
        guard let position = textView.closestPosition(to: point) else { return }

        let offset = textView.offset(from: textView.beginningOfDocument, to: position)
        let nsText = textView.text as NSString
        guard offset <= nsText.length else { return }

        let lineRange = nsText.lineRange(for: NSRange(location: offset, length: 0))
        let line = nsText.substring(with: lineRange)
        guard line.hasPrefix("○\t") || line.hasPrefix("●\t") else { return }

        let isChecked = line.hasPrefix("●\t")
        let replacement = isChecked ? "○" : "●"
        let markerRange = NSRange(location: lineRange.location, length: 1)
        let contentRange = NSRange(location: lineRange.location + 2, length: max(0, lineRange.length - 2))

        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: markerRange, with: NSAttributedString(string: replacement))
        if contentRange.length > 0 {
            textView.textStorage.addAttribute(
                .strikethroughStyle,
                value: isChecked ? 0 : NSUnderlineStyle.single.rawValue,
                range: contentRange
            )
            textView.textStorage.addAttribute(
                .foregroundColor,
                value: isChecked ? UIColor.label : UIColor.secondaryLabel,
                range: contentRange
            )
        }
        textView.textStorage.endEditing()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        notifyChange()
    }

    @objc func handleKeyboardDismissSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended else { return }
        textView?.resignFirstResponder()
    }

    @objc func tbUndo() {
        textView?.undoManager?.undo()
        refreshFormatState()
    }

    @objc func tbRedo() {
        textView?.undoManager?.redo()
        refreshFormatState()
    }

    @objc func tbBold() { toggleBold() }
    @objc func tbItalic() { toggleItalic() }
    @objc func tbUnderline() { toggleUnderline() }
    @objc func tbStrikethrough() { toggleStrikethrough() }
    @objc func tbChecklist() { insertChecklist() }
    @objc func tbBullet() { insertBullet() }
    @objc func tbNumbered() { insertNumberedList() }
    @objc func tbIndent() { indent() }
    @objc func tbOutdent() { outdent() }
    @objc func tbInsertTable() { insertTable() }
    @objc func tbHighlight() { toggleHighlight() }
    @objc func tbLink() { insertLink() }
    @objc func tbAlignLeft() { setAlignment(.left) }
    @objc func tbAlignCenter() { setAlignment(.center) }
    @objc func tbAlignRight() { setAlignment(.right) }
    @objc func tbMoveUp() { moveCurrentLineUp() }
    @objc func tbMoveDown() { moveCurrentLineDown() }
    @objc func tbHorizontalRule() { insertHorizontalRule() }
    @objc func tbDismiss() { textView?.resignFirstResponder() }

    func toggleHighlight() {
        guard let textView else { return }
        let selection = textView.selectedRange
        let current = currentAttributeValue(for: .backgroundColor, in: textView, selection: selection) as? UIColor
        let isActive = (current?.cgColor.alpha ?? 0) > 0.05
        let newColor: UIColor = isActive ? .clear : UIColor.systemYellow.withAlphaComponent(0.35)
        applyAttribute(.backgroundColor, value: newColor, in: textView, selection: selection)
    }

    func insertLink() {
        let alert = UIAlertController(title: "Add Link", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://"
            field.keyboardType = .URL
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  let tv = self.textView else { return }
            let urlString = raw.hasPrefix("http") ? raw : "https://\(raw)"
            guard let url = URL(string: urlString) else { return }
            let sel = tv.selectedRange
            if sel.length > 0 {
                self.applyAttribute(.link, value: url, in: tv, selection: sel)
            } else {
                let linkStr = NSMutableAttributedString(string: urlString, attributes: [
                    .link: url, .font: self.fonts.body,
                ])
                self.replaceSelection(in: tv, with: linkStr)
            }
        })
        present(alert)
    }

    func setAlignment(_ alignment: NSTextAlignment) {
        guard let textView else { return }
        let range = (textView.text as NSString).paragraphRange(for: textView.selectedRange)
        textView.textStorage.beginEditing()
        textView.textStorage.enumerateAttribute(.paragraphStyle, in: range) { value, r, _ in
            let base = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? baseParagraphStyle()
            base.alignment = alignment
            textView.textStorage.addAttribute(.paragraphStyle, value: base, range: r)
        }
        textView.textStorage.endEditing()
        var attrs = textView.typingAttributes
        let style = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? baseParagraphStyle()
        style.alignment = alignment
        attrs[.paragraphStyle] = style
        textView.typingAttributes = attrs
        notifyChange()
    }

    func moveCurrentLineUp() {
        guard let textView else { return }
        let nsText = textView.text as NSString
        let cursor = min(textView.selectedRange.location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        guard lineRange.location > 0 else { return }
        let prevLineRange = nsText.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
        let combined = NSRange(location: prevLineRange.location, length: prevLineRange.length + lineRange.length)
        let curr = textView.attributedText.attributedSubstring(from: lineRange)
        let prev = textView.attributedText.attributedSubstring(from: prevLineRange)
        let replacement = NSMutableAttributedString(attributedString: curr)
        replacement.append(prev)
        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: combined, with: replacement)
        textView.textStorage.endEditing()
        textView.selectedRange = NSRange(location: prevLineRange.location, length: 0)
        notifyChange()
    }

    func moveCurrentLineDown() {
        guard let textView else { return }
        let nsText = textView.text as NSString
        let cursor = min(textView.selectedRange.location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let nextStart = lineRange.location + lineRange.length
        guard nextStart < nsText.length else { return }
        let nextLineRange = nsText.lineRange(for: NSRange(location: nextStart, length: 0))
        let combined = NSRange(location: lineRange.location, length: lineRange.length + nextLineRange.length)
        let curr = textView.attributedText.attributedSubstring(from: lineRange)
        let next = textView.attributedText.attributedSubstring(from: nextLineRange)
        let replacement = NSMutableAttributedString(attributedString: next)
        replacement.append(curr)
        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: combined, with: replacement)
        textView.textStorage.endEditing()
        textView.selectedRange = NSRange(location: lineRange.location + nextLineRange.length, length: 0)
        notifyChange()
    }

    func insertHorizontalRule() {
        guard let textView else { return }
        let attachment = NSTextAttachment()
        attachment.image = renderedDivider(width: attachmentWidth(in: textView))
        attachment.bounds = CGRect(origin: .zero, size: attachment.image?.size ?? .zero)

        let content = NSMutableAttributedString(string: "\n", attributes: defaultAttrs())
        content.append(NSAttributedString(attachment: attachment))
        content.append(NSAttributedString(string: "\n", attributes: defaultAttrs()))
        replaceSelection(in: textView, with: content)
    }


    private func present(_ controller: UIViewController) {
        topViewController(from: textView?.window?.rootViewController)?
            .present(controller, animated: true)
    }

    private func topViewController(from controller: UIViewController?) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }
        if let tabBarController = controller as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(from: presented)
        }
        return controller
    }

    private func currentAttributeValue(
        for key: NSAttributedString.Key,
        in textView: UITextView,
        selection: NSRange
    ) -> Any? {
        if selection.length > 0, selection.location < textView.textStorage.length {
            return textView.textStorage.attribute(key, at: selection.location, effectiveRange: nil)
        }

        return textView.typingAttributes[key]
    }

    private func toggleTrait(
        _ trait: UIFontDescriptor.SymbolicTraits,
        boldFont: UIFont,
        italicFont: UIFont,
        boldItalicFont: UIFont,
        baseFont: UIFont
    ) {
        guard let textView else { return }

        let selection = textView.selectedRange
        let currentFont = currentAttributeValue(for: .font, in: textView, selection: selection) as? UIFont ?? baseFont
        let traits = currentFont.fontDescriptor.symbolicTraits
        let hasTrait = traits.contains(trait)

        let newFont: UIFont
        switch (trait, hasTrait) {
        case (.traitBold, false):
            newFont = traits.contains(.traitItalic) ? boldItalicFont : boldFont
        case (.traitBold, true):
            newFont = traits.contains(.traitItalic) ? italicFont : baseFont
        case (.traitItalic, false):
            newFont = traits.contains(.traitBold) ? boldItalicFont : italicFont
        case (.traitItalic, true):
            newFont = traits.contains(.traitBold) ? boldFont : baseFont
        default:
            newFont = baseFont
        }

        applyAttribute(.font, value: newFont, in: textView, selection: selection)
    }

    private func applyAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        in textView: UITextView,
        selection: NSRange
    ) {
        if selection.length > 0 {
            textView.textStorage.beginEditing()
            textView.textStorage.addAttribute(key, value: value, range: selection)
            textView.textStorage.endEditing()
        }

        var attrs = textView.typingAttributes
        attrs[key] = value
        attrs[.paragraphStyle] = attrs[.paragraphStyle] ?? baseParagraphStyle()
        textView.typingAttributes = attrs

        notifyChange()
    }

    private func refreshFormatState() {
        guard let textView else { return }

        let attrs = effectiveAttributes(in: textView)
        var state = FormatState()

        if let font = attrs[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            state.isBold = traits.contains(.traitBold)
            state.isItalic = traits.contains(.traitItalic)
            state.textStyle = fonts.style(for: font)
        }

        if let underline = attrs[.underlineStyle] as? Int {
            state.isUnderline = underline != 0
        }
        if let strikethrough = attrs[.strikethroughStyle] as? Int {
            state.isStrikethrough = strikethrough != 0
        }
        if let bg = attrs[.backgroundColor] as? UIColor {
            state.isHighlighted = bg.cgColor.alpha > 0.05
        }
        if let para = attrs[.paragraphStyle] as? NSParagraphStyle {
            state.alignment = para.alignment
        }

        state.canUndo = textView.undoManager?.canUndo == true
        state.canRedo = textView.undoManager?.canRedo == true

        formatState = state
        onFormatStateChange?(state)
    }

    private func effectiveAttributes(in textView: UITextView) -> [NSAttributedString.Key: Any] {
        let selection = textView.selectedRange
        if selection.length > 0, selection.location < textView.textStorage.length {
            return textView.textStorage.attributes(at: selection.location, effectiveRange: nil)
        }
        return textView.typingAttributes
    }

    private func handleReturnInList(_ textView: UITextView, at range: NSRange) -> Bool {
        let nsText = textView.text as NSString
        let cursor = range.location
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let line = nsText.substring(with: lineRange)

        if line.hasPrefix("○\t") || line.hasPrefix("●\t") {
            let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                exitList(textView, lineRange: lineRange, prefixLength: 2)
                return true
            }
            insertListContinuation(textView, at: cursor, prefix: "○\t", inheritAttributesFrom: lineRange)
            return true
        }

        if line.hasPrefix("•\t") {
            let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                exitList(textView, lineRange: lineRange, prefixLength: 2)
                return true
            }
            insertListContinuation(textView, at: cursor, prefix: "•\t", inheritAttributesFrom: lineRange)
            return true
        }

        if let (number, prefixLength) = numberedListPrefix(line) {
            let content = String(line.dropFirst(prefixLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                exitList(textView, lineRange: lineRange, prefixLength: prefixLength)
                return true
            }
            insertListContinuation(
                textView,
                at: cursor,
                prefix: "\(number + 1).\t",
                inheritAttributesFrom: lineRange
            )
            return true
        }

        if line.contains("\t") {
            insertTableRowContinuation(textView, at: cursor, inheritAttributesFrom: lineRange)
            return true
        }

        return false
    }

    private func insertTableRowContinuation(
        _ textView: UITextView,
        at cursor: Int,
        inheritAttributesFrom lineRange: NSRange
    ) {
        let attrs = textView.textStorage.length > lineRange.location
            ? textView.textStorage.attributes(at: lineRange.location, effectiveRange: nil)
            : [
                .font: fonts.body,
                .foregroundColor: UIColor.label,
                .paragraphStyle: tableParagraphStyle(in: textView),
                .backgroundColor: UIColor.secondarySystemGroupedBackground,
            ]

        replaceCharacters(
            in: textView,
            range: NSRange(location: cursor, length: 0),
            with: NSAttributedString(string: "\n\t", attributes: attrs)
        )
    }

    private func insertListContinuation(
        _ textView: UITextView,
        at cursor: Int,
        prefix: String,
        inheritAttributesFrom lineRange: NSRange
    ) {
        var attrs = textView.textStorage.length > lineRange.location
            ? textView.textStorage.attributes(at: lineRange.location, effectiveRange: nil)
            : defaultAttrs()
        attrs.removeValue(forKey: .strikethroughStyle)
        attrs[.foregroundColor] = UIColor.label

        let insertion = NSMutableAttributedString(string: "\n", attributes: attrs)
        insertion.append(NSAttributedString(string: prefix, attributes: attrs))
        replaceCharacters(in: textView, range: NSRange(location: cursor, length: 0), with: insertion)
    }

    private func exitList(_ textView: UITextView, lineRange: NSRange, prefixLength: Int) {
        let trimRange = NSRange(location: lineRange.location, length: min(prefixLength, lineRange.length))
        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: trimRange, with: NSAttributedString())
        textView.textStorage.endEditing()
        textView.selectedRange = NSRange(location: lineRange.location, length: 0)
        textView.typingAttributes = defaultAttrs()
        notifyChange()
    }

    private func numberedListPrefix(_ line: String) -> (Int, Int)? {
        let pattern = #"^(\d+)\.\t"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let numberRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        return (Int(String(line[numberRange])) ?? 0, match.range.length)
    }

    private func listParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        style.headIndent = 22
        style.firstLineHeadIndent = 0
        style.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
        return style
    }

    private func tableParagraphStyle(in textView: UITextView) -> NSMutableParagraphStyle {
        let style = baseParagraphStyle()
        let contentWidth = max(220, textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right)
        let columnWidth = contentWidth / 2
        style.tabStops = [NSTextTab(textAlignment: .left, location: columnWidth)]
        style.defaultTabInterval = columnWidth
        style.firstLineHeadIndent = 0
        style.headIndent = 0
        style.paragraphSpacing = 2
        style.lineSpacing = 10
        return style
    }

    private func baseParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 7
        style.paragraphSpacing = 6
        return style
    }

    private func insertListPrefix(_ textView: UITextView, prefix: String) {
        let selection = textView.selectedRange
        let nsText = textView.text as NSString
        let cursor = min(selection.location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let line = nsText.substring(with: lineRange)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: fonts.body,
            .foregroundColor: UIColor.label,
            .paragraphStyle: listParagraphStyle(),
        ]

        if line.hasPrefix(prefix) {
            textView.textStorage.beginEditing()
            let removeRange = NSRange(location: lineRange.location, length: min(prefix.utf16.count, lineRange.length))
            textView.textStorage.replaceCharacters(in: removeRange, with: NSAttributedString())
            textView.textStorage.endEditing()
            textView.selectedRange = NSRange(location: max(0, cursor - prefix.utf16.count), length: 0)
        } else {
            let prefixString = NSAttributedString(string: prefix, attributes: attrs)
            textView.textStorage.beginEditing()
            textView.textStorage.insert(prefixString, at: lineRange.location)
            textView.textStorage.endEditing()
            textView.selectedRange = NSRange(location: cursor + prefix.utf16.count, length: 0)
        }

        textView.typingAttributes = attrs
        notifyChange()
    }

    private func adjustIndent(_ textView: UITextView, delta: CGFloat) {
        let paragraphRange = (textView.text as NSString).paragraphRange(for: textView.selectedRange)

        textView.textStorage.beginEditing()
        textView.textStorage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, range, _ in
            let base = (value as? NSParagraphStyle) ?? baseParagraphStyle()
            guard let mutableStyle = base.mutableCopy() as? NSMutableParagraphStyle else { return }
            mutableStyle.headIndent = max(0, mutableStyle.headIndent + delta)
            mutableStyle.firstLineHeadIndent = max(0, mutableStyle.firstLineHeadIndent + delta)
            textView.textStorage.addAttribute(.paragraphStyle, value: mutableStyle, range: range)
        }
        textView.textStorage.endEditing()

        notifyChange()
    }

    private func insertImageAttachment(_ image: UIImage) {
        guard let textView else { return }

        let attachment = NSTextAttachment()
        attachment.image = preparedImage(image, maxWidth: attachmentWidth(in: textView))
        attachment.bounds = CGRect(origin: .zero, size: attachment.image?.size ?? .zero)

        let attrs = defaultAttrs()
        let content = NSMutableAttributedString(string: "\n", attributes: attrs)
        content.append(NSAttributedString(attachment: attachment))
        content.append(NSAttributedString(string: "\n", attributes: attrs))
        replaceSelection(in: textView, with: content)
    }

    private func insertFileCardAttachment(for url: URL) {
        guard let textView else { return }

        let attachment = NSTextAttachment()
        attachment.image = renderedFileCard(for: url, width: attachmentWidth(in: textView))
        attachment.bounds = CGRect(origin: .zero, size: attachment.image?.size ?? .zero)

        let content = NSMutableAttributedString(string: "\n", attributes: defaultAttrs())
        content.append(NSAttributedString(attachment: attachment))
        content.append(NSAttributedString(string: "\n", attributes: defaultAttrs()))
        replaceSelection(in: textView, with: content)
    }

    private func preparedImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let aspectRatio = image.size.height / max(image.size.width, 1)
        let width = min(maxWidth, image.size.width)
        let height = width * aspectRatio
        let size = CGSize(width: width, height: max(160, height))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let path = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: 18
            )
            path.addClip()
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func renderedFileCard(for url: URL, width: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: 72)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let cardRect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 18)
            UIColor.secondarySystemBackground.setFill()
            path.fill()

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            let icon = UIImage(systemName: iconName(for: url), withConfiguration: symbolConfig)
            let iconRect = CGRect(x: 18, y: 24, width: 24, height: 24)
            UIColor.secondaryLabel.setFill()
            icon?.draw(in: iconRect)

            let titleParagraph = NSMutableParagraphStyle()
            titleParagraph.lineBreakMode = .byTruncatingTail

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: titleParagraph,
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: titleParagraph,
            ]

            let fileName = url.lastPathComponent as NSString
            fileName.draw(
                in: CGRect(x: 54, y: 16, width: size.width - 70, height: 22),
                withAttributes: titleAttributes
            )

            let subtitle = (url.pathExtension.isEmpty ? "Attachment" : url.pathExtension.uppercased()) as NSString
            subtitle.draw(
                in: CGRect(x: 54, y: 40, width: size.width - 70, height: 18),
                withAttributes: subtitleAttributes
            )
        }
    }

    private func renderedEmptyTable(width: CGFloat) -> UIImage {
        let rowHeight: CGFloat = 42
        let rows = 2
        let columns = 2
        let size = CGSize(width: width, height: rowHeight * CGFloat(rows))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let cg = context.cgContext
            cg.setFillColor(UIColor.systemBackground.cgColor)
            cg.fill(rect)
            cg.setStrokeColor(UIColor.separator.withAlphaComponent(0.72).cgColor)
            cg.setLineWidth(1 / UIScreen.main.scale)

            let path = UIBezierPath(rect: rect)
            path.stroke()

            for row in 1..<rows {
                let y = CGFloat(row) * rowHeight
                cg.move(to: CGPoint(x: rect.minX, y: y))
                cg.addLine(to: CGPoint(x: rect.maxX, y: y))
            }

            for column in 1..<columns {
                let x = CGFloat(column) * rect.width / CGFloat(columns)
                cg.move(to: CGPoint(x: x, y: rect.minY))
                cg.addLine(to: CGPoint(x: x, y: rect.maxY))
            }

            cg.strokePath()

            let caretRect = CGRect(x: 14, y: 10, width: 3, height: rowHeight - 20)
            UIColor.tintColor.setFill()
            UIBezierPath(roundedRect: caretRect, cornerRadius: 1.5).fill()
        }
    }

    private func renderedDivider(width: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: 24)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.separator.withAlphaComponent(0.8).cgColor)
            cg.setLineWidth(1 / UIScreen.main.scale)
            let y = size.height / 2
            cg.move(to: CGPoint(x: 0, y: y))
            cg.addLine(to: CGPoint(x: size.width, y: y))
            cg.strokePath()
        }
    }


    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return "doc.richtext"
        case "mov", "mp4", "m4v":
            return "video"
        case "wav", "mp3", "m4a":
            return "waveform"
        default:
            return "doc"
        }
    }

    private func attachmentWidth(in textView: UITextView) -> CGFloat {
        let insets = textView.textContainerInset.left + textView.textContainerInset.right
        return max(220, textView.bounds.width - insets)
    }

    private func replaceSelection(in textView: UITextView, with content: NSMutableAttributedString) {
        replaceCharacters(in: textView, range: textView.selectedRange, with: content)
    }

    private func replaceCharacters(in textView: UITextView, range: NSRange, with content: NSAttributedString) {
        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: range, with: content)
        textView.textStorage.endEditing()
        let newLocation = range.location + content.length
        textView.selectedRange = NSRange(location: newLocation, length: 0)
        textView.typingAttributes = defaultAttrs()
        notifyChange()
    }

    private func notifyChange() {
        guard let textView else { return }
        onChange?(textView.attributedText)
        refreshFormatState()
    }

}

struct AppleNotesEditor: UIViewRepresentable {
    let coordinator: RichTextCoordinator
    var initialText: NSAttributedString? = nil

    func makeCoordinator() -> RichTextCoordinator {
        coordinator
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 18, left: 24, bottom: 64, right: 24)
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.autocorrectionType = .yes
        textView.autocapitalizationType = .sentences
        textView.spellCheckingType = .yes
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.smartInsertDeleteType = .yes
        textView.dataDetectorTypes = [.link]
        textView.tintColor = UIColor(named: "AccentColor") ?? .systemYellow
        textView.keyboardDismissMode = .onDrag
        textView.textDragInteraction?.isEnabled = true
        textView.isFindInteractionEnabled = true
        textView.allowsEditingTextAttributes = true
        if let initialText {
            textView.attributedText = initialText
        } else {
            textView.typingAttributes = context.coordinator.defaultAttrs()
        }

        let checkboxTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(RichTextCoordinator.handleCheckboxTap(_:))
        )
        checkboxTap.delegate = context.coordinator
        textView.addGestureRecognizer(checkboxTap)

        let dismissSwipe = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(RichTextCoordinator.handleKeyboardDismissSwipe(_:))
        )
        dismissSwipe.direction = .down
        dismissSwipe.delegate = context.coordinator
        textView.addGestureRecognizer(dismissSwipe)

        context.coordinator.textView = textView
        context.coordinator.textViewDidChangeSelection(textView)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.attributedText.length == 0, let initialText, initialText.length > 0 {
            uiView.attributedText = initialText
            context.coordinator.onChange?(initialText)
            context.coordinator.textViewDidChangeSelection(uiView)
        }
    }
}
