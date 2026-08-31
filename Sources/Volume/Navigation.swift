import SwiftUI

/// Where the app is pointed. Small enough to be shared, so search can send you
/// to a task without every view having to know about search.
@MainActor
final class Navigation: ObservableObject {
    static let shared = Navigation()

    @Published var tab: AppTab = .today
    /// The day History is showing.
    @Published var historyDay: Date?
    /// A planned task to open the drawer for, once Today is on screen.
    @Published var revealEntry: Int64?
    @Published var searchOpen = false
    @Published var exportOpen = false

    /// Take me to this entry, wherever it lives.
    func go(to entry: Entry) {
        searchOpen = false
        if let done = entry.completedAt {
            if Stats.calendar.isDateInToday(done) {
                tab = .today
                revealEntry = entry.id
            } else {
                historyDay = Stats.calendar.startOfDay(for: done)
                tab = .history
            }
        } else {
            tab = .today
            revealEntry = entry.id
        }
    }
}
