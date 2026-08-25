import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var estimate = ""
    @FocusState private var focusTitle: Bool
    @State private var completing: Entry?
    @State private var showRetro = false
    @State private var showCall = false
    @State private var now = Date.now

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && TimeParse.minutes(from: estimate) != nil
    }

    var body: some View {
        let dayInterval = Stats.dayInterval(now)
        let doneToday = store.entries
            .filter { e in e.completedAt.map { dayInterval.contains($0) } ?? false }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let planned = store.entries.filter { $0.kind == .task && !$0.isDone }
        let focusedToday = Stats.focusedMinutes(store.entries, in: dayInterval)
        let callsToday = Stats.callMinutes(store.entries, in: dayInterval)
        let tasksToday = doneToday.filter { $0.kind == .task }.count

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.title2.bold())
                    Text("Focused \(TimeParse.format(focusedToday)) · \(tasksToday) tasks · Calls \(TimeParse.format(callsToday))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Log past work") { showRetro = true }
                Button("Log call") { showCall = true }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                TextField("What are you going to do?", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusTitle)
                    .onSubmit { add() }
                TextField("Estimate (45m, 1h30…)", text: $estimate)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                    .onSubmit { add() }
                Button("Add") { add() }
                    .disabled(!canAdd)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            List {
                Section("Planned (\(planned.count))") {
                    if planned.isEmpty {
                        Text("Nothing planned — add something above.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(planned) { e in
                        PlannedRow(entry: e) { completing = e }
                    }
                }
                Section("Done today (\(doneToday.count))") {
                    if doneToday.isEmpty {
                        Text("Nothing yet — go get one.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(doneToday) { e in
                        DoneRow(entry: e)
                    }
                }
            }
        }
        .sheet(item: $completing) { CompleteSheet(entry: $0) }
        .sheet(isPresented: $showRetro) { RetroSheet() }
        .sheet(isPresented: $showCall) { CallSheet() }
        .onAppear { focusTitle = true }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func add() {
        guard canAdd, let est = TimeParse.minutes(from: estimate) else { return }
        store.addPlanned(title: title.trimmingCharacters(in: .whitespaces), estimateMin: est)
        title = ""
        estimate = ""
        focusTitle = true
    }
}

struct PlannedRow: View {
    @EnvironmentObject var store: Store
    let entry: Entry
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
            Text(entry.title)
            Spacer()
            Badge(text: "est \(TimeParse.format(entry.estimateMin ?? 0))", color: .gray)
            Button("Done") { onDone() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Delete", role: .destructive) { store.delete(entry.id) }
        }
    }
}
