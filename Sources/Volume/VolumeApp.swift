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
        _store = StateObject(wrappedValue: Store())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 740)
    }
}

enum AppTab: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case history = "History"
}

struct RootView: View {
    @State private var tab: AppTab

    init(tab: AppTab = .today) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(tab: $tab)
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
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear { NSApplication.shared.appearance = NSAppearance(named: .darkAqua) }
    }
}

struct TopBar: View {
    @Binding var tab: AppTab
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 9) {
                BarsGlyph()
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
            }
        }
        .padding(.leading, 86)
        .padding(.trailing, 22)
        .frame(height: 54)
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
