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
        .buttonStyle(PressScale())
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
        .buttonStyle(PressScale())
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

/// A row that can unfold. Open, the card and its drawer are one surface — the
/// row doesn't sprout a second box, it grows.
struct ExpandableRow<Row: View, Drawer: View>: View {
    let isOpen: Bool
    let onToggle: () -> Void
    @ViewBuilder var row: Row
    @ViewBuilder var drawer: Drawer
    @State private var hover = false

    var body: some View {
        VStack(spacing: 0) {
            row
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)
            if isOpen {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                drawer
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(hover && !isOpen ? Theme.raised : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isOpen ? Theme.accent.opacity(0.4) : Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isOpen)
    }
}

/// Marks a row that is carrying a note, so you can see it without opening it.
struct NoteMark: View {
    let hasNotes: Bool

    var body: some View {
        if hasNotes {
            Image(systemName: "text.alignleft")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Theme.accent.opacity(0.75))
                .transition(.scale.combined(with: .opacity))
        }
    }
}

private struct NoteHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The drawer itself. Saves as you type — there is nothing to press, and no
/// state to lose.
struct NotesDrawer: View {
    @EnvironmentObject var store: Store
    let entry: Entry
    var onEdit: (() -> Void)? = nil
    var onClose: () -> Void = {}

    @State private var text: String
    @State private var pendingSave: Task<Void, Never>?
    @State private var measured: CGFloat = 34
    @FocusState private var focused: Bool

    /// Two lines of room to start, growing to about a dozen before it scrolls.
    private var wellHeight: CGFloat { min(max(measured + 4, 40), 260) }

    /// Text ignores a trailing newline when it measures, so the well would
    /// stay put on the Return that opens a new line. The space forces it.
    private var twinText: String {
        if text.isEmpty { return " " }
        return text.hasSuffix("\n") ? text + " " : text
    }

    private let noteFont = Font.system(size: 12.5)
    private let noteLeading: CGFloat = 3
    /// NSTextView lays its text out inside a small padding of its own; the
    /// placeholder and the measuring twin match it rather than fight it.
    private let editorInset: CGFloat = 5

    init(entry: Entry, onEdit: (() -> Void)? = nil, onClose: @escaping () -> Void = {}) {
        self.entry = entry
        self.onEdit = onEdit
        self.onClose = onClose
        _text = State(initialValue: entry.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: 2)
                ZStack(alignment: .topLeading) {
                    // A hidden twin of the text does the measuring, so the
                    // drawer grows line by line instead of parking at a fixed
                    // height with dead space under two lines of note.
                    // fixedSize is what makes it work: without it the twin is
                    // squeezed into the height it is supposed to be reporting,
                    // and the well can never grow past its starting size.
                    Text(twinText)
                        .font(noteFont)
                        .lineSpacing(noteLeading)
                        .padding(.leading, editorInset)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: NoteHeightKey.self, value: g.size.height)
                        })
                        .opacity(0)
                        .allowsHitTesting(false)
                    if text.isEmpty {
                        Text("Notes…")
                            .font(noteFont)
                            .foregroundStyle(Theme.faint)
                            .padding(.leading, editorInset)
                    }
                    if Theme.isRendering {
                        Text(text)
                            .font(noteFont)
                            .foregroundStyle(Theme.text.opacity(0.9))
                            .lineSpacing(noteLeading)
                            .padding(.leading, editorInset)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        TextEditor(text: $text)
                            .textEditorStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .font(noteFont)
                            .foregroundStyle(Theme.text.opacity(0.9))
                            .lineSpacing(noteLeading)
                            .focused($focused)
                    }
                }
                .frame(height: wellHeight, alignment: .topLeading)
                .animation(.spring(response: 0.26, dampingFraction: 0.9), value: wellHeight)
                .onPreferenceChange(NoteHeightKey.self) { h in
                    if abs(h - measured) > 0.5 { measured = h }
                }
            }
            if let onEdit {
                HStack {
                    Spacer()
                    GhostButton(title: "Edit", action: onEdit)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.track)
        .onAppear { focused = true }
        .onExitCommand { commit(); onClose() }
        .onChange(of: text) { _, new in
            pendingSave?.cancel()
            pendingSave = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                store.setNotes(new, for: entry.id)
            }
        }
        .onDisappear { commit() }
    }

    private func commit() {
        pendingSave?.cancel()
        store.setNotes(text, for: entry.id)
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
                Capsule().fill(Theme.track)
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

/// What a scoreboard number is, so it knows how to roll to its next value.
enum StatValue: Equatable {
    case minutes(Int)
    case count(Int)
    case text(String)

    var number: Int? {
        switch self {
        case .minutes(let m): m
        case .count(let c): c
        case .text: nil
        }
    }

    func string(_ n: Int) -> String {
        switch self {
        case .minutes: TimeParse.format(n)
        case .count: "\(n)"
        case .text(let s): s
        }
    }
}

struct StatBlock: View {
    let label: String
    let value: StatValue
    var color: Color = Theme.text
    var size: CGFloat = 30

    /// Seeded from the first value rather than onAppear — ImageRenderer never
    /// runs onAppear, and a scoreboard that renders 0m is a broken screenshot.
    @State private var shown: Double

    init(label: String, value: StatValue, color: Color = Theme.text, size: CGFloat = 30) {
        self.label = label
        self.value = value
        self.color = color
        self.size = size
        _shown = State(initialValue: Double(value.number ?? 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Eyebrow(text: label, color: Theme.faint, size: 13)
            Group {
                if let n = value.number {
                    CountingText(value: shown, font: Theme.din(size)) { value.string($0) }
                        .onChange(of: n) { _, new in
                            withAnimation(.timingCurve(0.15, 0.9, 0.25, 1, duration: 0.75)) {
                                shown = Double(new)
                            }
                        }
                } else {
                    Text(value.string(0)).font(Theme.din(size))
                }
            }
            .foregroundStyle(color)
        }
    }
}

/// A bare rolling number for the Week hero, where the label sits above it.
struct StatNumber: View {
    let minutes: Int
    var size: CGFloat

    @State private var shown: Double

    init(minutes: Int, size: CGFloat = 54) {
        self.minutes = minutes
        self.size = size
        _shown = State(initialValue: Double(minutes))
    }

    var body: some View {
        CountingText(value: shown, font: Theme.din(size)) { TimeParse.format($0) }
            .onChange(of: minutes) { _, new in
                withAnimation(.timingCurve(0.15, 0.9, 0.25, 1, duration: 0.85)) {
                    shown = Double(new)
                }
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
    var isOpen = false
    var onToggle: () -> Void = {}
    var onEdit: (() -> Void)? = nil
    let onDone: () -> Void

    var body: some View {
        ExpandableRow(isOpen: isOpen, onToggle: onToggle) {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Theme.faint, lineWidth: 1.5)
                    .frame(width: 13, height: 13)
                Text(entry.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                NoteMark(hasNotes: !isOpen && entry.notes?.isEmpty == false)
                Spacer(minLength: 8)
                Chip(text: "est \(TimeParse.format(entry.estimateMin ?? 0))", color: Theme.ghost)
                AccentButton(title: "Done", action: onDone)
            }
        } drawer: {
            NotesDrawer(entry: entry, onEdit: onEdit, onClose: onToggle)
        }
        .contextMenu {
            Button(isOpen ? "Hide notes" : "Notes", action: onToggle)
            if onEdit != nil { Button("Edit") { onEdit?() } }
            Button("Delete", role: .destructive) { store.delete(entry.id) }
        }
    }
}

struct DoneRow: View {
    @EnvironmentObject var store: Store
    let entry: Entry
    var isOpen = false
    var onToggle: () -> Void = {}
    var onEdit: (() -> Void)? = nil
    @State private var landed = false

    private var resultColor: Color {
        if entry.kind == .call { return Theme.call }
        if let est = entry.estimateMin, let act = entry.actualMin {
            return act <= est ? Theme.good : Theme.over
        }
        return Theme.good
    }

    var body: some View {
        ExpandableRow(isOpen: isOpen, onToggle: onToggle) {
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
                NoteMark(hasNotes: !isOpen && entry.notes?.isEmpty == false)
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
        } drawer: {
            NotesDrawer(entry: entry, onEdit: onEdit, onClose: onToggle)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(resultColor.opacity(landed ? 0.85 : 0), lineWidth: 1.5)
        )
        .scaleEffect(landed ? 1.025 : 1, anchor: .leading)
        // The row you just finished announces itself, then settles.
        .onAppear {
            guard let c = entry.completedAt, Date.now.timeIntervalSince(c) < 2.5 else { return }
            landed = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(70))
                withAnimation(.easeOut(duration: 0.85)) { landed = false }
            }
        }
        .contextMenu {
            Button(isOpen ? "Hide notes" : "Notes", action: onToggle)
            if onEdit != nil { Button("Edit") { onEdit?() } }
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

/// Fix a logged entry after the fact — wrong title, wrong actual, wrong day.
struct EditSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let entry: Entry

    @State private var title: String
    @State private var estimate: String
    @State private var actual: String
    @State private var when: Date
    @FocusState private var focused: Bool

    init(entry: Entry) {
        self.entry = entry
        _title = State(initialValue: entry.title)
        _estimate = State(initialValue: entry.estimateMin.map { TimeParse.format($0) } ?? "")
        _actual = State(initialValue: entry.actualMin.map { TimeParse.format($0) } ?? "")
        _when = State(initialValue: entry.completedAt ?? entry.createdAt)
    }

    private var isCall: Bool { entry.kind == .call }
    /// Still in Up next: no actual, no time it happened at.
    private var isPlanned: Bool { entry.completedAt == nil }
    private var estMin: Int? { TimeParse.minutes(from: estimate) }
    private var actMin: Int? { TimeParse.minutes(from: actual) }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (isCall || estMin != nil)
            && (isPlanned || actMin != nil)
    }

    var body: some View {
        SheetChrome(eyebrow: isCall ? "Edit call" : (isPlanned ? "Edit task" : "Edit logged task")) {
            TextField("Title", text: $title)
                .darkField(focused: focused)
                .focused($focused)
            HStack(spacing: 8) {
                if !isCall {
                    TextField("Estimate", text: $estimate)
                        .darkField()
                        .onSubmit { save() }
                }
                if !isPlanned {
                    TextField(isCall ? "Duration" : "Actual", text: $actual)
                        .darkField()
                        .onSubmit { save() }
                }
            }
            if !isPlanned {
                DatePicker("When", selection: $when, in: ...Date.now)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
            if entry.source == "calendar" {
                Text("Synced from your calendar. Saving takes this entry over — later calendar changes stop applying to it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                GhostButton(title: "Delete") {
                    store.delete(entry.id)
                    dismiss()
                }
                Spacer()
                GhostButton(title: "Cancel") { dismiss() }
                AccentButton(title: "Save", disabled: !valid) { save() }
            }
        }
        .frame(width: 400)
        .onAppear { focused = true }
    }

    private func save() {
        guard valid else { return }
        store.update(entry.id,
                     title: title.trimmingCharacters(in: .whitespaces),
                     estimateMin: isCall ? nil : estMin,
                     actualMin: isPlanned ? nil : actMin,
                     completedAt: isPlanned ? nil : when)
        dismiss()
    }
}
