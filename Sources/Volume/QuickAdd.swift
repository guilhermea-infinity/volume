import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Global-hotkey quick capture: ⇧⌘Space from anywhere pops a floating card
/// that adds a task straight into Up next.
@MainActor
final class QuickAdd: NSObject, NSWindowDelegate {
    static let shared = QuickAdd()

    private var panel: KeyablePanel?
    private weak var store: Store?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// Set by RootView so Tab can reopen the window after it has been closed.
    static var openMainWindow: (() -> Void)?

    func configure(store: Store) {
        self.store = store
        registerHotKey()
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ -> OSStatus in
            Task { @MainActor in QuickAdd.shared.toggle() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x564F4C31), id: 1) // 'VOL1'
        let status = RegisterEventHotKey(UInt32(kVK_Space),
                                         UInt32(cmdKey | shiftKey),
                                         hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        print(status == noErr ? "hotkey registered: shift-cmd-Space" : "hotkey registration failed: \(status)")
        fflush(stdout)
    }

    func toggle() {
        if panel != nil { close() } else { show() }
    }

    func show(prefill: String = "") {
        guard let store, panel == nil else { return }
        let view = QuickAddView(
            initialText: prefill,
            onAdd: { [weak self] kind, title, minutes in
                switch kind {
                case .task: store.addPlanned(title: title, estimateMin: minutes)
                case .call: store.addCall(title: title, minutes: minutes, at: .now)
                }
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let p = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.contentView = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.onCancel = { [weak self] in self?.close() }

        // Spotlight-ish: centered on the screen the cursor is on, upper third
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.frame {
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                     y: f.minY + f.height * 0.68))
        }

        // Tab = open the full app. Intercepted in the panel's own sendEvent:
        // a non-activating panel in a background app does not reliably reach
        // NSApp-level monitors, and the field editor eats Tab for focus moves.
        p.onTab = { [weak self] in self?.openMainApp() }

        panel = p
        p.makeKeyAndOrderFront(nil)
    }

    func openMainApp() {
        close()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let existing = NSApp.windows.first {
            !($0 is KeyablePanel) && $0.styleMask.contains(.titled) && $0.canBecomeMain
        }
        if let win = existing {
            win.makeKeyAndOrderFront(nil)
        } else {
            // Window was closed — ask SwiftUI for a fresh one.
            QuickAdd.openMainWindow?()
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in self.close() }
    }
}

final class KeyablePanel: NSPanel {
    var onCancel: (() -> Void)?
    var onTab: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Every event routed to this window passes here, ahead of the responder
    /// chain and the text field's editor — so Tab is ours to claim.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 48, let onTab {   // 48 = tab
            onTab()
            return
        }
        super.sendEvent(event)
    }
}

struct QuickAddView: View {
    let onAdd: (Kind, String, Int) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(initialText: String = "", onAdd: @escaping (Kind, String, Int) -> Void, onCancel: @escaping () -> Void) {
        self.onAdd = onAdd
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    private var line: QuickAddLine { QuickAddParser.read(text) }

    var body: some View {
        let parsed = line
        HStack(spacing: 12) {
            BarsGlyph()
            if Theme.isRendering {
                Text(text.isEmpty
                     ? AttributedString("task + time")
                     : AttributedString(QuickAddSyntax.attributed(text)))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(text.isEmpty ? Theme.faint : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HighlightedField(text: $text, onSubmit: submit, onCancel: onCancel)
                    .frame(maxWidth: .infinity)
            }
            if let p = parsed.result {
                Chip(text: TimeParse.format(p.minutes),
                     color: p.kind == .call ? Theme.call : Theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 560)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
        .environment(\.colorScheme, Theme.mode)
        .onExitCommand { onCancel() }
    }

    private func submit() {
        guard let p = line.result else { return }
        onAdd(p.kind, p.title, p.minutes)
    }

    static func parse(_ raw: String) -> (kind: Kind, title: String, minutes: Int)? {
        QuickAddParser.read(raw).result
    }
}

/// What the parser makes of one line — including where it found the parts, so
/// the field can color exactly the runs it is going to act on.
struct QuickAddLine {
    var kind: Kind = .task
    var title = ""
    var minutes: Int?
    /// The "call with" that turns this into a meeting.
    var openerRange: NSRange?
    /// The duration lifted off the end.
    var durationRange: NSRange?

    var accentRanges: [NSRange] { [openerRange, durationRange].compactMap { $0 } }

    var result: (kind: Kind, title: String, minutes: Int)? {
        guard let minutes, !title.isEmpty else { return nil }
        return (kind, title, minutes)
    }
}

enum QuickAddParser {
    /// A line that opens with "call with" (or the obvious variants) is a
    /// meeting: it lands as call time, already done, instead of an estimate
    /// waiting in Up next.
    static let callOpeners = ["call with", "call w/", "meeting with", "meeting w/"]

    /// "review creatives 1h 30m" → (.task, "review creatives", 90). Tries the
    /// last two tokens as a duration first, then the last one.
    static func read(_ raw: String) -> QuickAddLine {
        var line = QuickAddLine()

        let indent = raw.prefix { $0.isWhitespace }
        let body = String(raw.dropFirst(indent.count)).lowercased()
        for opener in callOpeners where body.hasPrefix(opener) {
            line.kind = .call
            line.openerRange = NSRange(location: indent.utf16.count, length: opener.utf16.count)
            break
        }

        let words = tokens(raw)
        guard words.count >= 2 else { return line }
        for take in [2, 1] where words.count > take {
            let tail = Array(words.suffix(take))
            if take == 2, !validTwoTokenTail(tail[0].text, tail[1].text) { continue }
            guard let m = TimeParse.minutes(from: tail.map(\.text).joined(separator: " ")) else { continue }
            let title = words.dropLast(take).map(\.text).joined(separator: " ")
            if title.isEmpty { continue }
            line.title = title
            line.minutes = m
            let start = tail[0].range.location
            line.durationRange = NSRange(location: start,
                                         length: tail[take - 1].range.upperBound - start)
            break
        }
        return line
    }

    /// Words with their place in the line, so a run can be colored where it sits.
    private static func tokens(_ raw: String) -> [(text: String, range: NSRange)] {
        var out: [(String, NSRange)] = []
        var start: String.Index?
        var i = raw.startIndex
        while i < raw.endIndex {
            if raw[i].isWhitespace {
                if let s = start {
                    out.append((String(raw[s..<i]), NSRange(s..<i, in: raw)))
                    start = nil
                }
            } else if start == nil {
                start = i
            }
            i = raw.index(after: i)
        }
        if let s = start {
            out.append((String(raw[s...]), NSRange(s..<raw.endIndex, in: raw)))
        }
        return out
    }

    /// "1h" + "30m" or "2" + "hours" are one duration; "4" + "30m" is not —
    /// the 4 belongs to the title ("batch 4"), not the estimate.
    private static func validTwoTokenTail(_ a: String, _ b: String) -> Bool {
        let bIsUnitWord = !b.isEmpty && b.allSatisfy(\.isLetter)
        let aHasUnit = a.contains(where: \.isLetter)
        let bHasDigit = b.contains(where: \.isNumber)
        return bIsUnitWord || (aHasUnit && bHasDigit)
    }
}

/// One place that decides how a line looks, used by the live field and by the
/// headless renderer alike.
enum QuickAddSyntax {
    static let font = NSFont.systemFont(ofSize: 19, weight: .medium)

    static var base: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor(Theme.text)]
    }

    static func attributed(_ raw: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: raw, attributes: base)
        apply(to: s)
        return s
    }

    static func apply(to storage: NSMutableAttributedString) {
        let all = NSRange(location: 0, length: storage.length)
        storage.setAttributes(base, range: all)
        for r in QuickAddParser.read(storage.string).accentRanges where r.upperBound <= storage.length {
            storage.addAttribute(.foregroundColor, value: NSColor(Theme.accent), range: r)
        }
    }
}

/// SwiftUI's TextField paints one color at a time, so the recognised parts of
/// the line — the opener, the duration — need an AppKit field underneath.
struct HighlightedField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = QuickAddSyntax.font
        field.delegate = context.coordinator
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        // Without this the field editor flattens the attributed string back to
        // one colour the moment editing starts.
        field.allowsEditingTextAttributes = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.placeholderAttributedString = NSAttributedString(
            string: "task + time",
            attributes: [.font: QuickAddSyntax.font, .foregroundColor: NSColor(Theme.faint)])
        field.attributedStringValue = QuickAddSyntax.attributed(text)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.attributedStringValue = QuickAddSyntax.attributed(text)
        }
        if !context.coordinator.tookFocus {
            context.coordinator.tookFocus = true
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                // Taking first responder selects the whole line; put the caret
                // at the end so you carry on typing instead of overwriting.
                let end = (field.stringValue as NSString).length
                field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
                context.coordinator.recolor(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HighlightedField
        var tookFocus = false

        init(_ parent: HighlightedField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
            recolor(field)
        }

        /// Recolors the field editor in place: replacing the whole string would
        /// drop the caret to the end on every keystroke.
        func recolor(_ field: NSTextField) {
            guard let editor = field.currentEditor() as? NSTextView,
                  let storage = editor.textStorage else { return }
            let selection = editor.selectedRange()
            editor.insertionPointColor = NSColor(Theme.accent)
            QuickAddSyntax.apply(to: storage)
            editor.typingAttributes = QuickAddSyntax.base
            editor.setSelectedRange(selection)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
