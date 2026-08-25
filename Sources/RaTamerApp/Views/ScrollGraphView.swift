import AppKit
import RaTamerCore
import SwiftUI

/// Live scroll graph (RAT.ENERGY · TERMO) hosted in its own window.
/// Instrument-style: clean dark canvas, time/pixel axes, live readouts, a
/// raw/smoothed legend and a pulsing "now" needle. Two series — the raw wheel
/// input (amber ticks) and the smoothed output (bright line with a subtle
/// fill) — stay readable at a glance. The store lifecycle — and the 30 Hz
/// flush that feeds it — is owned by `ScrollGraphWindow`.
struct ScrollGraphView: View {
    @ObservedObject var store: ScrollGraphStore

    var body: some View {
        Canvas { context, size in
            ScrollGraphPainter.draw(samples: store.samples,
                                    smoothEnabled: store.smoothEnabled,
                                    size: size,
                                    in: &context)
        }
        .frame(height: 340)
        .background(ScrollGraphPalette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.08)))
        .padding()
    }
}

/// Clean instrument palette: neutral near-black canvas, gray grid and labels,
/// near-white smoothed line, amber raw input.
enum ScrollGraphPalette {
    static let ink = Color(red: 0.043, green: 0.047, blue: 0.063)    // #0B0C10
    static let grid = Color(red: 0.149, green: 0.153, blue: 0.180)   // #26272E
    static let line = Color(red: 0.910, green: 0.910, blue: 0.925)   // #E8E8EC
    static let accent = Color(red: 1.0, green: 0.722, blue: 0.302)   // #FFB84D
    static let peak = Color(red: 1.0, green: 0.820, blue: 0.400)     // #FFD166
    static let live = Color(red: 0.290, green: 0.878, blue: 0.502)   // #4ADE80
    static let dimText = Color(red: 0.478, green: 0.478, blue: 0.522) // #7A7B85
    static let faintText = Color(red: 0.604, green: 0.604, blue: 0.639) // #9A9AA3
}

/// Turns the sample array into the scroll waveform. Pure function of the
/// samples + canvas size; called once per 30 Hz frame while the window is open.
/// Canvas coordinates: origin at the top-left, y grows downward.
enum ScrollGraphPainter {
    struct Plot {
        let left: CGFloat
        let right: CGFloat
        let bottom: CGFloat
        let top: CGFloat
        let window: TimeInterval = 5
        let yFloor: Double = 60

        func x(for time: Date, now: Date, width: CGFloat) -> CGFloat {
            let age = now.timeIntervalSince(time)
            let clamped = min(max(age, 0), window)
            let fraction = 1 - clamped / window
            return left + width * CGFloat(fraction)
        }

        func y(for value: Double, scale: CGFloat, midY: CGFloat) -> CGFloat {
            midY - CGFloat(value) * scale
        }
    }

    static func draw(samples: [ScrollSample], smoothEnabled: Bool,
                     size: CGSize, in context: inout GraphicsContext) {
        let plot = Plot(left: 46, right: size.width - 46, bottom: size.height - 26, top: 76)
        let plotHeight = plot.bottom - plot.top
        let now = Date()
        let outputs = samples.filter { $0.kind == .output }
        let raws = samples.filter { $0.kind == .raw }
        let hasData = smoothEnabled && !outputs.isEmpty

        // Y range anchored on the smoothed output so the wave fills the plot;
        // raw notches that exceed the scale are clipped at the edges.
        let maxOutput = outputs.map { abs($0.value) }.max() ?? 0
        let maxRaw = raws.map { abs($0.value) }.max() ?? 0
        let reference = maxOutput > 0 ? maxOutput : maxRaw
        let range = roundedRange(max(reference, plot.yFloor))
        let scale = (plotHeight / 2) / CGFloat(range)
        let midY = plot.bottom - plotHeight / 2

        drawGridAndAxes(in: &context, plot: plot, range: range)

        if smoothEnabled {
            if !outputs.isEmpty {
                drawWave(outputs: outputs, in: &context, plot: plot, now: now, midY: midY, scale: scale)
                drawNeedle(outputs: outputs, in: &context, plot: plot, now: now, midY: midY, scale: scale)
                drawPeakMark(outputs: outputs, in: &context, plot: plot, now: now, midY: midY, scale: scale)
            }
            for raw in raws {
                drawFlare(raw: raw, in: &context, plot: plot, now: now, midY: midY, scale: scale)
            }
        } else {
            drawEmptyState(in: &context, plot: plot)
        }

        let eventRate = Double(raws.filter { now.timeIntervalSince($0.time) <= 5 }.count) / 5
        drawHUD(in: &context, plot: plot, active: hasData, lastOutput: outputs.last, eventRate: eventRate)
        if smoothEnabled {
            drawReadouts(outputs: outputs, raws: raws, in: &context, size: size)
            drawLegend(in: &context, size: size, active: hasData)
        }
    }

    /// Rounds the symmetric Y range up to the nearest multiple of 60 so axis
    /// labels are clean (120 / 60 / 0 / -60 / -120), never noisy.
    static func roundedRange(_ value: Double) -> Double {
        let step: Double = 60
        return max(step, (value / step).rounded(.up) * step)
    }

    // MARK: - Waveform

    private static func outputPath(_ outputs: [ScrollSample], plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) -> Path {
        var path = Path()
        for (index, sample) in outputs.enumerated() {
            let x = plot.x(for: sample.time, now: now, width: plot.right - plot.left)
            let y = plot.y(for: sample.value, scale: scale, midY: midY)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private static func drawWave(outputs: [ScrollSample], in context: inout GraphicsContext,
                                 plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        let line = outputPath(outputs, plot: plot, now: now, midY: midY, scale: scale)

        var area = line
        if let last = outputs.last {
            let lastX = plot.x(for: last.time, now: now, width: plot.right - plot.left)
            area.addLine(to: CGPoint(x: lastX, y: plot.bottom))
        }
        if let first = outputs.first {
            let firstX = plot.x(for: first.time, now: now, width: plot.right - plot.left)
            area.addLine(to: CGPoint(x: firstX, y: plot.bottom))
        }
        area.closeSubpath()
        let fill = Gradient(colors: [
            ScrollGraphPalette.line.opacity(0.10),
            ScrollGraphPalette.line.opacity(0.0),
        ])
        context.fill(area, with: .linearGradient(fill,
                                                 startPoint: CGPoint(x: 0, y: plot.top),
                                                 endPoint: CGPoint(x: 0, y: plot.bottom)))

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .white.opacity(0.45), radius: 4, x: 0, y: 0))
            layer.stroke(line, with: .color(ScrollGraphPalette.line), lineWidth: 2.5)
        }
    }

    /// Amber tick for each raw wheel notch, drawn up from the baseline.
    private static func drawFlare(raw: ScrollSample, in context: inout GraphicsContext,
                                  plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        let x = plot.x(for: raw.time, now: now, width: plot.right - plot.left)
        guard x >= plot.left else { return }
        let y = min(max(plot.y(for: raw.value, scale: scale, midY: midY), plot.top), plot.bottom)
        var tick = Path()
        tick.move(to: CGPoint(x: x, y: plot.bottom))
        tick.addLine(to: CGPoint(x: x, y: y))
        context.stroke(tick, with: .color(ScrollGraphPalette.accent.opacity(0.65)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    /// Glowing needle at the newest sample: a hairline over the whole plot and
    /// a pulsing dot at the current value, so "now" reads at a glance.
    private static func drawNeedle(outputs: [ScrollSample], in context: inout GraphicsContext,
                                   plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        guard let last = outputs.last else { return }
        let x = plot.x(for: last.time, now: now, width: plot.right - plot.left)
        let y = plot.y(for: last.value, scale: scale, midY: midY)
        let age = now.timeIntervalSince(last.time)
        let alpha = max(0.2, 1 - age * 0.8)

        let hair = Path()
        var hairLine = hair
        hairLine.move(to: CGPoint(x: x, y: plot.top))
        hairLine.addLine(to: CGPoint(x: x, y: plot.bottom))
        context.stroke(hairLine, with: .color(ScrollGraphPalette.line.opacity(0.15 * alpha)), lineWidth: 1)

        let halo = Path(ellipseIn: CGRect(x: x - 7, y: y - 7, width: 14, height: 14))
        context.fill(halo, with: .color(ScrollGraphPalette.accent.opacity(0.25 * alpha)))

        let dot = Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
        context.fill(dot, with: .color(ScrollGraphPalette.line.opacity(0.95 * alpha)))

        // Current value pinned beside the needle, so "now" is read without
        // looking away from the wave.
        let valueLabel = Text(String(format: "%.0f", last.value))
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(ScrollGraphPalette.faintText.opacity(0.9 * alpha))
        context.draw(valueLabel, at: CGPoint(x: x + 6, y: y - 4), anchor: .leading)
    }

    /// Accent-colored diamond pinned to the hottest sample of the window.
    private static func drawPeakMark(outputs: [ScrollSample], in context: inout GraphicsContext,
                                     plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        guard let peak = outputs.max(by: { abs($0.value) < abs($1.value) }), abs(peak.value) > 0 else { return }
        let x = plot.x(for: peak.time, now: now, width: plot.right - plot.left)
        let y = plot.y(for: peak.value, scale: scale, midY: midY)
        var diamond = Path()
        diamond.move(to: CGPoint(x: x, y: y - 4))
        diamond.addLine(to: CGPoint(x: x + 4, y: y))
        diamond.addLine(to: CGPoint(x: x, y: y + 4))
        diamond.addLine(to: CGPoint(x: x - 4, y: y))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(ScrollGraphPalette.peak.opacity(0.9)))
    }

    // MARK: - Axes and chrome

    private static func drawGridAndAxes(in context: inout GraphicsContext, plot: Plot, range: Double) {
        var grid = Path()
        for i in 0...4 {
            let y = plot.bottom - CGFloat(i) * (plot.bottom - plot.top) / 4
            grid.move(to: CGPoint(x: plot.left, y: y))
            grid.addLine(to: CGPoint(x: plot.right, y: y))
        }
        for age in 1...5 {
            let x = plot.left + (1 - CGFloat(age) / 5) * (plot.right - plot.left)
            grid.move(to: CGPoint(x: x, y: plot.top))
            grid.addLine(to: CGPoint(x: x, y: plot.bottom))
        }
        context.stroke(grid, with: .color(ScrollGraphPalette.grid), lineWidth: 1)

        // Emphasized zero baseline: sign of the signal reads at a glance.
        let zeroY = plot.bottom - (plot.bottom - plot.top) / 2
        var zero = Path()
        zero.move(to: CGPoint(x: plot.left, y: zeroY))
        zero.addLine(to: CGPoint(x: plot.right, y: zeroY))
        context.stroke(zero, with: .color(ScrollGraphPalette.line.opacity(0.18)), lineWidth: 1)

        // Y labels: +range at the top, -range at the bottom (positive = up).
        let axisFont = Font.system(size: 9, design: .monospaced)
        for i in 0...4 {
            let value = -range + Double(i) * (range / 2)
            let y = plot.bottom - CGFloat(i) * (plot.bottom - plot.top) / 4
            let label = Text(Int(value).description)
                .font(axisFont)
                .foregroundStyle(ScrollGraphPalette.dimText)
            context.draw(label, at: CGPoint(x: plot.left - 6, y: y - 4), anchor: .trailing)
        }

        // X labels: 0 at the right (now) going back to -5s on the left.
        for age in 0...5 {
            let x = plot.left + (1 - CGFloat(age) / 5) * (plot.right - plot.left)
            let label = Text(age == 0 ? "0" : "-\(age)s")
                .font(axisFont)
                .foregroundStyle(ScrollGraphPalette.dimText)
            let anchor: UnitPoint = age == 0 ? .trailing : (age == 5 ? .leading : .center)
            context.draw(label, at: CGPoint(x: x, y: plot.bottom + 8), anchor: anchor)
        }
    }

    private static func drawHUD(in context: inout GraphicsContext, plot: Plot, active: Bool,
                                lastOutput: ScrollSample?, eventRate: Double) {
        let status = active ? "● LIVE" : "○ IDLE"
        let direction: String
        if let value = lastOutput?.value {
            direction = value > 0.05 ? "▲" : (value < -0.05 ? "▼" : "·")
        } else {
            direction = "·"
        }
        let rateText = eventRate >= 1
            ? String(format: "  %.0f ev/s", eventRate)
            : (eventRate > 0 ? String(format: "  %.1f ev/s", eventRate) : "")
        let text = Text("RAT.ENERGY · TERMO  \(status)  \(direction)\(rateText)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(active ? ScrollGraphPalette.faintText : ScrollGraphPalette.dimText)
        context.draw(text, at: CGPoint(x: plot.left, y: 6), anchor: .topLeading)
    }

    /// Live numeric readouts of the 5 s window, right-aligned under the HUD.
    private static func drawReadouts(outputs: [ScrollSample], raws: [ScrollSample],
                                     in context: inout GraphicsContext, size: CGSize) {
        let lastOut = outputs.last?.value
        let lastRaw = raws.last?.value
        let peak = outputs.map { abs($0.value) }.max() ?? 0
        let avg = outputs.isEmpty ? 0 : outputs.reduce(0) { $0 + abs($1.value) } / Double(outputs.count)
        let out = lastOut.map { String(format: "%6.1f", $0) } ?? "    —"
        let raw = lastRaw.map { String(format: "%6.0f", $0) } ?? "    —"
        let lines = [
            "out  \(out)",
            "raw  \(raw)",
            "peak \(String(format: "%6.0f", peak))",
            "avg  \(String(format: "%6.1f", avg))",
        ]
        let font = Font.system(size: 9, design: .monospaced)
        let color = outputs.isEmpty ? ScrollGraphPalette.dimText : ScrollGraphPalette.faintText
        var y: CGFloat = 6
        for line in lines {
            context.draw(Text(line).font(font).foregroundStyle(color),
                         at: CGPoint(x: size.width - 6, y: y), anchor: .topTrailing)
            y += 11
        }
    }

    /// Legend mapping the two visual languages to the two data series.
    private static func drawLegend(in context: inout GraphicsContext, size: CGSize, active: Bool) {
        let font = Font.system(size: 9, design: .monospaced)
        let smoothColor = ScrollGraphPalette.line.opacity(active ? 0.9 : 0.35)
        let rawColor = ScrollGraphPalette.accent.opacity(active ? 0.9 : 0.35)
        context.draw(Text("— SMOOTHED output").font(font).foregroundStyle(smoothColor),
                     at: CGPoint(x: size.width - 6, y: 50), anchor: .topTrailing)
        context.draw(Text("| RAW input").font(font).foregroundStyle(rawColor),
                     at: CGPoint(x: size.width - 6, y: 62), anchor: .topTrailing)
    }

    private static func drawEmptyState(in context: inout GraphicsContext, plot: Plot) {
        let rect = Path(CGRect(x: plot.left, y: plot.top,
                               width: plot.right - plot.left, height: plot.bottom - plot.top))
        context.fill(rect, with: .color(ScrollGraphPalette.ink.opacity(0.7)))
        let title = Text("Enable Smooth scrolling to capture")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(ScrollGraphPalette.faintText)
        let subtitle = Text("RAW input and SMOOTHED output appear here as you scroll.")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(ScrollGraphPalette.dimText)
        let center = CGPoint(x: (plot.left + plot.right) / 2, y: (plot.top + plot.bottom) / 2)
        context.draw(title, at: CGPoint(x: center.x, y: center.y - 8))
        context.draw(subtitle, at: CGPoint(x: center.x, y: center.y + 10))
    }
}
