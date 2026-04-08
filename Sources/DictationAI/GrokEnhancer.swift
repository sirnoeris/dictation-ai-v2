import Foundation

// MARK: - GrokEnhancer
// Calls xAI's OpenAI-compatible chat completions endpoint to clean up raw
// dictation text: fix punctuation, remove fillers, normalise casing.

actor GrokEnhancer {

    static let shared = GrokEnhancer()
    private init() {}

    private let endpoint = URL(string: "https://api.x.ai/v1/chat/completions")!

    // MARK: - Enhance

    /// Returns cleaned text, or throws on network / API error.
    /// Callers should fall back to `rawText` on failure.
    func enhance(_ rawText: String, settings: AppSettings) async throws -> String {
        let wordCount = rawText.split(separator: " ").count
        guard settings.hasXAIKey else { return rawText }

        // Skip cleanup for very short utterances — save latency
        guard wordCount > 5 else { return rawText }

        let body: [String: Any] = [
            "model": settings.xaiModel,
            "messages": [
                ["role": "system", "content": settings.enhancementPrompt],
                ["role": "user",   "content": rawText]
            ],
            "temperature": 0.2,
            "max_tokens": 1024
        ]

        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.xaiApiKey.trimmingCharacters(in: .whitespaces))",
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GrokError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GrokError.httpError(http.statusCode, body)
        }

        guard let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GrokError.malformedResponse
        }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? rawText : cleaned
    }

    // MARK: - Errors

    enum GrokError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:           return "Invalid response from xAI API."
            case .httpError(let c, let b):   return "xAI API error \(c): \(b.prefix(200))"
            case .malformedResponse:         return "Unexpected xAI response format."
            }
        }
    }
}
