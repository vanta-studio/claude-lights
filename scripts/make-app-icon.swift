// Renders the ClaudeLights app icon (menu-bar pill motif, "working" state)
// and writes every size of the AppIcon icon set.
//
//   swift scripts/make-app-icon.swift
//
// Spec: docs/superpowers/specs/2026-07-04-app-icon-pill-design.md
import AppKit

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath().deletingLastPathComponent()
let iconsetDir = scriptDir
    .deletingLastPathComponent()
    .appendingPathComponent("ClaudeLights/Assets.xcassets/AppIcon.appiconset")

let S: CGFloat = 1024
let green = NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
let yellow = NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.04, alpha: 1)
let red = NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
let bgTop = NSColor(calibratedRed: 0.135, green: 0.145, blue: 0.20, alpha: 1)
let bgBottom = NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.10, alpha: 1)
let activeIndex = 1 // the yellow "working" light carries the bloom

func drawMaster() -> NSImage {
    let img = NSImage(size: NSSize(width: S, height: S))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError() }

    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: iconRect, xRadius: 185, yRadius: 185)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 34,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    bgBottom.setFill()
    squircle.fill()
    ctx.restoreGState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [bgTop, bgBottom])!.draw(in: iconRect, angle: -90)

    // faint light source behind the pill
    ctx.saveGState()
    let center = CGPoint(x: S / 2, y: S / 2)
    let glow = [NSColor.white.withAlphaComponent(0.10).cgColor,
                NSColor.white.withAlphaComponent(0).cgColor] as CFArray
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glow, locations: [0, 1]) {
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: 430, options: [])
    }
    ctx.restoreGState()

    // glass pill
    let pillRect = CGRect(x: (S - 620) / 2, y: (S - 250) / 2, width: 620, height: 250)
    let pill = NSBezierPath(roundedRect: pillRect, xRadius: 125, yRadius: 125)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 48,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.white.withAlphaComponent(0.05).setFill()
    pill.fill()
    ctx.restoreGState()

    NSGraphicsContext.saveGraphicsState()
    pill.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.14),
                        NSColor.white.withAlphaComponent(0.05)])!.draw(in: pillRect, angle: -90)
    let highlight = NSBezierPath(roundedRect: CGRect(x: pillRect.minX + 22, y: pillRect.maxY - 74,
                                                     width: pillRect.width - 44, height: 58),
                                 xRadius: 29, yRadius: 29)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28),
                        NSColor.white.withAlphaComponent(0.02)])!.draw(in: highlight, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.22).setStroke()
    pill.lineWidth = 4
    pill.stroke()

    // status lights
    for (i, c) in [green, yellow, red].enumerated() {
        let cx = S / 2 + CGFloat(i - 1) * 178
        let active = i == activeIndex
        let dotRect = CGRect(x: cx - 62, y: S / 2 - 62, width: 124, height: 124)

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: active ? 90 : 30,
                      color: c.withAlphaComponent(active ? 0.85 : 0.25).cgColor)
        (active ? c : c.withAlphaComponent(0.55)).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        ctx.restoreGState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: dotRect).addClip()
        let top = c.blended(withFraction: active ? 0.55 : 0.30, of: .white) ?? c
        let bottom = c.blended(withFraction: 0.25, of: .black) ?? c
        NSGradient(colors: [top, active ? c : c.withAlphaComponent(0.7), bottom],
                   atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)?
            .draw(in: dotRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    img.unlockFocus()
    return img
}

func writePNG(_ master: NSImage, size: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError() }
    try! png.write(to: url)
    print("wrote \(url.lastPathComponent) (\(size)x\(size))")
}

let master = drawMaster()
for size in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(master, size: size, to: iconsetDir.appendingPathComponent("icon_\(size).png"))
}
