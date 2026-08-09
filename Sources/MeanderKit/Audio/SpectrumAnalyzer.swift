import Accelerate
import Foundation

/// Real-time FFT analyzer: turns a stream of mono samples into a small set of
/// log-spaced frequency-band magnitudes for visualization. Output is the
/// *relative* spectral shape (0...1, peak normalized to 1) — the overall
/// loudness/amplitude is supplied separately, so the visual stays flat in
/// silence without any absolute dB thresholds to tune.
public final class SpectrumAnalyzer {
    private let fftSize: Int
    private let half: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let bandCount: Int
    private let bandEdges: [Int]

    private var window: [Float]
    private var ring: [Float]
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]

    public init(fftSize: Int = 1024, bandCount: Int = 24, sampleRate: Double = 16_000) {
        self.fftSize = fftSize
        self.half = fftSize / 2
        self.bandCount = bandCount
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.ring = [Float](repeating: 0, count: fftSize)
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.realp = [Float](repeating: 0, count: half)
        self.imagp = [Float](repeating: 0, count: half)
        self.magnitudes = [Float](repeating: 0, count: half)

        // Log-spaced band edges across the speech-relevant range.
        var edges = [Int]()
        let fMin = 80.0, fMax = 6_500.0
        for b in 0...bandCount {
            let frac = Double(b) / Double(bandCount)
            let freq = fMin * pow(fMax / fMin, frac)
            let bin = Int(freq / sampleRate * Double(fftSize))
            edges.append(min(half - 1, max(1, bin)))
        }
        self.bandEdges = edges
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Appends `chunk` to the rolling window and, once a full window exists,
    /// returns the relative band magnitudes (0...1). Returns nil while warming up.
    public func process(_ chunk: [Float]) -> [Float]? {
        ring.append(contentsOf: chunk)
        if ring.count > fftSize { ring.removeFirst(ring.count - fftSize) }
        guard ring.count == fftSize else { return nil }

        vDSP_vmul(ring, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        windowed.withUnsafeBufferPointer { wptr in
            wptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cptr in
                realp.withUnsafeMutableBufferPointer { rp in
                    imagp.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        vDSP_ctoz(cptr, 2, &split, 1, vDSP_Length(half))
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
                    }
                }
            }
        }

        // Reduce bins to bands (amplitude = sqrt of mean power per band).
        var bands = [Float](repeating: 0, count: bandCount)
        for b in 0..<bandCount {
            let lo = bandEdges[b]
            let hi = max(lo + 1, bandEdges[b + 1])
            var sum: Float = 0
            var count = 0
            var k = lo
            while k < hi && k < half { sum += magnitudes[k]; count += 1; k += 1 }
            bands[b] = (sum / Float(max(1, count))).squareRoot()
        }

        // Normalize to the frame's peak so the result is a pure shape; gate to
        // zero when there's essentially no signal (true silence).
        var peak: Float = 0
        vDSP_maxv(bands, 1, &peak, vDSP_Length(bandCount))
        guard peak > 1e-5 else { return [Float](repeating: 0, count: bandCount) }
        for i in 0..<bandCount {
            // Gamma < 1 lifts the quieter bands so the shape stays legible.
            bands[i] = pow(bands[i] / peak, 0.7)
        }
        return bands
    }
}
