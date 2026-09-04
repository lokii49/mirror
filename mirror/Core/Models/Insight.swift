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
    /// Which engine produced this insight — LLMEngine.rawValue ("foundationModels"/"gemma"),
    /// diagnostic attribution only (Track A6, .claude/2.1.0-design-plan.md). Not encrypted:
    /// this identifies which on-device model ran, not journal content. Never shown in the UI —
    /// InsightService callers still don't branch on which engine ran; this exists solely so a
    /// quality regression report can be traced to an engine. Optional/nil for insights
    /// generated before this field existed.
    var generatedByEngine: String? = nil

    var content: String {
        get { MirrorEncryption.decryptString(encryptedContent) }
        set { encryptedContent = MirrorEncryption.encryptString(newValue) }
    }

    var question: String? {
        get { MirrorEncryption.decryptOptionalString(encryptedQuestion) }
        set { encryptedQuestion = MirrorEncryption.encryptOptionalString(newValue) }
    }

    init(type: InsightType, content: String, periodIdentifier: String, question: String? = nil, generatedByEngine: LLMEngine? = nil) {
        self.id = UUID()
        self.type = type
        self.encryptedContent = MirrorEncryption.encryptString(content)
        self.generatedAt = Date()
        self.periodIdentifier = periodIdentifier
        self.encryptedQuestion = MirrorEncryption.encryptOptionalString(question)
        self.generatedByEngine = generatedByEngine?.rawValue
    }
}
