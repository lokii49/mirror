import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var insights: [Insight]
    @Query(sort: \Entry.createdAt, order: .reverse) private var allEntries: [Entry]

    let entry: Entry
    var onDone: (() -> Void)? = nil

    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var relatedInsight: Insight? = nil
    @State private var displayedWordCount: Int = 0

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
        return mood
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Main entry card
                VStack(alignment: .leading, spacing: 16) {
                    // Date header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.createdAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(MirrorTheme.textPrimary)

                        HStack(spacing: 6) {
                            Text(entry.createdAt, format: .dateTime.hour().minute())
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(MirrorTheme.textTertiary)
                            if let label = moodLabel {
                                Text("·")
                                    .foregroundStyle(MirrorTheme.textTertiary)
                                Text(label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(MirrorTheme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(MirrorTheme.inkRaised, in: Capsule())
                            }
                            Text("·")
                                .foregroundStyle(MirrorTheme.textTertiary)
                            Text("\(displayedWordCount) words")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(MirrorTheme.textTertiary)
                        }
                    }

                    Divider().overlay(MirrorTheme.inkBorder)

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
                        InlineEntryContent(text: entry.text, textStyleData: entry.textStyleData, photoDataArray: entry.photoDataArray)
                    } else {
                        Text("No text")
                            .font(.system(size: 17, weight: .regular, design: .serif))
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
                                    title: "Voice note \(index + 1)",
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
                                    Text("#\(tag)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(MirrorTheme.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(MirrorTheme.inkRaised, in: Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(22)
                .futureSurface(cornerRadius: 22)

                // "mirror noticed" card — only if a past insight references this entry
                if let insight = relatedInsight {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("mirror noticed", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MirrorTheme.violetLight)
                            .tracking(0.8)
                        Text(insight.content)
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .lineSpacing(5)
                            .foregroundStyle(MirrorTheme.textPrimary)
                            .italic()
                    }
                    .padding(18)
                    .inkCard(cornerRadius: 18)
                    .glowShadow(color: MirrorTheme.violet, radius: 20)
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
                    Button("Edit") { showEditor = true }
                        .font(.system(size: 16, weight: .medium))
                        .disabled(entry.textDecryptionFailed)

                    Menu {
                        Button("Share as text") { shareText() }
                        Button("Export as PDF") { sharePDF() }
                        Button("Delete Entry", systemImage: "trash", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
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
        if let mood = entry.mood { html += " · \(mood)" }
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

    private var dayMonthLabel: String {
        referenceDate.formatted(.dateTime.month(.wide).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("On this day", systemImage: "calendar.badge.clock")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MirrorTheme.textTertiary)
                .tracking(0.6)
                .padding(.horizontal, 4)

            ForEach(entries.prefix(3)) { past in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(past.createdAt, format: .dateTime.year())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(MirrorTheme.violetLight)
                        if let mood = past.mood {
                            Text("·")
                                .foregroundStyle(MirrorTheme.textTertiary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(MirrorTheme.moodColor(for: mood))
                                    .frame(width: 6, height: 6)
                                Text(mood)
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
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundStyle(MirrorTheme.textSecondary)
                            .lineLimit(3)
                            .lineSpacing(4)
                    }
                }
                .padding(14)
                .inkSurface(cornerRadius: 16)
            }
        }
    }
}

private struct InlineEntryContent: View {
    let text: String
    let textStyleData: Data?
    let photoDataArray: [Data]

    private var paragraphStyles: [NoteParagraphTextStyle] {
        guard let textStyleData,
              let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: textStyleData) else {
            return []
        }
        return document.paragraphStyles
    }

    private var displayLines: [String] {
        text.components(separatedBy: .newlines)
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
        if style == .title {
            Text(displayLine)
                .font(.system(size: 30, weight: .bold))
        } else if style == .heading {
            Text(displayLine)
                .font(.system(size: 22, weight: .bold))
        } else if style == .subheading {
            Text(displayLine)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
        } else if style == .monospaced {
            Text(displayLine)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
        } else if style == .checklistUnchecked || style == .checklistChecked {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(style == .checklistChecked ? "✓" : "○")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(style == .checklistChecked ? .tertiary : .secondary)
                    .frame(width: 24, alignment: .center)
                Text(displayLine)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(style == .checklistChecked ? .tertiary : .primary)
                    .strikethrough(style == .checklistChecked, color: .secondary)
            }
        } else {
            Text(line)
                .font(.system(.body, design: .serif))
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
