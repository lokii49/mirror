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
    /// The one file importer serves both plain-text and archive-folder imports.
    @State private var importsArchiveFolder = false
    @State private var exportProgress: Double?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportedArchive: ArchiveTransfer.ExportResult?
    @State private var archiveMessage: String?
    @State private var importPlan: ArchiveTransfer.ImportPlan?
    @State private var importChangedAsCopies = false
    @State private var lastImportBatch: ArchiveTransfer.ImportBatch?

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
        SettingsScroll {
            VStack(spacing: 14) {
                AppLockSettingsGroup()

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

                    ShareLink(
                        item: exportedMarkdown,
                        subject: Text("MirrorNotes Export (Markdown)"),
                        message: Text("My journal entries from Mirror, with formatting")
                    ) {
                        HStack {
                            SettingsRowLabel(title: "Export as Markdown", systemImage: "doc.richtext", iconColor: .purple)
                            Spacer()
                            SettingsChevron()
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button { startArchiveExport() } label: {
                        HStack {
                            SettingsRowLabel(title: "Export complete archive", systemImage: "archivebox", iconColor: .orange)
                            Spacer()
                            if let exportProgress {
                                ProgressView(value: exportProgress).frame(width: 60)
                            } else {
                                SettingsChevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(exportProgress != nil)
                    .accessibilityIdentifier("archive.export")
                    if exportProgress != nil {
                        Button("Cancel export", role: .cancel) { exportTask?.cancel() }
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    SettingsDivider()

                    Button { importsArchiveFolder = false; showImportPicker = true } label: {
                        HStack {
                            SettingsRowLabel(title: "Import entries", systemImage: "square.and.arrow.down", iconColor: .blue)
                            Spacer()
                            SettingsChevron()
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button { importsArchiveFolder = true; showImportPicker = true } label: {
                        HStack {
                            SettingsRowLabel(title: "Import archive folder", systemImage: "folder.badge.plus", iconColor: .blue)
                            Spacer()
                            SettingsChevron()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("archive.import")

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
                        Text("Permanently deletes all entries, mood check-ins and insights from this device and iCloud. Cannot be undone.")
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(MirrorTheme.bgBase)
        .settingsNavigationTitle(displayMode == .sentinel ? "Archive" : "Your Data")
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: importsArchiveFolder ? [.folder] : [.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls) where importsArchiveFolder:
                if let url = urls.first { planArchiveImport(url) }
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
        .modifier(ArchiveTransferAlerts(
            message: $archiveMessage,
            plan: $importPlan,
            importChangedAsCopies: $importChangedAsCopies,
            canUndo: lastImportBatch != nil,
            apply: applyArchiveImport,
            undo: undoArchiveImport
        ))
        #if os(iOS)
        .sheet(isPresented: Binding(get: { exportedArchive != nil }, set: { if !$0 { finishExport(saved: false) } })) {
            if let exportedArchive {
                ArchiveExportPicker(url: exportedArchive.zipURL) { saved in finishExport(saved: saved) }
            }
        }
        #endif
        .task { await checkiCloudStatus() }
        .task(id: exportCacheKey) { recomputeExportedText() }
    }

    // MARK: - Complete archive

    private func startArchiveExport() {
        exportProgress = 0
        let snapshot = entries
        exportTask = Task {
            do {
                let result = try await ArchiveTransfer.exportArchive(entries: snapshot) { value in
                    exportProgress = value
                }
                exportProgress = nil
                #if os(macOS)
                exportedArchive = result
                finishExport(saved: ArchiveExportPicker.save(result.zipURL))
                #else
                exportedArchive = result
                #endif
            } catch is CancellationError {
                exportProgress = nil
            } catch {
                exportProgress = nil
                archiveMessage = String(localized: "The archive could not be created. Nothing was exported.")
            }
        }
    }

    private func finishExport(saved: Bool) {
        guard let result = exportedArchive else { return }
        exportedArchive = nil
        ArchiveTransfer.discardExport(result.zipURL)
        guard saved else { return }
        if result.unreadable > 0 {
            archiveMessage = String(localized: "Exported \(result.exported) entries. \(result.unreadable) entries can't be read on this device yet and were not included; export again once they open.")
        } else {
            archiveMessage = String(localized: "Exported \(result.exported) entries with their photos and voice notes.")
        }
    }

    private func planArchiveImport(_ folder: URL) {
        let existing = entries
        Task {
            do {
                importChangedAsCopies = false
                importPlan = try await ArchiveTransfer.planImport(folder: folder, existing: existing)
            } catch {
                archiveMessage = String(localized: "This folder isn't a MirrorNotes archive, or it is damaged. Nothing was imported.")
            }
        }
    }

    private func applyArchiveImport() {
        guard let plan = importPlan else { return }
        importPlan = nil
        do {
            lastImportBatch = try ArchiveTransfer.applyImport(plan, importChangedAsCopies: importChangedAsCopies, context: modelContext)
            let added = lastImportBatch?.digests.count ?? 0
            archiveMessage = String(localized: "Imported \(added) entries.")
        } catch {
            archiveMessage = String(localized: "The import failed and nothing was added.")
        }
    }

    private func undoArchiveImport() {
        guard let batch = lastImportBatch else { return }
        lastImportBatch = nil
        if let result = try? ArchiveTransfer.undoImport(batch, context: modelContext) {
            archiveMessage = result.kept > 0
                ? String(localized: "Removed \(result.removed) imported entries. \(result.kept) edited since the import were kept.")
                : String(localized: "Removed \(result.removed) imported entries.")
        }
    }

    private func recomputeExportedText() {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        cachedExportedText = entries.map { entry in
            var block = "[\(formatter.string(from: entry.createdAt))]"
            if let mood = entry.mood { block += "\n[Mood: \(mood)]" }
            let text = entry.textDecryptionFailed ? "[Encrypted entry unavailable]" : entry.text
            block += "\n\(textWithPhotoTokensReplaced(text))"
            return block
        }
        .joined(separator: "\n\n---\n\n")
    }

    private var exportedMarkdown: String {
        MarkdownExportService.export(entries: entries)
    }

    private func deleteAllData() {
        let entries = (try? modelContext.fetch(FetchDescriptor<Entry>())) ?? []
        let checkIns = (try? modelContext.fetch(FetchDescriptor<MoodCheckIn>())) ?? []
        // Synced marker so other devices' on-device backups never offer these back. Saved
        // on its own, before the deletes: exports follow save order, so another device
        // gets the marker before (or with) the deletes and never offers them back.
        if !entries.isEmpty || !checkIns.isEmpty {
            modelContext.insert(JournalErasure(erasedEntryIDs: entries.map(\.id), erasedCheckInIDs: checkIns.map(\.id)))
            try? modelContext.save()
        }
        entries.forEach { modelContext.delete($0) }
        checkIns.forEach { modelContext.delete($0) }
        if let all = try? modelContext.fetch(FetchDescriptor<Insight>()) {
            all.forEach { modelContext.delete($0) }
        }
        try? modelContext.save()
        MoodCheckInMigration.eraseLegacyRecords()
        JournalSafety.shared.journalWasErased()
        // An unsaved Write draft is journal text too.
        WriteView.eraseAllDraftStorage()
    }

    private func checkiCloudStatus() async {
        #if DEBUG
        // The screenshot harness and perf/test runs (scratch journal) may run a build with no
        // iCloud container, where CKContainer.default() raises an Objective-C exception.
        if ProcessInfo.processInfo.arguments.contains("--macSnapshot") || PerfSeed.isRequested {
            iCloudStatus = .unknown
            return
        }
        #endif
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
