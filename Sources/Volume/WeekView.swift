import SwiftUI
import Charts

struct DayBar: Identifiable {
    let id: String
    let day: String
    let series: String
    let minutes: Int
}

struct WeekView: View {
    @EnvironmentObject var store: Store
    @State private var now = Date.now

    var body: some View {
        let thisWeek = Stats.week(containing: now)
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        let lastWeek = Stats.week(containing: weekAgo)
        let e = store.entries

        let focusedThis = Stats.focusedMinutes(e, in: thisWeek)
        let focusedLast = Stats.focusedMinutes(e, in: lastWeek)
        let paceEnd = max(lastWeek.start, min(weekAgo, lastWeek.end))
        let focusedPace = Stats.focusedMinutes(e, in: DateInterval(start: lastWeek.start, end: paceEnd))
        let callsThis = Stats.callMinutes(e, in: thisWeek)
        let callsLast = Stats.callMinutes(e, in: lastWeek)
        let tasksThis = Stats.completed(e, kind: .task, in: thisWeek).count
        let tasksLast = Stats.completed(e, kind: .task, in: lastWeek).count
        let ratio = Stats.medianRatio(e, in: thisWeek)
        let perThis = Stats.minutesPerDay(e, week: thisWeek)
        let perLast = Stats.minutesPerDay(e, week: lastWeek)
        let beaten = focusedLast > 0 && focusedThis > focusedLast
        let delta = focusedThis - focusedPace

        ScrollView {
            VStack(spacing: 14) {
                Card(title: "Focused this week") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(TimeParse.format(focusedThis))
                            .font(.system(size: 40, weight: .bold))
                            .monospacedDigit()
                        if beaten {
                            Text("🏆 Beat last week!")
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(focusedLast > 0
                                 ? "Last week: \(TimeParse.format(focusedLast))"
                                 : "No baseline yet — this week sets the bar")
                                .foregroundStyle(.secondary)
                            if focusedLast > 0 {
                                Text(delta >= 0
                                     ? "🔥 \(TimeParse.format(delta)) ahead of last week's pace"
                                     : "⏳ \(TimeParse.format(-delta)) behind last week's pace")
                                    .font(.callout)
                                    .foregroundStyle(delta >= 0 ? Color.green : Color.orange)
                            }
                        }
                    }
                    ProgressCapsule(
                        ratio: focusedLast > 0 ? Double(focusedThis) / Double(focusedLast) : nil,
                        beaten: beaten
                    )
                }

                HStack(spacing: 14) {
                    StatTile(title: "Tasks done", value: "\(tasksThis)", sub: "last week \(tasksLast)")
                    StatTile(title: "Estimation",
                             value: ratio.map { String(format: "×%.2f", $0) } ?? "—",
                             sub: estimationSub(ratio))
                    StatTile(title: "Best day", value: bestDayLabel(perThis), sub: "this week")
                    StatTile(title: "Calls",
                             value: TimeParse.format(callsThis),
                             sub: callsSub(callsThis: callsThis, focusedThis: focusedThis,
                                           callsLast: callsLast, focusedLast: focusedLast))
                }

                Card(title: "Minutes per day") {
                    Chart(makeBars(perThis: perThis, perLast: perLast)) { b in
                        BarMark(x: .value("Day", b.day), y: .value("Minutes", b.minutes))
                            .position(by: .value("Week", b.series))
                            .foregroundStyle(by: .value("Week", b.series))
                            .cornerRadius(3)
                    }
                    .chartXScale(domain: Stats.dayLabels)
                    .chartForegroundStyleScale(
                        domain: ["This week", "Last week"],
                        range: [Color.indigo, Color.gray.opacity(0.45)]
                    )
                    .frame(height: 230)
                }
            }
            .padding(18)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func estimationSub(_ r: Double?) -> String {
        guard let r else { return "no data yet" }
        if r > 1.05 { return "you underestimate by \(Int(((r - 1) * 100).rounded()))%" }
        if r < 0.95 { return "you overestimate by \(Int(((1 - r) * 100).rounded()))%" }
        return "spot on"
    }

    private func bestDayLabel(_ per: [Int]) -> String {
        guard let mx = per.max(), mx > 0, let i = per.firstIndex(of: mx) else { return "—" }
        return "\(Stats.dayLabels[i]) · \(TimeParse.format(mx))"
    }

    private func callsSub(callsThis: Int, focusedThis: Int, callsLast: Int, focusedLast: Int) -> String {
        let totThis = callsThis + focusedThis
        let pThis = totThis > 0 ? Int((100.0 * Double(callsThis) / Double(totThis)).rounded()) : 0
        let totLast = callsLast + focusedLast
        guard totLast > 0 else { return "\(pThis)% of logged time" }
        let pLast = Int((100.0 * Double(callsLast) / Double(totLast)).rounded())
        return "\(pThis)% of logged time (last wk \(pLast)%)"
    }

    private func makeBars(perThis: [Int], perLast: [Int]) -> [DayBar] {
        (0..<7).flatMap { i in
            [DayBar(id: "t\(i)", day: Stats.dayLabels[i], series: "This week", minutes: perThis[i]),
             DayBar(id: "l\(i)", day: Stats.dayLabels[i], series: "Last week", minutes: perLast[i])]
        }
    }
}
