import Foundation
import SwiftUI

@MainActor
@Observable
final class BrainViewModel {
    static let minimumEntries = 10

    enum State {
        case idle
        case notEnoughEntries(remaining: Int)
        case loading
        /// Enough entries, but no recurring terms survived the filters.
        case empty
        case ready(BrainGraph)
    }

    var state: State = .idle

    private var lastFingerprint: Int?

    func rebuild(entries: [Entry], canvasSize: CGSize) async {
        guard entries.count >= Self.minimumEntries else {
            state = .notEnoughEntries(remaining: Self.minimumEntries - entries.count)
            return
        }

        let fingerprint = Self.fingerprint(of: entries)
        // Every terminal state (.ready and .empty alike) re-mounts its own
        // .task(id:) on display, which fires this again. Without this guard
        // an .empty result set state back to .loading unconditionally below,
        // remounting the loading branch's task and looping .loading <-> .empty
        // forever — visible as "Mapping your mind…" never resolving.
        if fingerprint == lastFingerprint { return }

        if case .ready = state {} else { state = .loading }

        // Snapshot on the main actor — decryption happens here; @Model
        // instances never cross to the extraction actor.
        let snapshots: [EntryTextSnapshot] = entries.map { entry in
            EntryTextSnapshot(
                id: entry.id,
                fingerprint: Self.entryFingerprint(entry),
                text: String(entry.insightContext.prefix(ThemeExtractionService.maxTextLength)),
                moodScore: entry.mood.flatMap { MirrorTheme.moodScore[$0] },
                createdAt: entry.createdAt
            )
        }

        let termsByEntry = await ThemeExtractionService.shared.termsBatch(for: snapshots)
        let moodScoreByEntry = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.id, $0.moodScore) }
        )
        let size = canvasSize.width > 0 && canvasSize.height > 0
            ? canvasSize
            : CGSize(width: 390, height: 700)

        let graph = await Task.detached(priority: .userInitiated) {
            BrainGraphBuilder.build(
                termsByEntry: termsByEntry,
                moodScoreByEntry: moodScoreByEntry,
                canvasSize: size
            )
        }.value

        lastFingerprint = fingerprint
        state = graph.nodes.isEmpty ? .empty : .ready(graph)
    }

    func entries(for node: BrainNode, in allEntries: [Entry]) -> [Entry] {
        allEntries
            .filter { node.entryIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func fingerprint(of entries: [Entry]) -> Int {
        var hasher = Hasher()
        hasher.combine(entries.count)
        for entry in entries {
            hasher.combine(entryFingerprint(entry))
        }
        return hasher.finalize()
    }

    /// Hash of ciphertext blobs — changes only when content is rewritten,
    /// so it detects edits without decrypting.
    static func entryFingerprint(_ entry: Entry) -> Int {
        var hasher = Hasher()
        hasher.combine(entry.id)
        hasher.combine(entry.encryptedText)
        hasher.combine(entry.encryptedMood)
        hasher.combine(entry.encryptedVoiceNoteTranscript)
        hasher.combine(entry.encryptedVoiceNoteEnglishTranslation)
        hasher.combine(entry.encryptedAdditionalVoiceNoteTranscriptsStorage)
        hasher.combine(entry.encryptedAdditionalVoiceNoteEnglishTranslationsStorage)
        return hasher.finalize()
    }
}
