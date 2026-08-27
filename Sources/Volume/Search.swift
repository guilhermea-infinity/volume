import SwiftUI

/// ⌘F. Everything you've ever written down, filtered as you type — planned
/// work first, then the finished, newest back.
struct SearchOverlay: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var nav = Navigation.shared
    @State private var query = Theme.renderSearchQuery ?? ""
    @FocusState private var focused: Bool
    @State private var resultsHeight: CGFloat = 0

    private var hits: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let matches = store.entries.filter { Search.matches($0, q) }
        let planned = matches.filter { !$0.isDone }
            .sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
        let done = matches.filter(\.isDone)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return Array((planned + done).prefix(50))
    }

    var body: some View {
        let results = hits
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                if Theme.isRendering {
                    Text(query.isEmpty ? "Find a task" : query)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(query.isEmpty ? Theme.faint : Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Find a task", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .focused($focused)
                        .onSubmit { if let first = results.first { nav.go(to: first) } }
                }
                if !query.isEmpty {
                    Text("\(results.count)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if !results.isEmpty {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                MaybeScroll {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { e in
                            SearchRow(entry: e, query: query) { nav.go(to: e) }
                        }
                    }
                    .padding(6)
                    // Measured inside the scroll view, where nothing is
                    // clamping it, so the panel is exactly as tall as its hits.
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ResultsHeightKey.self, value: g.size.height)
                    })
                }
                .frame(height: min(max(resultsHeight, 44), 340))
                .onPreferenceChange(ResultsHeightKey.self) { h in
                    if abs(h - resultsHeight) > 0.5 { resultsHeight = h }
                }
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Text("Nothing matches.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 560)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
        .onAppear { focused = true }
        .onExitCommand { nav.searchOpen = false }
    }
}

private struct ResultsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SearchRow: View {
    let entry: Entry
    let query: String
    let onOpen: () -> Void
    @State private var hover = false

    private var mark: (String, Color) {
        if entry.kind == .call { return ("phone.fill", Theme.call) }
        if !entry.isDone { return (entry.priority ? "star.fill" : "circle", entry.priority ? Theme.accent : Theme.faint) }
        return ("checkmark", Theme.good)
    }

    private var trailing: String {
        guard let done = entry.completedAt else { return "Up next" }
        if Stats.calendar.isDateInToday(done) {
            return done.formatted(date: .omitted, time: .shortened)
        }
        return done.formatted(.dateTime.day().month(.abbreviated))
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: mark.0)
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(mark.1)
                    .frame(width: 14)
                Text(Search.highlighted(entry.title, query))
                    .font(.system(size: 13))
                    .foregroundStyle(entry.isDone ? Theme.dim : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 10)
                if let minutes = entry.actualMin ?? entry.estimateMin {
                    Chip(text: TimeParse.format(minutes),
                         color: entry.isDone ? Theme.ghost : Theme.ghost)
                }
                Text(trailing.uppercased())
                    .font(Theme.label(12))
                    .tracking(1.2)
                    .foregroundStyle(Theme.faint)
                    .frame(width: 74, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(hover ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

enum Search {
    static func matches(_ entry: Entry, _ query: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if entry.title.range(of: query, options: options) != nil { return true }
        if let notes = entry.notes, notes.range(of: query, options: options) != nil { return true }
        return false
    }

    /// The part you typed, in the accent — the same trick the quick-add field
    /// uses to show you what it recognised.
    static func highlighted(_ text: String, _ query: String) -> AttributedString {
        var out = AttributedString(text)
        out.foregroundColor = nil
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return out }
        var search = out.startIndex..<out.endIndex
        while let found = out[search].range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            out[found].foregroundColor = Theme.accent
            guard found.upperBound < out.endIndex else { break }
            search = found.upperBound..<out.endIndex
        }
        return out
    }
}
