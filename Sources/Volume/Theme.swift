import SwiftUI

enum Theme {
    /// True when rendering headless previews — swaps ScrollViews for plain stacks.
    static var isRendering = false
    /// Set by the renderer to freeze a completion burst mid-flight for review.
    static var renderBurstAt: Date?
    /// Resolved appearance, set by RootView before the tree evaluates.
    static var mode: ColorScheme = .dark
    private static var dark: Bool { mode == .dark }

    // Palette — night session (dark) / day session (light)
    static var bg: Color       { dark ? Color(hex: 0x0D1015) : Color(hex: 0xF4F2EC) }
    static var surface: Color  { dark ? Color(hex: 0x151B23) : Color(hex: 0xFCFBF7) }
    static var raised: Color   { dark ? Color(hex: 0x1D2530) : Color(hex: 0xE9E6DD) }
    static var hairline: Color { dark ? .white.opacity(0.08) : .black.opacity(0.09) }
    static var text: Color     { dark ? Color(hex: 0xF4F1E8) : Color(hex: 0x191A1E) }
    static var dim: Color      { text.opacity(0.55) }
    static var faint: Color    { text.opacity(dark ? 0.32 : 0.36) }
    static var accent: Color   { dark ? Color(hex: 0xFF7A1A) : Color(hex: 0xEE650D) }   // you
    static var accentHi: Color { dark ? Color(hex: 0xFFB25A) : Color(hex: 0xFF8E3D) }
    static var ghost: Color    { dark ? Color(hex: 0x8A93A6) : Color(hex: 0x707A8C) }   // last week's you
    static var good: Color     { dark ? Color(hex: 0x3DD68C) : Color(hex: 0x17A05E) }   // under estimate
    static var over: Color     { dark ? Color(hex: 0xFF5B5B) : Color(hex: 0xD84C4C) }   // over estimate
    static var call: Color     { dark ? Color(hex: 0x5AA9FF) : Color(hex: 0x2E7BD4) }
    static var track: Color    { dark ? .black.opacity(0.35) : .black.opacity(0.07) }

    /// Scoreboard numerals.
    static func din(_ size: CGFloat) -> Font { .custom("DINAlternate-Bold", size: size) }
    /// Athletic label caps.
    static func label(_ size: CGFloat) -> Font { .custom("Futura-CondensedMedium", size: size) }
    static func labelHeavy(_ size: CGFloat) -> Font { .custom("Futura-CondensedExtraBold", size: size) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = Theme.dim
    var size: CGFloat = 15

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(size))
            .tracking(1.8)
            .foregroundStyle(color)
    }
}

/// ScrollView normally; plain content when headless-rendering (NSScrollView doesn't rasterize).
struct MaybeScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if Theme.isRendering {
            VStack(spacing: 0) {
                content
                Spacer(minLength: 0)
            }
        } else {
            ScrollView(showsIndicators: false) { content }
        }
    }
}
