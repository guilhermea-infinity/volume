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

        let quickAdd = QuickAddView(initialText: "review IDS creatives batch 4 30m",
                                    onAdd: { _, _ in }, onCancel: {})
            .environment(\.colorScheme, light ? .light : .dark)
            .padding(30)
            .background(light ? Color(hex: 0xE5E2D9) : Color.black.opacity(0.94))
        let qr = ImageRenderer(content: quickAdd)
        qr.scale = 2
        if let img = qr.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("quickadd.png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
    }
}
