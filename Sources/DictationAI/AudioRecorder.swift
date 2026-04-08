import AVFoundation
import Foundation

// MARK: - Thread-safe buffer collector
// AVAudioEngine tap callback runs on a real-time audio thread — never touch
// @MainActor state from here. Use this lock-protected value type instead.

private final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var samples: [Float] = []
    private(set) var maxLevel: Float  = 0

    func append(_ newSamples: [Float], level: Float) {
        lock.withLock {
            samples.append(contentsOf: newSamples)
            maxLevel = max(maxLevel, level)
        }
    }

    func drain() -> (samples: [Float], maxLevel: Float) {
        lock.withLock {
            let s = samples; let m = maxLevel
            samples = []; maxLevel = 0
            return (s, m)
        }
    }
}

// MARK: - AudioRecorder

final class AudioRecorder {

    static let shared = AudioRecorder()
    private init() {}

    private let engine    = AVAudioEngine()
    private let collector = SampleCollector()
    private var isRunning = false

    /// Target sample rate for WhisperKit (must be 16 kHz).
    private let targetSampleRate: Double = 16_000

    // Callback for level updates → drives waveform animation.
    var onLevelUpdate: ((Float) -> Void)?

    // MARK: - Start

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // Desired format: mono, 16 kHz, Float32
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate:   targetSampleRate,
            channels:     1,
            interleaved:  false
        ) else {
            return
        }

        // Install a tap — buffers arrive in native hardware format.
        // We install the tap in the hardware format and convert in the callback.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isRunning else { return }
            self.process(buffer: buffer, inputFormat: inputFormat, targetFormat: monoFormat)
        }

        do {
            try engine.start()
        } catch {
            print("[AudioRecorder] Failed to start engine: \(error)")
            isRunning = false
        }
    }

    // MARK: - Stop

    /// Stop recording, write PCM to a temp WAV file, call completion on main thread.
    func stop(completion: @escaping (URL?) -> Void) {
        guard isRunning else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let (samples, _) = collector.drain()

        guard !samples.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // Write to a temp WAV on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let url = self.writePCMToFile(samples: samples)
            DispatchQueue.main.async { completion(url) }
        }
    }

    // MARK: - Processing

    private func process(buffer: AVAudioPCMBuffer,
                         inputFormat: AVAudioFormat,
                         targetFormat: AVAudioFormat) {
        // Convert to 16 kHz mono if needed
        let converted: AVAudioPCMBuffer
        if inputFormat.sampleRate == targetSampleRate && inputFormat.channelCount == 1 {
            converted = buffer
        } else if let c = convert(buffer: buffer, from: inputFormat, to: targetFormat) {
            converted = c
        } else {
            return
        }

        guard let channelData = converted.floatChannelData?[0] else { return }
        let frameCount = Int(converted.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Compute RMS for level metering
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, frameCount)))
        let db  = 20 * log10(max(rms, 1e-7))
        // Map -60dB … 0dB → 0 … 1
        let level = max(0, min(1, (db + 60) / 60))

        collector.append(samples, level: level)

        // Notify for waveform — no @MainActor call, just a closure.
        onLevelUpdate?(level)
    }

    // MARK: - Audio Format Conversion

    private func convert(buffer: AVAudioPCMBuffer,
                         from source: AVAudioFormat,
                         to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }

        let ratio = target.sampleRate / source.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outputFrames) else { return nil }

        var error: NSError?
        var inputDone = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if inputDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputDone = true
            return buffer
        }

        return error == nil ? output : nil
    }

    // MARK: - Write PCM → WAV temp file

    private func writePCMToFile(samples: [Float]) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation_\(UUID().uuidString).wav")

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate:   targetSampleRate,
            channels:     1,
            interleaved:  false
        ) else { return nil }

        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(samples.count))
            else { return nil }

            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { ptr in
                buffer.floatChannelData?[0].initialize(from: ptr.baseAddress!, count: samples.count)
            }
            try file.write(from: buffer)
            return url
        } catch {
            print("[AudioRecorder] Write failed: \(error)")
            return nil
        }
    }
}
