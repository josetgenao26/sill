#!/usr/bin/env swift

// Builds Resources/Sill.icns from the mark in Resources/icon-mark.svg.
//
// Run after changing the artwork:
//     swift scripts/make-icon.swift
//
// The mark ships as an SVG using `currentColor`, which is right for the web and useless
// for a rasteriser: NSImage would draw it in whatever default it picks. The colour is
// substituted here instead of keeping a second, divergent copy of the artwork.

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let markURL = root.appendingPathComponent("Resources/icon-mark.svg")
let iconsetURL = root.appendingPathComponent("build/Sill.iconset")
let icnsURL = root.appendingPathComponent("Resources/Sill.icns")

let background = NSColor(red: 0x16 / 255, green: 0x15 / 255, blue: 0x0F / 255, alpha: 1)
let foreground = "#F6DCAE"

guard var svg = try? String(contentsOf: markURL, encoding: .utf8) else {
    print("error: cannot read \(markURL.path)")
    exit(1)
}
svg = svg.replacingOccurrences(of: "currentColor", with: foreground)

let coloured = FileManager.default.temporaryDirectory.appendingPathComponent("sill-mark-coloured.svg")
try svg.write(to: coloured, atomically: true, encoding: .utf8)

guard let mark = NSImage(contentsOf: coloured) else {
    print("error: NSImage could not rasterise the SVG")
    exit(1)
}

/// Draws one icon at `size` points.
///
/// Apple's icons do not fill their canvas: the rounded body sits inside a transparent
/// margin, and the grid is what makes an icon look the same size as its neighbours in the
/// Dock. The proportions here follow that grid rather than filling edge to edge.
func render(size: CGFloat) -> Data? {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.10
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    background.setFill()
    NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237).fill()

    // The mark occupies just over half the body, which keeps it readable once the Dock
    // scales the whole thing down.
    let markSize = body.width * 0.56
    mark.draw(
        in: NSRect(
            x: body.midX - markSize / 2,
            y: body.midY - markSize / 2,
            width: markSize,
            height: markSize
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (base, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let suffix = scale == 2 ? "@2x" : ""
    guard let data = render(size: CGFloat(base * scale)) else {
        print("error: could not render \(base)@\(scale)x")
        exit(1)
    }
    try data.write(to: iconsetURL.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    print("error: iconutil failed")
    exit(1)
}
print("wrote \(icnsURL.path)")
