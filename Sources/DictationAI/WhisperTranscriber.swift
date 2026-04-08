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

    func transcribe(audioFileURL: URL,
                    language: String = "",
                    modelName: String = "base") async throws -> String {

        // Lazy-load the model if not already loaded
        if whisper == nil || !modelState.isReady {
            await loadModel(modelName)
        }

        guard let pipe = whisper else {
            throw TranscribeError.modelNotReady
        }

        var options = DecodingOptions()
        options.task = .transcribe
        if !language.isEmpty {
            options.language = language
        }
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true

        let results = try await pipe.transcribe(
            audioPath: audioFileURL.path,
            decodeOptions: options
        )

        // Flatten all segments into a single string
        let text = results
            .flatMap { $0.segments }
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

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
