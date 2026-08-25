import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Global-hotkey quick capture: ⌥⌘V from anywhere pops a floating card
/// that adds a task straight into Up next.
@MainActor
final class QuickAdd: NSObject, NSWindowDelegate {
    static let shared = QuickAdd()

    private var panel: KeyablePanel?
    private weak var store: Store?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

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
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V),
                                         UInt32(cmdKey | optionKey),
                                         hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        print(status == noErr ? "hotkey registered: opt-cmd-V" : "hotkey registration failed: \(status)")
        fflush(stdout)
    }

    func toggle() {
        if panel != nil { close() } else { show() }
    }

    func show() {
        guard let store, panel == nil else { return }
        let view = QuickAddView(
            onAdd: { [weak self] title, est in
                store.addPlanned(title: title, estimateMin: est)
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

        panel = p
        p.makeKeyAndOrderFront(nil)
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
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

struct QuickAddView: View {
    let onAdd: (String, Int) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(initialText: String = "", onAdd: @escaping (String, Int) -> Void, onCancel: @escaping () -> Void) {
        self.onAdd = onAdd
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    private var parsed: (title: String, est: Int)? { Self.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BarsGlyph()
                Eyebrow(text: "Quick add — up next", color: Theme.faint, size: 13)
                Spacer()
                Text("⌥⌘V")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(Theme.faint)
            }
            if Theme.isRendering {
                Text(text.isEmpty ? "task + its time" : text)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.text)
            } else {
                TextField("task + its time  ·  review creatives 30m", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { submit() }
            }
            HStack(spacing: 8) {
                if let p = parsed {
                    Chip(text: "est \(TimeParse.format(p.est))", color: Theme.accent)
                    Text(p.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                    Spacer()
                    Text("↩ add")
                        .font(Theme.mono(10, .medium))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("End with the estimate — 30m, 1h30, 1:30…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faint)
                    Spacer()
                    Text("esc close")
                        .font(Theme.mono(10, .medium))
                        .foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
        .environment(\.colorScheme, .dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onExitCommand { onCancel() }
    }

    private func submit() {
        guard let p = parsed else { return }
        onAdd(p.title, p.est)
    }

    /// "review creatives 1h 30m" → ("review creatives", 90). Tries the last
    /// two tokens as a duration first, then the last one.
    static func parse(_ raw: String) -> (title: String, est: Int)? {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2 else { return nil }
        for take in [2, 1] where tokens.count > take {
            let tail = Array(tokens.suffix(take))
            if take == 2, !validTwoTokenTail(tail[0], tail[1]) { continue }
            if let m = TimeParse.minutes(from: tail.joined(separator: " ")) {
                let title = tokens.dropLast(take).joined(separator: " ")
                if !title.isEmpty { return (title, m) }
            }
        }
        return nil
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
