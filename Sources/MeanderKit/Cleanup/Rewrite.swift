import Foundation

/// A provider that can follow a spoken instruction over a piece of text (Quill).
/// Only LLM-backed providers conform; the deterministic rules cannot rewrite.
public protocol RewriteProvider {
    /// - Parameters:
    ///   - selection: the text the user had selected, or empty to generate new text.
    ///   - instruction: what the user said, e.g. "make this friendlier".
    func rewrite(selection: String, instruction: String) async throws -> String
}

public enum QuillPrompt {
    public static let system = """
    You are a writing assistant that edits or writes text for the user. \
    The user gives a spoken instruction, and optionally the text it applies to. \
    If text is provided, apply the instruction to that text and return the full \
    revised text. If no text is provided, write the text the instruction asks for. \
    Keep the same language and script as the input unless told otherwise. \
    Output ONLY the resulting text, with no preface, quotes or commentary.
    """

    public static func user(selection: String, instruction: String) -> String {
        if selection.isEmpty {
            return "Instruction: \(instruction)"
        }
        return "Instruction: \(instruction)\n\nText:\n\(selection)"
    }
}

extension OllamaCleanup: RewriteProvider {
    public func rewrite(selection: String, instruction: String) async throws -> String {
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmedBase + "/api/generate") else {
            throw CleanupError.badResponse("invalid base URL")
        }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "system": QuillPrompt.system,
            "prompt": QuillPrompt.user(selection: selection, instruction: instruction),
            "stream": false,
            "options": ["temperature": 0.4],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CleanupError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["response"] as? String
        else { throw CleanupError.badResponse("unexpected response shape") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension OpenAICompatibleCleanup: RewriteProvider {
    public func rewrite(selection: String, instruction: String) async throws -> String {
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmedBase + "/chat/completions") else {
            throw CleanupError.badResponse("invalid base URL")
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": QuillPrompt.system],
                ["role": "user", "content": QuillPrompt.user(selection: selection, instruction: instruction)],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CleanupError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw CleanupError.badResponse("unexpected response shape") }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
