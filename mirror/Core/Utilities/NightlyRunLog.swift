import Foundation

/// When the night pass (`com.lokesh.mirror.nightlyInsights`: reflection, Sunday digest, monthly report,
/// mood backfill) last ran on this device and how it ended. iOS decides whether a BGProcessingTask runs
/// at all, so without this nobody can tell a skipped night from one cut off by the system (owner,
/// 2026-10-25). Shown in Sentinel's Diagnostics. Times and an outcome only, never journal content.
enum NightlyRunLog {
    enum Outcome: String {
        case finished, expired
    }

    private static let startKey = "nightlyRunLog.lastStart"
    private static let endKey = "nightlyRunLog.lastEnd"
    private static let outcomeKey = "nightlyRunLog.lastOutcome"
    private static let countKey = "nightlyRunLog.runCount"

    static func recordStart(at date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: startKey)
        defaults.removeObject(forKey: endKey)
        defaults.removeObject(forKey: outcomeKey)
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    static func recordEnd(_ outcome: Outcome, at date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: endKey)
        defaults.set(outcome.rawValue, forKey: outcomeKey)
    }

    /// "Started 25 Oct, 3:12 AM · finished after 4 min (12 runs on this device)", or a never-ran line.
    static func summary(defaults: UserDefaults = .standard, locale: Locale = .current) -> String {
        guard let start = defaults.object(forKey: startKey) as? Date else {
            return "The night job hasn't run on this device yet."
        }
        let count = defaults.integer(forKey: countKey)
        let started = start.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
        let runs = count == 1 ? "1 run on this device" : "\(count) runs on this device"
        guard let end = defaults.object(forKey: endKey) as? Date,
              let outcome = (defaults.string(forKey: outcomeKey)).flatMap(Outcome.init(rawValue:)) else {
            return "Started \(started), no end recorded: still running, or the app was stopped (\(runs))."
        }
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let duration = minutes < 1 ? "under a minute" : "\(minutes) min"
        let how = outcome == .finished ? "finished after \(duration)" : "cut off by iOS after \(duration)"
        return "Started \(started) · \(how) (\(runs))."
    }
}
