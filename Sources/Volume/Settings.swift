import SwiftUI
import EventKit
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance") }
    }
    @Published var calendarSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(calendarSyncEnabled, forKey: "calendarSyncEnabled")
            if calendarSyncEnabled {
                Task { @MainActor in await CalendarSync.shared.syncNow() }
            }
        }
    }

    init() {
        appearance = ProcessInfo.processInfo.environment["VOLUME_RENDER_APPEARANCE"]
            ?? UserDefaults.standard.string(forKey: "appearance") ?? "dark"
        calendarSyncEnabled = UserDefaults.standard.object(forKey: "calendarSyncEnabled") as? Bool ?? true
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var sync = CalendarSync.shared
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Eyebrow(text: "Settings", color: Theme.accent)
                Spacer()
                GhostButton(title: "Done") { dismiss() }
            }

            // Appearance
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Appearance", color: Theme.faint, size: 13)
                HStack(spacing: 6) {
                    SegPill(label: "Dark", selected: settings.appearance == "dark") { settings.appearance = "dark" }
                    SegPill(label: "Light", selected: settings.appearance == "light") { settings.appearance = "light" }
                    SegPill(label: "System", selected: settings.appearance == "system") { settings.appearance = "system" }
                }
            }

            // Calendar sync
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Meetings from Calendar", color: Theme.faint, size: 13)
                    Spacer()
                    Toggle("", isOn: $settings.calendarSyncEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                Text(sync.statusLine)
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(sync.healthy ? Theme.good : Theme.over)
                Text("Meetings on your calendar are logged as calls automatically — 2+ people, not declined, once they end. To connect Google Calendar: add your Google account below and switch on Calendars for it. Volume picks it up on the next sync.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    GhostButton(title: "Add account…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
                    }
                    GhostButton(title: "Sync now") {
                        Task { @MainActor in await CalendarSync.shared.syncNow() }
                    }
                }
            }

            // Startup
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: "Start at login", color: Theme.faint, size: 13)
                    Text("Keeps ⇧⌘Space and the sync alive after a restart.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.bg)
        .tint(Theme.accent)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            Task { @MainActor in CalendarSync.shared.refreshStatus() }
        }
    }
}

struct SegPill: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(Theme.label(13))
                .tracking(1.4)
                .foregroundStyle(selected ? Color(hex: 0x17110A) : (hover ? Theme.text : Theme.dim))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(hover ? Theme.raised : Theme.surface), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? .clear : Theme.hairline))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hover ? Theme.text : Theme.faint)
                .frame(width: 28, height: 28)
                .background(hover ? Theme.raised : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
