import SwiftUI
import AppKit

// MARK: - The payoff

/// A burst of the brand's bars, thrown from the centre and pulled back down.
/// Deterministic from `seed`, so every frame of the flight agrees with the last.
struct BurstView: View {
    let seed: UInt64
    let tint: Color
    let start: Date
    var count = 20
    var life: Double = 1.1
    /// Sideways push, for bursts thrown from a number near the window edge:
    /// the plume leans into open space instead of piling into the frame.
    var drift: Double = 0

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { g, size in
                guard t >= 0, t < life else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height / 2)
                var rng = Seeded(seed)

                // Shock ring — the hit, before the confetti reads
                let ring = min(t / 0.34, 1)
                if ring < 1 {
                    let r = 12 + ring * 52
                    let rect = CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2)
                    g.stroke(Circle().path(in: rect),
                             with: .color(tint.opacity(0.5 * (1 - ring))),
                             lineWidth: 3.5 * (1 - ring) + 0.5)
                }

                for _ in 0..<count {
                    let angle = -.pi / 2 + (rng.unit() - 0.5) * 2.3
                    let speed = 150 + rng.unit() * 230
                    let spin = (rng.unit() - 0.5) * 11
                    let scale = 0.7 + rng.unit() * 0.7
                    let shade = rng.unit()

                    // Squashed horizontally: a tall plume stays inside the
                    // canvas instead of getting clipped at the sides.
                    let x = origin.x + cos(angle) * speed * 0.72 * t + drift * t
                    let y = origin.y + sin(angle) * speed * t + 0.5 * 780 * t * t
                    let fade = t < life * 0.55 ? 1 : 1 - (t - life * 0.55) / (life * 0.45)

                    var p = g
                    p.opacity = max(0, fade)
                    p.translateBy(x: x, y: y)
                    p.rotate(by: .radians(spin * t))
                    let w = 3.4 * scale, h = 9 * scale
                    p.fill(Capsule().path(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)),
                           with: .color(shade < 0.55 ? tint
                                        : shade < 0.85 ? Theme.accentHi : Theme.text))
                }
            }
        }
    }
}

/// Small deterministic generator — the burst has to look random, not be random.
private struct Seeded {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func unit() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return Double((state &* 2685821657736338717) >> 11) * 0x1p-53
    }
}

/// A number that rolls to its new value instead of cutting to it.
struct CountingText: View, Animatable {
    var value: Double
    var font: Font
    var format: (Int) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(Int(value.rounded())))
            .font(font.monospacedDigit())
    }
}

// MARK: - Sound and touch

@MainActor
enum Feedback {
    private static var cache: [String: NSSound] = [:]

    /// Finishing something. Beating the estimate earns the brighter one.
    static func completed(underEstimate: Bool) {
        haptic(.generic)
        play(underEstimate ? "Glass" : "Pop", volume: underEstimate ? 0.4 : 0.5)
    }

    /// Passing last week's you — the whole point of the app.
    static func ghostBeaten() {
        haptic(.levelChange)
        play("Hero", volume: 0.35)
    }

    private static func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    private static func play(_ name: String, volume: Float) {
        guard AppSettings.shared.soundEnabled, !Theme.isRendering else { return }
        let sound = cache[name] ?? NSSound(named: name)
        cache[name] = sound
        sound?.stop()
        sound?.volume = volume
        sound?.play()
    }
}

// MARK: - Touch

/// Buttons give a little under the cursor. Cheap, and it makes every click
/// in the app feel like it landed.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
