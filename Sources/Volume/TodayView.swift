import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var estimate = ""
    @FocusState private var focusedField: Field?
    @State private var completing: Entry?
    @State private var showRetro = false
    @State private var showCall = false
    @State private var now = Date.now

    enum Field { case title, estimate }

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

        VStack(alignment: .leading, spacing: 0) {
            // Scoreboard strip
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                            color: Theme.faint, size: 14)
                    HStack(alignment: .firstTextBaseline, spacing: 26) {
                        StatBlock(label: "Focused", value: TimeParse.format(focusedToday),
                                  color: Theme.accent, size: 40)
                        StatBlock(label: "Tasks", value: "\(tasksToday)")
                        StatBlock(label: "Calls", value: TimeParse.format(callsToday),
                                  color: callsToday > 0 ? Theme.call : Theme.dim)
                    }
                    .animation(.spring(duration: 0.5), value: focusedToday)
                }
                Spacer()
                HStack(spacing: 8) {
                    GhostButton(title: "Log past work") { showRetro = true }
                    GhostButton(title: "Log call") { showCall = true }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)

            // Command bar
            HStack(spacing: 10) {
                if Theme.isRendering {
                    Text("What are you going to do?")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Theme.faint)
                        .darkField()
                    Text("est — 45m, 1h30")
                        .foregroundStyle(Theme.faint)
                        .darkField()
                        .frame(width: 150)
                } else {
                    TextField("What are you going to do?", text: $title)
                        .darkField(focused: focusedField == .title)
                        .focused($focusedField, equals: .title)
                        .onSubmit { add() }
                    TextField("est — 45m, 1h30", text: $estimate)
                        .darkField(focused: focusedField == .estimate)
                        .focused($focusedField, equals: .estimate)
                        .frame(width: 150)
                        .onSubmit { add() }
                }
                AccentButton(title: "Add", disabled: !canAdd) { add() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Two lanes
            HStack(alignment: .top, spacing: 14) {
                Lane(title: "Up next", count: planned.count,
                     empty: "Nothing planned. Add the first task above.") {
                    ForEach(planned) { e in
                        PlannedRow(entry: e) { completing = e }
                    }
                }
                Lane(title: "Done today", count: doneToday.count,
                     empty: "Nothing yet. Finish one and log it.") {
                    ForEach(doneToday) { e in
                        DoneRow(entry: e)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .animation(.spring(duration: 0.4), value: store.entries)
        }
        .sheet(item: $completing) { CompleteSheet(entry: $0) }
        .sheet(isPresented: $showRetro) { RetroSheet() }
        .sheet(isPresented: $showCall) { CallSheet() }
        .onAppear { focusedField = .title }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func add() {
        guard canAdd, let est = TimeParse.minutes(from: estimate) else { return }
        withAnimation(.spring(duration: 0.4)) {
            store.addPlanned(title: title.trimmingCharacters(in: .whitespaces), estimateMin: est)
        }
        title = ""
        estimate = ""
        focusedField = .title
    }
}

struct Lane<Content: View>: View {
    let title: String
    let count: Int
    let empty: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Eyebrow(text: title)
                Text("\(count)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faint)
            }
            if count == 0 {
                Text(empty)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .padding(.top, 2)
                Spacer(minLength: 0)
            } else {
                MaybeScroll {
                    LazyVStack(spacing: 8) { content }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
