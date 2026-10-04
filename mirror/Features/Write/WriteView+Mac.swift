#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import ImageIO

// The Mac Write screen's chrome, built to the approved design: a 52 pt toolbar, a 680 pt
// editor column with the date line above and mood/tag chips below, and a status bar. The
// behavior behind every control is WriteView's existing logic.

extension WriteView {

    // MARK: - Entry date

    /// The date and time of the entry. Changes apply as they are made, through the same
    /// `entryDate` the save reads.
    var macDatePopover: some View {
        MacEntryDatePopover(date: $entryDate) { showDatePicker = false }
    }

    // MARK: - Toolbar

    var macToolbar: some View {
        HStack(spacing: 6) {
            if entry != nil {
                // Editing an existing entry in the reader pane: the way back to the reader.
                macIconButton("chevron-left", label: "Back") { saveAndDismiss() }
                    .help("Back to the entry. Saves your changes (Esc leaves without saving).")
            } else if macStandaloneWindow {
                // A window of its own: room for the traffic lights instead of a sidebar button.
                Color.clear.frame(width: 56, height: 1)
            } else {
                macIconButton("sidebar", label: "Hide sidebar") {
                    NotificationCenter.default.post(name: .mirrorMacToggleSidebar, object: nil)
                }
            }

            Button { showDatePicker = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry == nil ? LocalizedStringKey("New entry") : LocalizedStringKey("Edit entry"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MacTokens.ink)
                        .lineLimit(1)
                    // In the reader pane there is no room for the date; the line above the text shows it.
                    if entry == nil {
                        Text(noteDate, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 11.5))
                            .foregroundStyle(MacTokens.secondaryInk)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Change date")
            .help("Change the entry's date and time")
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) { macDatePopover }

            Spacer(minLength: 4)

            // B / I / U / Aa
            HStack(spacing: 0) {
                formatCell(width: 32) {
                    Text("B").font(.system(size: 13, weight: .bold))
                } isOn: { activeInlineStyles.bold } action: { applyTextCommand(.bold) }
                .accessibilityLabel("Bold")
                .help("Bold")

                formatDivider
                formatCell(width: 32) {
                    Text("I").font(.custom("Georgia", size: 13).italic())
                } isOn: { activeInlineStyles.italic } action: { applyTextCommand(.italic) }
                .accessibilityLabel("Italic")
                .help("Italic")

                formatDivider
                formatCell(width: 32) {
                    Text("U").font(.system(size: 13)).underline()
                } isOn: { activeInlineStyles.underline } action: { applyTextCommand(.underline) }
                .accessibilityLabel("Underline")
                .help("Underline")

                formatDivider
                formatCell(width: 40) {
                    Text("Aa").font(.system(size: 12))
                } isOn: { showFormattingPanel } action: { showFormattingPanel.toggle() }
                .accessibilityLabel("Text formatting")
                .help("Text formatting")
                .popover(isPresented: $showFormattingPanel, arrowEdge: .bottom) {
                    FormattingPanelView(state: panelState, presentation: .popover)
                        .frame(width: 600, height: 350)
                        .environment(\.appDisplayMode, displayMode)
                }
            }
            .background(MacTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(MacTokens.controlBorder, lineWidth: 1) }

            Rectangle().fill(MacTokens.controlBorder).frame(width: 1, height: 20).padding(.horizontal, 6)

            Menu {
                macMoodMenuItems
            } label: {
                MacIcon(name: "smile", size: 17)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(MacTokens.controlInk)
            .accessibilityLabel("Mood")
            .help("Mood")

            macIconButton("tag", label: "Add tag") {
                showTagInput = true
            }
            macIconButton("image", label: "Add photo") {
                macChoosePhoto()
            }
            macIconButton("mic", label: "Record voice note") {
                toggleInlineRecording()
            }

            Button { presentTalkItOut() } label: {
                Text("Talk it out")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(MacTokens.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(MacTokens.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(MacTokens.controlBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .fixedSize()
            .help("Talk it out")
        }
        .padding(.horizontal, 16)
        .frame(height: MacTokens.chromeHeight)
        .background(MacTokens.windowBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(MacTokens.divider).frame(height: 1) }
    }

    private func macIconButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MacIcon(name: icon, size: 17)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(MacHoverButtonStyle())
        .foregroundStyle(MacTokens.controlInk)
        .accessibilityLabel(label)
        .help(label)
    }

    private var formatDivider: some View {
        Rectangle().fill(MacTokens.segmentDivider).frame(width: 1, height: 26)
    }

    private func formatCell<Label: View>(width: CGFloat, @ViewBuilder label: () -> Label, isOn: () -> Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(isOn() ? MacTokens.accent : MacTokens.ink)
                .frame(width: width, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(MacHoverButtonStyle())
        .accessibilityAddTraits(isOn() ? .isSelected : [])
    }

    @ViewBuilder
    private var macMoodMenuItems: some View {
        Button {
            detectMoodWithMirror()
        } label: {
            Label(isDetectingMood ? "Detecting..." : "Mirror suggests", systemImage: "sparkles")
        }
        .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDetectingMood)
        Divider()
        ForEach(MirrorTheme.moodOptions, id: \.self) { mood in
            Button {
                moodWasSuggested = false
                viewModel.selectedMood = viewModel.selectedMood == mood ? nil : mood
            } label: {
                Text(MirrorTheme.localizedMoodName(for: mood))
            }
        }
        if viewModel.selectedMood != nil {
            Divider()
            Button("Clear mood") {
                moodWasSuggested = false
                viewModel.selectedMood = nil
            }
        }
    }

    // MARK: - Editor column

    /// "WEDNESDAY · 30 SEPTEMBER · 9:42 AM"
    var macDateLine: some View {
        let weekday = noteDate.formatted(.dateTime.weekday(.wide))
        let dayMonth = noteDate.formatted(.dateTime.day().month(.wide))
        let time = noteDate.formatted(.dateTime.hour().minute())
        return Text("\(weekday) · \(dayMonth) · \(time)".uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(MacTokens.secondaryInk)
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mood chip, tag chips and the suggestion hint, under the text.
    var macChipsRow: some View {
        ViewThatFits(in: .horizontal) {
            macChips
            ScrollView(.horizontal) { macChips }
                .scrollIndicators(.hidden)
                .frame(height: 26)
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var macChips: some View {
        HStack(spacing: 10) {
            if let mood = viewModel.selectedMood {
                Text(MirrorTheme.localizedMoodName(for: mood))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(MacTokens.accent, in: Capsule())
            }
            ForEach(entryTags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text("#\(MirrorTheme.localizedTagName(for: tag))")
                        .font(.system(size: 12.5))
                    Button {
                        entryTags.removeAll { $0 == tag }
                        if entry == nil { saveDraftToStorage() }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tag")
                }
                .foregroundStyle(MacTokens.controlInk)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(MacTokens.surface, in: Capsule())
                .overlay { Capsule().stroke(MacTokens.controlBorder, lineWidth: 1) }
            }
            if showTagInput {
                TextField("tag", text: $tagText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .frame(width: 90)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(MacTokens.surface, in: Capsule())
                    .overlay { Capsule().stroke(MacTokens.accent, lineWidth: 1) }
                    .onSubmit {
                        commitTag()
                        showTagInput = false
                    }
                    .focused($tagFieldFocused)
                    .onAppear { DispatchQueue.main.async { tagFieldFocused = true } }
            }
            if viewModel.selectedMood != nil, moodWasSuggested {
                Text("Mood suggested from your entry. Change it any time.")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTokens.secondaryInk)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Photos

    /// Thumbnails of the attached photos and the drop zone, under the chips.
    var macPhotosRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(photoDataArray.indices, id: \.self) { index in
                    MacPhotoTile(
                        data: photoDataArray[index],
                        onOpen: { fullscreenPhotoIndex = index },
                        onRemove: { macRemovePhoto(at: index) }
                    )
                }
                MacPhotoDropZone(onChoose: { macChoosePhoto() }, onData: { macAttachPhoto(data: $0) })
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 92)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opens a file chooser and attaches the chosen image, the same way the iOS picker does.
    func macChoosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "image" : url.pathExtension)
            try FileManager.default.copyItem(at: url, to: tempURL)
            handlePickedPhoto(.success(tempURL))
        } catch {
            handlePickedPhoto(.failure(error))
        }
    }

    /// Attaches image data that arrived by drop or paste.
    func macAttachPhoto(data: Data) {
        isAttachingPhoto = true
        Task {
            let prepared = await Task.detached(priority: .userInitiated) { preparedInlinePhotoData(from: data) }.value
            let index = photoDataArray.count
            photoDataArray.append(prepared)
            viewModel.text = textWithInlinePhotoToken(viewModel.text, at: index)
            isAttachingPhoto = false
        }
    }

    func macRemovePhoto(at index: Int) {
        guard photoDataArray.indices.contains(index) else { return }
        let body = NoteEditorCodec.splitTrailingPhotoTokens(viewModel.text).body
        photoDataArray.remove(at: index)
        viewModel.text = NoteEditorCodec.appendingPhotoTokens(to: body, count: photoDataArray.count)
        if entry == nil { saveDraftToStorage() }
    }

    // MARK: - Status bar

    var macStatusBar: some View {
        HStack(spacing: 14) {
            Text("\(viewModel.wordCount) words")
                .font(.system(size: 12))
                .foregroundStyle(MacTokens.secondaryInk)
            if entry == nil, hasDraftContent {
                Text("Draft saved")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTokens.secondaryInk)
            }
            Spacer(minLength: 0)
            Text("⌘↩ to save")
                .font(.system(size: 12))
                .foregroundStyle(MacTokens.secondaryInk)
            Button {
                if entry == nil { saveDraft() } else { saveAndDismiss() }
            } label: {
                Text("Save entry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .frame(height: 30)
                    .background(MacTokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(hasDraftContent ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!hasDraftContent)
            .accessibilityLabel("Save entry")
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .overlay(alignment: .top) { Rectangle().fill(MacTokens.divider).frame(height: 1) }
        .background(MacTokens.windowBackground)
    }
}

/// The system draws a soft band under a bar that overlaps scrolling content (macOS 26). The board
/// has a flat toolbar over a flat background, so the effect is turned off.
struct MacNoScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}

/// Centers the scrolling content in the board's 680 pt column (plus the 20 pt side padding
/// every child already has).
struct MacEditorColumn: ViewModifier {
    @AppStorage(MacPrefs.widthKey) private var lineWidth = MacPrefs.LineWidth.comfortable.rawValue

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: MacPrefs.lineWidth(lineWidth).column + 40)
            .frame(maxWidth: .infinity)
    }
}

/// One attached photo: a 132 x 92 thumbnail, opened on click, removable from its menu or the
/// hover button.
struct MacPhotoTile: View {
    let data: Data
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    MacTokens.surface
                }
            }
            .frame(width: 132, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MacTokens.controlBorder, lineWidth: 1) }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(5)
                .accessibilityLabel("Remove photo")
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { Button("Remove photo", role: .destructive, action: onRemove) }
        .task(id: data.count) { image = Self.thumbnail(from: data) }
        .accessibilityLabel("Photo")
        .accessibilityAddTraits(.isButton)
    }

    private static func thumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}

/// "Drop a photo or paste one": a dashed tile that also opens the file chooser on click.
struct MacPhotoDropZone: View {
    let onChoose: () -> Void
    let onData: (Data) -> Void
    @State private var targeted = false

    var body: some View {
        Button(action: onChoose) {
            Text("Drop a photo\nor paste one")
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .foregroundStyle(MacTokens.secondaryInk)
                .frame(width: 132, height: 92)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(targeted ? MacTokens.accent : MacTokens.controlBorder,
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.image, .fileURL], isTargeted: $targeted) { providers in
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        if let data { DispatchQueue.main.async { onData(data) } }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url, let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                            DispatchQueue.main.async { onData(data) }
                        }
                    }
                }
            }
            return true
        }
        .accessibilityLabel("Add a photo")
    }
}

/// A month calendar in the app's own style for choosing an entry's day and time: quick chips for
/// today and yesterday, a dot under every day that already has an entry, future days off, and a
/// time field with a way back to now. The day keeps the time already chosen, and the result never
/// lands in the future.
struct MacEntryDatePopover: View {
    @Binding var date: Date
    let onDone: () -> Void

    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var month: Date
    @State private var daysWithEntries: Set<Date> = []
    @FocusState private var doneFocused: Bool
    private let calendar = Calendar.current

    init(date: Binding<Date>, onDone: @escaping () -> Void) {
        _date = date
        self.onDone = onDone
        _month = State(initialValue: Self.startOfMonth(date.wrappedValue))
    }

    static func startOfMonth(_ day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
    }

    /// `day`'s date with `time`'s hour and minute, held back to `now` if that is later.
    static func combining(day: Date, time: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let t = calendar.dateComponents([.hour, .minute], from: time)
        let merged = calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
        return min(merged, now)
    }

    private var today: Date { calendar.startOfDay(for: Date()) }
    private var canGoForward: Bool { Self.startOfMonth(today) > month }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quickChips
            VStack(spacing: 4) {
                weekdayRow
                dayGrid
            }
            Rectangle().fill(MacTokens.divider).frame(height: 1)
            timeRow
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .frame(height: 28)
                        .background(MacTokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .focused($doneFocused)
            }
        }
        .padding(16)
        .frame(width: 300)
        // Without this the popover opens with the hour field selected, which looks like an edit in progress.
        .onAppear {
            doneFocused = true
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .background(MacTokens.surface)
        .task(id: entries.count) {
            daysWithEntries = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 4) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacTokens.ink)
            Spacer()
            navButton("chevron-left", label: "Previous month", enabled: true) {
                month = calendar.date(byAdding: .month, value: -1, to: month) ?? month
            }
            navButton("chevron", label: "Next month", enabled: canGoForward) {
                month = calendar.date(byAdding: .month, value: 1, to: month) ?? month
            }
        }
    }

    private func navButton(_ icon: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MacIcon(name: icon, size: 14)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? MacTokens.controlInk : MacTokens.secondaryInk.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
        .help(label)
    }

    private var quickChips: some View {
        HStack(spacing: 8) {
            chip("Today", day: today)
            chip("Yesterday", day: calendar.date(byAdding: .day, value: -1, to: today) ?? today)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: LocalizedStringKey, day: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: day)
        return Button { pick(day) } label: {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? MacTokens.accentInk : MacTokens.controlInk)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(selected ? MacTokens.toggleActiveFill : Color.clear, in: Capsule())
                .overlay { if !selected { Capsule().stroke(MacTokens.controlBorder, lineWidth: 1) } }
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(first + i) % 7])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTokens.secondaryInk)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Six weeks, leading and trailing days of neighbouring months left blank.
    private var weeks: [[Date?]] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for day in range { cells.append(calendar.date(byAdding: .day, value: day - 1, to: month)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var dayGrid: some View {
        VStack(spacing: 2) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        dayCell(week[i])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let isFuture = day > today
            let isSelected = calendar.isDate(day, inSameDayAs: date)
            let isToday = calendar.isDate(day, inSameDayAs: today)
            let hasEntry = daysWithEntries.contains(calendar.startOfDay(for: day))
            Button { pick(day) } label: {
                VStack(spacing: 2) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 13, weight: isSelected || isToday ? .semibold : .regular))
                        .monospacedDigit()
                    Circle()
                        .fill(hasEntry ? (isSelected ? Color.white : MacTokens.accent) : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .foregroundStyle(isSelected ? Color.white : (isFuture ? MacTokens.secondaryInk.opacity(0.4) : MacTokens.ink))
                .frame(width: 34, height: 36)
                .background(isSelected ? MacTokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if isToday && !isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MacTokens.accent.opacity(0.6), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isFuture)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 36)
        }
    }

    private var timeRow: some View {
        HStack(spacing: 10) {
            Text("Time")
                .font(.system(size: 12.5))
                .foregroundStyle(MacTokens.secondaryInk)
            DatePicker("Entry time", selection: Binding(
                get: { date },
                set: { date = Self.combining(day: date, time: $0) }
            ), displayedComponents: .hourAndMinute)
                .datePickerStyle(.stepperField)
                .labelsHidden()
                .fixedSize()
            Spacer(minLength: 0)
            Button {
                date = Date()
                month = Self.startOfMonth(date)
            } label: {
                Text("Now")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTokens.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .overlay { Capsule().stroke(MacTokens.controlBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .help("Set the entry to the current date and time")
        }
    }

    private func pick(_ day: Date) {
        date = Self.combining(day: day, time: date)
        month = Self.startOfMonth(day)
    }
}
#endif
