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
    var encryptedContent: String = ""
    var generatedAt: Date = Date()
    var periodIdentifier: String = ""
    var encryptedQuestion: String?

    var content: String {
        get { MirrorEncryption.decryptString(encryptedContent) }
        set { encryptedContent = MirrorEncryption.encryptString(newValue) }
    }

    var question: String? {
        get { MirrorEncryption.decryptOptionalString(encryptedQuestion) }
        set { encryptedQuestion = MirrorEncryption.encryptOptionalString(newValue) }
    }

    init(type: InsightType, content: String, periodIdentifier: String, question: String? = nil) {
        self.id = UUID()
        self.type = type
        self.encryptedContent = MirrorEncryption.encryptString(content)
        self.generatedAt = Date()
        self.periodIdentifier = periodIdentifier
        self.encryptedQuestion = MirrorEncryption.encryptOptionalString(question)
    }
}
