import Foundation
import Combine

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case done(String)
    case error(String)

    var label: String {
        switch self {
        case .idle:            return "Ready"
        case .recording:       return "Recording…"
        case .processing:      return "Transcribing…"
        case .done(let text):  return text
        case .error(let msg):  return "Error: \(msg)"
        }
    }

    var isRecording:  Bool { self == .recording }
    var isProcessing: Bool { self == .processing }
    var isDone: Bool {
        if case .done = self { return true }
        return false
    }
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()
    private init() {}

    @Published var state: RecordingState = .idle

    /// Normalised 0–1 audio power level, updated on recording thread.
    @Published var audioLevel: Float = 0.0

    /// Per-bar levels for the waveform visualiser (5 bars).
    @Published var barLevels: [Float] = [0, 0, 0, 0, 0]

    // Convenience booleans for views
    var isRecording:  Bool { state.isRecording }
    var isProcessing: Bool { state.isProcessing }
    var isBusy: Bool { state.isRecording || state.isProcessing }

    // MARK: Transitions

    func transition(to newState: RecordingState) {
        state = newState
        if newState == .idle || newState == .recording {
            audioLevel = 0
            barLevels  = [0, 0, 0, 0, 0]
        }
    }

    func setResult(_ text: String) {
        state = .done(text)
    }

    /// Called from audio thread — bounced to main.
    nonisolated func updateAudioLevel(_ level: Float) {
        Task { @MainActor in
            self.audioLevel = level
            // Compute 5 pseudo-random bar heights from the overall level
            // so they look independently animated while still tracking volume.
            let t = Double(level)
            self.barLevels = (0..<5).map { i in
                let phase = Double(i) * 0.7
                let wave  = (sin(Date().timeIntervalSinceReferenceDate * 8.0 + phase) * 0.3 + 0.7)
                return Float(t * wave)
            }
        }
    }
}
