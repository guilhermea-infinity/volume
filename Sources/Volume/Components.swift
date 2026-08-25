import SwiftUI

// MARK: - Atoms

struct Chip: View {
    let text: String
    let color: Color
    var filled = false

    var body: some View {
        Text(text)
            .font(Theme.mono(11))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.14)), in: Capsule())
            .foregroundStyle(filled ? Theme.bg : color)
    }
}

struct AccentButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Theme.labelHeavy(14))
                .tracking(1.4)
                .foregroundStyle(disabled ? Theme.faint : Color(hex: 0x17110A))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    disabled ? AnyShapeStyle(Theme.raised)
                             : AnyShapeStyle(hover ? Theme.accentHi : Theme.accent),
                    in: Capsule())
                .overlay(Capsule().strokeBorder(disabled ? Theme.hairline : .clear))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct GhostButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Theme.label(14))
                .tracking(1.4)
                .foregroundStyle(hover ? Theme.text : Theme.dim)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(hover ? Theme.raised : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct CardBG: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
    }
}
extension View { func card() -> some View { modifier(CardBG()) } }

struct RowCard<Content: View>: View {
    @State private var hover = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(hover ? Theme.raised : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct DarkField: ViewModifier {
    var focused = false
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(focused ? Theme.accent.opacity(0.7) : Theme.hairline))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
extension View { func darkField(focused: Bool = false) -> some View { modifier(DarkField(focused: focused)) } }

// MARK: - Signature: the ghost race track

struct GhostRaceBar: View {
    let progress: Double?   // this week / last week total; nil = no baseline
    let ghostAt: Double?    // where last week's you is right now, 0...1
    let beaten: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.35))
                Capsule().strokeBorder(Theme.hairline)
                if let p = progress, p > 0 {
                    Capsule()
                        .fill(LinearGradient(
                            colors: beaten ? [Theme.good, Color(hex: 0x86ECBC)] : [Theme.accent, Theme.accentHi],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, w * min(p, 1)))
                }
                if let g = ghostAt {
                    Capsule()
                        .fill(Theme.ghost)
                        .frame(width: 3)
                        .padding(.vertical, -4)
                        .offset(x: w * min(max(g, 0), 1) - 1.5)
                }
            }
        }
        .frame(height: 18)
    }
}

// MARK: - Stat displays

struct StatBlock: View {
    let label: String
    let value: String
    var color: Color = Theme.text
    var size: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Eyebrow(text: label, color: Theme.faint, size: 13)
            Text(value)
                .font(Theme.din(size))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
    }
}

struct Tile: View {
    let label: String
    let value: String
    let sub: String
    var valueColor: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: label, color: Theme.faint, size: 13)
            Text(value)
                .font(Theme.din(26))
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .card()
    }
}

// MARK: - Rows

struct PlannedRow: View {
    @EnvironmentObject var store: Store
    let entry: Entry
    let onDone: () -> Void

    var body: some View {
        RowCard {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Theme.faint, lineWidth: 1.5)
                    .frame(width: 13, height: 13)
                Text(entry.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Chip(text: "est \(TimeParse.format(entry.estimateMin ?? 0))", color: Theme.ghost)
                AccentButton(title: "Done", action: onDone)
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) { store.delete(entry.id) }
        }
    }
}

struct DoneRow: View {
    @EnvironmentObject var store: Store
    let entry: Entry

    private var resultColor: Color {
        if entry.kind == .call { return Theme.call }
        if let est = entry.estimateMin, let act = entry.actualMin {
            return act <= est ? Theme.good : Theme.over
        }
        return Theme.good
    }

    var body: some View {
        RowCard {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(resultColor.opacity(0.16)).frame(width: 18, height: 18)
                    Image(systemName: entry.kind == .call ? "phone.fill" : "checkmark")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(resultColor)
                }
                Text(entry.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if entry.kind == .task, let est = entry.estimateMin {
                    Chip(text: "est \(TimeParse.format(est))", color: Theme.ghost)
                }
                if let act = entry.actualMin {
                    Chip(text: TimeParse.format(act), color: resultColor)
                }
                if let c = entry.completedAt {
                    Text(c.formatted(date: .omitted, time: .shortened))
                        .font(Theme.mono(10, .medium))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) { store.delete(entry.id) }
        }
    }
}

// MARK: - Sheets

private struct SheetChrome<Content: View>: View {
    let eyebrow: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: eyebrow, color: Theme.accent)
            content
        }
        .padding(22)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}

struct CompleteSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let entry: Entry
    @State private var actual = ""
    @FocusState private var focused: Bool

    private var parsed: Int? { TimeParse.minutes(from: actual) }

    var body: some View {
        SheetChrome(eyebrow: "Task done") {
            Text(entry.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Estimated \(TimeParse.format(entry.estimateMin ?? 0)). How long did it take?")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
            TextField("45m, 1h30, 1:30…", text: $actual)
                .darkField(focused: focused)
                .focused($focused)
                .onSubmit { save() }
            HStack {
                Spacer()
                GhostButton(title: "Cancel") { dismiss() }
                AccentButton(title: "Save", disabled: parsed == nil) { save() }
            }
        }
        .frame(width: 360)
        .onAppear { focused = true }
    }

    private func save() {
        guard let m = parsed else { return }
        store.complete(entry.id, actualMin: m)
        dismiss()
    }
}

struct RetroSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var estimate = ""
    @State private var actual = ""
    @State private var date = Date.now
    @FocusState private var focused: Bool

    private var estMin: Int? { TimeParse.minutes(from: estimate) }
    private var actMin: Int? { TimeParse.minutes(from: actual) }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && estMin != nil && actMin != nil
    }

    var body: some View {
        SheetChrome(eyebrow: "Log past work") {
            TextField("What did you do?", text: $title)
                .darkField(focused: focused)
                .focused($focused)
            HStack(spacing: 8) {
                TextField("Estimate", text: $estimate).darkField()
                TextField("Actual", text: $actual).darkField()
            }
            DatePicker("When", selection: $date, in: ...Date.now)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
            HStack {
                Spacer()
                GhostButton(title: "Cancel") { dismiss() }
                AccentButton(title: "Save", disabled: !valid) { save() }
            }
        }
        .frame(width: 400)
        .onAppear { focused = true }
    }

    private func save() {
        guard let est = estMin, let act = actMin else { return }
        store.addRetro(title: title.trimmingCharacters(in: .whitespaces),
                       estimateMin: est, actualMin: act, at: date)
        dismiss()
    }
}

struct CallSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var duration = ""
    @State private var date = Date.now
    @FocusState private var focused: Bool

    private var durMin: Int? { TimeParse.minutes(from: duration) }

    var body: some View {
        SheetChrome(eyebrow: "Log a call") {
            TextField("What call? (optional)", text: $title)
                .darkField()
            TextField("Duration — 30m, 1h…", text: $duration)
                .darkField(focused: focused)
                .focused($focused)
                .onSubmit { save() }
            DatePicker("When", selection: $date, in: ...Date.now)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
            HStack {
                Spacer()
                GhostButton(title: "Cancel") { dismiss() }
                AccentButton(title: "Save", disabled: durMin == nil) { save() }
            }
        }
        .frame(width: 400)
        .onAppear { focused = true }
    }

    private func save() {
        guard let m = durMin else { return }
        let t = title.trimmingCharacters(in: .whitespaces)
        store.addCall(title: t.isEmpty ? "Call" : t, minutes: m, at: date)
        dismiss()
    }
}
