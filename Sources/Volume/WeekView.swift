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
    @State private var burstAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        MaybeScroll {
            VStack(spacing: 14) {
                // Hero: the race against your ghost
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: "Focused this week", color: Theme.dim)
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                StatNumber(minutes: focusedThis, size: 54)
                                    .foregroundStyle(Theme.text)
                                    .overlay {
                                        if let at = burstAt {
                                            BurstView(seed: UInt64(at.timeIntervalSince1970 * 1000),
                                                      tint: Theme.good, start: at,
                                                      count: 30, drift: 70)
                                                .frame(width: 620, height: 500)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                if beaten {
                                    Chip(text: "GHOST BEATEN", color: Theme.good, filled: true)
                                        .transition(.scale.combined(with: .opacity))
                                } else if focusedLast > 0 {
                                    Chip(text: delta >= 0
                                         ? "▲ \(TimeParse.format(delta)) ahead"
                                         : "▼ \(TimeParse.format(-delta)) behind",
                                         color: delta >= 0 ? Theme.good : Theme.accentHi)
                                }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Eyebrow(text: "Last week", color: Theme.faint, size: 13)
                            Text(focusedLast > 0 ? TimeParse.format(focusedLast) : "—")
                                .font(Theme.din(28))
                                .foregroundStyle(Theme.ghost)
                        }
                    }

                    GhostRaceBar(
                        progress: focusedLast > 0 ? Double(focusedThis) / Double(focusedLast) : nil,
                        ghostAt: focusedLast > 0 ? Double(focusedPace) / Double(focusedLast) : nil,
                        beaten: beaten
                    )
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: focusedThis)
                    .onChange(of: beaten) { was, now in
                        guard now, !was else { return }
                        Feedback.ghostBeaten()
                        guard !reduceMotion, !Theme.isRendering else { return }
                        burstAt = .now
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(1600))
                            burstAt = nil
                        }
                    }

                    HStack(spacing: 14) {
                        LegendKey(color: beaten ? Theme.good : Theme.accent, label: "You")
                        LegendKey(color: Theme.ghost, label: "Ghost — last week's you, right now")
                        Spacer()
                        if focusedLast == 0 {
                            Text("First week. You're setting the bar.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.faint)
                        } else {
                            Text("Finish line: \(TimeParse.format(focusedLast))")
                                .font(Theme.mono(10, .medium))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .animation(.spring(duration: 0.5), value: beaten)

                // Stat tiles
                HStack(spacing: 14) {
                    Tile(label: "Tasks done", value: "\(tasksThis)",
                         sub: "last week \(tasksLast)")
                    Tile(label: "Estimation", value: ratio.map { String(format: "×%.2f", $0) } ?? "—",
                         sub: estimationSub(ratio),
                         valueColor: estimationColor(ratio))
                    Tile(label: "Best day", value: bestDayValue(perThis),
                         sub: bestDaySub(perThis))
                    Tile(label: "Calls", value: TimeParse.format(callsThis),
                         sub: callsSub(callsThis: callsThis, focusedThis: focusedThis,
                                       callsLast: callsLast, focusedLast: focusedLast),
                         valueColor: callsThis > 0 ? Theme.call : Theme.text)
                }

                // Where the focused time went
                let byTag = Stats.minutesByTag(e, in: thisWeek)
                if !byTag.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Eyebrow(text: "Where the time went")
                            Spacer()
                            Text("vs same point last week")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.faint)
                        }
                        // Compare against last week at this same point, not the full week
                        TagBreakdown(items: byTag,
                                     lastWeek: Stats.minutesByTag(e, in: DateInterval(start: lastWeek.start, end: paceEnd)))
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                // Daily chart
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Eyebrow(text: "Minutes per day")
                        Spacer()
                        LegendKey(color: Theme.accent, label: "This week")
                        LegendKey(color: Theme.ghost, label: "Last week")
                    }
                    Chart(makeBars(perThis: perThis, perLast: perLast)) { b in
                        BarMark(x: .value("Day", b.day), y: .value("Minutes", b.minutes), width: .ratio(0.42))
                            .position(by: .value("Week", b.series))
                            .foregroundStyle(by: .value("Week", b.series))
                            .cornerRadius(3)
                    }
                    .chartXScale(domain: Stats.dayLabels)
                    .chartForegroundStyleScale(
                        domain: ["This week", "Last week"],
                        range: [Theme.accent, Theme.ghost.opacity(0.45)]
                    )
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(Theme.mono(10, .medium))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) { _ in
                            AxisGridLine().foregroundStyle(Theme.hairline)
                            AxisValueLabel()
                                .font(Theme.mono(10, .medium))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .frame(height: 220)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .padding(20)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func estimationSub(_ r: Double?) -> String {
        guard let r else { return "no data yet" }
        if r > 1.05 { return "you underestimate by \(Int(((r - 1) * 100).rounded()))%" }
        if r < 0.95 { return "you overestimate by \(Int(((1 - r) * 100).rounded()))%" }
        return "spot on"
    }

    private func estimationColor(_ r: Double?) -> Color {
        guard let r else { return Theme.text }
        return abs(r - 1) <= 0.05 ? Theme.good : Theme.text
    }

    private func bestDayValue(_ per: [Int]) -> String {
        guard let mx = per.max(), mx > 0, let i = per.firstIndex(of: mx) else { return "—" }
        return Stats.dayLabels[i]
    }

    private func bestDaySub(_ per: [Int]) -> String {
        guard let mx = per.max(), mx > 0 else { return "no focus logged yet" }
        return "\(TimeParse.format(mx)) focused"
    }

    private func callsSub(callsThis: Int, focusedThis: Int, callsLast: Int, focusedLast: Int) -> String {
        let totThis = callsThis + focusedThis
        let pThis = totThis > 0 ? Int((100.0 * Double(callsThis) / Double(totThis)).rounded()) : 0
        let totLast = callsLast + focusedLast
        guard totLast > 0 else { return "\(pThis)% of logged time" }
        let pLast = Int((100.0 * Double(callsLast) / Double(totLast)).rounded())
        return "\(pThis)% of time (last wk \(pLast)%)"
    }

    private func makeBars(perThis: [Int], perLast: [Int]) -> [DayBar] {
        (0..<7).flatMap { i in
            [DayBar(id: "t\(i)", day: Stats.dayLabels[i], series: "This week", minutes: perThis[i]),
             DayBar(id: "l\(i)", day: Stats.dayLabels[i], series: "Last week", minutes: perLast[i])]
        }
    }
}

struct TagBreakdown: View {
    let items: [(Tag, Int)]
    let lastWeek: [(Tag, Int)]

    var body: some View {
        let total = max(1, items.reduce(0) { $0 + $1.1 })
        VStack(alignment: .leading, spacing: 12) {
            // One stacked bar: the shape of your week at a glance
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(items, id: \.0) { tag, mins in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: tag.hex))
                            .frame(width: max(3, geo.size.width * Double(mins) / Double(total)))
                    }
                }
            }
            .frame(height: 12)

            VStack(spacing: 7) {
                ForEach(items, id: \.0) { tag, mins in
                    let prev = lastWeek.first { $0.0 == tag }?.1 ?? 0
                    let pct = Int((100.0 * Double(mins) / Double(total)).rounded())
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: tag.hex)).frame(width: 7, height: 7)
                        Text(tag.rawValue)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                        Text("\(pct)%")
                            .font(Theme.mono(10, .medium))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 34, alignment: .trailing)
                        Text(TimeParse.format(mins))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.text)
                            .frame(width: 62, alignment: .trailing)
                        Text(prev > 0 ? deltaLabel(mins - prev) : "new")
                            .font(Theme.mono(10, .medium))
                            .foregroundStyle(prev > 0 ? (mins >= prev ? Theme.good : Theme.faint) : Theme.faint)
                            .frame(width: 62, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func deltaLabel(_ delta: Int) -> String {
        delta == 0 ? "same" : (delta > 0 ? "+" : "−") + TimeParse.format(abs(delta))
    }
}

struct LegendKey: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
    }
}
