import Foundation

enum TimeParse {
    /// Parses "90", "90m", "1h", "1h30", "1h 30m", "1.5h", "1:30", "45 min" into minutes.
    static func minutes(from raw: String) -> Int? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        s = s.replacingOccurrences(of: ",", with: ".")
        s = s.replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }

        if s.contains(":") {
            let parts = s.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
                  h >= 0, m >= 0, m < 60 else { return nil }
            let total = h * 60 + m
            return total > 0 ? total : nil
        }

        var idx = s.startIndex

        func readNumber() -> Double? {
            var t = ""
            while idx < s.endIndex, s[idx].isNumber || s[idx] == "." {
                t.append(s[idx])
                idx = s.index(after: idx)
            }
            return t.isEmpty ? nil : Double(t)
        }

        func readLetters() -> String {
            var t = ""
            while idx < s.endIndex, s[idx].isLetter {
                t.append(s[idx])
                idx = s.index(after: idx)
            }
            return t
        }

        let hourUnits: Set<String> = ["h", "hr", "hrs", "hour", "hours"]
        let minUnits: Set<String> = ["m", "min", "mins", "minute", "minutes"]

        guard let first = readNumber() else { return nil }

        // Plain number = minutes
        if idx == s.endIndex {
            let m = Int(first.rounded())
            return m > 0 ? m : nil
        }

        var total: Double = 0
        if s[idx] == "h" {
            guard hourUnits.contains(readLetters()) else { return nil }
            total = first * 60
            if let mins = readNumber() {
                if idx < s.endIndex {
                    guard minUnits.contains(readLetters()) else { return nil }
                }
                guard idx == s.endIndex else { return nil }
                total += mins
            } else if idx != s.endIndex {
                return nil
            }
        } else if s[idx] == "m" {
            guard minUnits.contains(readLetters()), idx == s.endIndex else { return nil }
            total = first
        } else {
            return nil
        }

        let m = Int(total.rounded())
        return m > 0 ? m : nil
    }

    static func format(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(minutes)m"
    }
}
