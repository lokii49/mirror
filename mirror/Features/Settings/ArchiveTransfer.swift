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

    static func exportArchive(entries: [Entry], progress: @escaping (Double) -> Void) async throws -> ExportResult {
        let now = Date()
        let timeZone = TimeZone.current
        let name = "MirrorNotes Export \(ArchivePackage.iso(now).prefix(10))"
        let root = try ArchivePackage.makeStagingDirectory(named: name)
        let container = root.deletingLastPathComponent()
        do {
            var records: [ArchivePackage.Manifest.EntryRecord] = []
            var unreadable: [ArchivePackage.Unreadable] = []
            for (index, entry) in entries.enumerated() {
                try Task.checkCancellation()
                if let snapshot = entry.archiveSnapshot() {
                    let record = try await Task.detached(priority: .userInitiated) {
                        try ArchivePackage.write(snapshot, to: root, exportTimeZone: timeZone)
                    }.value
                    records.append(record)
                } else {
                    unreadable.append(.init(id: entry.id, createdAt: entry.createdAt))
                }
                progress(Double(index + 1) / Double(max(entries.count, 1)) * 0.9)
            }
            try Task.checkCancellation()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            try ArchivePackage.writeManifest(records: records, unreadable: unreadable, to: root,
                                             appVersion: version, exportedAt: now, timeZone: timeZone)
            let zip = try await Task.detached(priority: .userInitiated) { try zipped(root, named: name) }.value
            try? FileManager.default.removeItem(at: root)
            progress(1)
            return ExportResult(zipURL: zip, exported: records.count, unreadable: unreadable.count)
        } catch {
            try? FileManager.default.removeItem(at: container)
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
        var new: [ArchivePackage.ArchiveEntry]
        var changed: [ArchivePackage.ArchiveEntry]
        var identical: Int
        var unreadableInPackage: Int
    }

    /// What one import added, so it can be undone while the entries are untouched.
    struct ImportBatch {
        var digests: [UUID: String]
    }

    /// Reads and validates the package (off the main actor), then compares it
    /// with the journal by entry ID and content.
    static func planImport(folder: URL, existing: [Entry]) async throws -> ImportPlan {
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let package = try await Task.detached(priority: .userInitiated) { try ArchivePackage.read(from: folder) }.value
        var byID: [UUID: Entry] = [:]
        for entry in existing { byID[entry.id] = entry }
        var plan = ImportPlan(new: [], changed: [], identical: 0, unreadableInPackage: package.unreadable.count)
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
        let toInsert = plan.new.map { ($0, $0.id) } + (importChangedAsCopies ? plan.changed.map { ($0, UUID()) } : [])
        for (archived, id) in toInsert {
            Entry.insert(archived, id: id, into: context)
            var stored = archived
            stored.id = id
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
        for entry in entries where entry.archiveSnapshot()?.digest == batch.digests[entry.id] {
            context.delete(entry)
            removed += 1
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
