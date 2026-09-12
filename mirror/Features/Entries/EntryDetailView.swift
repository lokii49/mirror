import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode
    @Query private var insights: [Insight]
    @Query(sort: \Entry.createdAt, order: .reverse) private var allEntries: [Entry]

    let entry: Entry
    var onDone: (() -> Void)? = nil

    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var relatedInsight: Insight? = nil
    @State private var displayedWordCount: Int = 0
    private var writingFontDesign: Font.Design {
        WritingFontChoice.resolved(entryDefault: entry.fontChoice, override: nil).swiftUIDesign
    }

    private var onThisDayEntries: [Entry] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: entry.createdAt)
        let thisYear = cal.component(.year, from: entry.createdAt)
        return allEntries.filter { other in
            guard other.id != entry.id else { return false }
            let otherComps = cal.dateComponents([.year, .month, .day], from: other.createdAt)
            return otherComps.month == comps.month
                && otherComps.day == comps.day
                && otherComps.year != thisYear
        }
    }

    private var moodLabel: String? {
        let mood = entry.mood
        guard let mood, !mood.isEmpty else { return nil }
        return MirrorTheme.localizedMoodName(for: mood)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Main entry card
                VStack(alignment: .leading, spacing: 16) {
                    // Date header
                    VStack(alignment: .leading, spacing: 4) {
                        if displayMode == .sentinel {
                            Text(entry.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).uppercased())
                                .font(MirrorTheme.mono(15, weight: .bold))
                                .foregroundStyle(MirrorTheme.textPrimary)
                                .kerning(0.4)
                        } else {
                            Text(entry.createdAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(MirrorTheme.textPrimary)
                        }

                        HStack(spacing: 6) {
                            Text(entry.createdAt, format: .dateTime.hour().minute())
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(MirrorTheme.textTertiary)
                            if let label = moodLabel {
                                Text("·")
                                    .foregroundStyle(MirrorTheme.textTertiary)
                                Text(displayMode == .sentinel ? label.uppercased() : label)
                                    .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .semibold) : .system(size: 13, weight: .medium))
                                    .kerning(displayMode == .sentinel ? 0.2 : 0)
                                    .foregroundStyle(MirrorTheme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        MirrorTheme.inkRaised,
                                        in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                                    )
                                    .overlay {
                                        if displayMode == .sentinel {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1)
                                        }
                                    }
                            }
                            Text("·")
                                .foregroundStyle(MirrorTheme.textTertiary)
                            Text(displayedWordCount == 1 ? "1 word" : "\(displayedWordCount) words")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(MirrorTheme.textTertiary)
                        }
                    }

                    Divider().overlay(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.25) : MirrorTheme.inkBorder)

                    if entry.textDecryptionFailed {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Encrypted entry unavailable")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(MirrorTheme.textPrimary)
                            Text("This entry still exists, but this device does not have the encryption key needed to read its text.")
                                .font(.system(size: 15))
                                .foregroundStyle(MirrorTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !entry.photoDataArray.isEmpty || !allPhotoTokens(in: entry.text).isEmpty || !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        InlineEntryContent(text: entry.text, textStyleData: entry.textStyleData, inlineStyleData: entry.inlineStyleData, photoDataArray: entry.photoDataArray, fontChoice: entry.fontChoice)
                    } else {
                        Text("No text")
                            .font(.system(size: 17, weight: .regular, design: writingFontDesign))
                            .foregroundStyle(MirrorTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !entry.voiceNotes.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(entry.voiceNotes.indices, id: \.self) { index in
                                let note = entry.voiceNotes[index]
                                VoiceNoteAttachmentView(
                                    data: note.data,
                                    duration: note.duration,
                                    title: String(localized: "Voice note \(index + 1)"),
                                    transcript: note.transcript,
                                    languageName: note.languageName,
                                    transcriptionFailed: index == 0 && entry.voiceNoteTranscriptionFailed
                                )
                            }
                        }
                    }

                    if !entry.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(entry.tags, id: \.self) { tag in
                                    Text("#\(MirrorTheme.localizedTagName(for: tag))")
                                        .font(displayMode == .sentinel ? MirrorTheme.mono(11.5, weight: .medium) : .system(size: 12, weight: .medium))
                                        .foregroundStyle(MirrorTheme.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            MirrorTheme.inkRaised,
                                            in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
                                        )
                                        .overlay {
                                            if displayMode == .sentinel {
                                                RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1)
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(22)
                .themedHeroCard(cornerRadius: 22)

                // "mirror noticed" card — only if a past insight references this entry
                if let insight = relatedInsight {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(displayMode == .sentinel ? "SIGNAL DETECTED" : "mirror noticed", systemImage: displayMode == .sentinel ? "waveform" : "sparkles")
                            .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 11, weight: .bold))
                            .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
                            .tracking(0.8)
                        Text(insight.content)
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .lineSpacing(5)
                            .foregroundStyle(MirrorTheme.textPrimary)
                            .italic()
                    }
                    .padding(18)
                    .themedCard(cornerRadius: 18, classicBase: .elevated)
                    .glowShadow(color: displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet, radius: 20)
                }

                // On This Day
                if !onThisDayEntries.isEmpty {
                    OnThisDaySection(entries: onThisDayEntries, referenceDate: entry.createdAt)
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(MirrorTheme.bgBase)
        .task(id: entry.id) {
            let text = entry.text
            let prefix = text
                .components(separatedBy: .whitespacesAndNewlines)
                .prefix(6)
                .joined(separator: " ")
            relatedInsight = insights.first { insight in
                insight.content.localizedCaseInsensitiveContains(prefix)
            }
            displayedWordCount = strippedWordCount(text)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button(displayMode == .sentinel ? "EDIT" : "Edit") { showEditor = true }
                        .font(displayMode == .sentinel ? MirrorTheme.mono(13, weight: .bold) : .system(size: 16, weight: .medium))
                        .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor)
                        .disabled(entry.textDecryptionFailed)

                    Menu {
                        Button(
                            entry.isPinned ? "Unpin Entry" : "Pin Entry",
                            systemImage: entry.isPinned ? "pin.slash" : "pin"
                        ) {
                            entry.isPinned.toggle()
                            try? modelContext.save()
                        }
                        Button("Share as text") { shareText() }
                        Button("Export as PDF") { sharePDF() }
                        Button("Delete Entry", systemImage: "trash", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor)
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showEditor) {
            WriteView(entry: entry, autoFocus: true, showsBackButton: true)
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
                onDone?()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func shareText() {
        let dateStr = entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        let shareText = "\(dateStr)\n\n\(entry.text)"
        let av = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }

    private func sharePDF() {
        guard let url = makePDF() else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }

    private func makePDF() -> URL? {
        let dateStr = entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        var html = "<html><body style='font-family: Georgia, serif; font-size: 15px; margin: 40px; line-height: 1.8;'>"
        html += "<p style='color: #888; font-size: 12px; font-family: -apple-system; letter-spacing: 0.05em;'>\(dateStr)"
        if let mood = entry.mood { html += " · \(MirrorTheme.localizedMoodName(for: mood))" }
        html += "</p><hr style='border-color: #eee;'>"
        let escaped = entry.text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
        html += "<p style='line-height: 1.8;'>\(escaped)</p></body></html>"
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let pageSize = CGSize(width: 595, height: 842) // A4
        let margin: CGFloat = 57
        let printable = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        renderer.setValue(NSValue(cgRect: CGRect(origin: .zero, size: pageSize)), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, CGRect(origin: .zero, size: pageSize), nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirror-entry-\(entry.id.uuidString.prefix(8)).pdf")
        try? (data as Data).write(to: url)
        return url
    }
}

// MARK: - On This Day

private struct OnThisDaySection: View {
    let entries: [Entry]
    let referenceDate: Date
    @Environment(\.appDisplayMode) private var displayMode

    private func writingFontDesign(for entry: Entry) -> Font.Design {
        WritingFontChoice.resolved(entryDefault: entry.fontChoice, override: nil).swiftUIDesign
    }

    private var dayMonthLabel: String {
        referenceDate.formatted(.dateTime.month(.wide).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(displayMode == .sentinel ? "ON THIS DAY" : "On this day", systemImage: "calendar.badge.clock")
                .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 12, weight: .bold))
                .foregroundStyle(MirrorTheme.textTertiary)
                .tracking(0.6)
                .padding(.horizontal, 4)

            ForEach(entries.prefix(3)) { past in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(past.createdAt, format: .dateTime.year())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
                        if let mood = past.mood {
                            Text("·")
                                .foregroundStyle(MirrorTheme.textTertiary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(MirrorTheme.moodColor(for: mood))
                                    .frame(width: 6, height: 6)
                                Text(MirrorTheme.localizedMoodName(for: mood))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(MirrorTheme.textSecondary)
                            }
                        }
                        Spacer()
                        Text(past.createdAt, format: .dateTime.hour().minute())
                            .font(.system(size: 11))
                            .foregroundStyle(MirrorTheme.textTertiary)
                    }
                    let preview = past.text
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .first ?? ""
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 14, weight: .regular, design: writingFontDesign(for: past)))
                            .foregroundStyle(MirrorTheme.textSecondary)
                            .lineLimit(3)
                            .lineSpacing(4)
                    }
                }
                .padding(14)
                .themedCard(cornerRadius: 16)
            }
        }
    }
}

private struct InlineEntryContent: View {
    let text: String
    let textStyleData: Data?
    let inlineStyleData: Data?
    let photoDataArray: [Data]
    let fontChoice: String?
    @Environment(\.appDisplayMode) private var displayMode

    private var paragraphStyles: [NoteParagraphTextStyle] {
        guard let textStyleData,
              let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: textStyleData) else {
            return []
        }
        return document.paragraphStyles
    }

    private var fontChoices: [String] {
        guard let textStyleData,
              let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: textStyleData) else {
            return []
        }
        return document.fontChoices ?? []
    }

    private var inlineRanges: [InlineStyleRange] {
        guard let inlineStyleData,
              let document = try? JSONDecoder().decode(InlineStyleDocument.self, from: inlineStyleData) else {
            return []
        }
        return document.ranges
    }

    private var indentLevels: [Int] {
        guard let textStyleData,
              let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: textStyleData) else {
            return []
        }
        return document.indentLevels ?? []
    }

    /// Ordinal for a numbered-list paragraph at `index`, restarting per indent
    /// level so a nested sub-list reads 1, 2 instead of continuing the parent's
    /// count — same rule `NoteEditorTextView`'s renderer and
    /// `MarkdownExportService` use, kept in sync so a number doesn't change
    /// depending on which surface shows it.
    private func listMarker(for style: NoteParagraphTextStyle, level: Int, index: Int) -> String {
        switch style {
        case .bulletedList: return level == 0 ? "•" : (level == 1 ? "◦" : "▸")
        case .dashedList:    return level == 1 ? "·" : "–"
        case .numberedList:  return "\(numberedOrdinal(at: index))."
        default:             return ""
        }
    }

    private func numberedOrdinal(at index: Int) -> Int {
        var counters: [Int: Int] = [:]
        var result = 1
        for i in 0...index {
            guard paragraphStyles.indices.contains(i), paragraphStyles[i] == .numberedList else {
                counters.removeAll()
                continue
            }
            let level = indentLevels.indices.contains(i) ? indentLevels[i] : 0
            counters = counters.filter { $0.key <= level }
            let next = (counters[level] ?? 0) + 1
            counters[level] = next
            if i == index { result = next }
        }
        return result
    }

    private func writingFontUIDesign(at index: Int) -> UIFontDescriptor.SystemDesign {
        let override = fontChoices.indices.contains(index) ? fontChoices[index] : nil
        return WritingFontChoice.resolved(entryDefault: fontChoice, override: override).uiDesign
    }

    private var displayLines: [String] {
        text.components(separatedBy: .newlines)
    }

    /// Cumulative UTF-16 (NSString) offset of `displayLines[index]`'s start —
    /// the same coordinate space `InlineStyleRange.location` was recorded in
    /// (paragraph breaks = newlines, one line here per paragraph there).
    private func paragraphStartOffset(at index: Int) -> Int {
        var offset = 0
        for i in 0..<index where displayLines.indices.contains(i) {
            offset += (displayLines[i] as NSString).length + 1  // +1 for the newline
        }
        return offset
    }

    private func designedFont(size: CGFloat, weight: UIFont.Weight, design: UIFontDescriptor.SystemDesign) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Bridges to `AttributedString` so `Text` renders bold/italic/underline/
    /// strikethrough/highlight/link runs that `styledText(for:at:)`'s plain
    /// `Text(line)` used to silently drop — the read view previously ignored
    /// every inline style `inlineStyleData` stores, matching characters only
    /// against paragraph-level style.
    /// `raw` is the *full* paragraph text (matching `InlineStyleRange`'s
    /// coordinate space) — `dropPrefixCount` trims a legacy markdown-ish
    /// prefix (e.g. "### ") off the front of the *result*, after ranges are
    /// applied against the untrimmed offsets, since that prefix isn't present
    /// in `paragraphStartOffset`'s count for newer (non-legacy) entries. In
    /// practice legacy-prefixed entries predate inlineStyleData entirely, so
    /// this is defensive rather than a case that actually occurs.
    private func styledLine(_ raw: String, paragraphStart: Int, baseFont: UIFont, dropPrefixCount: Int = 0) -> AttributedString {
        let ns = raw as NSString
        let mutable = NSMutableAttributedString(string: raw, attributes: [.font: baseFont])
        guard !inlineRanges.isEmpty, ns.length > 0 else {
            return trimmedPrefix(AttributedString(mutable), count: dropPrefixCount)
        }

        let paragraphEnd = paragraphStart + ns.length
        let highlightColors = HighlightPalette.colors(for: displayMode)

        for range in inlineRanges {
            let start = max(range.location, paragraphStart)
            let end = min(range.location + range.length, paragraphEnd)
            guard end > start else { continue }
            let localRange = NSRange(location: start - paragraphStart, length: end - start)
            guard localRange.location >= 0, NSMaxRange(localRange) <= ns.length else { continue }

            if range.bold || range.italic {
                var font = baseFont
                if range.bold { font = font.withTrait(.traitBold, add: true) }
                if range.italic { font = font.withTrait(.traitItalic, add: true) }
                mutable.addAttribute(.font, value: font, range: localRange)
            }
            if range.underline {
                mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: localRange)
            }
            if range.strikethrough {
                mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: localRange)
            }
            if let idx = range.highlightIndex, idx < highlightColors.count {
                mutable.addAttribute(.backgroundColor, value: UIColor(highlightColors[idx]), range: localRange)
            }
            if let url = validatedLinkURL(from: range.linkURL) {
                mutable.addAttribute(.link, value: url, range: localRange)
            }
        }
        return trimmedPrefix(AttributedString(mutable), count: dropPrefixCount)
    }

    private func trimmedPrefix(_ attr: AttributedString, count: Int) -> AttributedString {
        guard count > 0, let idx = attr.characters.index(attr.startIndex, offsetBy: count, limitedBy: attr.endIndex) else {
            return attr
        }
        return AttributedString(attr[idx...])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                if let photoIndex = inlinePhotoIndex(from: line.trimmingCharacters(in: .whitespaces)),
                   photoIndex < photoDataArray.count,
                   let uiImage = UIImage(data: photoDataArray[photoIndex]) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                        .padding(.vertical, 4)
                } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    styledText(for: line, at: index)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func styledText(for line: String, at index: Int) -> some View {
        let style = paragraphStyles.indices.contains(index) ? paragraphStyles[index] : legacyStyle(for: line)
        let displayLine = lineWithoutLegacyPrefix(line)
        let dropCount = line.count - displayLine.count
        let paragraphStart = paragraphStartOffset(at: index)
        if style == .title {
            let font = designedFont(size: 30, weight: .bold, design: .default)
            Text(styledLine(line, paragraphStart: paragraphStart, baseFont: font, dropPrefixCount: dropCount))
        } else if style == .heading {
            let font = designedFont(size: 22, weight: .bold, design: .default)
            Text(styledLine(line, paragraphStart: paragraphStart, baseFont: font, dropPrefixCount: dropCount))
        } else if style == .subheading {
            let font = designedFont(size: 17, weight: .semibold, design: .default)
            Text(styledLine(line, paragraphStart: paragraphStart, baseFont: font, dropPrefixCount: dropCount))
                .foregroundStyle(.secondary)
        } else if style == .monospaced {
            let font = designedFont(size: 16, weight: .regular, design: .monospaced)
            Text(styledLine(line, paragraphStart: paragraphStart, baseFont: font, dropPrefixCount: dropCount))
        } else if style == .blockQuote {
            let font = designedFont(size: 17, weight: .regular, design: writingFontUIDesign(at: index))
            Text(styledLine(line, paragraphStart: paragraphStart, baseFont: font, dropPrefixCount: dropCount))
                .foregroundStyle(.secondary)
                .lineSpacing(6)
                .padding(.leading, 16)
        } else if style == .checklistUnchecked || style == .checklistChecked {
            let font = designedFont(size: 17, weight: .regular, design: writingFontUIDesign(at: index))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(style == .checklistChecked ? "✓" : "○")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(style == .checklistChecked ? .tertiary : .secondary)
                    .frame(width: 24, alignment: .center)
                Text(styledLine(line, paragraphStart: paragraphStart, baseFont: font, dropPrefixCount: dropCount))
                    .foregroundStyle(style == .checklistChecked ? .tertiary : .primary)
                    .strikethrough(style == .checklistChecked, color: .secondary)
            }
        } else if style == .bulletedList || style == .dashedList || style == .numberedList {
            // Previously fell through to the plain-body `else` below — bulleted,
            // dashed, and numbered paragraphs rendered as unmarked plain text
            // here even though the editor shows glyphs/numbers and indent for
            // them. Markers/indent match NoteEditorTextView's; numbering uses
            // the same per-level-restart rule as `numberedOrdinal(at:)`.
            let font = designedFont(size: 17, weight: .regular, design: writingFontUIDesign(at: index))
            let level = indentLevels.indices.contains(index) ? indentLevels[index] : 0
            let marker = listMarker(for: style, level: level, index: index)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(marker)
                    .font(.system(size: style == .numberedList ? 17 : 20, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: style == .numberedList ? .trailing : .center)
                Text(styledLine(line, paragraphStart: paragraphStart, baseFont: font, dropPrefixCount: dropCount))
                    .foregroundStyle(MirrorTheme.textPrimary)
            }
            .padding(.leading, CGFloat(level) * 20)
        } else {
            let font = designedFont(size: 17, weight: .regular, design: writingFontUIDesign(at: index))
            Text(styledLine(line, paragraphStart: paragraphStart, baseFont: font))
                .foregroundStyle(MirrorTheme.textPrimary)
                .lineSpacing(6)
        }
    }

    private func lineWithoutLegacyPrefix(_ line: String) -> String {
        if line.hasPrefix("### ") { return String(line.dropFirst(4)) }
        if line.hasPrefix("## ") { return String(line.dropFirst(3)) }
        if line.hasPrefix("# ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
        if line.hasPrefix("○ ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("✓ ") { return String(line.dropFirst(2)) }
        return line
    }

    private func legacyStyle(for line: String) -> NoteParagraphTextStyle {
        if line.hasPrefix("### ") { return .subheading }
        if line.hasPrefix("## ") { return .heading }
        if line.hasPrefix("# ") { return .title }
        if line.hasPrefix("    ") { return .monospaced }
        if line.hasPrefix("✓ ") { return .checklistChecked }
        if line.hasPrefix("○ ") { return .checklistUnchecked }
        return .body
    }
}
