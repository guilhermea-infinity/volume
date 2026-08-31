import SwiftUI
import AppKit

/// Pick a window, see what comes out, take it away. Copy is the primary action
/// — the usual destination is a chat box, not a folder.
struct ExportSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var range: ExportRange = .last7
    @State private var format: ExportFormat = .markdown
    @State private var from = Date.now
    @State private var to = Date.now
    @State private var copied = false

    private var text: String {
        Export.build(store.entries, from: from, to: to, format: format, includeUpNext: true)
    }

    private var loggedCount: Int {
        let window = Export.interval(from: from, to: to)
        return store.entries.filter { e in e.completedAt.map { window.contains($0) } ?? false }.count
    }

    var body: some View {
        let body = text
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Eyebrow(text: "Export history", color: Theme.accent)
                Spacer()
                GhostButton(title: "Done") { dismiss() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Period", color: Theme.faint, size: 13)
                HStack(spacing: 6) {
                    ForEach(ExportRange.allCases, id: \.self) { r in
                        SegPill(label: r.rawValue, selected: range == r) { pick(r) }
                    }
                }
                HStack(spacing: 12) {
                    if Theme.isRendering {
                        Text("From \(from.formatted(date: .abbreviated, time: .omitted)) to \(to.formatted(date: .abbreviated, time: .omitted))")
                    } else {
                        DatePicker("From", selection: $from, in: ...Date.now, displayedComponents: .date)
                        DatePicker("to", selection: $to, in: ...Date.now, displayedComponents: .date)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
            }

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Format", color: Theme.faint, size: 13)
                HStack(spacing: 6) {
                    ForEach(ExportFormat.allCases, id: \.self) { f in
                        SegPill(label: f.rawValue, selected: format == f) { format = f }
                    }
                    Spacer()
                    Text("\(loggedCount) entries · \(sizeLabel(body))")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                }
            }

            MaybeScroll {
                Text(body.isEmpty ? "Nothing logged in this period." : body)
                    .font(Theme.mono(10.5, .regular))
                    .foregroundStyle(Theme.dim)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .frame(height: 220)
            .background(Theme.track, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))

            HStack {
                Text("Markdown reads best if you're handing it to a model.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faint)
                Spacer()
                GhostButton(title: "Save…") { save(body) }
                AccentButton(title: copied ? "Copied" : "Copy", disabled: body.isEmpty) { copy(body) }
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(Theme.bg)
        .tint(Theme.accent)
        .onAppear { pick(range) }
    }

    private func pick(_ r: ExportRange) {
        range = r
        let earliest = store.entries.compactMap(\.completedAt).min()
        let (start, end) = r.days(now: .now, earliest: earliest)
        from = start
        to = end
    }

    private func copy(_ body: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        Feedback.dropped()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.25)) { copied = false }
        }
    }

    private func save(_ body: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Export.filename(from: from, to: to, format: format)
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func sizeLabel(_ body: String) -> String {
        let bytes = body.utf8.count
        return bytes < 1024 ? "\(bytes) B" : String(format: "%.1f KB", Double(bytes) / 1024)
    }
}
