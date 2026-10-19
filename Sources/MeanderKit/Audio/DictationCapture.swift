// TEMPORARY: saves each dictation's audio so the log/lock experiment can compare
// live push-to-talk capture against the same speech fed in from a file. Off unless
// the capture folder exists. Delete this file and its one call in Pipeline when done.
import Foundation

enum DictationCapture {
    /// Capture is enabled by the folder existing, so it can be turned on and off
    /// without relaunching the app, and can never be left on by accident.
    private static var directory: URL? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Meander/capture", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        return folder
    }

    /// Writes 16 kHz mono samples as a 16-bit WAV, numbered in dictation order.
    static func save(_ samples: [Float]) {
        guard let directory, !samples.isEmpty else { return }
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .filter { $0.hasSuffix(".wav") }.count ?? 0
        let url = directory.appendingPathComponent(String(format: "%03d.wav", existing + 1))

        let sampleRate = 16_000
        var body = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var value = Int16(clamped * 32_767).littleEndian
            withUnsafeBytes(of: &value) { body.append(contentsOf: $0) }
        }

        func chunk(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func chunk(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

        var file = Data("RIFF".utf8)
        file += chunk(UInt32(36 + body.count))
        file += Data("WAVEfmt ".utf8)
        file += chunk(UInt32(16))
        file += chunk(UInt16(1))
        file += chunk(UInt16(1))
        file += chunk(UInt32(sampleRate))
        file += chunk(UInt32(sampleRate * 2))
        file += chunk(UInt16(2))
        file += chunk(UInt16(16))
        file += Data("data".utf8)
        file += chunk(UInt32(body.count))
        file += body

        try? file.write(to: url)
        LatencyLog.record("dictation audio captured: \(url.lastPathComponent)")
    }
}
