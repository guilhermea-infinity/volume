import SwiftUI

@main
struct VolumeApp: App {
    @StateObject private var store: Store

    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--render") {
            let dir = CommandLine.arguments.indices.contains(i + 1)
                ? CommandLine.arguments[i + 1] : "."
            Theme.isRendering = true
            Renderer.renderAll(to: dir)
            exit(0)
        }
        // Dev hook for checking the quick-add grammar without opening the panel.
        if let i = CommandLine.arguments.firstIndex(of: "--parse") {
            let raw = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : ""
            if let p = QuickAddView.parse(raw) {
                print("\(p.kind.rawValue)|\(p.title)|\(p.minutes)")
            } else {
                print("nil")
            }
            exit(0)
        }
        let s = Store()
        _store = StateObject(wrappedValue: s)
        QuickAdd.shared.configure(store: s)
        CalendarSync.shared.configure(store: s)
        s.tagPending()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 640, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 740)

        MenuBarExtra {
            MenuBarPanel().environmentObject(store)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

enum AppTab: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case history = "History"
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var tab: AppTab
    @State private var showSettings = false
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.openWindow) private var openWindow

    init(tab: AppTab = .today) {
        _tab = State(initialValue: tab)
    }

    private var resolvedScheme: ColorScheme {
        switch settings.appearance {
        case "light": .light
        case "dark": .dark
        default: systemScheme
        }
    }

    var body: some View {
        let scheme = resolvedScheme
        let _ = { Theme.mode = scheme }()
        VStack(spacing: 0) {
            TopBar(tab: $tab, showSettings: $showSettings)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Group {
                switch tab {
                case .today: TodayView()
                case .week: WeekView()
                case .history: HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id("appearance-\(settings.appearance)-\(scheme == .dark ? "d" : "l")")
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(settings.appearance == "system" ? nil : scheme)
        .tint(Theme.accent)
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(settings).environmentObject(store) }
        .environmentObject(settings)
        .onAppear {
            applyAppAppearance(scheme)
            QuickAdd.openMainWindow = { openWindow(id: "main") }
        }
        .onChange(of: settings.appearance) { _, _ in applyAppAppearance(resolvedScheme) }
    }

    private func applyAppAppearance(_ scheme: ColorScheme) {
        NSApplication.shared.appearance = settings.appearance == "system"
            ? nil
            : NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    }
}

struct TopBar: View {
    @Binding var tab: AppTab
    @Binding var showSettings: Bool
    @Namespace private var underline

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                BarsGlyph()
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                Text("VOLUME")
                    .font(Theme.labelHeavy(19))
                    .tracking(4)
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(AppTab.allCases, id: \.self) { t in
                    TabButton(label: t.rawValue, isSelected: tab == t, ns: underline) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = t }
                    }
                }
                TabIcon(symbol: "gearshape.fill") { showSettings = true }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        // The window's safe area already keeps this row clear of the traffic
        // lights, so the wordmark can sit flush at the left edge.
        .padding(.vertical, 10)
        .background(Theme.bg)
    }
}

struct BarsGlyph: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            Capsule().fill(Theme.ghost).frame(width: 4, height: 8)
            Capsule().fill(Theme.ghost).frame(width: 4, height: 12)
            Capsule().fill(Theme.accent).frame(width: 4, height: 17)
        }
    }
}

struct TabButton: View {
    let label: String
    let isSelected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(label.uppercased())
                    .font(Theme.labelHeavy(16))
                    .tracking(2.2)
                    .foregroundStyle(isSelected ? Theme.text : (hover ? Theme.dim : Theme.faint))
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Theme.accent)
                            .matchedGeometryEffect(id: "tab-underline", in: ns)
                    }
                }
                .frame(height: 3)
            }
            .fixedSize()
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// An icon that lives in the tab row: same optical size, same baseline, same
/// underline slot — so it reads as one of the options rather than a stray glyph.
struct TabIcon: View {
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                // A hidden label glyph sizes the icon slot, so the gear inherits
                // the tabs' exact height and baseline instead of guessing at them.
                Text("W")
                    .font(Theme.labelHeavy(16))
                    .foregroundStyle(.clear)
                    .frame(width: 17)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(hover ? Theme.dim : Theme.faint)
                    }
                Color.clear.frame(width: 17, height: 3)
            }
            .fixedSize()
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
