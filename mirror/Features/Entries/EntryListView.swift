import SwiftUI
import SwiftData

private struct NewEntryTag: Hashable {}

struct EntriesTabView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var searchText = ""
    @State private var path = NavigationPath()

    private var filteredEntries: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.text.localizedCaseInsensitiveContains(query) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var groupedByDay: [(date: Date, entries: [Entry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            (day, groups[day, default: []].sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if entries.isEmpty && searchText.isEmpty {
                    emptyState
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    entryList
                }
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle("Mirror")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationDestination(for: Entry.self) { entry in WriteView(entry: entry) }
            .navigationDestination(for: NewEntryTag.self) { _ in WriteView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(NewEntryTag()) } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("New Entry")
                }
            }
        }
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                journalHeader

                ForEach(groupedByDay, id: \.date) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sectionTitle(for: group.date))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .padding(.horizontal, 4)

                        ForEach(group.entries) { entry in
                            NavigationLink(value: entry) {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(MirrorTheme.bgBase)
    }

    private var journalHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(headerSubtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(MirrorTheme.accentGradient)
                        .frame(width: 46, height: 46)
                    Image(systemName: "sparkle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 12) {
                statPill(label: "\(entries.count)", caption: "entries", icon: "book.pages")
                statPill(label: totalWords.formatted(), caption: "words", icon: "text.word.spacing")
            }

            Capsule()
                .fill(
                    LinearGradient(colors: MirrorTheme.moodSpectrum, startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 6)
                .overlay(Capsule().stroke(Color(white: 1, opacity: 0.14), lineWidth: 0.5))
                .shadow(color: MirrorTheme.primary.opacity(0.25), radius: 8, x: 0, y: 2)
        }
        .padding(20)
        .futureSurface(cornerRadius: 28)
    }

    private func statPill(label: String, caption: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MirrorTheme.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MirrorTheme.bgCard, in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(MirrorTheme.accentGradient)
                    .frame(width: 88, height: 88)
                    .shadow(color: MirrorTheme.primary.opacity(0.35), radius: 24, x: 0, y: 10)
                Image(systemName: "pencil.and.sparkles")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Text("Your mirror awaits")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("A private space for thoughts, feelings, and patterns.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { path.append(NewEntryTag()) } label: {
                Label("Write first entry", systemImage: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 22)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MirrorTheme.bgBase)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Late night thoughts"
        }
    }

    private var headerSubtitle: String {
        guard !entries.isEmpty else { return "Start writing" }
        let words = totalWords
        return "\(entries.count) \(entries.count == 1 ? "entry" : "entries") · \(words.formatted()) words"
    }

    private var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

private struct EntryRow: View {
    let entry: Entry

    private var moodColor: Color { MirrorTheme.moodColor(entry.mood) }
    private var hasMood: Bool { !(entry.mood ?? "").isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            // Mood accent strip — transparent when no mood
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(hasMood ? moodColor : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title.isEmpty ? "Untitled" : entry.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(entry.createdAt, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Text(preview)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if hasMood || entry.wordCount > 0 || !entry.tags.isEmpty {
                    HStack(spacing: 6) {
                        if let mood = entry.mood, !mood.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: MirrorTheme.moodSymbol(mood))
                                    .font(.system(size: 10, weight: .semibold))
                                Text(mood)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(moodColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(moodColor.opacity(0.12), in: Capsule())
                        }

                        Text("\(entry.wordCount)w")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.quaternary)

                        ForEach(entry.tags.prefix(2), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.quaternary)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
        .background {
            HStack(spacing: 0) {
                if hasMood {
                    moodColor
                        .frame(width: 3)
                }
                MirrorTheme.bgCard
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(white: 1, opacity: 0.18), lineWidth: 0.5)
        }
    }

    private var preview: String {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = entry.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let first = lines.first, !title.isEmpty, first == title {
            lines.removeFirst()
        }

        return lines.isEmpty ? "No additional text" : lines.joined(separator: " ")
    }
}
