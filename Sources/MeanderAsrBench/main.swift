import AVFoundation
import Foundation
import MeanderKit

// Compares local speech backends on the same audio. Each NAME.wav in the given
// directory needs a NAME.txt holding the reference transcript.

func normalize(_ s: String) -> [String] {
    s.lowercased()
        .replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression)
        .split(separator: " ").map(String.init)
}

func editDistance(_ a: [String], _ b: [String]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    for i in 1...a.count {
        var cur = [i] + Array(repeating: 0, count: b.count)
        for j in 1...b.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        prev = cur
    }
    return prev[b.count]
}

func loadSamples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    guard let conv = AVAudioConverter(from: file.processingFormat, to: fmt),
          let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
    else { throw NSError(domain: "bench", code: 1) }
    try file.read(into: inBuf)
    let outCap = AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1024
    let outBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: outCap)!
    var fed = false
    var err: NSError?
    conv.convert(to: outBuf, error: &err) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true; status.pointee = .haveData; return inBuf
    }
    if let err { throw err }
    return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
}

let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let wavs = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
var clips: [(name: String, samples: [Float], ref: [String])] = []
for w in wavs {
    let txt = w.deletingPathExtension().appendingPathExtension("txt")
    guard let ref = try? String(contentsOf: txt, encoding: .utf8) else { continue }
    clips.append((w.lastPathComponent, try loadSamples(w), normalize(ref)))
}
guard !clips.isEmpty else { print("No NAME.wav + NAME.txt pairs in \(dir.path)"); exit(1) }
let totalAudioSec = clips.reduce(0.0) { $0 + Double($1.samples.count) / 16_000 }
print("\(clips.count) clips, \(String(format: "%.1f", totalAudioSec))s of audio\n")

let backends: [TranscriptionBackend] = [.fluidAudioParakeet, .parakeetUnified, .appleSpeech, .parakeetEou, .nemotronMultilingual]
    .filter { $0.isAvailableOnThisSystem }
for backend in backends {
    Settings.shared.transcriptionBackend = backend
    let mm = ModelManager()
    let loadStart = Date()
    let t: Transcriber
    do { t = try await mm.loadTranscriber(onProgress: nil) } catch {
        print("[\(backend.displayName)] load failed: \(error)"); continue
    }
    let loadSec = Date().timeIntervalSince(loadStart)
    _ = try? await t.transcribe(samples: Array(clips[0].samples.prefix(16_000)), language: .english) // warm up
    var errs = 0, words = 0
    let start = Date()
    var lines: [String] = []
    for c in clips {
        let out = (try? await t.transcribe(samples: c.samples, language: .english)) ?? ""
        let e = editDistance(c.ref, normalize(out))
        errs += e; words += c.ref.count
        if e > 0 { lines.append("  \(c.name): \(e) err -> \(out)") }
    }
    let elapsed = Date().timeIntervalSince(start)
    print("== \(backend.displayName) (\(backend.modelDisplayName ?? ""))")
    print(String(format: "load %.1fs · WER %.1f%% (%d/%d) · %.2fs total · RTF %.3f",
                 loadSec, Double(errs) / Double(max(words, 1)) * 100, errs, words, elapsed, elapsed / totalAudioSec))
    lines.forEach { print($0) }
    print()
}
