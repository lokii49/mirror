import Foundation
import SwiftData

@Model final class UserProfile {
    var onboardingComplete: Bool = false
    var streakCount: Int = 0
    var lastWritten: Date? = nil

    init() {}
}
