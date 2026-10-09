import CryptoKit
import Foundation
import SwiftLlama

/// Ask's semantic retrieval (2026-10-08): EmbeddingGemma v1 300M (Q8_0 GGUF) through SwiftLlama's
/// `LlamaEmbedder`, measured in tools/llmrig/retrieval. The one-time model download (on unmetered
/// networks only) happens only after the user agrees, in Ask's offer card or in Settings >
/// Smarter Ask search (`consent`). Until the model is installed and the index covers the journal,
/// Ask keeps using `SearchService.search`.
///
/// Privacy: entry text never leaves the device. The download sends no journal data. Vectors are
/// derived from journal text, so they live only in Application Support: excluded from backups,
/// never in SwiftData/CloudKit, and never logged.
actor SemanticSearchService {
    static let shared = SemanticSearchService()

    // MARK: Model

    static let modelFileName = "embeddinggemma-300M-Q8_0.gguf"
    /// Own static host (owner decision 2026-10-08). Must serve exactly the file below.
    static let modelURL = URL(string: "https://models.mirrornotes.org/embeddinggemma/embeddinggemma-300M-Q8_0.gguf")!
    /// SHA-256 of ggml-org/embeddinggemma-300M-GGUF `embeddinggemma-300M-Q8_0.gguf` (333,590,944 bytes).
    static let modelSHA256 = "b5ce9d77a3fc4b3b39ccb5643c36777911cc4eb46a66962eadfa3f5f60490d63"
    static let queryPrefix = "task: search result | query: "
    static let documentPrefix = "title: none | text: "
    /// Characters of an entry that are embedded. 2,048 tokens fit far more, but long entries are
    /// truncated anyway so one pass stays bounded; the rig's entries were 1-3 sentences.
    static let maxEmbeddedCharacters = 4_000
    /// Ask switches to semantic retrieval only when the index covers this share of readable entries.
    static let minimumCoverage = 0.95

    enum ModelState: Equatable {
        case absent, downloading, installed, failed
    }

    /// The user's per-device answer to "download the search model?". Nothing downloads before
    /// `.accepted`; `.declined` hides Ask's offer card (Settings can still turn it on).
    enum Consent: String {
        case undecided = "", accepted, declined
    }

    static let consentKey = "smartAskSearchConsent"
    static let modelByteCount: Int64 = 333_590_944
    /// "333.6 MB", with a no-break space so a translated sentence never wraps between number and unit.
    static var modelSizeText: String {
        ByteCountFormatter.string(fromByteCount: modelByteCount, countStyle: .file)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    nonisolated static var consent: Consent {
        get { Consent(rawValue: UserDefaults.standard.string(forKey: consentKey) ?? "") ?? .undecided }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: consentKey) }
    }

    /// Cheap check for views: the model file is on disk (the actor's `modelState` is authoritative).
    nonisolated static var isModelOnDisk: Bool {
        (try? FileManager.default.fileExists(atPath: modelFileURL().path)) == true
    }

    private(set) var modelState: ModelState
    /// The running download, kept so its bytes received can be read for a progress bar.
    private var downloadTask: URLSessionDownloadTask?

    /// Bytes of the model received so far while `.downloading` (0 otherwise). Settings polls it.
    var downloadedBytes: Int64 {
        guard modelState == .downloading, let task = downloadTask else { return 0 }
        return max(0, task.countOfBytesReceived)
    }
    private var index: [UUID: IndexRecord]
    private var backfillTask: Task<Void, Never>?

    private init() {
        modelState = (try? FileManager.default.fileExists(atPath: Self.modelFileURL().path)) == true ? .installed : .absent
        index = (try? Self.loadIndex()) ?? [:]
    }

    static func modelFileURL() throws -> URL {
        try LocalLLMService.modelDirectory().appendingPathComponent(modelFileName)
    }

    /// Starts the download once the user has agreed; later calls are no-ops while it runs or after it
    /// finished. A failed download is retried on the next call (each Ask makes one).
    func ensureModelDownloadStarted() {
        guard Self.consent == .accepted, modelState == .absent || modelState == .failed else { return }
        modelState = .downloading
        Task { await download() }
    }

    private func download() async {
        do {
            let configuration = URLSessionConfiguration.default
            configuration.allowsExpensiveNetworkAccess = false     // never on cellular / hotspot
            configuration.allowsConstrainedNetworkAccess = false   // nor in Low Data Mode
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForResource = 6 * 60 * 60
            // A download task (not `download(from:)`) so `downloadedBytes` can read its progress. The
            // finished file is moved out inside the handler: URLSession deletes it when the handler returns.
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            let (temporary, response): (URL, URLResponse) = try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: Self.modelURL) { location, response, error in
                    guard let location, let response else {
                        continuation.resume(throwing: error ?? URLError(.unknown))
                        return
                    }
                    do {
                        let kept = FileManager.default.temporaryDirectory
                            .appendingPathComponent("embeddinggemma-\(UUID().uuidString).download")
                        try FileManager.default.moveItem(at: location, to: kept)
                        continuation.resume(returning: (kept, response))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                downloadTask = task
                task.resume()
            }
            downloadTask = nil
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            guard try Self.sha256(of: temporary) == Self.modelSHA256 else { throw URLError(.cannotDecodeContentData) }
            var destination = try Self.modelFileURL()
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try destination.setResourceValues(values)
            modelState = .installed
        } catch {
            downloadTask = nil
            modelState = .failed
        }
    }

    /// Settings > Smarter Ask search > Remove: deletes the model and every stored vector.
    func removeModel() {
        backfillTask?.cancel()
        downloadTask?.cancel()
        downloadTask = nil
        try? FileManager.default.removeItem(at: Self.modelFileURL())
        try? FileManager.default.removeItem(at: Self.indexURL())
        try? FileManager.default.removeItem(at: Self.legacyPlaintextIndexURL())
        index = [:]
        modelState = .absent
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Index

    /// What the index needs from an entry, copied off the main actor's SwiftData objects.
    struct Document: Sendable {
        let id: UUID
        let text: String
    }

    struct IndexRecord: Codable {
        let textHash: String
        let vector: [Float]
    }

    /// The index is sealed with the same Keychain key as entry text (`MirrorEncryption`, AES-GCM):
    /// vectors are derived from journal text and can leak some of it, so they get the entries'
    /// protection, not just iOS file protection (which is weaker still on the Mac).
    private static func indexDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = appSupport.appendingPathComponent("Mirror", isDirectory: true).appendingPathComponent("Index", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func indexURL() throws -> URL {
        try indexDirectory().appendingPathComponent("entry-embeddings.sealed")
    }

    /// Pre-encryption dev builds (2026-10-08) wrote the index unsealed under this name.
    private static func legacyPlaintextIndexURL() throws -> URL {
        try indexDirectory().appendingPathComponent("entry-embeddings.plist")
    }

    /// The index as a sealed blob, or nil when the content key isn't available (nothing is written then).
    static func sealIndex(_ index: [UUID: IndexRecord]) -> Data? {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let plain = try? encoder.encode(index) else { return nil }
        return MirrorEncryption.sealData(plain)
    }

    /// nil when the blob can't be opened (key unavailable, or not a sealed index); the index is then rebuilt.
    static func openIndex(_ sealed: Data) -> [UUID: IndexRecord]? {
        guard let plain = MirrorEncryption.openData(sealed) else { return nil }
        return try? PropertyListDecoder().decode([UUID: IndexRecord].self, from: plain)
    }

    private static func loadIndex() throws -> [UUID: IndexRecord] {
        if let legacy = try? legacyPlaintextIndexURL() { try? FileManager.default.removeItem(at: legacy) }
        guard let index = openIndex(try Data(contentsOf: indexURL())) else {
            try? FileManager.default.removeItem(at: indexURL())
            return [:]
        }
        return index
    }

    private func saveIndex() throws {
        guard let sealed = Self.sealIndex(index) else { return }
        var url = try Self.indexURL()
        try sealed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func embeddedText(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxEmbeddedCharacters))
    }

    static func textHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func isCurrent(_ document: Document) -> Bool {
        index[document.id]?.textHash == Self.textHash(Self.embeddedText(document.text))
    }

    /// Embeds every document that's missing or edited since, drops vectors of deleted entries, and
    /// saves. Loads the embedder for the pass and releases it after, so it never sits in memory next
    /// to Gemma longer than one pass.
    func refresh(_ documents: [Document]) async {
        guard modelState == .installed else { return }
        // One pass at a time. The task clears `backfillTask` itself before it finishes, so a caller
        // that waited never sees the finished task again (2026-10-08: re-checking a finished task
        // that hadn't been cleared yet recursed without end, and iOS killed the app mid-backfill).
        while let running = backfillTask {
            await running.value
        }
        let task = Task {
            await runRefresh(documents)
            backfillTask = nil
        }
        backfillTask = task
        await task.value
    }

    private func runRefresh(_ documents: [Document]) async {
        let live = Set(documents.map(\.id))
        index = index.filter { live.contains($0.key) }
        let stale = documents.filter { !isCurrent($0) }
        guard !stale.isEmpty else {
            try? saveIndex()
            return
        }
        guard let embedder = try? LlamaEmbedder(path: Self.modelFileURL().path) else {
            modelState = .failed
            return
        }
        for (count, document) in stale.enumerated() {
            if Task.isCancelled { break }
            let text = Self.embeddedText(document.text)
            if let vector = try? Self.embed(Self.documentPrefix + text, with: embedder) {
                index[document.id] = IndexRecord(textHash: Self.textHash(text), vector: vector)
            }
            if count % 50 == 49 { try? saveIndex() }
        }
        try? saveIndex()
    }

    /// `LlamaEmbedder.embed`, halving text that's over the token limit instead of failing.
    private static func embed(_ text: String, with embedder: LlamaEmbedder) throws -> [Float] {
        var text = text
        while true {
            do {
                return try embedder.embed(text)
            } catch LlamaEmbedder.EmbedderError.tooLong {
                guard text.count > 64 else { throw LlamaEmbedder.EmbedderError.tooLong(tokens: 0, limit: embedder.maxTokens) }
                text = String(text.prefix(text.count / 2))
            }
        }
    }

    // MARK: Search

    /// The `limit` documents closest to `question`, best first, or nil when Ask should use keyword
    /// search instead: no model yet, or the index doesn't cover enough of the journal (a backfill
    /// is started for next time). `documents` must be the readable entries, newest first; ties keep
    /// that order.
    func search(question: String, in documents: [Document], limit: Int) async -> [UUID]? {
        guard modelState == .installed, !documents.isEmpty else { return nil }
        let covered = documents.filter(isCurrent).count
        guard Double(covered) / Double(documents.count) >= Self.minimumCoverage else {
            Task { await refresh(documents) }
            return nil
        }
        guard let embedder = try? LlamaEmbedder(path: Self.modelFileURL().path),
              let query = try? Self.embed(Self.queryPrefix + question, with: embedder) else { return nil }
        let scored: [(index: Int, id: UUID, score: Float)] = documents.enumerated().compactMap { position, document in
            guard isCurrent(document), let record = index[document.id] else { return nil }
            return (position, document.id, zip(query, record.vector).reduce(0) { $0 + $1.0 * $1.1 })
        }
        let ranked = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        let result = ranked.prefix(limit).map(\.id)
        // Entries written since the last pass get indexed in the background for the next question.
        if covered < documents.count { Task { await refresh(documents) } }
        return result
    }
}
