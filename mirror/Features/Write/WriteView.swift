import SwiftUI
import SwiftData

private struct MoodOption: Identifiable, Equatable {
    let symbol: String
    let label: String
    let caption: String
    let color: Color

    var id: String { label }
}

struct WriteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var entry: Entry? = nil

    @State private var viewModel = WriteViewModel()
    @State private var showsEmotionLog = false

    private let moodOptions: [MoodOption] = [
        MoodOption(symbol: "cloud.rain", label: "Heavy", caption: "low energy", color: .indigo),
        MoodOption(symbol: "moon", label: "Quiet", caption: "turned inward", color: .blue),
        MoodOption(symbol: "circle.dashed", label: "Neutral", caption: "steady", color: .gray),
        MoodOption(symbol: "leaf", label: "Calm", caption: "settled", color: .green),
        MoodOption(symbol: "sparkle", label: "Hopeful", caption: "opening up", color: MirrorTheme.primary),
        MoodOption(symbol: "sun.max", label: "Joyful", caption: "light", color: .yellow),
        MoodOption(symbol: "flame", label: "Fired Up", caption: "charged", color: .red),
    ]

    private var initialText: NSAttributedString? {
        guard let entry else { return nil }
        if let data = entry.richTextData, let decoded = decodeRichText(from: data) {
            return bodyTextIncludingTitle(decoded, entry: entry)
        }
        return plainTextIncludingTitle(entry)
    }

    private var noteDate: Date { entry?.createdAt ?? Date() }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            AppleNotesEditor(coordinator: viewModel.coordinator, initialText: initialText)
                .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .navigationTitle(entry == nil ? "New Entry" : "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            writeToolbar
        }
        .sheet(isPresented: $showsEmotionLog) {
            emotionLogPicker
                .presentationDetents([.height(430), .medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            viewModel.configure(entry: entry)
            if let initial = initialText { viewModel.coordinator.onChange?(initial) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                viewModel.coordinator.focus()
            }
        }
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                Text(noteDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                if viewModel.wordCount > 0 {
                    Circle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 3, height: 3)
                    Text("\(viewModel.wordCount) words")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                emotionLogButton
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var emotionLogButton: some View {
        Button { showsEmotionLog = true } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selectedMoodColor.opacity(0.16))
                        .frame(width: 30, height: 30)
                    Image(systemName: selectedMoodSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedMoodColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.selectedMood ?? "Log emotion")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(selectedMoodCaption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 48)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(selectedMoodColor.opacity(viewModel.selectedMood == nil ? 0.18 : 0.38), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Emotion log")
    }

    private var emotionLogPicker: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Button("Clear") { selectMood(nil) }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(viewModel.selectedMood == nil ? Color.secondary.opacity(0.55) : Color.secondary)
                        .disabled(viewModel.selectedMood == nil)

                    Spacer()

                    Button("Done") { showsEmotionLog = false }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MirrorTheme.primary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("How does this entry feel?")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Pick the closest tone. You can change it later.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                moodSpectrum

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    Button {
                        selectMood(nil)
                    } label: {
                        moodTile(
                            symbol: "circle",
                            label: "None",
                            caption: "skip",
                            color: .secondary,
                            selected: viewModel.selectedMood == nil
                        )
                    }

                    ForEach(moodOptions) { mood in
                        Button {
                            selectMood(mood.label)
                        } label: {
                            moodTile(
                                symbol: mood.symbol,
                                label: mood.label,
                                caption: mood.caption,
                                color: mood.color,
                                selected: viewModel.selectedMood == mood.label
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var moodSpectrum: some View {
        GeometryReader { proxy in
            let selectedIndex = selectedMoodIndex
            let width = proxy.size.width
            let step = width / CGFloat(max(moodOptions.count - 1, 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: moodOptions.map(\.color),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 12)
                    .blur(radius: 0.2)

                Circle()
                    .fill(.background)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Circle()
                            .fill(selectedMoodColor)
                            .frame(width: 16, height: 16)
                    }
                    .shadow(color: selectedMoodColor.opacity(0.28), radius: 14, x: 0, y: 4)
                    .offset(x: CGFloat(selectedIndex) * step - 13)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selectedIndex)
            }
            .frame(height: 42)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectMood(at: value.location.x, width: width)
                    }
            )
        }
        .frame(height: 42)
        .padding(.horizontal, 28)
    }

    private func moodTile(symbol: String, label: String, caption: String, color: Color, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(height: 96)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? color.opacity(0.55) : Color(.separator).opacity(0.16), lineWidth: selected ? 1.2 : 0.6)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func emotionRow(symbol: String, label: String, color: Color, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MirrorTheme.primary)
            }
        }
        .contentShape(Rectangle())
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { saveAndDismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
            }
            .buttonStyle(.plain)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button { saveAndDismiss() } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save entry")
        }
    }

    private var writeToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                styleButton
                toolbarButton("checklist", label: "Checklist") { viewModel.coordinator.tbChecklist() }
                toolbarButton("tablecells", label: "Table") { viewModel.coordinator.tbInsertTable() }
                attachmentButton
                toolbarButton("pencil.tip.crop.circle", label: "Drawing") { viewModel.coordinator.presentDrawingCanvas() }
                Divider().frame(height: 24)
                toolbarButton("bold", label: "Bold", isActive: viewModel.formatState.isBold) { viewModel.coordinator.tbBold() }
                toolbarButton("italic", label: "Italic", isActive: viewModel.formatState.isItalic) { viewModel.coordinator.tbItalic() }
                toolbarButton("highlighter", label: "Highlight", isActive: viewModel.formatState.isHighlighted) { viewModel.coordinator.tbHighlight() }
                toolbarButton("link", label: "Link") { viewModel.coordinator.tbLink() }
                toolbarButton("keyboard.chevron.compact.down", label: "Dismiss Keyboard") { viewModel.coordinator.tbDismiss() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var styleButton: some View {
        Menu {
            Button("Title", systemImage: "textformat.size.larger") { viewModel.coordinator.setTextStyle(.title) }
            Button("Heading", systemImage: "textformat") { viewModel.coordinator.setTextStyle(.heading) }
            Button("Subheading", systemImage: "textformat.size.smaller") { viewModel.coordinator.setTextStyle(.subheading) }
            Button("Body", systemImage: "text.alignleft") { viewModel.coordinator.setTextStyle(.body) }
            Button("Monospaced", systemImage: "chevron.left.forwardslash.chevron.right") { viewModel.coordinator.setTextStyle(.monospaced) }
        } label: {
            Text("Aa")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Text style")
    }

    private var attachmentButton: some View {
        Menu {
            Button("Choose Photo or Video", systemImage: "photo.on.rectangle") {
                viewModel.coordinator.presentPhotoVideoPicker()
            }
            Button("Take Photo or Video", systemImage: "camera") {
                viewModel.coordinator.presentCameraCapture()
            }
            Button("Scan Documents", systemImage: "doc.viewfinder") {
                viewModel.coordinator.presentDocumentScanner()
            }
            Button("Attach File", systemImage: "folder") {
                viewModel.coordinator.presentFilePicker()
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 19, weight: .regular))
                .frame(width: 44, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attachments")
    }

    private func toolbarButton(
        _ symbol: String,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 38)
                .background(isActive ? Color.primary.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var selectedMoodSymbol: String {
        selectedMood?.symbol ?? "circle"
    }

    private var selectedMoodColor: Color {
        selectedMood?.color ?? MirrorTheme.primary
    }

    private var selectedMoodCaption: String {
        selectedMood?.caption ?? "tap to choose"
    }

    private var selectedMood: MoodOption? {
        moodOptions.first(where: { $0.label == viewModel.selectedMood })
    }

    private var selectedMoodIndex: Int {
        guard let selectedMood,
              let index = moodOptions.firstIndex(where: { $0.id == selectedMood.id })
        else {
            return moodOptions.count / 2
        }
        return index
    }

    private func selectMood(_ mood: String?) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            viewModel.selectedMood = mood
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func selectMood(at xPosition: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let clamped = min(max(xPosition, 0), width)
        let progress = clamped / width
        let index = Int((progress * CGFloat(moodOptions.count - 1)).rounded())
        let mood = moodOptions[min(max(index, 0), moodOptions.count - 1)]
        guard viewModel.selectedMood != mood.label else { return }
        selectMood(mood.label)
    }

    private func saveAndDismiss() {
        if let entry {
            if viewModel.hasContent { viewModel.updateEntry(entry) }
        } else {
            if viewModel.hasContent { viewModel.save(context: modelContext) }
        }
        dismiss()
    }

    private func bodyTextIncludingTitle(_ attributedText: NSAttributedString, entry: Entry) -> NSAttributedString {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return attributedText }

        let text = attributedText.string as NSString
        guard text.length > 0 else {
            return NSAttributedString(string: title)
        }

        let firstLineRange = text.lineRange(for: NSRange(location: 0, length: 0))
        let firstLine = text.substring(with: firstLineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstLine != title else { return attributedText }

        let mutable = NSMutableAttributedString(attributedString: attributedText)
        mutable.insert(NSAttributedString(string: "\(title)\n\n"), at: 0)
        return mutable
    }

    private func plainTextIncludingTitle(_ entry: Entry) -> NSAttributedString {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [title, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return NSAttributedString(string: combined)
    }
}

#Preview {
    NavigationStack {
        WriteView()
            .modelContainer(for: Entry.self, inMemory: true)
    }
}
