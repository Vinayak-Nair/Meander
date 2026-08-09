// Meander brand renderer — draws the luminous woven-strand waveform mark natively
// with CoreGraphics so the logo matches the in-app LiveWaveform exactly.
//
//   swift render_assets.swift icon     <size> <out.png>
//   swift render_assets.swift menubar  <size> <out.png>     (template: black on clear)
//   swift render_assets.swift mark     <w> <h> <out.png>    (glow wave on transparent)
//   swift render_assets.swift panel    <w> <h> <out.png>    (glow wave on dark panel)
//   swift render_assets.swift lockup   <w> <h> <out.png>    (wave + "meander" on dark panel)
//
// The strand math is a static frame of Sources/MeanderApp/DesignSystem.swift's
// LiveWaveform so the two stay visually identical.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Colour palette (the Meander teal-cyan → deep blue brand)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let darkTop = rgb(0.086, 0.090, 0.116)
let darkBot = rgb(0.027, 0.031, 0.043)
let tealCore = rgb(0.34, 1.00, 0.84)   // bright cyan-teal centre
let blueEdge = rgb(0.11, 0.40, 0.80)   // deep blue tips
let glowTeal = rgb(0.18, 0.92, 0.82)
let coreLine = rgb(0.62, 1.00, 0.93)
let particle = rgb(0.74, 1.00, 0.97)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Output

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h))   // flip to a top-left origin
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    return ctx
}

func writePNG(_ ctx: CGContext, _ path: String) {
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                     UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not encode \(path)") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - The woven strands (a static LiveWaveform frame)

func strandPath(_ k: Int, _ n: Int, _ W: CGFloat, _ H: CGFloat, _ t: CGFloat, _ amp: CGFloat) -> CGPath {
    let TAU = CGFloat.pi * 2
    let phase = TAU * CGFloat(k) / CGFloat(n)
    let midY = H / 2, centreAmp = H * 0.10, bundleAmp = H * 0.36 * amp
    let steps = 90
    var pts: [CGPoint] = []
    pts.reserveCapacity(steps + 1)
    for s in 0...steps {
        let fx = CGFloat(s) / CGFloat(steps)
        let edge = pow(sin(fx * .pi), 0.5)
        let centre = sin(fx * TAU * 0.8 + t * 0.5) * 0.6 + sin(fx * TAU * 0.5 - t * 0.35) * 0.4
        let swell = 0.3 + 0.7 * (0.5 + 0.5 * sin(fx * TAU * 1.1 - t * 0.6))
        let radius = bundleAmp * edge * swell
        let twist = fx * TAU * 1.6 + t * 0.9
        let y = midY + centre * centreAmp * edge + radius * sin(twist + phase)
        pts.append(CGPoint(x: fx * W, y: y))
    }
    let p = CGMutablePath()
    p.addLines(between: pts)
    return p
}

func strandGradient() -> CGGradient {
    let cols = [blueEdge.copy(alpha: 0)!, blueEdge.copy(alpha: 0.6)!, tealCore.copy(alpha: 0.92)!,
                blueEdge.copy(alpha: 0.6)!, blueEdge.copy(alpha: 0)!] as CFArray
    return CGGradient(colorsSpace: sRGB, colors: cols, locations: [0, 0.12, 0.5, 0.88, 1])!
}

/// Draws the glowing woven waveform into the current CTM, spanning W×H.
func drawWave(_ ctx: CGContext, _ W: CGFloat, _ H: CGFloat, t: CGFloat, amp: CGFloat, glow: Bool,
              n: Int = 26, centerline: Bool = true) {
    let grad = strandGradient()

    // Soft central bloom.
    if glow {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let bloom = CGGradient(colorsSpace: sRGB,
                               colors: [glowTeal.copy(alpha: 0.20)!, glowTeal.copy(alpha: 0)!] as CFArray,
                               locations: [0, 1])!
        ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                               endCenter: CGPoint(x: W/2, y: H/2), endRadius: W * 0.40, options: [])
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Wide, blurred glow pass underneath.
    if glow {
        for k in 0..<n {
            let path = strandPath(k, n, W, H, t, amp)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: H * 0.014, color: glowTeal.copy(alpha: 0.9)!)
            ctx.setStrokeColor(glowTeal.copy(alpha: 0.05)!)
            ctx.setLineWidth(max(1, H * 0.012))
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // Sharp gradient core strands.
    for k in 0..<n {
        let path = strandPath(k, n, W, H, t, amp)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(max(0.8, H * 0.0017))
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H/2), end: CGPoint(x: W, y: H/2), options: [])
        ctx.restoreGState()
    }

    // Bright centreline.
    if centerline {
        let lineH = max(1, H * 0.0045)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: H/2 - lineH/2, width: W, height: lineH))
        let cl = CGGradient(colorsSpace: sRGB,
                            colors: [coreLine.copy(alpha: 0)!, coreLine.copy(alpha: 0.7)!, coreLine.copy(alpha: 0)!] as CFArray,
                            locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(cl, start: CGPoint(x: 0, y: 0), end: CGPoint(x: W, y: 0), options: [])
        ctx.restoreGState()
    }

    // Drifting particles.
    let parts: [(CGFloat, CGFloat)] = [(0.33, 0.40), (0.62, 0.34), (0.71, 0.63), (0.42, 0.68), (0.54, 0.28)]
    for (i, p) in parts.enumerated() {
        let px = p.0 * W, py = p.1 * H
        let r = H * 0.012 * (i % 2 == 0 ? 1.0 : 0.7)
        let g = CGGradient(colorsSpace: sRGB,
                           colors: [particle.copy(alpha: 0.9)!, particle.copy(alpha: 0)!] as CFArray,
                           locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: px, y: py), startRadius: 0,
                               endCenter: CGPoint(x: px, y: py), endRadius: r, options: [])
    }
    ctx.restoreGState()
}

// MARK: - Squircle background

func squircle(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.height * 0.225, transform: nil)
}

func drawDarkTile(_ ctx: CGContext, _ rect: CGRect, shadow: Bool) {
    let path = squircle(rect)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: rect.height * 0.012),
                      blur: rect.height * 0.03, color: rgb(0, 0, 0, 0.55))
        ctx.addPath(path); ctx.setFillColor(darkBot); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: sRGB, colors: [darkTop, darkBot] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    ctx.restoreGState()
}

func strokeTileEdge(_ ctx: CGContext, _ rect: CGRect, _ S: CGFloat) {
    ctx.saveGState()
    ctx.addPath(squircle(rect))
    ctx.setLineWidth(max(1, S * 0.0022))
    ctx.setStrokeColor(rgb(1, 1, 1, 0.08))
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Modes

let waveT = CGFloat(ProcessInfo.processInfo.environment["MEANDER_T"].flatMap { Double($0) } ?? 3.14)
let waveAmp = CGFloat(ProcessInfo.processInfo.environment["MEANDER_AMP"].flatMap { Double($0) } ?? 0.62)
let waveN = ProcessInfo.processInfo.environment["MEANDER_N"].flatMap { Int($0) } ?? 5
let waveCL = (ProcessInfo.processInfo.environment["MEANDER_CL"] ?? "0") == "1"

func renderIcon(_ size: Int, _ out: String) {
    let ctx = makeContext(size, size)
    let S = CGFloat(size)
    let inset = S * 0.085
    let rect = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
    drawDarkTile(ctx, rect, shadow: true)
    ctx.saveGState()
    ctx.addPath(squircle(rect)); ctx.clip()
    let pad = S * 0.165
    ctx.saveGState()
    ctx.translateBy(x: pad, y: pad)
    drawWave(ctx, S - 2*pad, S - 2*pad, t: waveT, amp: waveAmp, glow: true, n: waveN, centerline: waveCL)
    ctx.restoreGState()
    ctx.restoreGState()
    strokeTileEdge(ctx, rect, S)
    writePNG(ctx, out)
}

func renderMenubar(_ size: Int, _ out: String) {
    let ctx = makeContext(size, size)
    let S = CGFloat(size)
    // A simplified solid spindle of five rounded bars — reads at 16px and
    // renders as a template (black on clear) so the menu bar tints it.
    let n = 5
    let barW = S * 0.118, gap = S * 0.072, pitch = barW + gap
    let total = CGFloat(n) * barW + CGFloat(n - 1) * gap
    let startX = (S - total) / 2
    let heights: [CGFloat] = [0.34, 0.62, 0.86, 0.62, 0.34]
    let midY = S / 2
    ctx.setFillColor(rgb(0, 0, 0, 1))
    for i in 0..<n {
        let h = heights[i] * S
        let x = startX + CGFloat(i) * pitch
        let r = CGRect(x: x, y: midY - h/2, width: barW, height: h)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW/2, cornerHeight: barW/2, transform: nil))
    }
    ctx.fillPath()
    writePNG(ctx, out)
}

func renderMark(_ w: Int, _ h: Int, _ out: String) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    let pad = W * 0.10
    ctx.saveGState()
    ctx.translateBy(x: pad, y: H * 0.18)
    drawWave(ctx, W - 2*pad, H * 0.64, t: waveT, amp: 0.86, glow: true)
    ctx.restoreGState()
    writePNG(ctx, out)
}

func renderPanel(_ w: Int, _ h: Int, _ out: String, withText: Bool) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    // Full-bleed dark background.
    ctx.saveGState()
    let bg = CGGradient(colorsSpace: sRGB, colors: [rgb(0.043, 0.047, 0.063), rgb(0.016, 0.020, 0.031)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                           endCenter: CGPoint(x: W/2, y: H/2), endRadius: max(W, H) * 0.75, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    if withText {
        let waveW = W * 0.40
        ctx.saveGState()
        ctx.translateBy(x: W * 0.10, y: H * 0.30)
        drawWave(ctx, waveW, H * 0.40, t: waveT, amp: 0.92, glow: true)
        ctx.restoreGState()
        // Wordmark.
        let fontSize = H * 0.30
        var font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        if let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: fontSize) ?? font }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.918, green: 0.984, blue: 0.965, alpha: 1),
            .kern: -fontSize * 0.02,
        ]
        let str = NSAttributedString(string: "meander", attributes: attrs)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let textSize = str.size()
        str.draw(at: CGPoint(x: W * 0.10 + waveW + W * 0.02, y: (H - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
    } else {
        let pad = W * 0.18
        ctx.saveGState()
        ctx.translateBy(x: pad, y: H * 0.22)
        drawWave(ctx, W - 2*pad, H * 0.56, t: waveT, amp: 0.9, glow: true)
        ctx.restoreGState()
    }
    writePNG(ctx, out)
}

// MARK: - Flowing ribbon mark (tapered, overlapping calligraphic waves)

// The ribbon colorway. Blue → white reads on dark surfaces (app icon, panels);
// MEANDER_RIBBON=light switches to periwinkle → deep indigo so the mark still stands
// out on a light surface such as the in-app top bar.
let ribbonLightBG = (ProcessInfo.processInfo.environment["MEANDER_RIBBON"] ?? "dark") == "light"
let ribbonGlowColor = ribbonLightBG ? rgb(0.30, 0.34, 0.80, 0.28) : rgb(0.44, 0.52, 0.96, 0.5)

func ribbonGrad(_ topA: CGFloat, _ botA: CGFloat) -> CGGradient {
    let cols: CFArray = ribbonLightBG
        ? [rgb(0.47, 0.51, 0.93, Double(topA)), rgb(0.20, 0.22, 0.66, Double(botA))] as CFArray
        : [rgb(0.94, 0.96, 1.00, Double(topA)), rgb(0.38, 0.43, 0.88, Double(botA))] as CFArray
    return CGGradient(colorsSpace: sRGB, colors: cols, locations: [0, 1])!
}

/// One tapered ribbon: an S-curve centreline offset by a width that swells in the
/// middle and tapers to fine points at both tips, filled with a satin teal gradient.
func drawRibbon(_ ctx: CGContext, _ W: CGFloat, _ H: CGFloat,
                amp: CGFloat, freq: CGFloat, phase: CGFloat,
                amp2: CGFloat, freq2: CGFloat, phase2: CGFloat,
                maxW: CGFloat, x0: CGFloat, x1: CGFloat,
                topA: CGFloat, botA: CGFloat, glow: Bool) {
    let mid = H / 2, TAU = CGFloat.pi * 2
    func cl(_ t: CGFloat) -> CGPoint {
        CGPoint(x: x0 + t * (x1 - x0),
                y: mid + amp * sin(TAU * freq * t + phase) + amp2 * sin(TAU * freq2 * t + phase2))
    }
    func wd(_ t: CGFloat) -> CGFloat { maxW * pow(sin(.pi * t), 0.62) }
    let samples = 160
    var top: [CGPoint] = [], bot: [CGPoint] = []
    for i in 0...samples {
        let t = CGFloat(i) / CGFloat(samples)
        let p = cl(t)
        let dt: CGFloat = 0.0015
        let a = cl(max(0, t - dt)), b = cl(min(1, t + dt))
        var tx = b.x - a.x, ty = b.y - a.y
        let l = max(1e-4, hypot(tx, ty)); tx /= l; ty /= l
        let nx = -ty, ny = tx, w = wd(t) / 2
        top.append(CGPoint(x: p.x + nx * w, y: p.y + ny * w))
        bot.append(CGPoint(x: p.x - nx * w, y: p.y - ny * w))
    }
    let path = CGMutablePath()
    path.addLines(between: top)
    path.addLines(between: bot.reversed())
    path.closeSubpath()
    ctx.saveGState()
    if glow { ctx.setShadow(offset: .zero, blur: H * 0.022, color: ribbonGlowColor) }
    ctx.addPath(path); ctx.clip()
    let box = path.boundingBox
    ctx.drawLinearGradient(ribbonGrad(topA, botA),
                           start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.maxY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func drawFlow(_ ctx: CGContext, _ W: CGFloat, _ H: CGFloat, glow: Bool) {
    let P = CGFloat.pi
    // Three gentle crossing ribbons — weave by offsetting phase.
    drawRibbon(ctx, W, H, amp: H*0.14, freq: 0.80, phase: 0.30, amp2: H*0.04, freq2: 1.9, phase2: 1.0,
               maxW: H*0.165, x0: W*0.06, x1: W*0.94, topA: 0.96, botA: 0.72, glow: glow)
    drawRibbon(ctx, W, H, amp: H*0.115, freq: 0.80, phase: 0.30 + P, amp2: H*0.035, freq2: 1.7, phase2: 0.5,
               maxW: H*0.11, x0: W*0.05, x1: W*0.95, topA: 0.72, botA: 0.46, glow: glow)
    drawRibbon(ctx, W, H, amp: H*0.175, freq: 0.74, phase: 1.5, amp2: H*0.03, freq2: 2.1, phase2: 0.0,
               maxW: H*0.05, x0: W*0.07, x1: W*0.93, topA: 0.6, botA: 0.3, glow: false)
}

func renderFlowIcon(_ size: Int, _ out: String) {
    let ctx = makeContext(size, size)
    let S = CGFloat(size)
    let inset = S * 0.085
    let rect = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
    drawDarkTile(ctx, rect, shadow: true)
    ctx.saveGState()
    ctx.addPath(squircle(rect)); ctx.clip()
    let pad = S * 0.12
    ctx.saveGState()
    ctx.translateBy(x: pad, y: S * 0.27)
    drawFlow(ctx, S - 2*pad, S * 0.46, glow: true)
    ctx.restoreGState()
    ctx.restoreGState()
    strokeTileEdge(ctx, rect, S)
    writePNG(ctx, out)
}

func renderFlowMark(_ w: Int, _ h: Int, _ out: String) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    ctx.saveGState()
    ctx.translateBy(x: 0, y: H * 0.18)
    drawFlow(ctx, W, H * 0.64, glow: true)
    ctx.restoreGState()
    writePNG(ctx, out)
}

func renderFlowPanel(_ w: Int, _ h: Int, _ out: String, withText: Bool) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    // Full-bleed dark background.
    ctx.saveGState()
    let bg = CGGradient(colorsSpace: sRGB, colors: [rgb(0.043, 0.047, 0.063), rgb(0.016, 0.020, 0.031)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                           endCenter: CGPoint(x: W/2, y: H/2), endRadius: max(W, H) * 0.75, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    if withText {
        let waveW = W * 0.42
        ctx.saveGState()
        ctx.translateBy(x: W * 0.08, y: H * 0.27)
        drawFlow(ctx, waveW, H * 0.46, glow: true)
        ctx.restoreGState()
        let fontSize = H * 0.30
        var font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        if let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: fontSize) ?? font }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.93, green: 0.95, blue: 1.0, alpha: 1),
            .kern: -fontSize * 0.02,
        ]
        let str = NSAttributedString(string: "meander", attributes: attrs)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let textSize = str.size()
        str.draw(at: CGPoint(x: W * 0.08 + waveW + W * 0.02, y: (H - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
    } else {
        ctx.saveGState()
        ctx.translateBy(x: W * 0.12, y: H * 0.20)
        drawFlow(ctx, W * 0.76, H * 0.60, glow: true)
        ctx.restoreGState()
    }
    writePNG(ctx, out)
}

// MARK: - Minimal two-stroke "hill" mark (clean line waveform)

// Left periwinkle-blue → faint near-white on the right: pops on dark, and on a light
// surface the right tips fade out the way the reference mark does.
let minLeft  = rgb(0.42, 0.47, 0.83)
let minRight = rgb(0.86, 0.88, 0.97)

/// The two strokes in a canonical 270×100 logo box: an upper hill and a lower,
/// right-shifted echo, each a smooth cubic with round caps.
let minCanonW: CGFloat = 270, minCanonH: CGFloat = 100
func minimalCanonPaths() -> [CGPath] {
    let top = CGMutablePath()
    top.move(to: CGPoint(x: 0, y: 66))
    top.addCurve(to: CGPoint(x: 156, y: 0),  control1: CGPoint(x: 93, y: 64),  control2: CGPoint(x: 113, y: 0))
    top.addCurve(to: CGPoint(x: 270, y: 64), control1: CGPoint(x: 199, y: 0),  control2: CGPoint(x: 229, y: 64))
    let bot = CGMutablePath()
    bot.move(to: CGPoint(x: 96, y: 68))
    bot.addCurve(to: CGPoint(x: 189, y: 88),  control1: CGPoint(x: 131, y: 68), control2: CGPoint(x: 151, y: 88))
    bot.addCurve(to: CGPoint(x: 270, y: 100), control1: CGPoint(x: 229, y: 88), control2: CGPoint(x: 250, y: 100))
    return [top, bot]
}

func drawMinimal(_ ctx: CGContext, originX: CGFloat, originY: CGFloat, scale: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: originX, y: originY)
    ctx.scaleBy(x: scale, y: scale)
    let grad = CGGradient(colorsSpace: sRGB, colors: [minLeft, minRight] as CFArray, locations: [0, 1])!
    for path in minimalCanonPaths() {
        ctx.saveGState()
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setLineWidth(11)
        ctx.addPath(path)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: minCanonH/2), end: CGPoint(x: minCanonW, y: minCanonH/2),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

/// Fits the canonical logo into `rect` (uniform scale, centred).
func placeMinimal(_ ctx: CGContext, in rect: CGRect) {
    let scale = min(rect.width / minCanonW, rect.height / minCanonH)
    let w = minCanonW * scale, h = minCanonH * scale
    drawMinimal(ctx, originX: rect.midX - w/2, originY: rect.midY - h/2, scale: scale)
}

func renderLineMark(_ w: Int, _ h: Int, _ out: String) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    placeMinimal(ctx, in: CGRect(x: W * 0.08, y: 0, width: W * 0.84, height: H))
    writePNG(ctx, out)
}

func renderLineIcon(_ size: Int, _ out: String) {
    let ctx = makeContext(size, size)
    let S = CGFloat(size)
    let inset = S * 0.085
    let rect = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
    drawDarkTile(ctx, rect, shadow: true)
    ctx.saveGState(); ctx.addPath(squircle(rect)); ctx.clip()
    placeMinimal(ctx, in: CGRect(x: S * 0.19, y: S * 0.30, width: S * 0.62, height: S * 0.40))
    ctx.restoreGState()
    strokeTileEdge(ctx, rect, S)
    writePNG(ctx, out)
}

func renderLinePanel(_ w: Int, _ h: Int, _ out: String, withText: Bool) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    ctx.saveGState()
    let bg = CGGradient(colorsSpace: sRGB, colors: [rgb(0.043, 0.047, 0.063), rgb(0.016, 0.020, 0.031)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                           endCenter: CGPoint(x: W/2, y: H/2), endRadius: max(W, H) * 0.75, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    if withText {
        let markW = W * 0.34
        placeMinimal(ctx, in: CGRect(x: W * 0.10, y: H * 0.30, width: markW, height: H * 0.40))
        let fontSize = H * 0.30
        var font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        if let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: fontSize) ?? font }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.93, green: 0.95, blue: 1.0, alpha: 1),
            .kern: -fontSize * 0.02,
        ]
        let str = NSAttributedString(string: "meander", attributes: attrs)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let textSize = str.size()
        str.draw(at: CGPoint(x: W * 0.10 + markW + W * 0.03, y: (H - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
    } else {
        placeMinimal(ctx, in: CGRect(x: W * 0.14, y: H * 0.22, width: W * 0.72, height: H * 0.56))
    }
    writePNG(ctx, out)
}

// MARK: - Image source (use the real artwork PNG verbatim)

// The mark is supplied as a transparent PNG (the designer's exact artwork) rather
// than drawn. We trim its transparent margins and composite it for each asset so it
// reproduces the source pixel-for-pixel.
let srcPath = ProcessInfo.processInfo.environment["MEANDER_SRC"] ?? "Branding/meander-mark-source.png"

func loadTrimmedImage(_ path: String) -> (CGImage, CGRect) {
    guard let img = NSImage(contentsOfFile: path),
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let cg = rep.cgImage,
          let data = cg.dataProvider?.data,
          let ptr = CFDataGetBytePtr(data) else { fatalError("could not load \(path)") }
    let w = cg.width, h = cg.height, bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
    let info = cg.alphaInfo
    let alphaFirst = (info == .premultipliedFirst || info == .first || info == .noneSkipFirst)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        let row = y * bpr
        for x in 0..<w {
            let a = ptr[row + x * bpp + (alphaFirst ? 0 : bpp - 1)]
            if a > 8 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX else { return (cg, CGRect(x: 0, y: 0, width: w, height: h)) }
    return (cg, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}

/// Draws a CGImage upright (the render context uses a top-left origin) into `rect`.
func drawImageUpright(_ ctx: CGContext, _ cg: CGImage, in rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.restoreGState()
}

/// Fits the trimmed mark (plus optional breathing room) into `rect`, centred.
func placeImage(_ ctx: CGContext, _ cg: CGImage, _ bbox: CGRect, into rect: CGRect, pad: CGFloat = 0) {
    let m = bbox.height * pad
    let crop = bbox.insetBy(dx: -m, dy: -m).intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    guard let cropped = cg.cropping(to: crop) else { return }
    let aspect = crop.width / crop.height
    var dw = rect.width, dh = dw / aspect
    if dh > rect.height { dh = rect.height; dw = dh * aspect }
    drawImageUpright(ctx, cropped, in: CGRect(x: rect.midX - dw/2, y: rect.midY - dh/2, width: dw, height: dh))
}

/// Tightly-cropped mark on transparent, scaled to `width` px — for the in-app mark
/// and the Branding/ mark export.
func renderImgCrop(_ width: Int, _ out: String) {
    let (cg, bbox) = loadTrimmedImage(srcPath)
    let pad = bbox.height * 0.10
    let crop = bbox.insetBy(dx: -pad, dy: -pad).intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    guard let cropped = cg.cropping(to: crop) else { fatalError("crop failed") }
    let ow = width, oh = Int((CGFloat(width) * CGFloat(cropped.height) / CGFloat(cropped.width)).rounded())
    let ctx = makeContext(ow, oh)
    drawImageUpright(ctx, cropped, in: CGRect(x: 0, y: 0, width: CGFloat(ow), height: CGFloat(oh)))
    writePNG(ctx, out)
}

func renderImgIcon(_ size: Int, _ out: String) {
    let ctx = makeContext(size, size)
    let S = CGFloat(size)
    let inset = S * 0.085
    let rect = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
    drawDarkTile(ctx, rect, shadow: true)
    ctx.saveGState(); ctx.addPath(squircle(rect)); ctx.clip()
    let (cg, bbox) = loadTrimmedImage(srcPath)
    placeImage(ctx, cg, bbox, into: CGRect(x: S * 0.16, y: S * 0.32, width: S * 0.68, height: S * 0.36))
    ctx.restoreGState()
    strokeTileEdge(ctx, rect, S)
    writePNG(ctx, out)
}

func renderImgPanel(_ w: Int, _ h: Int, _ out: String, withText: Bool) {
    let ctx = makeContext(w, h)
    let W = CGFloat(w), H = CGFloat(h)
    ctx.saveGState()
    let bg = CGGradient(colorsSpace: sRGB, colors: [rgb(0.043, 0.047, 0.063), rgb(0.016, 0.020, 0.031)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                           endCenter: CGPoint(x: W/2, y: H/2), endRadius: max(W, H) * 0.75, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    let (cg, bbox) = loadTrimmedImage(srcPath)
    if withText {
        let markW = W * 0.34
        placeImage(ctx, cg, bbox, into: CGRect(x: W * 0.10, y: H * 0.30, width: markW, height: H * 0.40))
        let fontSize = H * 0.30
        var font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        if let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: fontSize) ?? font }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.93, green: 0.95, blue: 1.0, alpha: 1),
            .kern: -fontSize * 0.02,
        ]
        let str = NSAttributedString(string: "meander", attributes: attrs)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let textSize = str.size()
        str.draw(at: CGPoint(x: W * 0.10 + markW + W * 0.03, y: (H - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
    } else {
        placeImage(ctx, cg, bbox, into: CGRect(x: W * 0.14, y: H * 0.22, width: W * 0.72, height: H * 0.56))
    }
    writePNG(ctx, out)
}

// MARK: - Dispatch

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: render_assets.swift <mode> ...\n".data(using: .utf8)!)
    exit(1)
}
switch args[1] {
case "icon":    renderIcon(Int(args[2])!, args[3])
case "menubar": renderMenubar(Int(args[2])!, args[3])
case "mark":    renderMark(Int(args[2])!, Int(args[3])!, args[4])
case "panel":   renderPanel(Int(args[2])!, Int(args[3])!, args[4], withText: false)
case "lockup":  renderPanel(Int(args[2])!, Int(args[3])!, args[4], withText: true)
case "flowicon": renderFlowIcon(Int(args[2])!, args[3])
case "flowmark": renderFlowMark(Int(args[2])!, Int(args[3])!, args[4])
case "flowpanel": renderFlowPanel(Int(args[2])!, Int(args[3])!, args[4], withText: false)
case "flowlockup": renderFlowPanel(Int(args[2])!, Int(args[3])!, args[4], withText: true)
case "lineicon": renderLineIcon(Int(args[2])!, args[3])
case "linemark": renderLineMark(Int(args[2])!, Int(args[3])!, args[4])
case "linepanel": renderLinePanel(Int(args[2])!, Int(args[3])!, args[4], withText: false)
case "linelockup": renderLinePanel(Int(args[2])!, Int(args[3])!, args[4], withText: true)
case "imgcrop": renderImgCrop(Int(args[2])!, args[3])
case "imgicon": renderImgIcon(Int(args[2])!, args[3])
case "imgpanel": renderImgPanel(Int(args[2])!, Int(args[3])!, args[4], withText: false)
case "imglockup": renderImgPanel(Int(args[2])!, Int(args[3])!, args[4], withText: true)
default:
    FileHandle.standardError.write("unknown mode \(args[1])\n".data(using: .utf8)!)
    exit(1)
}
