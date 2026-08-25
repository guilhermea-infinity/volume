import SwiftUI

enum Theme {
    /// True when rendering headless previews — swaps ScrollViews for plain stacks.
    static var isRendering = false

    // Palette — night-session scoreboard
    static let bg       = Color(hex: 0x0D1015)
    static let surface  = Color(hex: 0x151B23)
    static let raised   = Color(hex: 0x1D2530)
    static let hairline = Color.white.opacity(0.08)
    static let text     = Color(hex: 0xF4F1E8)
    static let dim      = Color(hex: 0xF4F1E8).opacity(0.55)
    static let faint    = Color(hex: 0xF4F1E8).opacity(0.32)
    static let accent   = Color(hex: 0xFF7A1A)   // you
    static let accentHi = Color(hex: 0xFFB25A)
    static let ghost    = Color(hex: 0x8A93A6)   // last week's you
    static let good     = Color(hex: 0x3DD68C)   // under estimate
    static let over     = Color(hex: 0xFF5B5B)   // over estimate
    static let call     = Color(hex: 0x5AA9FF)

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
