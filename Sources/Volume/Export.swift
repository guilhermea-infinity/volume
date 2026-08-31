import SwiftUI
import AppKit

enum ExportFormat: String, CaseIterable {
    case markdown = "Markdown"
    case csv = "CSV"
    case json = "JSON"

    var ext: String {
        switch self {
        case .markdown: "md"
        case .csv: "csv"
        case .json: "json"
        }
    }
}

enum ExportRange: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This week"
    case last7 = "Last 7 days"
    case last30 = "Last 30 days"
    case all = "All"

    /// First and last day of the range, inclusive.
    func days(now: Date, earliest: Date?) -> (Date, Date) {
        let cal = Stats.calendar
        let today = cal.startOfDay(for: now)
        switch self {
        case .today:
            return (today, today)
        case .thisWeek:
            let week = Stats.week(containing: now)
            return (cal.startOfDay(for: week.start), today)
        case .last7:
            return (cal.date(byAdding: .day, value: -6, to: today) ?? today, today)
        case .last30:
            return (cal.date(byAdding: .day, value: -29, to: today) ?? today, today)
        case .all:
            return (cal.startOfDay(for: earliest ?? today), today)
        }
    }
}

/// Everything logged in a window, as text you can hand to something else —
/// a spreadsheet, a script, or a model you want to ask about your week.
enum Export {
    static func interval(from: Date, to: Date) -> DateInterval {
        let cal = Stats.calendar
        let start = cal.startOfDay(for: min(from, to))
        let endDay = cal.startOfDay(for: max(from, to))
        let end = cal.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        return DateInterval(start: start, end: end)
    }

    static func filename(from: Date, to: Date, format: ExportFormat) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let a = f.string(from: min(from, to)), b = f.string(from: max(from, to))
        return a == b ? "volume-\(a).\(format.ext)" : "volume-\(a)-to-\(b).\(format.ext)"
    }

    static func build(_ entries: [Entry], from: Date, to: Date,
                      format: ExportFormat, includeUpNext: Bool) -> String {
        let window = interval(from: from, to: to)
        let logged = entries
            .filter { e in e.completedAt.map { window.contains($0) } ?? false }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let upNext = includeUpNext
            ? entries.filter { $0.kind == .task && !$0.isDone }
                .sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
            : []

        switch format {
        case .markdown: return markdown(logged, upNext: upNext, window: window)
        case .csv: return csv(logged)
        case .json: return json(logged, upNext: upNext, window: window)
        }
    }

    // MARK: - Markdown

    private static func markdown(_ logged: [Entry], upNext: [Entry], window: DateInterval) -> String {
        let cal = Stats.calendar
        let focused = Stats.focusedMinutes(logged, in: window)
        let calls = Stats.callMinutes(logged, in: window)
        let tasks = logged.filter { $0.kind == .task }.count
        let dayCount = max(1, cal.dateComponents([.day], from: window.start, to: window.end).day ?? 1)

        var out = "# Volume — \(dayLabel(window.start)) to \(dayLabel(window.end.addingTimeInterval(-1)))\n\n"
        out += "Focused \(TimeParse.format(focused)) across \(tasks) task\(tasks == 1 ? "" : "s")"
        out += " · calls \(TimeParse.format(calls))"
        if focused + calls > 0 {
            out += " (\(Int((Double(calls) / Double(focused + calls) * 100).rounded()))% of logged time)"
        }
        let workedDays = Set(logged.compactMap { $0.completedAt.map { cal.startOfDay(for: $0) } }).count
        out += "\nSpan \(dayCount) day\(dayCount == 1 ? "" : "s")"
        out += ", \(workedDays) with work logged"
        if workedDays > 0 {
            out += " · \(TimeParse.format(focused / workedDays)) focused per working day"
        }
        out += "\n"

        if let ratio = Stats.medianRatio(logged, in: window) {
            let pct = Int((abs(ratio - 1) * 100).rounded())
            let verdict = ratio > 1.02 ? "underestimates by \(pct)%"
                : ratio < 0.98 ? "overestimates by \(pct)%" : "spot on"
            out += "Estimation: median actual/estimate ×\(String(format: "%.2f", ratio)) — \(verdict)\n"
        }

        let byTag = Stats.minutesByTag(logged, in: window)
        if !byTag.isEmpty {
            let total = max(1, byTag.reduce(0) { $0 + $1.1 })
            let parts = byTag.map { "\($0.0.rawValue.capitalized) \(TimeParse.format($0.1)) (\(Int((Double($0.1) / Double(total) * 100).rounded()))%)" }
            out += "Where the time went: \(parts.joined(separator: ", "))\n"
        }

        // One section per day that actually has something in it.
        let grouped = Dictionary(grouping: logged) { e in cal.startOfDay(for: e.completedAt ?? .distantPast) }
        for day in grouped.keys.sorted() {
            let items = (grouped[day] ?? []).sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            let dayWindow = Stats.dayInterval(day)
            let dayFocused = Stats.focusedMinutes(items, in: dayWindow)
            let dayCalls = Stats.callMinutes(items, in: dayWindow)
            out += "\n## \(fullDayLabel(day)) — focused \(TimeParse.format(dayFocused))"
            if dayCalls > 0 { out += " · calls \(TimeParse.format(dayCalls))" }
            out += "\n"
            for e in items { out += line(for: e) }
        }

        if !upNext.isEmpty {
            out += "\n## Still up next (\(upNext.count))\n"
            for e in upNext {
                out += "- \(e.priority ? "★ " : "")\(e.title) — est \(TimeParse.format(e.estimateMin ?? 0))\n"
                if let n = e.notes, !n.isEmpty { out += indented(n) }
            }
        }
        return out
    }

    private static func line(for e: Entry) -> String {
        let time = (e.completedAt ?? .distantPast).formatted(date: .omitted, time: .shortened)
        var s = "- \(time) "
        if e.kind == .call {
            s += "call: \(e.title) — \(TimeParse.format(e.actualMin ?? 0))\n"
        } else {
            s += "\(e.title) — "
            if let est = e.estimateMin, let act = e.actualMin {
                let delta = act - est
                s += "est \(TimeParse.format(est)), took \(TimeParse.format(act))"
                if delta != 0 { s += " (\(delta > 0 ? "+" : "−")\(TimeParse.format(abs(delta))))" }
            } else {
                s += "took \(TimeParse.format(e.actualMin ?? 0))"
            }
            if let tag = e.tag { s += " [\(tag)]" }
            s += "\n"
        }
        if let n = e.notes, !n.isEmpty { s += indented(n) }
        return s
    }

    private static func indented(_ notes: String) -> String {
        notes.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "  > \($0)\n" }
            .joined()
    }

    // MARK: - CSV

    private static func csv(_ logged: [Entry]) -> String {
        var out = "date,time,kind,title,estimate_min,actual_min,delta_min,tag,notes,source\n"
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        let clock = DateFormatter(); clock.dateFormat = "HH:mm"
        for e in logged {
            let when = e.completedAt ?? e.createdAt
            let delta: String = {
                guard let est = e.estimateMin, let act = e.actualMin else { return "" }
                return "\(act - est)"
            }()
            let row = [day.string(from: when), clock.string(from: when), e.kind.rawValue, e.title,
                       e.estimateMin.map(String.init) ?? "", e.actualMin.map(String.init) ?? "",
                       delta, e.tag ?? "", e.notes ?? "", e.source ?? "manual"]
            out += row.map(quoted).joined(separator: ",") + "\n"
        }
        return out
    }

    private static func quoted(_ field: String) -> String {
        guard field.contains(where: { ",\"\n".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - JSON

    private static func json(_ logged: [Entry], upNext: [Entry], window: DateInterval) -> String {
        let iso = ISO8601DateFormatter()
        func encode(_ e: Entry) -> [String: Any] {
            var d: [String: Any] = ["id": e.id, "kind": e.kind.rawValue, "title": e.title]
            if let v = e.estimateMin { d["estimate_min"] = v }
            if let v = e.actualMin { d["actual_min"] = v }
            if let est = e.estimateMin, let act = e.actualMin { d["delta_min"] = act - est }
            if let v = e.completedAt { d["completed_at"] = iso.string(from: v) }
            if let v = e.tag { d["tag"] = v }
            if let v = e.notes { d["notes"] = v }
            if e.priority { d["priority"] = true }
            d["source"] = e.source ?? "manual"
            return d
        }
        let payload: [String: Any] = [
            "from": iso.string(from: window.start),
            "to": iso.string(from: window.end.addingTimeInterval(-1)),
            "focused_min": Stats.focusedMinutes(logged, in: window),
            "call_min": Stats.callMinutes(logged, in: window),
            "tasks": logged.filter { $0.kind == .task }.count,
            "by_tag": Dictionary(uniqueKeysWithValues: Stats.minutesByTag(logged, in: window).map { ($0.0.rawValue, $0.1) }),
            "logged": logged.map(encode),
            "up_next": upNext.map(encode),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    // MARK: - Labels

    private static func dayLabel(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private static func fullDayLabel(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
