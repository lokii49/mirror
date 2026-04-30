import Foundation

struct VoiceTranscription: Codable {
    let transcript: String
    let languageCode: String
    let languageName: String
    let englishTranslation: String
}

private struct VoiceTranscriptionRequest: Encodable {
    let type = "transcribeVoiceNote"
    let audioBase64: String
    let mimeType: String
}

enum VoiceTranscriptionService {
    static func transcribe(audioData: Data, token: String) async throws -> VoiceTranscription {
        var request = URLRequest(url: InsightService.workerURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            VoiceTranscriptionRequest(
                audioBase64: audioData.base64EncodedString(),
                mimeType: "audio/mp4"
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200:
            return try JSONDecoder().decode(VoiceTranscription.self, from: data)
        case 401:
            throw InsightError.unauthorized
        case 402:
            throw InsightError.subscriptionRequired
        default:
            throw InsightError.serverError(status)
        }
    }
}
