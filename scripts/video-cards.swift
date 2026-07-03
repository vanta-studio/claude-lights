import AppKit

// Renders the title/end cards and the lower-third text overlays for the hero
// video (run via `xcrun swift`). The overlays are transparent PNGs composited
// by ffmpeg's overlay filter — the Homebrew ffmpeg ships without drawtext,
// and native SF typography looks better anyway.
// Usage: swift video-cards.swift <output-dir>

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let size = NSSize(width: 1920, height: 1080)
let background = NSColor(calibratedRed: 0.106, green: 0.106, blue: 0.118, alpha: 1)

func render(_ name: String, transparent: Bool = false, _ draw: (NSRect) -> Void) {
    let image = NSImage(size: size)
    image.lockFocus()
    if !transparent {
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
    }
    draw(NSRect(origin: .zero, size: size))
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { fatalError("render failed") }
    try! png.write(to: outputDir.appendingPathComponent(name))
    print("wrote \(name)")
}

/// A rounded dark pill with centered white text, sitting in the lower third.
func renderLowerThird(_ name: String, _ text: String) {
    render(name, transparent: true) { _ in
        let font = NSFont.systemFont(ofSize: 46, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let paddingX: CGFloat = 44
        let paddingY: CGFloat = 24
        let pill = NSRect(
            x: (size.width - textSize.width) / 2 - paddingX,
            y: 96,
            width: textSize.width + paddingX * 2,
            height: textSize.height + paddingY * 2
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        string.draw(at: NSPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2))
    }
}

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let string = NSAttributedString(string: text, attributes: attributes)
    let textSize = string.size()
    string.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: y))
}

func drawTrafficDots(y: CGFloat, diameter: CGFloat, spacing: CGFloat) {
    let colors: [NSColor] = [.systemGreen, .systemYellow, .systemRed]
    let total = CGFloat(colors.count) * diameter + CGFloat(colors.count - 1) * spacing
    var x = (size.width - total) / 2
    for color in colors {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: diameter, height: diameter)).fill()
        x += diameter + spacing
    }
}

render("card-title.png") { _ in
    drawTrafficDots(y: 660, diameter: 46, spacing: 34)
    drawCentered("ClaudeLights",
                 y: 500,
                 font: .systemFont(ofSize: 128, weight: .bold),
                 color: .white)
    drawCentered("A traffic light for your Claude Code sessions",
                 y: 410,
                 font: .systemFont(ofSize: 46, weight: .regular),
                 color: NSColor.white.withAlphaComponent(0.72))
}

renderLowerThird("ov-parallel.png", "Run Claude Code sessions in parallel — and stop babysitting them")
renderLowerThird("ov-red.png", "The moment Claude needs you, the light turns red")
renderLowerThird("ov-answer.png", "Answer — everyone gets back to work")
renderLowerThird("ov-features.png", "Named sessions · live work timers · usage stats")

render("card-end.png") { _ in
    drawTrafficDots(y: 700, diameter: 38, spacing: 28)
    drawCentered("ClaudeLights",
                 y: 560,
                 font: .systemFont(ofSize: 104, weight: .bold),
                 color: .white)
    drawCentered("Native macOS · No Electron · No telemetry",
                 y: 480,
                 font: .systemFont(ofSize: 40, weight: .regular),
                 color: NSColor.white.withAlphaComponent(0.72))
    drawCentered("github.com/vanta-studio/claude-lights",
                 y: 380,
                 font: .monospacedSystemFont(ofSize: 44, weight: .medium),
                 color: NSColor.systemYellow)
    drawCentered("macOS 13+  ·  Free & open source",
                 y: 300,
                 font: .systemFont(ofSize: 32, weight: .regular),
                 color: NSColor.white.withAlphaComponent(0.55))
}
