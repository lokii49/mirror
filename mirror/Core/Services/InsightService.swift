import Foundation

enum InsightError: LocalizedError {
    case unauthorized
    case subscriptionRequired
    case serverError(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Sign in to generate insights."
        case .subscriptionRequired: return "Core subscription required."
        case .serverError(let code, let detail):
            return detail.isEmpty ? "Server error (\(code))." : "[\(code)] \(detail)"
        case .emptyResponse: return "No insight returned."
        }
    }
}

private struct WorkerRequest: Encodable {
    let type: String
    let entries: [String]
    let periodIdentifier: String
    let question: String?
}

private struct WorkerResponse: Decodable {
    let insight: String
}

enum InsightService {
    static let workerURL = URL(string: "https://mirror-worker.2qm8vh77mq.workers.dev")!

    static func generateNudge(entries: [Entry], token: String) async throws -> String {
        let texts = entries.prefix(7).map { $0.insightContext }
        return try await post(
            WorkerRequest(
                type: "dailyNudge",
                entries: Array(texts),
                periodIdentifier: DateHelpers.dayIdentifier(for: Date()),
                question: nil
            ),
            token: token
        )
    }

    static func generateWeeklyDigest(entries: [Entry], token: String) async throws -> String {
        let texts = entries.prefix(14).map { $0.insightContext }
        return try await post(
            WorkerRequest(
                type: "weeklyDigest",
                entries: Array(texts),
                periodIdentifier: DateHelpers.weekIdentifier(for: Date()),
                question: nil
            ),
            token: token
        )
    }

    static func ask(question: String, entries: [Entry], token: String) async throws -> String {
        let relevant = SearchService.search(query: question, in: entries)
        return try await post(
            WorkerRequest(
                type: "askQuestion",
                entries: relevant.map { $0.insightContext },
                periodIdentifier: DateHelpers.monthIdentifier(for: Date()),
                question: question
            ),
            token: token
        )
    }

    static func detectEmotion(text: String, token: String) async throws -> String {
        let trimmed = String(text.prefix(3000))
        return try await post(
            WorkerRequest(
                type: "detectEmotion",
                entries: [trimmed],
                periodIdentifier: "",
                question: nil
            ),
            token: token
        )
    }

    private static func post(_ body: WorkerRequest, token: String) async throws -> String {
        var req = URLRequest(url: workerURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200:
            let decoded = try JSONDecoder().decode(WorkerResponse.self, from: data)
            guard !decoded.insight.isEmpty else { throw InsightError.emptyResponse }
            return decoded.insight
        case 401: throw InsightError.unauthorized
        case 402: throw InsightError.subscriptionRequired
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw InsightError.serverError(status, body)
        }
    }
}

extension Entry {
    var insightContext: String {
        var parts: [String] = []
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !plain.isEmpty {
            parts.append(plain)
        }

        for (index, voiceNote) in voiceNotes.enumerated() {
            let transcript = voiceNote.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let translation = voiceNote.englishTranslation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !transcript.isEmpty || !translation.isEmpty else { continue }

            var block = "Voice note \(index + 1):"
            if let languageName = voiceNote.languageName, !languageName.isEmpty {
                block += "\nLanguage: \(languageName)"
            }
            if !transcript.isEmpty {
                block += "\nTranscript: \(transcript)"
            }
            if !translation.isEmpty, translation != transcript {
                block += "\nEnglish translation: \(translation)"
            }
            parts.append(block)
        }

        return parts.joined(separator: "\n\n")
    }
}
