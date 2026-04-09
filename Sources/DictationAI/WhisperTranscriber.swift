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

        // Primary attempt — transcribe(audioArray:) returns [TranscriptionResult]
        var results = try await pipe.transcribe(audioArray: audioSamples,
                                                decodeOptions: options)
        let primaryText = results.compactMap { $0.text }.joined(separator: " ")
                                 .trimmingCharacters(in: .whitespacesAndNewlines)
        print("[Whisper] Primary result: \(primaryText.debugDescription)")

        // Fallback: retry with only skipSpecialTokens (no task/language constraints)
        // Primary sometimes fails no-speech detection; simpler options often succeed.
        if primaryText.isEmpty {
            print("[Whisper] Primary empty — retrying with minimal options")
            var fallbackOptions = DecodingOptions()
            fallbackOptions.skipSpecialTokens = true
            results = try await pipe.transcribe(audioArray: audioSamples,
                                                decodeOptions: fallbackOptions)
            let fallback = results.compactMap { $0.text }.joined(separator: " ")
                                  .trimmingCharacters(in: .whitespacesAndNewlines)
            print("[Whisper] Fallback result: \(fallback.debugDescription)")
        }

        // Strip blank-audio tokens and any residual WhisperKit timestamp tokens
        // (e.g. <|startoftranscript|>, <|0.00|>, <|endoftext|>)
        let blankTokens: Set<String> = ["[_blank_audio]", "[blank_audio]"]
        let text = results
            .flatMap { $0.segments }
            .map { seg -> String in
                // Remove <|...|> special tokens that skipSpecialTokens may have missed
                var t = seg.text
                    .replacingOccurrences(of: "<\\|[^|]+\\|>",
                                          with: "",
                                          options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return t
            }
            .filter { !blankTokens.contains($0.lowercased()) && !$0.isEmpty }
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
