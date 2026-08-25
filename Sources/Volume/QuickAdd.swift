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

    func show() {
        guard let store, panel == nil else { return }
        let view = QuickAddView(
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
    @FocusState private var focused: Bool

    init(initialText: String = "", onAdd: @escaping (Kind, String, Int) -> Void, onCancel: @escaping () -> Void) {
        self.onAdd = onAdd
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    private var parsed: (kind: Kind, title: String, minutes: Int)? { Self.parse(text) }

    var body: some View {
        HStack(spacing: 12) {
            BarsGlyph()
            if Theme.isRendering {
                Text(text.isEmpty ? "task + time" : text)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("task + time", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { submit() }
            }
            if let p = parsed {
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onExitCommand { onCancel() }
    }

    private func submit() {
        guard let p = parsed else { return }
        onAdd(p.kind, p.title, p.minutes)
    }

    /// A line that opens with "call with" (or the obvious variants) is a
    /// meeting: it lands as call time, already done, instead of an estimate
    /// waiting in Up next.
    private static let callOpeners = ["call with", "call w/", "meeting with", "meeting w/"]

    /// "review creatives 1h 30m" → (.task, "review creatives", 90). Tries the
    /// last two tokens as a duration first, then the last one.
    static func parse(_ raw: String) -> (kind: Kind, title: String, minutes: Int)? {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2 else { return nil }
        let opener = tokens.joined(separator: " ").lowercased()
        let kind: Kind = callOpeners.contains(where: opener.hasPrefix) ? .call : .task
        for take in [2, 1] where tokens.count > take {
            let tail = Array(tokens.suffix(take))
            if take == 2, !validTwoTokenTail(tail[0], tail[1]) { continue }
            if let m = TimeParse.minutes(from: tail.joined(separator: " ")) {
                let title = tokens.dropLast(take).joined(separator: " ")
                if !title.isEmpty { return (kind, title, m) }
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
