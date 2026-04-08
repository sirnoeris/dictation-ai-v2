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

// MARK: - AppSettings

final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    // ── xAI / Grok ────────────────────────────────────────────────────────────

    @Published var xaiApiKey: String           { didSet { save("xaiApiKey", xaiApiKey) } }
    @Published var xaiModel: String            { didSet { save("xaiModel", xaiModel) } }
    @Published var enhancementEnabled: Bool    { didSet { save("enhancementEnabled", enhancementEnabled) } }
    @Published var enhancementPrompt: String   { didSet { save("enhancementPrompt", enhancementPrompt) } }

    // ── Whisper ───────────────────────────────────────────────────────────────

    @Published var whisperModel: String        { didSet { save("whisperModel", whisperModel) } }
    @Published var language: String            { didSet { save("language", language) } }

    // ── Hotkey ────────────────────────────────────────────────────────────────

    @Published var recordingMode: RecordingMode {
        didSet { save("recordingMode", recordingMode.rawValue) }
    }
    @Published var holdKeyCode: Int            { didSet { save("holdKeyCode", holdKeyCode) } }
    @Published var holdKeyLabel: String        { didSet { save("holdKeyLabel", holdKeyLabel) } }

    // ── Behaviour ─────────────────────────────────────────────────────────────

    @Published var autoPaste: Bool             { didSet { save("autoPaste", autoPaste) } }

    // ── Pill position ─────────────────────────────────────────────────────────

    @Published var pillX: CGFloat              { didSet { save("pillX", Double(pillX)) } }
    @Published var pillY: CGFloat              { didSet { save("pillY", Double(pillY)) } }

    // ── Static lists ──────────────────────────────────────────────────────────

    static let whisperModels = ["tiny", "base", "small", "medium", "large-v3", "large-v3-turbo"]
    static let grokModels    = ["grok-3-mini", "grok-3", "grok-2"]

    static let defaultPrompt = """
        You are a dictation cleanup assistant. Fix punctuation and capitalisation. \
        Remove filler words (um, uh, like, you know). Return only the cleaned text — \
        no explanation, no quotes.
        """

    // ── Init ──────────────────────────────────────────────────────────────────

    private init() {
        let d = defaults
        xaiApiKey         = d.string(forKey: "xaiApiKey") ?? ""
        xaiModel          = d.string(forKey: "xaiModel")  ?? "grok-3-mini"
        enhancementEnabled = d.object(forKey: "enhancementEnabled") as? Bool ?? true
        enhancementPrompt = d.string(forKey: "enhancementPrompt") ?? AppSettings.defaultPrompt
        whisperModel      = d.string(forKey: "whisperModel") ?? "base"
        language          = d.string(forKey: "language") ?? ""
        recordingMode     = RecordingMode(rawValue: d.string(forKey: "recordingMode") ?? "") ?? .hold
        holdKeyCode       = d.object(forKey: "holdKeyCode") as? Int ?? 63  // Globe/Fn
        holdKeyLabel      = d.string(forKey: "holdKeyLabel") ?? "Fn / Globe ⌨"
        autoPaste         = d.object(forKey: "autoPaste") as? Bool ?? true

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

    var hasXAIKey: Bool { !xaiApiKey.trimmingCharacters(in: .whitespaces).isEmpty }
}
