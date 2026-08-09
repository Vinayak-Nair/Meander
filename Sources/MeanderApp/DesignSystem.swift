import SwiftUI

// MARK: - Palette

/// Meander's hand-tuned dark palette — an ink canvas with a luminous teal-green
/// brand accent. Hardcoded (not semantic) so the signature look is identical
/// across windows.
enum Ink {
    static func text(_ o: Double) -> Color { .white.opacity(o) }

    static let bgTop = Color(red: 0.070, green: 0.072, blue: 0.090)
    static let bgBottom = Color(red: 0.032, green: 0.033, blue: 0.046)

    // The brand: one teal-green hue in three shades, darkest to lightest. Every
    // accent in the app is built from these so the colour reads as a single brand.
    static let brandDeep = Color(red: 0.06, green: 0.52, blue: 0.52)
    static let brand = Color(red: 0.12, green: 0.80, blue: 0.68)
    static let brandLight = Color(red: 0.46, green: 0.95, blue: 0.82)

    static let accentSolid = brand
    static let accentGlow = brand
    static let accentGradient = LinearGradient(
        colors: [brandLight, brand, brandDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let amber = Color(red: 1.00, green: 0.72, blue: 0.38)
    static let green = Color(red: 0.34, green: 0.86, blue: 0.58)
    static let red = Color(red: 1.00, green: 0.42, blue: 0.47)
}

// MARK: - Canvas

/// Layered ink background with a soft aurora glow that warms while recording.
struct InkCanvas: View {
    var active: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Ink.bgTop, Ink.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Ink.accentGlow.opacity(active ? 0.36 : 0.18), .clear],
                center: .top, startRadius: 0, endRadius: 760
            )
            RadialGradient(
                colors: [Ink.brandLight.opacity(0.10), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 620
            )
        }
        .animation(.easeOut(duration: 0.4), value: active)
    }
}

// MARK: - Panels

/// A glass panel with a subtle fill, a top-lit hairline border, and depth.
struct GlassPanel: ViewModifier {
    var corner: CGFloat = 18
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.16), .white.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
            )
    }
}

extension View {
    func glassPanel(corner: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(GlassPanel(corner: corner, padding: padding))
    }
}

/// Standard card container with consistent stacking and padding.
struct Card<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(corner: 18, padding: 16)
    }
}

// MARK: - Labels & buttons

struct SectionLabel: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Ink.accentSolid)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(1.1)
                .foregroundStyle(Ink.text(0.5))
        }
    }
}

struct SoftButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    var prominent: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(stroke, lineWidth: 1))
                .foregroundStyle(foreground)
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var fill: AnyShapeStyle {
        if prominent { return AnyShapeStyle(Ink.accentGradient.opacity(hovering ? 1 : 0.9)) }
        if role == .destructive { return AnyShapeStyle(Ink.red.opacity(hovering ? 0.18 : 0.1)) }
        return AnyShapeStyle(Color.white.opacity(hovering ? 0.12 : 0.06))
    }
    private var stroke: Color {
        if prominent { return .white.opacity(0.2) }
        if role == .destructive { return Ink.red.opacity(hovering ? 0.5 : 0.25) }
        return .white.opacity(hovering ? 0.22 : 0.1)
    }
    private var foreground: Color {
        if prominent { return .white }
        return role == .destructive ? Ink.red : Ink.text(0.9)
    }
}

/// Gives any pressable surface instant press feedback: a subtle scale-down so the
/// UI feels like it heard the click. Hover styling stays on the views themselves;
/// this only adds the press response, so it composes with `.plain`-style labels.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// A keyboard-key chip, e.g. for the push-to-talk key.
struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
            .foregroundStyle(Ink.text(0.85))
    }
}

// MARK: - Aura orb

struct AuraOrb: View {
    var diameter: CGFloat = 56
    let recording: Bool
    let busy: Bool
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Ink.accentGlow)
                .frame(width: diameter, height: diameter)
                .blur(radius: diameter * 0.42)
                .opacity(breathe ? (recording ? 0.95 : 0.5) : (recording ? 0.7 : 0.32))

            if recording && !reduceMotion {
                PulseRing(diameter: diameter, delay: 0)
                PulseRing(diameter: diameter, delay: 0.6)
            }

            Circle()
                .fill(Ink.accentGradient)
                .overlay(
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .frame(width: diameter, height: diameter)

            if busy { BusyArc(diameter: diameter) }

            Image(systemName: "waveform")
                .font(.system(size: diameter * 0.41, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: recording)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

struct PulseRing: View {
    var diameter: CGFloat = 56
    let delay: Double
    @State private var animate = false
    var body: some View {
        Circle()
            .strokeBorder(Ink.accentGlow.opacity(0.6), lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .scaleEffect(animate ? 1.7 : 0.95)
            .opacity(animate ? 0 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false).delay(delay)) {
                    animate = true
                }
            }
    }
}

struct BusyArc: View {
    var diameter: CGFloat = 52
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: max(2, diameter * 0.045), lineCap: .round))
            .frame(width: diameter * 0.92, height: diameter * 0.92)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

// MARK: - Live waveform

/// A flowing glowing ribbon: a few translucent teal strands sharing a spindle
/// envelope (tapering to points at both ends, billowing in the middle) with a
/// soft bloom. The strands flow and interweave; the live FFT gently shapes where
/// the ribbon swells. Gated by loudness — a fine glowing line in silence, a
/// living ribbon while you speak. Designed for a dark background.
///
/// The mic level and spectrum only arrive ~12×/sec; a per-frame `WaveMotion`
/// eases them toward their targets every frame (fast attack so it blooms on
/// intensity, slow release so the flow stays buttery) decoupled from that rate.
struct LiveWaveform: View {
    var active: Bool
    var level: Double = 0
    var spectrum: [Double] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = WaveMotion()

    /// Each strand is a travelling sine of its own frequency/speed/phase; layering
    /// a few at different weights and opacities creates the interweaving ribbon.
    private struct Strand {
        let freq: Double, speed: Double, phase: Double
        let amp: Double, opacity: Double, width: Double
    }
    private static let strands: [Strand] = [
        .init(freq: 0.7, speed:  1.1,  phase: 0.0, amp: 1.00, opacity: 0.95, width: 1.6),
        .init(freq: 1.0, speed: -0.85, phase: 1.6, amp: 0.85, opacity: 0.55, width: 1.3),
        .init(freq: 1.3, speed:  1.4,  phase: 3.0, amp: 0.62, opacity: 0.42, width: 1.1),
        .init(freq: 0.5, speed: -1.0,  phase: 4.5, amp: 0.72, opacity: 0.32, width: 1.0),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // Ease amplitude/spectrum toward the latest mic targets so motion is
            // smooth at display rate, not the 12 Hz audio rate.
            let frame = motion.step(towardLevel: level, spectrum: spectrum, time: t)
            // The lateral flow is decorative; freeze it under reduced motion but
            // keep amplitude responding to the voice (that's functional).
            let flowT = reduceMotion ? 0 : t
            ZStack {
                ribbon(flowT, frame.level, frame.spectrum)
                    .blur(radius: 3).opacity(0.25 + 0.4 * frame.level)  // soft bloom, brightens when loud
                ribbon(flowT, frame.level, frame.spectrum)              // crisp
            }
        }
    }

    private func ribbon(_ t: Double, _ level: Double, _ spectrum: [Double]) -> some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            let maxAmp = size.height / 2 - 1
            let steps = 48

            for strand in Self.strands {
                var points: [CGPoint] = []
                points.reserveCapacity(steps + 1)
                for s in 0...steps {
                    let fx = Double(s) / Double(steps)
                    let envelope = sin(fx * .pi)            // spindle: 0 at ends, 1 in middle
                    // A single clean sine sweep per strand — smooth, no ripple or
                    // FFT bumps. Amplitude is the overall loudness, gated by level
                    // so silence is a flat glowing line.
                    let wave = sin(fx * .pi * 2 * strand.freq + t * strand.speed + strand.phase)
                    let y = midY + envelope * strand.amp * level * maxAmp * wave
                    points.append(CGPoint(x: fx * size.width, y: y))
                }
                ctx.stroke(Self.smoothCurve(points),
                           with: horizontalShading(opacity: strand.opacity, width: size.width, midY: midY),
                           style: StrokeStyle(lineWidth: strand.width, lineCap: .round, lineJoin: .round))
            }

            // Bright central core, brightest in the middle, fading at the ends.
            var core = Path()
            core.move(to: CGPoint(x: 0, y: midY))
            core.addLine(to: CGPoint(x: size.width, y: midY))
            ctx.stroke(core, with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Ink.brandLight.opacity(0.5 * (0.4 + 0.6 * level)), location: 0.5),
                    .init(color: .clear, location: 1.0),
                ]),
                startPoint: CGPoint(x: 0, y: midY), endPoint: CGPoint(x: size.width, y: midY)
            ), lineWidth: 1)
        }
    }

    /// Brand-coloured gradient along the ribbon: transparent at the tapered ends,
    /// deep teal toward the edges, bright mint through the centre.
    private func horizontalShading(opacity: Double, width: CGFloat, midY: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Ink.brandDeep.opacity(opacity), location: 0.14),
                .init(color: Ink.brandLight.opacity(opacity), location: 0.5),
                .init(color: Ink.brandDeep.opacity(opacity), location: 0.86),
                .init(color: .clear, location: 1.0),
            ]),
            startPoint: CGPoint(x: 0, y: midY), endPoint: CGPoint(x: width, y: midY)
        )
    }

    /// Builds a smooth path through `points` using a Catmull-Rom spline rendered
    /// as cubic Béziers, so the strokes flow as curves instead of line segments.
    private static func smoothCurve(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        path.move(to: points[0])
        for i in 0..<points.count - 1 {
            let p0 = points[i == 0 ? i : i - 1]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[i + 2 < points.count ? i + 2 : i + 1]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// Smoothly samples a spectrum at `d` (0 = centre/bass, 1 = edge/treble).
    private static func sampledSpectrum(_ spectrum: [Double], _ d: Double) -> Double {
        guard spectrum.count > 1 else { return 0 }
        let pos = min(max(d, 0), 1) * Double(spectrum.count - 1)
        let i = Int(pos)
        let f = pos - Double(i)
        let a = spectrum[i]
        let b = spectrum[min(i + 1, spectrum.count - 1)]
        let smooth = f * f * (3 - 2 * f)   // smoothstep for a fluid curve
        return a + (b - a) * smooth
    }
}

/// Per-frame easing of the waveform's amplitude and spectrum. Because the mic
/// data arrives at ~12 Hz, this interpolates toward the latest targets at the
/// display's frame rate using frame-rate-independent exponential smoothing —
/// fast attack so the amplitude pops on a loud syllable, slower release so it
/// settles smoothly. This is what makes the ribbon feel buttery rather than
/// stepping between audio frames.
final class WaveMotion {
    private var level: Double = 0
    private var spectrum: [Double] = []
    private var lastTime: Double = 0

    /// Advances the eased values toward the latest targets and returns them.
    func step(towardLevel targetLevel: Double, spectrum targetSpectrum: [Double], time: Double) -> (level: Double, spectrum: [Double]) {
        let dt = lastTime == 0 ? 1.0 / 60.0 : min(0.1, max(0.0001, time - lastTime))
        lastTime = time

        // Time constants: ~38 ms attack (snappy jump), ~190 ms release (smooth).
        let attack = 1 - exp(-dt / 0.038)
        let release = 1 - exp(-dt / 0.190)

        level += (targetLevel - level) * (targetLevel > level ? attack : release)

        if spectrum.count != targetSpectrum.count {
            spectrum = targetSpectrum
        } else {
            for i in spectrum.indices {
                let target = targetSpectrum[i]
                spectrum[i] += (target - spectrum[i]) * (target > spectrum[i] ? attack : release)
            }
        }
        return (level, spectrum)
    }
}

// MARK: - Status badge

struct StatusBadge: View {
    let text: String
    let color: Color
    let pulsing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                if pulsing && !reduceMotion { PulseDot(color: color) }
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(text).font(.caption.weight(.semibold)).contentTransition(.opacity).id(text)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(color.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
        .foregroundStyle(color)
    }
}

struct PulseDot: View {
    let color: Color
    @State private var animate = false
    var body: some View {
        Circle().fill(color.opacity(0.6)).frame(width: 8, height: 8)
            .scaleEffect(animate ? 2.4 : 1).opacity(animate ? 0 : 0.6)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { animate = true }
            }
    }
}
