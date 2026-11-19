import AVFoundation
import Foundation
import FluidAudio

/// Lightweight FluidAudio backend using Parakeet Realtime EOU 120M (English-only,
/// ~120M params). A small cache-aware streaming model for a fast, low-memory
/// dictation mode. Same batch-shaped adapter as the Nemotron prototype.
public final class ParakeetEouTranscriber: Transcriber, StreamingTranscriber {
    private let manager: StreamingEouAsrManager
    private let sampleRate: Double = 16_000

    // Live streaming session state.
    private var continuation: AsyncStream<[Float]>.Continuation?
    private var consumerTask: Task<Void, Never>?
    private var streamStart: DispatchTime?

    public init(manager: StreamingEouAsrManager) {
        self.manager = manager
    }

    public func transcribe(samples: [Float], language _: Language) async throws -> String {
        // Each push-to-talk utterance is independent: clear any prior stream state.
        await manager.reset()

        guard !samples.isEmpty,
            let buffer = Self.makeBuffer(from: Self.padded(samples))
        else { return "" }

        let start = DispatchTime.now()
        try await manager.appendAudio(buffer)
        try await manager.processBufferedAudio()
        let text = try await manager.finish()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

        let audioMs = Double(samples.count) / sampleRate * 1_000
        let rtf = audioMs > 0 ? elapsedMs / audioMs : 0
        print(String(
            format: "[ParakeetEOU] audio %.0fms · transcribed in %.0fms · RTF %.2f",
            audioMs, elapsedMs, rtf
        ))

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - StreamingTranscriber

    public func beginStream(onPartial: @escaping @Sendable (String) -> Void) async {
        await manager.reset()
        await manager.setPartialCallback { text in
            onPartial(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let (stream, cont) = AsyncStream<[Float]>.makeStream()
        continuation = cont
        streamStart = DispatchTime.now()

        // Single ordered consumer: feeds the manager chunk-by-chunk so the encoder
        // cache advances correctly. processBufferedAudio() decodes whole chunks as
        // enough audio accumulates, firing the partial callback as it goes.
        let manager = self.manager
        consumerTask = Task.detached {
            for await chunk in stream {
                guard let buffer = ParakeetEouTranscriber.makeBuffer(from: chunk) else { continue }
                try? await manager.appendAudio(buffer)
                try? await manager.processBufferedAudio()
            }
        }
    }

    public func feed(_ samples: [Float]) {
        continuation?.yield(samples)
    }

    public func finishStream() async throws -> String {
        continuation?.yield([Float](repeating: 0, count: Self.tailSilence))
        continuation?.finish()
        await consumerTask?.value
        let text = try await manager.finish()
        consumerTask = nil
        continuation = nil

        if let start = streamStart {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            print(String(format: "[ParakeetEOU] streaming session ended · wall %.0fms", elapsedMs))
        }
        streamStart = nil

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Silence added around a recording. The cache-aware encoder has right-context
    /// latency, so the last words are only emitted once later audio arrives, and
    /// the first word needs some lead-in; without padding both get clipped.
    private static let leadSilence = 4_800   // 300 ms
    private static let tailSilence = 24_000  // 1.5 s

    private static func padded(_ samples: [Float]) -> [Float] {
        [Float](repeating: 0, count: leadSilence) + samples + [Float](repeating: 0, count: tailSilence)
    }

    /// Wraps Meander's 16 kHz mono float samples in an `AVAudioPCMBuffer`. The
    /// manager resamples internally, but feeding 16 kHz avoids that work.
    private static func makeBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
