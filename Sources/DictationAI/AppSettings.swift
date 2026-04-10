import Foundation
import AppKit

// MARK: - Recording Mode

enum RecordingMode: String, CaseIterable, Identifiable {
    case hold   = "hold"
    case toggle = "toggle"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hold:   return "Hold to Talk"
        case .toggle: return "Toggle"
        }
    }
}

// MARK: - LLM Provider

enum LLMProvider: String, CaseIterable, Identifiable {
    case xai        = "xai"
    case openrouter = "openrouter"
    case custom     = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .xai:        return "xAI (Grok)"
        case .openrouter: return "OpenRouter"
        case .custom:     return "Custom (OpenAI-compatible)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .xai:        return "https://api.x.ai/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .custom:     return "https://api.example.com/v1"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .xai:        return "sk-…"
        case .openrouter: return "sk-or-v1-…"
        case .custom:     return "sk-…"
        }
    }

    var keyURL: URL {
        switch self {
        case .xai:        return URL(string: "https://console.x.ai")!
        case .openrouter: return URL(string: "https://openrouter.ai/keys")!
        case .custom:     return URL(string: "https://openrouter.ai/keys")!
        }
    }

    var keyLinkLabel: String {
        switch self {
        case .xai:        return "Get xAI key →"
        case .openrouter: return "Get OpenRouter key →"
        case .custom:     return "Get API key →"
        }
    }

    var defaultModels: [String] {
        switch self {
        case .xai:        return ["grok-3-mini", "grok-3", "grok-2"]
        case .openrouter: return [
            "openrouter/free",
            "meta-llama/llama-3.3-70b-instruct:free",
            "google/gemma-3-27b-it:free",
            "mistralai/devstral-2512:free",
            "nvidia/nemotron-3-super:free"
        ]
        case .custom:     return []
        }
    }

    var defaultModel: String {
        switch self {
        case .xai:        return "grok-3-mini"
        case .openrouter: return "openrouter/free"
        case .custom:     return ""
        }
    }
}

// MARK: - AppSettings

final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    // ── LLM Provider ──────────────────────────────────────────────────────────

    @Published var llmProvider: LLMProvider {
        didSet {
            save("llmProvider", llmProvider.rawValue)
            // When switching provider, reset base URL and model to provider defaults
            if oldValue != llmProvider {
                llmBaseURL = llmProvider.defaultBaseURL
                llmModel   = llmProvider.defaultModel
            }
        }
    }

    @Published var llmApiKey: String            { didSet { save("llmApiKey", llmApiKey) } }
    @Published var llmBaseURL: String           { didSet { save("llmBaseURL", llmBaseURL) } }
    @Published var llmModel: String             { didSet { save("llmModel", llmModel) } }
    @Published var enhancementEnabled: Bool     { didSet { save("enhancementEnabled", enhancementEnabled) } }
    @Published var enhancementPrompt: String    { didSet { save("enhancementPrompt", enhancementPrompt) } }

    // ── Legacy compat — read old xAI key on first migration ───────────────────

    // ── Whisper ───────────────────────────────────────────────────────────────

    @Published var whisperModel: String         { didSet { save("whisperModel", whisperModel) } }
    @Published var language: String             { didSet { save("language", language) } }

    // ── Hotkey ────────────────────────────────────────────────────────────────

    @Published var recordingMode: RecordingMode {
        didSet { save("recordingMode", recordingMode.rawValue) }
    }
    @Published var holdKeyCode: Int             { didSet { save("holdKeyCode", holdKeyCode) } }
    @Published var holdKeyLabel: String         { didSet { save("holdKeyLabel", holdKeyLabel) } }

    // ── Behaviour ─────────────────────────────────────────────────────────────

    @Published var autoPaste: Bool              { didSet { save("autoPaste", autoPaste) } }

    // ── Pill position ─────────────────────────────────────────────────────────

    @Published var pillX: CGFloat               { didSet { save("pillX", Double(pillX)) } }
    @Published var pillY: CGFloat               { didSet { save("pillY", Double(pillY)) } }

    // ── Static lists ──────────────────────────────────────────────────────────

    static let whisperModels = ["tiny", "base", "small", "medium", "large-v3", "large-v3-turbo"]

    static let defaultPrompt = """
        You are a dictation cleanup assistant. Fix punctuation and capitalisation. \
        Remove filler words (um, uh, like, you know). Return only the cleaned text — \
        no explanation, no quotes.
        """

    // ── Init ──────────────────────────────────────────────────────────────────

    private init() {
        let d = defaults

        // Resolve provider (migrate from old xAI-only settings if needed)
        let providerRaw = d.string(forKey: "llmProvider") ?? ""
        let resolvedProvider = LLMProvider(rawValue: providerRaw) ?? .xai
        llmProvider = resolvedProvider

        // API key — migrate from old "xaiApiKey" if no new key stored yet
        let newKey = d.string(forKey: "llmApiKey")
        if let newKey, !newKey.isEmpty {
            llmApiKey = newKey
        } else {
            llmApiKey = d.string(forKey: "xaiApiKey") ?? ""
        }

        llmBaseURL = d.string(forKey: "llmBaseURL") ?? resolvedProvider.defaultBaseURL
        llmModel   = d.string(forKey: "llmModel")   ?? d.string(forKey: "xaiModel") ?? resolvedProvider.defaultModel

        enhancementEnabled = d.object(forKey: "enhancementEnabled") as? Bool ?? true
        enhancementPrompt  = d.string(forKey: "enhancementPrompt") ?? AppSettings.defaultPrompt
        whisperModel       = d.string(forKey: "whisperModel") ?? "base"
        language           = d.string(forKey: "language") ?? ""
        recordingMode      = RecordingMode(rawValue: d.string(forKey: "recordingMode") ?? "") ?? .hold
        holdKeyCode        = d.object(forKey: "holdKeyCode") as? Int ?? 63  // Globe/Fn
        holdKeyLabel       = d.string(forKey: "holdKeyLabel") ?? "Fn / Globe ⌨"
        autoPaste          = d.object(forKey: "autoPaste") as? Bool ?? true

        // Default pill position: bottom-right of screen
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let savedX = d.double(forKey: "pillX")
        let savedY = d.double(forKey: "pillY")
        pillX = CGFloat(savedX != 0 ? savedX : screen.maxX - 420)
        pillY = CGFloat(savedY != 0 ? savedY : screen.minY + 80)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }

    var hasAPIKey: Bool { !llmApiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Full chat completions endpoint URL built from the base URL.
    var completionsURL: URL {
        let base = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/chat/completions")!
    }
}
