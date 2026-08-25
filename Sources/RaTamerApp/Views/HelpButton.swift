import SwiftUI

struct HelpButton: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            Text(text)
                .font(.caption)
                .frame(width: 300, alignment: .leading)
                .padding(10)
        }
    }
}

enum HelpTexts {
    static let smoothness = "Smoothness (0–100): the overall scrolling feel. 0–17.5 = Native, a pass-through at macOS line speed with no processing; 17.5–47.5 = momentum; 47.5+ = glide (smoothing). Six named presets anchor the curve and each preset derives every parameter below."
    static let preset = "Preset: a named combination of every smoothing parameter. Native = macOS factory behavior with no Logi Options+ — a raw pass-through at ~48 px/detent, no boost, no bounce filter, no invert. Smooth = classic momentum (boost 2.5, decay 0.88). Glide = near-Mac-trackpad feel (90 px/notch). Mos = the Mos app's defaults (115 px/notch, ~3.0 duration). Soft = softened Mos (122 px/notch). RaT = the RaTamer default (128 px/notch). Warm = closest to Flow, without losing fluidity (133 px/notch). Flow = 140 px/notch. Fluid = 165 px/notch, the strongest glide."
    static let momentum = "Momentum: inertia. After the wheel stops, the last scroll velocity keeps decaying at 120 Hz, so a flick keeps scrolling. Each preset enables either momentum or glide — never both."
    static let maxBoost = "Max boost: feeds arriving within the accel window (fast scrolling) are multiplied by up to this. 1.0 = no boost; slow, deliberate scrolls are never affected."
    static let momentumDecay = "Momentum decay: fraction of velocity kept each tick (120 Hz). 0.85 keeps 85%, coasting briefly; lower stops sooner, higher slides much longer."
    static let momentumStop = "Momentum stop: absolute velocity (px/tick) below which momentum stops and the coast ends."
    static let smoothing = "Smoothing (glide): converts each notch into a smooth exponential ease-out toward a target, Mos-style. When enabled it takes priority over momentum."
    static let smoothFraction = "Smooth fraction: share of the remaining distance emitted per tick (120 Hz). 0.13 ≈ Mos Duration 3.0. Lower = slower, silkier glide; higher = snappier."
    static let glideStop = "Glide stop: remaining distance (px) below which the glide emits the rest in one step and stops, avoiding a slow crawl."
    static let pixelsPerNotch = "Pixels per notch: base pixels emitted per wheel detent (deltaV == multiplier). Native ≈ 48 (~3 macOS lines); Mos = 115; the curve interpolates 48 → 165."
    static let accelWindow = "Accel window (s): feeds arriving within this gap after the previous one are treated as fast and multiplied by the max boost."
    static let feedGap = "Feed gap timeout (s): idle time after the last feed before momentum is allowed to run, so momentum never starts mid-rotation."
    static let bounceWindow = "Bounce window (s): retained for compatibility. Reversal detection no longer relies on timing — the ratcheted wheel can emit opposite pulses at any delay, so only consecutive opposite pulses (reversal confirmation) decide a reversal."
    static let bounceRatio = "Bounce ratio: retained for compatibility. Magnitude no longer gates reversals either, because jitter pulses can equal the main pulse size; every unconfirmed opposite pulse is damped until reversal confirmation is met."
    static let bounceDamping = "Bounce damping: multiplier applied to unconfirmed opposite pulses while they build reversal confirmation (0.15 keeps 15%, nearly suppressing the reverse tick of the ratchet)."
    static let reversalConfirmation = "Reversal confirmation: consecutive opposite pulses required before a direction reversal is accepted. The ratcheted wheel can emit up to two opposite pulses when a tooth settles between grooves, so 3 avoids spurious reversals while still reacting to a sustained change of direction."
    static let directionThreshold = "Direction threshold: minimum pixel magnitude a feed needs to establish or refresh the dominant scroll direction."
}
