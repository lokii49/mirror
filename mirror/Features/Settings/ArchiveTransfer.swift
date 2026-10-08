import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Drives a complete-archive export and a package import. Entries are decrypted
/// one at a time on the main actor and written off it, so the archive is never
/// held decrypted in memory all at once during export.
enum ArchiveTransfer {

    struct ExportResult {
        var zipURL: URL
        var exported: Int
        var unreadable: Int
    }

    enum TransferError: Error { case zipFailed }

    struct StagedArchive {
        var root: URL
        var exported: Int
        var unreadable: Int
    }

    static func exportArchive(entries: [Entry], collections: [JournalCollection], savedViews: [SavedEntryView] = [],
                              progress: @escaping (Double) -> Void) async throws -> ExportResult {
        let staged = try await stageArchive(entries: entries, collections: collections, savedViews: savedViews) { progress($0 * 0.9) }
        do {
            let root = staged.root
            let name = root.lastPathComponent
            let zip = try await Task.detached(priority: .userInitiated) { try zipped(root, named: name) }.value
            try? FileManager.default.removeItem(at: root)
            progress(1)
            return ExportResult(zipURL: zip, exported: staged.exported, unreadable: staged.unreadable)
        } catch {
            try? FileManager.default.removeItem(at: staged.root.deletingLastPathComponent())
            throw error
        }
    }

    /// Writes the package folder (the part the zip wraps). Separate so tests can
    /// import exactly what export wrote.
    static func stageArchive(entries: [Entry], collections: [JournalCollection], savedViews: [SavedEntryView] = [],
                             progress: @escaping (Double) -> Void) async throws -> StagedArchive {
        // Names are decrypted here once; an unreadable collection name is left out
        // (its entries still carry the id).
        var collectionRecords: [ArchivePackage.Manifest.CollectionRecord] = []
        var names: [UUID: String] = [:]
        for collection in collections {
            guard let payload = collection.payload else { continue }
            names[collection.id] = payload.name
            collectionRecords.append(.init(id: collection.id, name: payload.name, icon: payload.icon, colorIndex: payload.colorIndex))
        }
        // Views the device can't decrypt are left out, like collections.
        let viewRecords: [ArchivePackage.Manifest.SavedViewRecord] = savedViews
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            .compactMap { view in
                guard let payload = view.payload else { return nil }
                return .init(id: view.id, name: payload.name, query: payload.query, criteria: payload.criteria, sort: payload.sort)
            }
        let now = Date()
        let timeZone = TimeZone.current
        let name = "MirrorNotes Export \(ArchivePackage.iso(now).prefix(10))"
        let root = try ArchivePackage.makeStagingDirectory(named: name)
        do {
            var records: [ArchivePackage.Manifest.EntryRecord] = []
            var unreadable: [ArchivePackage.Unreadable] = []
            for (index, entry) in entries.enumerated() {
                try Task.checkCancellation()
                if let snapshot = entry.archiveSnapshot() {
                    let collectionName = snapshot.collectionID.flatMap { names[$0] }
                    let record = try await Task.detached(priority: .userInitiated) {
                        try ArchivePackage.write(snapshot, to: root, exportTimeZone: timeZone, collectionName: collectionName)
                    }.value
                    records.append(record)
                } else {
                    unreadable.append(.init(id: entry.id, createdAt: entry.createdAt))
                }
                progress(Double(index + 1) / Double(max(entries.count, 1)))
            }
            try Task.checkCancellation()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            try ArchivePackage.writeManifest(records: records, unreadable: unreadable, to: root,
                                             appVersion: version, exportedAt: now, timeZone: timeZone,
                                             collections: collectionRecords, savedViews: viewRecords)
            return StagedArchive(root: root, exported: records.count, unreadable: unreadable.count)
        } catch {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
            throw error
        }
    }

    /// `.forUploading` gives a zip of the folder on iOS and macOS; it is deleted
    /// when the accessor returns, so it is moved next to the folder first.
    nonisolated private static func zipped(_ folder: URL, named name: String) throws -> URL {
        let destination = folder.deletingLastPathComponent().appendingPathComponent("\(name).zip")
        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zip in
            do { try FileManager.default.moveItem(at: zip, to: destination) } catch { moveError = error }
        }
        if let error = coordinationError ?? moveError { throw error }
        guard FileManager.default.fileExists(atPath: destination.path) else { throw TransferError.zipFailed }
        return destination
    }

    /// Removes an export's zip and its staging folder once it was saved or the
    /// user cancelled.
    static func discardExport(_ zipURL: URL) {
        try? FileManager.default.removeItem(at: zipURL.deletingLastPathComponent())
    }

    // MARK: - Import

    struct ImportPlan {
        /// Collections named in the package; missing ones are created on import.
        var collections: [ArchivePackage.Manifest.CollectionRecord] = []
        /// Saved views named in the package; ones this journal lacks are created.
        var savedViews: [ArchivePackage.Manifest.SavedViewRecord] = []
        var new: [ArchivePackage.ArchiveEntry]
        var changed: [ArchivePackage.ArchiveEntry]
        var identical: Int
        var unreadableInPackage: Int
    }

    /// What one import added, so it can be undone while the entries are untouched.
    struct ImportBatch {
        var digests: [UUID: String]
        var createdCollections: [UUID] = []
        var createdSavedViews: [UUID] = []
    }

    /// Reads and validates the package (off the main actor), then compares it
    /// with the journal by entry ID and content.
    static func planImport(folder: URL, existing: [Entry]) async throws -> ImportPlan {
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let package = try await Task.detached(priority: .userInitiated) { try ArchivePackage.read(from: folder) }.value
        var byID: [UUID: Entry] = [:]
        for entry in existing { byID[entry.id] = entry }
        var plan = ImportPlan(collections: package.manifest.collections ?? [],
                              savedViews: package.manifest.savedViews ?? [], new: [], changed: [], identical: 0,
                              unreadableInPackage: package.unreadable.count)
        for archived in package.entries {
            guard let current = byID[archived.id] else {
                plan.new.append(archived)
                continue
            }
            // An entry this device can't read is treated as changed: never overwritten,
            // only offered as a copy.
            if current.archiveSnapshot()?.digest == archived.digest {
                plan.identical += 1
            } else {
                plan.changed.append(archived)
            }
        }
        return plan
    }

    /// Inserts new entries with their original IDs and, if asked, changed ones as
    /// copies with new IDs. Existing entries are never modified. One save: either
    /// everything is added or nothing is.
    static func applyImport(_ plan: ImportPlan, importChangedAsCopies: Bool, context: ModelContext) throws -> ImportBatch {
        var batch = ImportBatch(digests: [:])
        // Membership needs the collection: create the ones this journal lacks (same
        // id, so a re-import lines up). Unknown ids without a record become Unfiled.
        var known = Set(((try? context.fetch(FetchDescriptor<JournalCollection>())) ?? []).map(\.id))
        var nextIndex = (((try? context.fetch(FetchDescriptor<JournalCollection>())) ?? []).map(\.sortIndex).max() ?? -1) + 1
        for record in plan.collections where !known.contains(record.id) {
            let collection = JournalCollection(id: record.id, payload: .init(name: record.name, icon: record.icon, colorIndex: record.colorIndex),
                                               sortIndex: nextIndex)
            guard collection.encryptedPayload != nil else { continue }
            context.insert(collection)
            known.insert(record.id)
            batch.createdCollections.append(record.id)
            nextIndex += 1
        }
        // Saved views too: same id, so a re-import adds nothing and never overwrites a
        // view the user has since edited.
        let existingViews = (try? context.fetch(FetchDescriptor<SavedEntryView>())) ?? []
        var knownViews = Set(existingViews.map(\.id))
        var nextViewIndex = (existingViews.map(\.sortIndex).max() ?? -1) + 1
        for record in plan.savedViews where !knownViews.contains(record.id) {
            let view = SavedEntryView(id: record.id, payload: .init(name: record.name, query: record.query,
                                                                    criteria: record.criteria, sort: record.sort),
                                      sortIndex: nextViewIndex)
            guard view.encryptedPayload != nil else { continue }
            context.insert(view)
            knownViews.insert(record.id)
            batch.createdSavedViews.append(record.id)
            nextViewIndex += 1
        }
        let toInsert = plan.new.map { ($0, $0.id) } + (importChangedAsCopies ? plan.changed.map { ($0, UUID()) } : [])
        for (archived, id) in toInsert {
            var stored = archived
            stored.id = id
            if let collectionID = stored.collectionID, !known.contains(collectionID) { stored.collectionID = nil }
            Entry.insert(stored, id: id, into: context)
            batch.digests[id] = stored.digest
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return batch
    }

    /// Deletes the imported entries that are still exactly as imported; an entry
    /// edited since is kept. Returns (removed, kept).
    static func undoImport(_ batch: ImportBatch, context: ModelContext) throws -> (removed: Int, kept: Int) {
        let ids = Set(batch.digests.keys)
        let entries = try context.fetch(FetchDescriptor<Entry>()).filter { ids.contains($0.id) }
        var removed = 0
        var removedIDs = Set<UUID>()
        for entry in entries where entry.archiveSnapshot()?.digest == batch.digests[entry.id] {
            removedIDs.insert(entry.id)
            context.delete(entry)
            removed += 1
        }
        // Collections the import created go too, unless an entry that stays uses them.
        for id in batch.createdCollections {
            let members = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.collectionID == id }))) ?? []
            guard members.allSatisfy({ removedIDs.contains($0.id) }),
                  let collection = try? context.fetch(FetchDescriptor<JournalCollection>(predicate: #Predicate { $0.id == id })).first
            else { continue }
            context.delete(collection)
        }
        // Views the import created go too (they hold no entries, only a search).
        for id in batch.createdSavedViews {
            if let view = try? context.fetch(FetchDescriptor<SavedEntryView>(predicate: #Predicate { $0.id == id })).first {
                context.delete(view)
            }
        }
        try context.save()
        return (removed, batch.digests.count - removed)
    }
}

// MARK: - Saving the zip

#if os(iOS)
/// Lets the user pick where the zip goes (Files, iCloud Drive, a USB drive).
/// Exporting by URL keeps a large archive out of memory.
struct ArchiveExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(false) }
    }
}
#elseif os(macOS)
enum ArchiveExportPicker {
    /// Save panel, then a file copy (never loads the zip into memory).
    @MainActor
    static func save(_ url: URL) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        try? FileManager.default.removeItem(at: destination)
        return (try? FileManager.default.copyItem(at: url, to: destination)) != nil
    }
}
#endif

/// Import preview (what will be added, what is skipped) and result messages,
/// kept out of ArchiveSettingsView's body.
struct ArchiveTransferAlerts: ViewModifier {
    @Binding var message: String?
    @Binding var plan: ArchiveTransfer.ImportPlan?
    @Binding var importChangedAsCopies: Bool
    let canUndo: Bool
    let apply: () -> Void
    let undo: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Import archive?", isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } }),
                   presenting: plan) { plan in
                if plan.changed.isEmpty {
                    Button("Import \(plan.new.count) entries") { apply() }
                        .disabled(plan.new.isEmpty)
                } else {
                    Button("Import new only (\(plan.new.count))") { importChangedAsCopies = false; apply() }
                    Button("Also add \(plan.changed.count) changed as copies") { importChangedAsCopies = true; apply() }
                }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text(Self.summary(plan))
            }
            .alert("Archive", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                if canUndo { Button("Undo import", role: .destructive) { undo() } }
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
    }

    static func summary(_ plan: ArchiveTransfer.ImportPlan) -> String {
        var parts = [String(localized: "\(plan.new.count) new entries will be added.")]
        if plan.identical > 0 { parts.append(String(localized: "\(plan.identical) are already in your journal and will be skipped.")) }
        if !plan.changed.isEmpty {
            parts.append(String(localized: "\(plan.changed.count) differ from the version in your journal. Your journal's version is never replaced; you can add the archive's version as a copy."))
        }
        if plan.unreadableInPackage > 0 {
            parts.append(String(localized: "\(plan.unreadableInPackage) entries were not readable when the archive was made and are not in it."))
        }
        return parts.joined(separator: " ")
    }
}
