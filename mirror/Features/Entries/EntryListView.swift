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
                    }
                    .accessibilityLabel("New Entry")
                }
            }
        }
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                journalHeader

            ForEach(groupedByDay, id: \.date) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sectionTitle(for: group.date))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
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
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(MirrorTheme.bgBase)
    }

    private var journalHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("\(entries.count) entries · \(totalWords.formatted()) words")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
                    .frame(width: 46, height: 46)
                    .background(MirrorTheme.primary.opacity(0.12), in: Circle())
            }

            Capsule()
                .fill(LinearGradient(colors: MirrorTheme.moodSpectrum, startPoint: .leading, endPoint: .trailing))
                .frame(height: 8)
                .opacity(0.82)
        }
        .padding(18)
        .futureSurface(cornerRadius: 26)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(MirrorTheme.primary)
                .frame(width: 86, height: 86)
                .background(MirrorTheme.primary.opacity(0.12), in: Circle())
            VStack(spacing: 6) {
                Text("Start your mirror")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("A private space for notes, feelings, and patterns.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { path.append(NewEntryTag()) } label: {
                Label("New Entry", systemImage: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MirrorTheme.bgBase)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(entry.createdAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let mood = entry.mood, !mood.isEmpty {
                    Label(mood, systemImage: MirrorTheme.moodSymbol(mood))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(MirrorTheme.moodColor(mood))
                }

                Label("\(entry.wordCount) words", systemImage: "text.word.spacing")
                    .labelStyle(.titleAndIcon)

                ForEach(entry.tags.prefix(2), id: \.self) { tag in
                    Text("#\(tag)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .futureSurface(cornerRadius: 20)
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
