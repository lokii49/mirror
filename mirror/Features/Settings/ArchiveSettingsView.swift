import SwiftUI
import SwiftData
import CloudKit
import UniformTypeIdentifiers

/// "Your Data" in Classic, "Archive" in Sentinel — export, import, iCloud
/// status, and destructive delete. Split out of the old single-screen
/// Settings so destructive actions aren't sitting one scroll away from
/// everything else.
struct ArchiveSettingsView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode

    @State private var iCloudStatus: ICloudStatus = .checking
    @State private var showDeleteConfirmation = false
    @State private var showImportPicker = false
    @State private var importResultMessage: String?
    @State private var showImportResult = false

    // `exportedText` decrypts every entry's text on every body re-eval, but was
    // read directly in `body` via `ShareLink(item:)` — so every unrelated @State
    // change in this view (delete confirmation, import picker/result, iCloud
    // status) re-decrypted the full history. Cached via `.task(id:)`, matching
    // the CalendarHeatmap/MoodTimelineView precedent. Keyed on the raw
    // `encryptedText`/`encryptedMood` fields (not the decrypted `text`/`mood`),
    // so computing the key itself never triggers decryption.
    @State private var cachedExportedText: String = ""

    private var iCloudStatusColor: Color { iCloudStatus.color }

    private var exportCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(entries.count)
        for entry in entries {
            hasher.combine(entry.createdAt)
            hasher.combine(entry.encryptedMood)
            hasher.combine(entry.encryptedText)
        }
        return hasher.finalize()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsGroup(title: "Your Data") {
                    ShareLink(
                        item: cachedExportedText,
                        subject: Text("MirrorNotes Export"),
                        message: Text("My journal entries from Mirror")
                    ) {
                        HStack {
                            SettingsRowLabel(title: "Export all entries", systemImage: "square.and.arrow.up", iconColor: .green)
                            Spacer()
                            SettingsChevron()
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button { showImportPicker = true } label: {
                        HStack {
                            SettingsRowLabel(title: "Import entries", systemImage: "square.and.arrow.down", iconColor: .blue)
                            Spacer()
                            SettingsChevron()
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    HStack {
                        SettingsRowLabel(title: "iCloud sync", systemImage: "icloud.fill", iconColor: .blue)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(iCloudStatusColor)
                                .frame(width: 7, height: 7)
                            Text(iCloudStatus.label)
                                .font(displayMode == .sentinel ? MirrorTheme.mono(12.5) : .system(size: 13))
                                .foregroundStyle(MirrorTheme.textSecondary)
                        }
                    }

                    SettingsDivider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        SettingsRowLabel(title: "Delete all data", systemImage: "trash.fill", iconColor: .red)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "Delete all journal data?",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Everything", role: .destructive) { deleteAllData() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Permanently deletes all entries and insights from this device and iCloud. Cannot be undone.")
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle(displayMode == .sentinel ? "Archive" : "Your Data")
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let count = importEntries(from: url)
                if count > 0 {
                    importResultMessage = count == 1
                        ? String(localized: "Imported 1 entry.")
                        : String(localized: "Imported \(count) entries.")
                } else {
                    importResultMessage = String(localized: "No entries found in file.")
                }
                showImportResult = true
            case .failure:
                importResultMessage = String(localized: "Could not read file.")
                showImportResult = true
            }
        }
        .alert("Import", isPresented: $showImportResult) {
            Button("OK") { importResultMessage = nil }
        } message: {
            Text(importResultMessage ?? "")
        }
        .task { await checkiCloudStatus() }
        .task(id: exportCacheKey) { recomputeExportedText() }
    }

    private func recomputeExportedText() {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        cachedExportedText = entries.map { entry in
            var block = "[\(formatter.string(from: entry.createdAt))]"
            if let mood = entry.mood { block += "\n[Mood: \(mood)]" }
            block += "\n\(entry.text)"
            return block
        }
        .joined(separator: "\n\n---\n\n")
    }

    private func deleteAllData() {
        if let all = try? modelContext.fetch(FetchDescriptor<Entry>()) {
            all.forEach { modelContext.delete($0) }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<Insight>()) {
            all.forEach { modelContext.delete($0) }
        }
        try? modelContext.save()
    }

    private func checkiCloudStatus() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            await MainActor.run {
                switch status {
                case .available: iCloudStatus = .active
                case .noAccount: iCloudStatus = .noAccount
                case .restricted: iCloudStatus = .restricted
                case .temporarilyUnavailable: iCloudStatus = .unavailable
                default: iCloudStatus = .unknown
                }
            }
        } catch {
            await MainActor.run { iCloudStatus = .error }
        }
    }

    @discardableResult
    private func importEntries(from url: URL) -> Int {
        guard url.startAccessingSecurityScopedResource() else { return 0 }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return 0 }

        let separator = "\n\n---\n\n"
        var count = 0

        if raw.contains(separator) {
            let blocks = raw.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for block in blocks {
                if insertEntry(fromBlock: block) { count += 1 }
            }
        } else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let entry = Entry(text: trimmed, source: .typed)
                modelContext.insert(entry)
                count = 1
            }
        }

        try? modelContext.save()
        return count
    }

    private func insertEntry(fromBlock block: String) -> Bool {
        var lines = block.components(separatedBy: "\n")
        var date = Date()
        var mood: String? = nil

        if let header = lines.first, header.hasPrefix("["), header.hasSuffix("]") {
            let inner = String(header.dropFirst().dropLast())
            if !inner.hasPrefix("Mood:") {
                date = parseMirrorDate(inner) ?? Date()
                lines.removeFirst()
            }
        }

        if let moodLine = lines.first,
           moodLine.hasPrefix("[Mood: "), moodLine.hasSuffix("]") {
            let moodStr = String(moodLine.dropFirst("[Mood: ".count).dropLast())
            if MirrorTheme.moodOptions.contains(moodStr) {
                mood = moodStr
                lines.removeFirst()
            }
        }

        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let entry = Entry(text: text, mood: mood, source: .typed)
        entry.createdAt = date
        entry.weekIdentifier = DateHelpers.weekIdentifier(for: date)
        modelContext.insert(entry)
        return true
    }

    private func parseMirrorDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.date(from: string)
    }
}
