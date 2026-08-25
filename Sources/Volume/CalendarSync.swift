import Foundation
import EventKit

/// Native meeting-time sync: reads macOS Calendar (EventKit) every 15 minutes
/// and mirrors ended meetings into the log as calendar-sourced calls.
/// No network, no OAuth — the OS keeps Google Calendar synced for us.
@MainActor
final class CalendarSync: ObservableObject {
    static let shared = CalendarSync()

    @Published var statusLine = "Waiting for first sync…"
    @Published var healthy = false

    private let eventStore = EKEventStore()
    private weak var store: Store?
    private var timer: Timer?

    func configure(store: Store) {
        self.store = store
        Task { await self.requestAndSync() }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in await CalendarSync.shared.syncNow() }
        }
    }

    private func requestAndSync() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await eventStore.requestFullAccessToEvents()
        }
        await syncNow()
    }

    var enabled: Bool {
        UserDefaults.standard.object(forKey: "calendarSyncEnabled") as? Bool ?? true
    }

    func refreshStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            let count = eventStore.calendars(for: .event).count
            if count == 0 {
                statusLine = "No calendars on this Mac yet"
                healthy = false
            }
        case .denied, .restricted:
            statusLine = "Access denied — Privacy & Security → Calendars"
            healthy = false
        case .notDetermined:
            statusLine = "Access not requested yet"
            healthy = false
        default:
            break
        }
        if !enabled { statusLine = "Sync is off"; healthy = false }
    }

    func syncNow() async {
        guard enabled else { refreshStatus(); return }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess, let store else {
            refreshStatus()
            print("calendar sync skipped: no access"); fflush(stdout)
            return
        }
        let now = Date.now
        let windowStart = now.addingTimeInterval(-14 * 86400)
        let predicate = eventStore.predicateForEvents(withStart: windowStart, end: now, calendars: nil)
        let events = eventStore.events(matching: predicate)

        var items: [Store.CalendarCall] = []
        for e in events {
            guard !e.isAllDay,
                  let start = e.startDate, let end = e.endDate,
                  end <= now else { continue }
            // A meeting has people in it — solo focus blocks and reminders don't count.
            let attendees = e.attendees ?? []
            guard attendees.count >= 2 else { continue }
            if let me = attendees.first(where: { $0.isCurrentUser }),
               me.participantStatus == .declined { continue }
            let minutes = Int(end.timeIntervalSince(start) / 60)
            guard minutes >= 5, minutes <= 8 * 60 else { continue }
            items.append(Store.CalendarCall(
                externalId: "\(e.calendarItemIdentifier)@\(Int(start.timeIntervalSince1970))",
                title: e.title ?? "Meeting",
                minutes: minutes,
                endedAt: end))
        }
        store.syncCalendarCalls(items, windowStart: windowStart, windowEnd: now)
        let calendars = eventStore.calendars(for: .event).count
        if calendars == 0 {
            statusLine = "No calendars on this Mac yet"
            healthy = false
        } else {
            statusLine = "\(items.count) meetings synced · \(now.formatted(date: .omitted, time: .shortened))"
            healthy = true
        }
        print("calendar sync: \(items.count) meetings in 14-day window"); fflush(stdout)
    }
}
