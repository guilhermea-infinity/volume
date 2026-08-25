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
            MaybeScroll {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(groups) { g in
                        HStack(spacing: 8) {
                            Eyebrow(text: g.label, color: Theme.faint, size: 13)
                            Spacer()
                            Text(TimeParse.format(g.totalFocused))
                                .font(Theme.mono(10, .medium))
                                .foregroundStyle(Theme.faint)
                        }
                        .padding(.top, 14)
                        .padding(.bottom, 5)
                        .padding(.horizontal, 6)
                        ForEach(g.days, id: \.self) { day in
                            DayRow(day: day,
                                   isSelected: (selected ?? groups.first?.days.first) == day) {
                                withAnimation(.easeOut(duration: 0.15)) { selected = day }
                            }
                        }
                    }
                    if groups.isEmpty {
                        Text("No history yet. Finish your first task.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                            .padding(14)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(width: 320)

            Rectangle().fill(Theme.hairline).frame(width: 1)

            if let day = selected ?? groups.first?.days.first {
                DayDetail(day: day)
            } else {
                VStack {
                    Spacer()
                    Eyebrow(text: "The archive", color: Theme.faint)
                    Text("Every finished day lands here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faint)
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

struct DayRow: View {
    @EnvironmentObject var store: Store
    let day: Date
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        let interval = Stats.dayInterval(day)
        let focused = Stats.focusedMinutes(store.entries, in: interval)
        let tasks = Stats.completed(store.entries, kind: .task, in: interval).count

        HStack {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.text : Theme.dim)
            Spacer()
            Text("\(TimeParse.format(focused)) · \(tasks)")
                .font(Theme.mono(10.5, .medium))
                .foregroundStyle(isSelected ? Theme.accent : Theme.faint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? Theme.accent.opacity(0.13) : (hover ? Theme.raised : .clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hover = $0 }
    }
}

struct DayDetail: View {
    @EnvironmentObject var store: Store
    let day: Date
    @State private var editing: Entry?

    var body: some View {
        let interval = Stats.dayInterval(day)
        let items = store.entries
            .filter { e in e.completedAt.map { interval.contains($0) } ?? false }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let focused = Stats.focusedMinutes(store.entries, in: interval)
        let calls = Stats.callMinutes(store.entries, in: interval)
        let taskCount = items.filter { $0.kind == .task }.count

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: day.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                        color: Theme.faint, size: 14)
                HStack(alignment: .firstTextBaseline, spacing: 26) {
                    StatBlock(label: "Focused", value: .minutes(focused), color: Theme.accent)
                    StatBlock(label: "Tasks", value: .count(taskCount))
                    StatBlock(label: "Calls", value: .minutes(calls),
                              color: calls > 0 ? Theme.call : Theme.dim)
                }
            }
            .padding(20)

            MaybeScroll {
                LazyVStack(spacing: 8) {
                    ForEach(items) { e in
                        DoneRow(entry: e) { editing = e }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editing) { EditSheet(entry: $0) }
    }
}
