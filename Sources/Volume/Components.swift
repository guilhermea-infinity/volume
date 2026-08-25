import SwiftUI

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(sub)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProgressCapsule: View {
    let ratio: Double? // nil = no baseline
    let beaten: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.18))
                if let r = ratio, r > 0 {
                    Capsule()
                        .fill(beaten
                              ? AnyShapeStyle(LinearGradient(colors: [.green, .mint],
                                                             startPoint: .leading, endPoint: .trailing))
                              : AnyShapeStyle(Color.indigo))
                        .frame(width: max(8, geo.size.width * min(r, 1)))
                }
            }
        }
        .frame(height: 14)
    }
}

struct DoneRow: View {
    @EnvironmentObject var store: Store
    let entry: Entry

    private var actualColor: Color {
        if entry.kind == .call { return .blue }
        if let est = entry.estimateMin, let act = entry.actualMin {
            return act <= est ? .green : .red
        }
        return .green
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.kind == .call ? "phone.fill" : "checkmark.circle.fill")
                .foregroundStyle(entry.kind == .call ? Color.blue : Color.green)
            Text(entry.title)
            Spacer()
            if entry.kind == .task, let est = entry.estimateMin {
                Badge(text: "est \(TimeParse.format(est))", color: .gray)
            }
            if let act = entry.actualMin {
                Badge(text: TimeParse.format(act), color: actualColor)
            }
            if let c = entry.completedAt {
                Text(c.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Delete", role: .destructive) { store.delete(entry.id) }
        }
    }
}

// MARK: - Sheets

struct CompleteSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let entry: Entry
    @State private var actual = ""
    @FocusState private var focused: Bool

    private var parsed: Int? { TimeParse.minutes(from: actual) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry.title).font(.headline)
            Text("Estimated \(TimeParse.format(entry.estimateMin ?? 0)) — how long did it take?")
                .foregroundStyle(.secondary)
            TextField("e.g. 45m or 1h30", text: $actual)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { save() }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Done") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed == nil)
            }
        }
        .padding(20)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Log past work").font(.headline)
            TextField("What did you do?", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            HStack {
                TextField("Estimate (45m…)", text: $estimate)
                    .textFieldStyle(.roundedBorder)
                TextField("Actual (1h10…)", text: $actual)
                    .textFieldStyle(.roundedBorder)
            }
            DatePicker("When", selection: $date, in: ...Date.now)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
        }
        .padding(20)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Log a call").font(.headline)
            TextField("What call? (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Duration (30m, 1h…)", text: $duration)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { save() }
            DatePicker("When", selection: $date, in: ...Date.now)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(durMin == nil)
            }
        }
        .padding(20)
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
