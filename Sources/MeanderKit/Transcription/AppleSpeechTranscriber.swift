import AVFoundation
import Foundation
import Speech

/// Apple's on-device SpeechAnalyzer (macOS 26+). The system manages the model, so
/// there is no Meander download beyond Apple's own one-time locale asset.
/// Meander feeds the whole utterance in and reads back the finalized transcript.
@available(macOS 26.0, *)
public final class AppleSpeechTranscriber: Transcriber {
    public init() {}

    public static func locale(for language: Language) -> Locale {
        language == .english ? Locale(identifier: "en_US") : Locale(identifier: language.code)
    }

    public func transcribe(samples: [Float], language: Language) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let transcriber = SpeechTranscriber(
            locale: Self.locale(for: language),
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        try await Self.ensureAssets(for: transcriber)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else { throw NSError(domain: "AppleSpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: "No compatible audio format"]) }
        let buffer = try Self.convert(samples, to: format)

        let collector = Task { () -> String in
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = try await collector.value
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Downloads Apple's speech asset for the locale if it is not installed yet.
    public static func ensureAssets(for transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    private static func convert(_ samples: [Float], to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let src = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(samples.count)),
              let converter = AVAudioConverter(from: src, to: format)
        else { throw NSError(domain: "AppleSpeech", code: 2) }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }

        let ratio = format.sampleRate / 16_000
        let cap = AVAudioFrameCount(Double(samples.count) * ratio) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap)
        else { throw NSError(domain: "AppleSpeech", code: 3) }
        var fed = false
        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        if let error { throw error }
        return outBuf
    }
}
