import Foundation

// MARK: - LLMEnhancer
// Calls any OpenAI-compatible chat completions endpoint to clean up raw
// dictation text: fix punctuation, remove fillers, normalise casing.
// Works with xAI, OpenRouter, or any custom provider.

actor GrokEnhancer {

    static let shared = GrokEnhancer()
    private init() {}

    // MARK: - Enhance

    /// Returns cleaned text, or throws on network / API error.
    /// Callers should fall back to `rawText` on failure.
    ///
    /// The `endpointURL` parameter allows any OpenAI-compatible provider
    /// (xAI, OpenRouter, local Ollama, etc.).
    func enhance(_ rawText: String,
                 apiKey:     String,
                 model:      String,
                 prompt:     String,
                 endpointURL: URL) async throws -> String {
        let wordCount = rawText.split(separator: " ").count
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { return rawText }

        // Skip cleanup for very short utterances — save latency
        guard wordCount > 5 else { return rawText }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user",   "content": rawText]
            ],
            "temperature": 0.2,
            "max_tokens": 1024
        ]

        var request = URLRequest(url: endpointURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespaces))",
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(http.statusCode, body)
        }

        guard let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.malformedResponse
        }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? rawText : cleaned
    }

    // MARK: - Errors

    enum LLMError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:           return "Invalid response from LLM API."
            case .httpError(let c, let b):   return "LLM API error \(c): \(b.prefix(200))"
            case .malformedResponse:         return "Unexpected LLM response format."
            }
        }
    }
}
