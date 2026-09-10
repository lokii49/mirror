import Foundation
import SwiftData

/// One-time repair pass over already-cached daily reflections.
///
/// A pre-existing gap let raw model preamble — "Okay, here's a reflection for
/// you, your friend:" ahead of the real observation — survive validation and
/// reach the reflection card. `cleanedInsightOutput()` now strips it
/// (`String.strippingLeadingMetaPreamble` / `strippingFriendVocative`), but a
/// reflection generated before that fix stays in SwiftData — and synced via
/// CloudKit — until a new one replaces it, which only happens on a later day
/// with new writing. This re-runs the current cleaner over each stored
/// `.dailyNudge` and writes back anything it strictly improves.
///
/// Non-destructive: never deletes a row (a CloudKit-synced delete can hand
/// another device a tombstone). Rewrites `content` in place, and only when the
/// re-cleaned text is shorter (junk removed) and still substantial. Idempotent —
/// once the flag is set it never runs again. Bump the flag suffix to force a
/// re-run after a future cleaner change.
enum CachedInsightRepair {
    private static let flag = "mirror.didRepairCachedInsights.metaPreamble.v1"
    private static let minRepairedLength = 40

    @MainActor
    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: flag) else { return }

        let insights = (try? context.fetch(FetchDescriptor<Insight>())) ?? []
        var changed = 0
        for insight in insights where insight.type == .dailyNudge {
            let original = insight.content
            let repaired = original.cleanedInsightOutput()
            // Accept only a strict improvement: shorter (preamble / "friend"
            // vocative removed) and still a real reflection, never an over-trim.
            guard repaired != original,
                  repaired.count < original.count,
                  repaired.count >= minRepairedLength else { continue }
            insight.content = repaired
            changed += 1
        }

        do {
            if changed > 0 {
                try context.save()
                mirrorApp.syncNudgeToWidget(context: context)
            }
            UserDefaults.standard.set(true, forKey: flag)
        } catch {
            // Leave the flag unset — retry on the next foreground.
        }
    }
}
