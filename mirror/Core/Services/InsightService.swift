import Foundation

enum InsightError: LocalizedError {
    case unauthorized
    case subscriptionRequired
    case serverError(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Sign in to generate insights."
        case .subscriptionRequired: return "Core subscription required."
        case .serverError(let code): return "Server error (\(code))."
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
        let texts = entries.prefix(7).map(\.text)
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

    static func ask(question: String, entries: [Entry], token: String) async throws -> String {
        let relevant = SearchService.search(query: question, in: entries)
        return try await post(
            WorkerRequest(
                type: "askQuestion",
                entries: relevant.map(\.text),
                periodIdentifier: DateHelpers.monthIdentifier(for: Date()),
                question: question
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
        default:  throw InsightError.serverError(status)
        }
    }
}
