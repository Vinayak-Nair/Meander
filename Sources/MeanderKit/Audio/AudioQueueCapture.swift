import AudioToolbox
import Foundation

/// Low-latency microphone capture via an AudioToolbox input queue. This is the
/// default recorder path: an AudioQueue spins up much faster than an
/// AVAudioEngine graph, which is what makes push-to-talk feel instant. It also
/// resamples to the requested format internally, so we ask for 16 kHz mono
/// Float32 (what WhisperKit wants) and need no converter of our own.
final class AudioQueueCapture {
    enum CaptureError: Error { case failed(OSStatus) }

    /// Chunk duration per queue buffer. Small enough for a responsive level
    /// meter and streaming partials, large enough to keep callback overhead low.
    private static let chunkSeconds = 0.05
    private static let bufferCount = 3

    private let sampleRate: Double
    private let lock = NSLock()
    private var queue: AudioQueueRef?

    /// Called with each captured 16 kHz mono chunk, on the audio queue's thread.
    var onChunk: (([Float]) -> Void)?

    init(sampleRate: Double = 16_000) {
        self.sampleRate = sampleRate
    }

    deinit { stop() }

    /// Starts capturing from the device with the given UID, or the system
    /// default input when nil.
    func start(deviceUID: String?) throws {
        stop()

        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        let callback: AudioQueueInputCallback = { userData, queue, buffer, _, _, _ in
            guard let userData else { return }
            Unmanaged<AudioQueueCapture>.fromOpaque(userData)
                .takeUnretainedValue()
                .handle(buffer: buffer, queue: queue)
        }

        var created: AudioQueueRef?
        var status = AudioQueueNewInput(
            &format,
            callback,
            Unmanaged.passUnretained(self).toOpaque(),
            nil, nil, 0,
            &created
        )
        guard status == noErr, let q = created else { throw CaptureError.failed(status) }

        if let deviceUID {
            var uid = deviceUID as CFString
            status = withUnsafePointer(to: &uid) { pointer in
                AudioQueueSetProperty(
                    q,
                    kAudioQueueProperty_CurrentDevice,
                    pointer,
                    UInt32(MemoryLayout<CFString>.size)
                )
            }
            guard status == noErr else {
                AudioQueueDispose(q, true)
                throw CaptureError.failed(status)
            }
        }

        let bufferBytes = UInt32(sampleRate * Self.chunkSeconds) * UInt32(MemoryLayout<Float>.size)
        for _ in 0..<Self.bufferCount {
            var buffer: AudioQueueBufferRef?
            guard AudioQueueAllocateBuffer(q, bufferBytes, &buffer) == noErr, let buffer else { continue }
            AudioQueueEnqueueBuffer(q, buffer, 0, nil)
        }

        status = AudioQueueStart(q, nil)
        guard status == noErr else {
            AudioQueueDispose(q, true)
            throw CaptureError.failed(status)
        }

        lock.lock()
        queue = q
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let q = queue
        queue = nil
        lock.unlock()
        guard let q else { return }
        // Both calls are synchronous (immediate = true): no callbacks arrive
        // after this returns.
        AudioQueueStop(q, true)
        AudioQueueDispose(q, true)
    }

    private func handle(buffer: AudioQueueBufferRef, queue q: AudioQueueRef) {
        lock.lock()
        let active = queue != nil
        lock.unlock()
        guard active else { return } // stopping; don't touch the dying queue

        let byteCount = Int(buffer.pointee.mAudioDataByteSize)
        let count = byteCount / MemoryLayout<Float>.size
        if count > 0 {
            let floats = buffer.pointee.mAudioData.bindMemory(to: Float.self, capacity: count)
            onChunk?(Array(UnsafeBufferPointer(start: floats, count: count)))
        }
        AudioQueueEnqueueBuffer(q, buffer, 0, nil)
    }
}
