import Foundation

/// Cleanup via any OpenAI-compatible chat-completions endpoint. One struct covers
/// OpenAI, Groq, Sarvam, LM Studio, and similar: only the base URL, model, and
/// key differ. This is the seam for Indian-language models like Sarvam.
public struct OpenAICompatibleCleanup: CleanupProvider {
    public let id = "openai"
    public let displayName = "Cloud (OpenAI-compatible)"
    public let requiresNetwork = true

    let baseURL: String
    let model: String
    let apiKey: String
    let tone: String?
    let vocabulary: [String]
    let destination: String?

    public init(baseURL: String, model: String, apiKey: String, tone: String? = nil,
                vocabulary: [String] = [], destination: String? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.tone = tone
        self.vocabulary = vocabulary
        self.destination = destination
    }

    public func clean(_ text: String, language: Language) async throws -> String {
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmedBase + "/chat/completions") else {
            throw CleanupError.badResponse("invalid base URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": CleanupPrompt.system(for: language, tone: tone, vocabulary: vocabulary, destination: destination)],
                ["role": "user", "content": text],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CleanupError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw CleanupError.badResponse("unexpected response shape")
        }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }
}
