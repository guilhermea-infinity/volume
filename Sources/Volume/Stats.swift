import Foundation

enum Stats {
    static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // Monday
        return c
    }

    static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func week(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date, duration: 7 * 86400)
    }

    static func completed(_ entries: [Entry], kind: Kind, in interval: DateInterval) -> [Entry] {
        entries.filter { e in
            guard e.kind == kind, let c = e.completedAt else { return false }
            return interval.contains(c)
        }
    }

    static func focusedMinutes(_ entries: [Entry], in interval: DateInterval) -> Int {
        completed(entries, kind: .task, in: interval).reduce(0) { $0 + ($1.actualMin ?? 0) }
    }

    static func callMinutes(_ entries: [Entry], in interval: DateInterval) -> Int {
        completed(entries, kind: .call, in: interval).reduce(0) { $0 + ($1.actualMin ?? 0) }
    }

    /// Median of actual/estimate over completed tasks with an estimate.
    static func medianRatio(_ entries: [Entry], in interval: DateInterval) -> Double? {
        let ratios = completed(entries, kind: .task, in: interval)
            .compactMap { e -> Double? in
                guard let est = e.estimateMin, est > 0, let act = e.actualMin else { return nil }
                return Double(act) / Double(est)
            }
            .sorted()
        guard !ratios.isEmpty else { return nil }
        let mid = ratios.count / 2
        return ratios.count % 2 == 1 ? ratios[mid] : (ratios[mid - 1] + ratios[mid]) / 2
    }

    /// Focused minutes for each day of the given week, index 0 = Monday.
    static func minutesPerDay(_ entries: [Entry], week: DateInterval) -> [Int] {
        var out = [Int](repeating: 0, count: 7)
        let weekStart = calendar.startOfDay(for: week.start)
        for e in completed(entries, kind: .task, in: week) {
            guard let c = e.completedAt else { continue }
            let d = calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: c)).day ?? 0
            if d >= 0 && d < 7 { out[d] += e.actualMin ?? 0 }
        }
        return out
    }

    /// Focused minutes per tag in the interval, biggest first. Untagged work
    /// is omitted rather than lumped into a misleading bucket.
    static func minutesByTag(_ entries: [Entry], in interval: DateInterval) -> [(Tag, Int)] {
        var totals: [Tag: Int] = [:]
        for e in completed(entries, kind: .task, in: interval) {
            guard let raw = e.tag, let tag = Tag(rawValue: raw) else { continue }
            totals[tag, default: 0] += e.actualMin ?? 0
        }
        return totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    static func dayInterval(_ day: Date) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        return DateInterval(start: start, duration: 86400)
    }
}
