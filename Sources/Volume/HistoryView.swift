import SwiftUI

struct WeekGroup: Identifiable {
    let id: Date
    let label: String
    let totalFocused: Int
    let days: [Date]
}

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @State private var selected: Date?

    var body: some View {
        let groups = makeGroups()
        HStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(groups) { g in
                    Section("\(g.label) · \(TimeParse.format(g.totalFocused))") {
                        ForEach(g.days, id: \.self) { day in
                            DayRowLabel(day: day).tag(day)
                        }
                    }
                }
            }
            .frame(width: 330)

            Divider()

            if let day = selected ?? groups.first?.days.first {
                DayDetail(day: day)
            } else {
                VStack {
                    Spacer()
                    Text("No history yet — finish your first task.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func makeGroups() -> [WeekGroup] {
        let cal = Stats.calendar
        let days = Set(store.entries.compactMap { e in
            e.completedAt.map { cal.startOfDay(for: $0) }
        }).sorted(by: >)
        guard !days.isEmpty else { return [] }

        var byWeek: [Date: [Date]] = [:]
        for day in days {
            byWeek[Stats.week(containing: day).start, default: []].append(day)
        }

        let f = Date.FormatStyle().day().month(.abbreviated)
        return byWeek.keys.sorted(by: >).map { start in
            let interval = Stats.week(containing: start)
            let label = "\(interval.start.formatted(f)) – \(interval.end.addingTimeInterval(-1).formatted(f))"
            return WeekGroup(
                id: start,
                label: label,
                totalFocused: Stats.focusedMinutes(store.entries, in: interval),
                days: byWeek[start] ?? []
            )
        }
    }
}

struct DayRowLabel: View {
    @EnvironmentObject var store: Store
    let day: Date

    var body: some View {
        let interval = Stats.dayInterval(day)
        let focused = Stats.focusedMinutes(store.entries, in: interval)
        let tasks = Stats.completed(store.entries, kind: .task, in: interval).count
        HStack {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            Spacer()
            Text("\(TimeParse.format(focused)) · \(tasks)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct DayDetail: View {
    @EnvironmentObject var store: Store
    let day: Date

    var body: some View {
        let interval = Stats.dayInterval(day)
        let items = store.entries
            .filter { e in e.completedAt.map { interval.contains($0) } ?? false }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let focused = Stats.focusedMinutes(store.entries, in: interval)
        let calls = Stats.callMinutes(store.entries, in: interval)
        let taskCount = items.filter { $0.kind == .task }.count

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.title2.bold())
                Text("Focused \(TimeParse.format(focused)) · \(taskCount) tasks · Calls \(TimeParse.format(calls))")
                    .foregroundStyle(.secondary)
            }
            .padding(18)

            List {
                ForEach(items) { e in
                    DoneRow(entry: e)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
