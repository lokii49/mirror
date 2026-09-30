import Foundation
import SwiftData

/// One-time pass that recounts stored `Entry.wordCount` for Japanese and Chinese entries.
/// Before `segmentedWordCount`, a whole unspaced line counted as one word, so these entries have
/// tiny counts that feed XP, the daily goal, Settings totals, the "most words" sort and monthly
/// report totals. Only entries containing those scripts are touched; every other entry keeps the
/// count it has. Sets `wordCount` only (no text, no other field).
enum CJKWordCountRecount {
    static let flag = "mirror.didRecountCJKWordCounts.v1"

    @MainActor
    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        // An empty store may just not have synced yet: retry next foreground instead of
        // marking done.
        guard !entries.isEmpty else { return }

        var changed = 0
        for entry in entries {
            guard let text = entry.decryptedText, containsUnspacedScript(text) else { continue }
            let recount = strippedWordCount(text)
            if recount != entry.wordCount {
                entry.wordCount = recount
                changed += 1
            }
        }
        do {
            if changed > 0 { try context.save() }
            UserDefaults.standard.set(true, forKey: flag)
        } catch {
            // Leave the flag unset; retry next foreground.
        }
    }
}
