import Foundation
import Testing
@testable import mirror

/// Mood check-ins to Health: every mood maps to a State of Mind label and a valence whose sign
/// matches the app's own positive/difficult split.
@Suite("Health mood mapping")
struct HealthMoodWriterTests {
    @Test(arguments: MirrorTheme.moodOptions)
    func everyMoodHasAValenceOfTheRightSign(_ mood: String) throws {
        let valence = try #require(HealthMoodWriter.valence[mood])
        #expect((-1...1).contains(valence))
        #expect(MirrorTheme.negativeMoods.contains(mood) ? valence < 0 : valence > 0)
    }

    @Test(arguments: MirrorTheme.moodOptions)
    func everyMoodHasAHealthLabel(_ mood: String) {
        if #available(iOS 18.0, *) {
            #expect(HealthMoodWriter.label(for: mood) != nil)
        }
    }

    @Test func offByDefault() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: HealthMoodWriter.enabledKey)
        defaults.removeObject(forKey: HealthMoodWriter.enabledKey)
        #expect(!HealthMoodWriter.isEnabled)
        if let saved { defaults.set(saved, forKey: HealthMoodWriter.enabledKey) }
    }
}
