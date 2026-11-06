import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Mood check-ins to Apple Health as State of Mind (3.1.8, item 8; owner: write only, never read).
/// iPhone, iOS 18+, off until turned on in Settings. Written only from the check-in saved on this
/// device, never when a check-in arrives by sync, so two devices can't both write the same mood.
enum HealthMoodWriter {
    static let enabledKey = "mirror.health.writeMoodCheckIns"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// The mood scale's valence (-1…1) and Health's label for each MirrorNotes mood.
    static let valence: [String: Double] = [
        "Joyful": 0.9, "Grateful": 0.8, "Peaceful": 0.6, "Content": 0.5, "Energized": 0.6, "Hopeful": 0.5,
        "Anxious": -0.5, "Overwhelmed": -0.7, "Frustrated": -0.5, "Drained": -0.6, "Sad": -0.7, "Numb": -0.3,
    ]

    /// Whether this device can write State of Mind at all (iPhone with Health, iOS 18+).
    static var isAvailable: Bool {
        #if os(iOS) && canImport(HealthKit)
        if #available(iOS 18.0, *) { return HKHealthStore.isHealthDataAvailable() }
        #endif
        return false
    }

    #if os(iOS) && canImport(HealthKit)
    private static let store = HKHealthStore()

    @available(iOS 18.0, *)
    static func label(for mood: String) -> HKStateOfMind.Label? {
        switch mood {
        case "Joyful": return .joyful
        case "Grateful": return .grateful
        case "Peaceful": return .peaceful
        case "Content": return .content
        case "Energized": return .excited
        case "Hopeful": return .hopeful
        case "Anxious": return .anxious
        case "Overwhelmed": return .overwhelmed
        case "Frustrated": return .frustrated
        case "Drained": return .drained
        case "Sad": return .sad
        case "Numb": return .indifferent
        default: return nil
        }
    }

    /// Asks to write State of Mind (nothing is read). True when Health allows it.
    @available(iOS 18.0, *)
    static func requestAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let type = HKSampleType.stateOfMindType()
        do {
            try await store.requestAuthorization(toShare: [type], read: [])
        } catch {
            return false
        }
        return store.authorizationStatus(for: type) == .sharingAuthorized
    }
    #endif

    /// Writes one check-in, if turned on and allowed. Fire and forget: a failure never blocks the
    /// check-in, which is already saved in the journal.
    static func writeCheckIn(mood: String, at date: Date = Date()) {
        #if os(iOS) && canImport(HealthKit)
        guard isEnabled, let valence = valence[mood] else { return }
        guard #available(iOS 18.0, *), HKHealthStore.isHealthDataAvailable(), let label = label(for: mood),
              store.authorizationStatus(for: HKSampleType.stateOfMindType()) == .sharingAuthorized else { return }
        let sample = HKStateOfMind(date: date, kind: .momentaryEmotion, valence: valence, labels: [label], associations: [])
        Task.detached(priority: .utility) {
            try? await store.save(sample)
        }
        #endif
    }
}
