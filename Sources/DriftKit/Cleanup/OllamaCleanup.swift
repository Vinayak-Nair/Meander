import Foundation

/// Cleanup via a local Ollama server. Advanced/opt-in: keeps everything on-device
/// but requires the user to run Ollama and pull a model. Never part of the
/// default flow.
public struct OllamaCleanup: CleanupProvider {
    public let id = "ollama"
    public let displayName = "Local LLM (Ollama)"
    public let requiresNetwork = false // localhost only

    let baseURL: String
    let model: String
    let tone: String?
    let vocabulary: VocabularyBook
    let destination: String?

    public init(baseURL: String, model: String, tone: String? = nil,
                vocabulary: VocabularyBook = .init(), destination: String? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.tone = tone
        self.vocabulary = vocabulary
        self.destination = destination
    }

    public func clean(_ text: String, language: Language) async throws -> String {
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmedBase + "/api/generate") else {
            throw CleanupError.badResponse("invalid base URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "system": CleanupPrompt.system(for: language, tone: tone, vocabulary: vocabulary, destination: destination),
            "prompt": text,
            "stream": false,
            "options": ["temperature": 0.2],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CleanupError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let responseText = obj["response"] as? String
        else {
            throw CleanupError.badResponse("unexpected response shape")
        }

        let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }
}
