import Foundation
import WhisperKit

// MARK: - WhisperTranscriber

@MainActor
final class WhisperTranscriber: ObservableObject {

    static let shared = WhisperTranscriber()
    private init() {}

    @Published var modelState: ModelState = .notLoaded
    @Published var downloadProgress: Double = 0

    private var whisper: WhisperKit?

    enum ModelState: Equatable {
        case notLoaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .notLoaded:            return "Model not loaded"
            case .downloading(let p):   return "Downloading model (\(Int(p * 100))%)"
            case .loading:              return "Loading model…"
            case .ready:                return "Ready"
            case .failed(let e):        return "Error: \(e)"
            }
        }
        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    // MARK: - Load model

    func loadModel(_ modelName: String) async {
        guard modelState != .ready else { return }

        modelState = .loading
        do {
            let config = WhisperKitConfig(
                model:                 modelName,
                verbose:               false,
                logLevel:              .none,
                prewarm:               true,
                load:                  true,
                download:              true
            )
            whisper = try await WhisperKit(config)
            modelState = .ready
        } catch {
            modelState = .failed(error.localizedDescription)
            print("[WhisperTranscriber] Load failed: \(error)")
        }
    }

    // MARK: - Transcribe

    /// Transcribe Float32 audio samples (16 kHz mono) directly.
    /// Uses transcribe(audioArray:) which bypasses WAV file I/O and is
    /// the most reliable path. Falls back to bare defaults if options
    /// cause empty results (known WhisperKit quirk).
    func transcribe(audioSamples: [Float],
                    language: String = "",
                    modelName: String = "base") async throws -> String {

        // Lazy-load the model if not already loaded
        if whisper == nil || !modelState.isReady {
            await loadModel(modelName)
        }

        guard let pipe = whisper else {
            throw TranscribeError.modelNotReady
        }

        print("[Whisper] Transcribing \(audioSamples.count) samples via audioArray")

        var options = DecodingOptions()
        options.task             = .transcribe
        options.skipSpecialTokens = true
        if !language.isEmpty { options.language = language }

        // Primary attempt
        var result = try await pipe.transcribe(audioArray: audioSamples,
                                               decodeOptions: options)
        print("[Whisper] Primary result: \(result?.text.debugDescription ?? "nil")")

        // speak2-style fallback: if empty, retry with bare defaults
        // (some DecodingOptions combinations trigger false no-speech detection)
        if result?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            print("[Whisper] Primary empty — retrying with default options")
            result = try await pipe.transcribe(audioArray: audioSamples)
            print("[Whisper] Fallback result: \(result?.text.debugDescription ?? "nil")")
        }

        // Strip blank-audio special tokens
        let blankTokens: Set<String> = ["[_blank_audio]", "[blank_audio]"]
        let raw = result?.segments ?? []
        let text = raw
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !blankTokens.contains($0.lowercased()) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("[Whisper] Final text: \(text.debugDescription)")
        return text
    }

    // MARK: - Errors

    enum TranscribeError: LocalizedError {
        case modelNotReady
        var errorDescription: String? {
            switch self {
            case .modelNotReady: return "Whisper model is not loaded yet."
            }
        }
    }
}
