import CryptoKit
import Foundation

/// A portable copy of the journal: one Markdown file per entry (for people,
/// Obsidian and other Markdown tools), the entry's photos and recordings as
/// files, and a versioned `manifest.json` that our importer reads for an exact
/// round trip (formatting, pins, transcripts).
///
/// Plaintext exists only in the package the user asked for and in short-lived
/// staging under the temporary directory (removed after export/import and at
/// launch). Entries that can't be decrypted on this device are listed in the
/// manifest and summary and never written as placeholders.
nonisolated enum ArchivePackage {
    static let format = "mirrornotes-archive"
    static let version = 1

    // MARK: - Values

    struct VoiceNote: Codable, Equatable, Sendable {
        var data: Data
        var duration: Double
        var transcript: String?
        var languageCode: String?
        var languageName: String?
        var englishTranslation: String?
    }

    /// Fully decrypted entry. Built only when every field decrypts.
    struct ArchiveEntry: Equatable, Sendable {
        var id: UUID
        var createdAt: Date
        var text: String
        var textStyleData: Data?
        var inlineStyleData: Data?
        var mood: String?
        var tags: [String]
        var fontChoice: String?
        var isPinned: Bool
        var source: String
        var photos: [Data]
        var voiceNotes: [VoiceNote]
        var collectionID: UUID? = nil

        /// Covers everything the package carries, so a re-import can tell an
        /// identical entry from a changed one.
        var digest: String {
            var hasher = SHA256()
            func add(_ data: Data?) {
                let value = data ?? Data()
                var length = UInt64(value.count).bigEndian
                hasher.update(data: Data(bytes: &length, count: 8))
                hasher.update(data: value)
            }
            func add(_ string: String?) { add(string.map { Data($0.utf8) }) }
            add(String(createdAt.timeIntervalSinceReferenceDate))
            add(text); add(textStyleData); add(inlineStyleData); add(mood)
            add(tags.joined(separator: "\u{1F}")); add(fontChoice); add(isPinned ? "1" : "0")
            add(collectionID?.uuidString)
            photos.forEach { add($0) }
            add("|")
            for note in voiceNotes {
                add(note.data); add(String(note.duration)); add(note.transcript)
                add(note.languageCode); add(note.languageName); add(note.englishTranslation)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    struct Unreadable: Codable, Equatable, Sendable {
        var id: UUID
        var createdAt: Date
    }

    // MARK: - Manifest

    struct Manifest: Codable, Sendable {
        struct FileRef: Codable, Sendable {
            var path: String
            var sha256: String
        }
        struct VoiceRef: Codable, Sendable {
            var file: FileRef
            var duration: Double
            var transcript: String?
            var languageCode: String?
            var languageName: String?
            var englishTranslation: String?
        }
        struct EntryRecord: Codable, Sendable {
            var id: UUID
            var markdown: FileRef
            var createdAt: Date
            var text: String
            var textStyleData: Data?
            var inlineStyleData: Data?
            var mood: String?
            var tags: [String]
            var fontChoice: String?
            var isPinned: Bool
            var source: String
            var photos: [FileRef]
            var voiceNotes: [VoiceRef]
            var collectionID: UUID?
        }
        struct CollectionRecord: Codable, Sendable, Equatable {
            var id: UUID
            var name: String
            var icon: String
            var colorIndex: Int
        }
        var format: String
        var version: Int
        var appVersion: String
        var exportedAt: Date
        var exportedTimeZone: String
        var entries: [EntryRecord]
        var unreadable: [Unreadable]
        /// Absent in packages written before collections existed.
        var collections: [CollectionRecord]?
    }

    enum PackageError: Error, Equatable {
        case notAPackage, unsupportedVersion, tooLarge, unsafePath, missingFile, checksumMismatch, unreadableManifest
    }

    // MARK: - Staging

    static var stagingRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MirrorNotesArchiveStaging", isDirectory: true)
    }

    /// Called at launch: removes plaintext left by an export or import that was
    /// interrupted (crash, force quit).
    static func removeStaleStaging() {
        try? FileManager.default.removeItem(at: stagingRoot)
    }

    static func makeStagingDirectory(named name: String) throws -> URL {
        let dir = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        return dir
    }

    // MARK: - Writing

    static func fileName(for entry: ArchiveEntry) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entry.createdAt)
        let stamp = String(format: "%04d-%02d-%02d-%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        return "\(stamp)-\(entry.id.uuidString.lowercased()).md"
    }

    /// Writes one entry's Markdown and attachments under `root` and returns its
    /// manifest record. Call once per entry so only one entry is decrypted at a time.
    static func write(_ entry: ArchiveEntry, to root: URL, exportTimeZone: TimeZone,
                      collectionName: String? = nil) throws -> Manifest.EntryRecord {
        let fm = FileManager.default
        let entriesDir = root.appendingPathComponent("entries", isDirectory: true)
        try fm.createDirectory(at: entriesDir, withIntermediateDirectories: true)
        let folder = entry.id.uuidString.lowercased()
        var photoRefs: [Manifest.FileRef] = []
        var voiceRefs: [Manifest.VoiceRef] = []
        if !entry.photos.isEmpty || !entry.voiceNotes.isEmpty {
            let attachments = root.appendingPathComponent("attachments/\(folder)", isDirectory: true)
            try fm.createDirectory(at: attachments, withIntermediateDirectories: true)
            for (index, photo) in entry.photos.enumerated() {
                let path = "attachments/\(folder)/photo-\(index + 1).\(imageExtension(photo))"
                try photo.write(to: root.appendingPathComponent(path), options: .completeFileProtection)
                photoRefs.append(.init(path: path, sha256: sha256(photo)))
            }
            for (index, note) in entry.voiceNotes.enumerated() {
                let path = "attachments/\(folder)/voice-\(index + 1).m4a"
                try note.data.write(to: root.appendingPathComponent(path), options: .completeFileProtection)
                voiceRefs.append(.init(file: .init(path: path, sha256: sha256(note.data)), duration: note.duration,
                                       transcript: note.transcript, languageCode: note.languageCode,
                                       languageName: note.languageName, englishTranslation: note.englishTranslation))
            }
        }
        let markdown = Data(markdownDocument(entry, photoPaths: photoRefs.map(\.path), voicePaths: voiceRefs.map(\.file.path),
                                             exportTimeZone: exportTimeZone, collectionName: collectionName).utf8)
        let mdPath = "entries/\(fileName(for: entry))"
        try markdown.write(to: root.appendingPathComponent(mdPath), options: .completeFileProtection)
        return Manifest.EntryRecord(
            id: entry.id, markdown: .init(path: mdPath, sha256: sha256(markdown)), createdAt: entry.createdAt,
            text: entry.text, textStyleData: entry.textStyleData, inlineStyleData: entry.inlineStyleData,
            mood: entry.mood, tags: entry.tags, fontChoice: entry.fontChoice, isPinned: entry.isPinned,
            source: entry.source, photos: photoRefs, voiceNotes: voiceRefs, collectionID: entry.collectionID
        )
    }

    static func writeManifest(records: [Manifest.EntryRecord], unreadable: [Unreadable], to root: URL,
                              appVersion: String, exportedAt: Date, timeZone: TimeZone,
                              collections: [Manifest.CollectionRecord] = []) throws {
        let manifest = Manifest(format: format, version: version, appVersion: appVersion, exportedAt: exportedAt,
                                exportedTimeZone: timeZone.identifier, entries: records, unreadable: unreadable,
                                collections: collections)
        try encoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: .completeFileProtection)
        let readme = """
        # MirrorNotes export

        Exported \(iso(exportedAt)) (device time zone \(timeZone.identifier)).

        - `entries/`: one Markdown file per entry. The front matter holds the date (UTC), mood, tags and pin.
        - `attachments/`: photos and voice recordings, one folder per entry.
        - `manifest.json`: everything MirrorNotes needs to import this package exactly. Keep it with the files.

        \(unreadable.isEmpty ? "" : "\(unreadable.count) entries could not be read on the exporting device and are not included; they are listed in manifest.json.\n")
        """
        try Data(readme.utf8).write(to: root.appendingPathComponent("README.md"), options: .completeFileProtection)
    }

    /// Markdown for people and other apps. Formatting comes from the same codec
    /// as the plain Markdown export; text colour has no Markdown form and is not
    /// written (the manifest keeps it for our own import).
    static func markdownDocument(_ entry: ArchiveEntry, photoPaths: [String], voicePaths: [String],
                                 exportTimeZone: TimeZone, collectionName: String? = nil) -> String {
        var lines = ["---"]
        lines.append("id: \(yamlString(entry.id.uuidString.lowercased()))")
        lines.append("created: \(yamlString(iso(entry.createdAt)))")
        lines.append("exported_timezone: \(yamlString(exportTimeZone.identifier))")
        if let mood = entry.mood { lines.append("mood: \(yamlString(mood))") }
        lines.append("tags: [\(entry.tags.map(yamlString).joined(separator: ", "))]")
        if entry.isPinned { lines.append("pinned: true") }
        if let collectionName { lines.append("collection: \(yamlString(collectionName))") }
        lines.append("---")
        lines.append("")
        var body = MarkdownExportService.markdownLines(text: entry.text, textStyleData: entry.textStyleData,
                                                       inlineStyleData: entry.inlineStyleData)
        for (range, index) in allPhotoTokens(in: body).reversed() {
            let replacement = index < photoPaths.count ? "![Photo \(index + 1)](../\(photoPaths[index]))" : ""
            body.replaceSubrange(range, with: replacement)
        }
        if !body.isEmpty { lines.append(body) }
        // Photos without an inline position still appear.
        let referenced = Set(allPhotoTokens(in: entry.text).map(\.index))
        for (index, path) in photoPaths.enumerated() where !referenced.contains(index) {
            lines.append("")
            lines.append("![Photo \(index + 1)](../\(path))")
        }
        for (index, note) in entry.voiceNotes.enumerated() where index < voicePaths.count {
            lines.append("")
            lines.append("### Voice note \(index + 1)")
            lines.append("[Recording, \(durationLabel(note.duration))](../\(voicePaths[index]))")
            if let transcript = note.transcript, !transcript.isEmpty {
                lines.append("")
                lines.append(note.languageName.map { "Transcript (\($0)):" } ?? "Transcript:")
                lines.append(contentsOf: transcript.components(separatedBy: .newlines).map { "> \($0)" })
            }
            if let translation = note.englishTranslation, !translation.isEmpty {
                lines.append("")
                lines.append("English translation:")
                lines.append(contentsOf: translation.components(separatedBy: .newlines).map { "> \($0)" })
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Reading

    struct Limits: Sendable {
        var maxEntries = 50_000
        var maxTotalBytes: Int64 = 4 * 1024 * 1024 * 1024
        var maxManifestBytes = 512 * 1024 * 1024
        static let standard = Limits()
    }

    /// Reads and validates a package folder. Every attachment path must stay
    /// inside `root` (no absolute paths, `..` or symlinks) and match its checksum.
    /// Nothing is fetched from the network.
    static func read(from root: URL, limits: Limits = .standard) throws -> (entries: [ArchiveEntry], unreadable: [Unreadable], manifest: Manifest) {
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let size = try? manifestURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
              size.isSymbolicLink != true else { throw PackageError.notAPackage }
        guard (size.fileSize ?? 0) <= limits.maxManifestBytes else { throw PackageError.tooLarge }
        guard let manifest = try? decoder.decode(Manifest.self, from: Data(contentsOf: manifestURL)) else {
            throw PackageError.unreadableManifest
        }
        guard manifest.format == format else { throw PackageError.notAPackage }
        guard manifest.version <= version else { throw PackageError.unsupportedVersion }
        guard manifest.entries.count <= limits.maxEntries else { throw PackageError.tooLarge }

        var total: Int64 = 0
        func load(_ ref: Manifest.FileRef) throws -> Data {
            let url = try resolve(ref.path, in: root)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else { throw PackageError.unsafePath }
            total += Int64(values.fileSize ?? 0)
            guard total <= limits.maxTotalBytes else { throw PackageError.tooLarge }
            guard let data = try? Data(contentsOf: url) else { throw PackageError.missingFile }
            guard sha256(data) == ref.sha256 else { throw PackageError.checksumMismatch }
            return data
        }

        var entries: [ArchiveEntry] = []
        for record in manifest.entries {
            _ = try resolve(record.markdown.path, in: root)
            entries.append(ArchiveEntry(
                id: record.id, createdAt: record.createdAt, text: record.text,
                textStyleData: record.textStyleData, inlineStyleData: record.inlineStyleData,
                mood: record.mood, tags: record.tags, fontChoice: record.fontChoice,
                isPinned: record.isPinned, source: record.source,
                photos: try record.photos.map(load),
                voiceNotes: try record.voiceNotes.map { ref in
                    VoiceNote(data: try load(ref.file), duration: ref.duration, transcript: ref.transcript,
                              languageCode: ref.languageCode, languageName: ref.languageName,
                              englishTranslation: ref.englishTranslation)
                },
                collectionID: record.collectionID
            ))
        }
        return (entries, manifest.unreadable, manifest)
    }

    /// Relative path inside `root`, or `unsafePath`.
    static func resolve(_ path: String, in root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw PackageError.unsafePath }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let url = base.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(base.path + "/") else { throw PackageError.unsafePath }
        // A symlinked folder on the way would also lead outside.
        guard url.resolvingSymlinksInPath().path.hasPrefix(base.path + "/") else { throw PackageError.unsafePath }
        return url
    }

    // MARK: - Helpers

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func imageExtension(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if bytes.count >= 12, bytes[4...7] == [0x66, 0x74, 0x79, 0x70][...] {
            let brand = String(bytes: bytes[8...11], encoding: .ascii) ?? ""
            if ["heic", "heix", "mif1", "msf1"].contains(brand) { return "heic" }
        }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        return "bin"
    }

    /// Double-quoted YAML scalar with escapes, safe for any user text.
    static func yamlString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value) {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
