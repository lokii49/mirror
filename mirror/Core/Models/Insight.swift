import Foundation
import SwiftData

enum InsightType: String, Codable {
    case dailyNudge
    case weeklyDigest
    case monthlyReport
    case askResponse
}

@Model final class Insight {
    var id: UUID = UUID()
    var type: InsightType = InsightType.dailyNudge
    var content: String = ""
    var generatedAt: Date = Date()
    var periodIdentifier: String = ""
    var question: String?

    init(type: InsightType, content: String, periodIdentifier: String, question: String? = nil) {
        self.id = UUID()
        self.type = type
        self.content = content
        self.generatedAt = Date()
        self.periodIdentifier = periodIdentifier
        self.question = question
    }
}
