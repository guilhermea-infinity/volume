// Renders the Volume app icon (gradient squircle + three rising bars) as PNGs.
// Usage: swift scripts/make-icon.swift <output-iconset-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.185, yRadius: s * 0.185)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.075, green: 0.086, blue: 0.11, alpha: 1),
        NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.165, alpha: 1),
    ])!.draw(in: bg, angle: 90)

    let barW = rect.width * 0.155
    let gap = rect.width * 0.085
    let bars: [(CGFloat, NSColor)] = [
        (0.30, NSColor(calibratedRed: 0.54, green: 0.58, blue: 0.65, alpha: 1)),
        (0.48, NSColor(calibratedRed: 0.54, green: 0.58, blue: 0.65, alpha: 1)),
        (0.72, NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.10, alpha: 1)),
    ]
    let totalW = barW * 3 + gap * 2
    var x = rect.midX - totalW / 2
    for (h, color) in bars {
        color.setFill()
        let bar = NSRect(x: x, y: rect.minY + rect.height * 0.16,
                         width: barW, height: rect.height * h)
        NSBezierPath(roundedRect: bar, xRadius: barW * 0.3, yRadius: barW * 0.3).fill()
        x += barW + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let files: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
var cache: [Int: Data] = [:]
for (name, px) in files {
    let data = cache[px] ?? render(px: px)
    cache[px] = data
    try! data.write(to: outDir.appendingPathComponent(name))
}
print("iconset written")
