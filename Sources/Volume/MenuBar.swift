import SwiftUI
import AppKit

/// The three-bar mark, drawn as a template image so macOS tints it to match
/// whatever is behind the menu bar.
enum MenuBarIcon {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 17, height: 14), flipped: false) { _ in
            NSColor.black.setFill()
            for (i, h) in [CGFloat(5), 8, 12].enumerated() {
                NSBezierPath(roundedRect: NSRect(x: 1.5 + CGFloat(i) * 5, y: 1, width: 3.5, height: h),
                             xRadius: 1.75, yRadius: 1.75).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }()
}

/// Today's scoreboard, one click away from anywhere.
struct MenuBarPanel: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var systemScheme
    @State private var now = Date.now

    private var scheme: ColorScheme {
        switch settings.appearance {
        case "light": .light
        case "dark": .dark
        default: systemScheme
        }
    }

    var body: some View {
        let resolved = scheme
        let _ = { Theme.mode = resolved }()
        let day = Stats.dayInterval(now)
        let focused = Stats.focusedMinutes(store.entries, in: day)
        let calls = Stats.callMinutes(store.entries, in: day)
        let tasks = Stats.completed(store.entries, kind: .task, in: day).count

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                BarsGlyph()
                Eyebrow(text: now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                        color: Theme.faint, size: 13)
                Spacer(minLength: 10)
                IconButton(symbol: "arrow.up.forward") { QuickAdd.shared.openMainApp() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                StatBlock(label: "Focused", value: TimeParse.format(focused),
                          color: Theme.accent, size: 32)
                StatBlock(label: "Tasks", value: "\(tasks)", size: 24)
                StatBlock(label: "Calls", value: TimeParse.format(calls),
                          color: calls > 0 ? Theme.call : Theme.dim, size: 24)
            }
        }
        .padding(16)
        .frame(width: 292, alignment: .leading)
        .background(Theme.bg)
        .environment(\.colorScheme, resolved)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .onAppear { store.reload() }
    }
}
