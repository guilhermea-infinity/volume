import SwiftUI
import AppKit

/// Headless preview renderer: `Volume --render <dir>` writes PNGs of each tab
/// using the DB at $VOLUME_DB (never the real one unless you point it there).
@MainActor
enum Renderer {
    static func renderAll(to dir: String) {
        let store = Store()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for tab in AppTab.allCases {
            let content = RootView(tab: tab)
                .environmentObject(store)
                .frame(width: 1120, height: 740)
                .environment(\.colorScheme, .dark)
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
    }
}
