import SwiftUI
import AppKit

/// Headless preview renderer: `Volume --render <dir>` writes PNGs of each tab
/// using the DB at $VOLUME_DB (never the real one unless you point it there).
@MainActor
enum Renderer {
    static func renderAll(to dir: String) {
        let light = ProcessInfo.processInfo.environment["VOLUME_RENDER_APPEARANCE"] == "light"
        Theme.mode = light ? .light : .dark
        let store = Store()
        store.tagPendingSync()
        let env = ProcessInfo.processInfo.environment
        let w = Double(env["VOLUME_RENDER_W"] ?? "") ?? 1120
        let h = Double(env["VOLUME_RENDER_H"] ?? "") ?? 740
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for tab in AppTab.allCases {
            let content = RootView(tab: tab)
                .environmentObject(store)
                .frame(width: w, height: h)
                .environment(\.colorScheme, light ? .light : .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let img = renderer.nsImage,
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                print("render failed: \(tab.rawValue)")
                continue
            }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(tab.rawValue.lowercased()).png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }

        let menuBar = MenuBarPanel()
            .environmentObject(store)
            .environment(\.colorScheme, light ? .light : .dark)
            .padding(24)
            .background(light ? Color(hex: 0xE5E2D9) : Color.black.opacity(0.94))
        let mr = ImageRenderer(content: menuBar)
        mr.scale = 2
        if let img = mr.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("menubar.png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }

        // The search overlay, mid-query.
        Theme.renderSearchQuery = "enigmic"
        Navigation.shared.searchOpen = true
        let searching = RootView(tab: .today)
            .environmentObject(store)
            .frame(width: w, height: h)
            .environment(\.colorScheme, light ? .light : .dark)
        let searchRenderer = ImageRenderer(content: searching)
        searchRenderer.scale = 2
        if let img = searchRenderer.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("search.png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
        Theme.renderSearchQuery = nil
        Navigation.shared.searchOpen = false

        // Today with a notes drawer open.
        Theme.renderNotesOpen = true
        let noting = RootView(tab: .today)
            .environmentObject(store)
            .frame(width: w, height: h)
            .environment(\.colorScheme, light ? .light : .dark)
        let nr = ImageRenderer(content: noting)
        nr.scale = 2
        if let img = nr.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("today-notes.png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
        Theme.renderNotesOpen = false

        // Today, caught mid-celebration — checks the burst sits over the
        // number without moving anything.
        Theme.renderBurstAt = Date.now.addingTimeInterval(-0.28)
        let celebrating = RootView(tab: .today)
            .environmentObject(store)
            .frame(width: w, height: h)
            .environment(\.colorScheme, light ? .light : .dark)
        let cr = ImageRenderer(content: celebrating)
        cr.scale = 2
        if let img = cr.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("today-burst.png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
        Theme.renderBurstAt = nil

        // Filmstrip of the completion burst — the only way to review an
        // animation from a still.
        let strip = HStack(spacing: 1) {
            ForEach([0.06, 0.16, 0.3, 0.5, 0.75, 1.0], id: \.self) { t in
                BurstView(seed: 4242, tint: Theme.good,
                          start: Date.now.addingTimeInterval(-t), count: 26)
                    .frame(width: 300, height: 280)
                    .background(Theme.bg)
            }
        }
        let sr = ImageRenderer(content: strip)
        sr.scale = 2
        if let img = sr.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("burst.png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }

        for (name, line) in [("quickadd", "review IDS creatives batch 4 30m"),
                             ("quickadd-call", "call with Rafaela 30m")] {
            let quickAdd = QuickAddView(initialText: line, onAdd: { _, _, _ in }, onCancel: {})
                .environment(\.colorScheme, light ? .light : .dark)
                .padding(30)
                .background(light ? Color(hex: 0xE5E2D9) : Color.black.opacity(0.94))
            let qr = ImageRenderer(content: quickAdd)
            qr.scale = 2
            if let img = qr.nsImage, let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
                try? png.write(to: url)
                print("wrote \(url.path)")
            }
        }
    }
}
