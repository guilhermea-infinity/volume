import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var estimate = ""
    @FocusState private var focusedField: Field?
    @State private var completing: Entry?
    @State private var showRetro = false
    @State private var showCall = false
    @State private var editing: Entry?
    @State private var expanded: Int64?
    @State private var dragID: Int64?
    @State private var dragFrom: Int?
    @State private var dragTo: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var rowStride: CGFloat = 48
    @State private var burstAt: Date?
    @State private var burstTint = Theme.accent
    @State private var burstCount = 18
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var nav = Navigation.shared
    @State private var now = Date.now
    @State private var laneWidth: CGFloat = 1000

    enum Field { case title, estimate }

    /// Below this the two lanes stop fitting side by side and stack instead.
    private var stacked: Bool { laneWidth < 760 }

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && TimeParse.minutes(from: estimate) != nil
    }

    var body: some View {
        let dayInterval = Stats.dayInterval(now)
        let doneToday = store.entries
            .filter { e in e.completedAt.map { dayInterval.contains($0) } ?? false }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let planned = store.entries
            .filter { $0.kind == .task && !$0.isDone }
            .sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
        let focusedToday = Stats.focusedMinutes(store.entries, in: dayInterval)
        let callsToday = Stats.callMinutes(store.entries, in: dayInterval)
        let tasksToday = doneToday.filter { $0.kind == .task }.count
        let openID = expanded ?? (Theme.renderNotesOpen ? planned.first?.id : nil)

        VStack(alignment: .leading, spacing: 0) {
            // Scoreboard strip
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                            color: Theme.faint, size: 14)
                    HStack(alignment: .firstTextBaseline, spacing: 26) {
                        StatBlock(label: "Focused", value: .minutes(focusedToday),
                                  color: Theme.accent)
                            .scaleEffect(pulse ? 1.16 : 1, anchor: .bottomLeading)
                            .shadow(color: Theme.accent.opacity(pulse ? 0.5 : 0), radius: 22)
                            .overlay {
                                if let at = burstAt ?? Theme.renderBurstAt {
                                    BurstView(seed: UInt64(at.timeIntervalSince1970 * 1000),
                                              tint: burstTint, start: at,
                                              count: burstCount, drift: 110)
                                        .frame(width: 520, height: 420)
                                        .allowsHitTesting(false)
                                }
                            }
                        StatBlock(label: "Tasks", value: .count(tasksToday))
                        StatBlock(label: "Calls", value: .minutes(callsToday),
                                  color: callsToday > 0 ? Theme.call : Theme.dim)
                    }
                    .onChange(of: focusedToday) { old, new in
                        guard new > old else { return }
                        let last = doneToday.first { $0.kind == .task }
                        let beatEstimate = (last?.actualMin ?? 0) <= (last?.estimateMin ?? 0)
                        celebrate(underEstimate: beatEstimate)
                    }
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

            // Lanes: side by side when there is room, stacked when there isn't.
            Group {
                if stacked {
                    MaybeScroll {
                        VStack(alignment: .leading, spacing: 18) {
                            upNextLane(planned, openID: openID, scrolls: false)
                            doneLane(doneToday, openID: openID, scrolls: false)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        upNextLane(planned, openID: openID, scrolls: true)
                        doneLane(doneToday, openID: openID, scrolls: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .animation(.spring(duration: 0.4), value: store.entries)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: LaneWidthKey.self, value: g.size.width)
                }
            )
            .onPreferenceChange(LaneWidthKey.self) { w in
                if abs(w - laneWidth) > 0.5 { laneWidth = w }
            }
            .onPreferenceChange(RowHeightKey.self) { h in
                if h > 1, abs(h + 8 - rowStride) > 0.5 { rowStride = h + 8 }
            }
        }
        .sheet(item: $completing) { CompleteSheet(entry: $0) }
        .sheet(item: $editing) { EditSheet(entry: $0) }
        .sheet(isPresented: $showRetro) { RetroSheet() }
        .sheet(isPresented: $showCall) { CallSheet() }
        .onAppear { focusedField = .title }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .onChange(of: nav.revealEntry) { _, id in
            guard let id else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { expanded = id }
            nav.revealEntry = nil
        }
    }

    @ViewBuilder
    private func upNextLane(_ planned: [Entry], openID: Int64?, scrolls: Bool) -> some View {
        Lane(title: "Up next", count: planned.count,
             empty: "Nothing planned. Add the first task above.", scrolls: scrolls) {
            ForEach(Array(planned.enumerated()), id: \.element.id) { i, e in
                let lifted = dragID == e.id
                PlannedRow(entry: e, isOpen: openID == e.id,
                           onToggle: { toggle(e.id) },
                           onEdit: { editing = e }) { completing = e }
                    .background(rowRuler(measuring: openID != e.id))
                    .offset(y: lifted ? dragOffset : shift(i))
                    .scaleEffect(lifted ? 1.02 : 1)
                    .shadow(color: .black.opacity(lifted ? 0.5 : 0),
                            radius: lifted ? 16 : 0, y: lifted ? 8 : 0)
                    .zIndex(lifted ? 2 : 0)
                    // The row under the cursor tracks it exactly; everything
                    // else springs out of the way.
                    .animation(lifted ? nil : .spring(response: 0.28, dampingFraction: 0.82),
                               value: dragTo)
                    .gesture(reorderGesture(planned, index: i, id: e.id))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .scale(scale: 0.88).combined(with: .opacity)))
            }
        }
    }

    @ViewBuilder
    private func doneLane(_ doneToday: [Entry], openID: Int64?, scrolls: Bool) -> some View {
        Lane(title: "Done today", count: doneToday.count,
             empty: "Nothing yet. Finish one and log it.", scrolls: scrolls) {
            ForEach(doneToday) { e in
                DoneRow(entry: e, isOpen: openID == e.id,
                        onToggle: { toggle(e.id) }) { editing = e }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity))
            }
        }
    }

    /// Only closed rows report their height — an open drawer would make the
    /// list think every row is note-sized.
    @ViewBuilder
    private func rowRuler(measuring: Bool) -> some View {
        if measuring {
            GeometryReader { g in
                Color.clear.preference(key: RowHeightKey.self, value: g.size.height)
            }
        }
    }

    /// How far a row steps aside to open a gap where the dragged one will land.
    private func shift(_ i: Int) -> CGFloat {
        guard dragID != nil, let from = dragFrom, let to = dragTo, from != to else { return 0 }
        if from < to, i > from, i <= to { return -rowStride }
        if from > to, i >= to, i < from { return rowStride }
        return 0
    }

    private func reorderGesture(_ planned: [Entry], index: Int, id: Int64) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragID != id {
                    dragID = id
                    dragFrom = index
                    dragTo = index
                    // Uniform heights while dragging, so the gap maths hold.
                    if expanded != nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded = nil }
                    }
                    Feedback.reorderTick()
                }
                dragOffset = value.translation.height
                let steps = Int((dragOffset / rowStride).rounded())
                let target = min(max(index + steps, 0), planned.count - 1)
                if target != dragTo {
                    dragTo = target
                    Feedback.reorderTick()
                }
            }
            .onEnded { _ in
                if let from = dragFrom, let to = dragTo, from != to {
                    var ids = planned.map(\.id)
                    ids.insert(ids.remove(at: from), at: to)
                    store.reorder(ids)
                    Feedback.dropped()
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    dragID = nil
                    dragFrom = nil
                    dragTo = nil
                    dragOffset = 0
                }
            }
    }

    /// One drawer at a time — the lane stays a list, not a pile of open boxes.
    private func toggle(_ id: Int64) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            expanded = expanded == id ? nil : id
        }
    }

    /// The reward: a click, a kick on the number, and a burst of bars off it.
    /// Beating your own estimate earns the green, bigger one.
    private func celebrate(underEstimate: Bool) {
        Feedback.completed(underEstimate: underEstimate)
        guard !reduceMotion, !Theme.isRendering else { return }
        burstTint = underEstimate ? Theme.good : Theme.accent
        burstCount = underEstimate ? 26 : 16
        burstAt = .now
        withAnimation(.spring(response: 0.24, dampingFraction: 0.42)) { pulse = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { pulse = false }
            try? await Task.sleep(for: .milliseconds(1300))
            burstAt = nil
        }
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

/// Height of one closed row, so a drag knows how far a step is.
struct RowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Width of the lane container, so Today can pick its layout.
struct LaneWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct Lane<Content: View>: View {
    let title: String
    let count: Int
    let empty: String
    /// Side by side, each lane scrolls itself. Stacked, the page scrolls instead
    /// and the lane sizes to its rows.
    var scrolls: Bool = true
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
                if scrolls { Spacer(minLength: 0) }
            } else if scrolls {
                MaybeScroll {
                    LazyVStack(spacing: 8) { content }
                }
            } else {
                LazyVStack(spacing: 8) { content }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil, alignment: .topLeading)
    }
}
