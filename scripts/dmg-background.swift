import AppKit

// Renders the DMG window background (600x400 points): a light, elegant gradient
// so the (system-colored, dark) Finder icon labels stay readable in both Light
// and Dark Mode. Title + instruction are dark; a coral arrow echoes the app
// icon. Icon slots are left empty (Finder draws the real icons).
let W = 600, H = 400
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// Light background gradient (warm white -> soft cool grey).
let bg = NSGradient(colors: [col(250, 249, 247), col(233, 234, 240)])!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// Very soft warm glow behind the arrow (subtle brand warmth).
let glow = NSGradient(colors: [col(240, 150, 90, 0.14), col(240, 150, 90, 0.0)])!
glow.draw(in: NSRect(x: 300 - 210, y: 210 - 210, width: 420, height: 420), relativeCenterPosition: .zero)

// Icon-slot coordinates (Finder positions, y from top): app {150,190}, apps {450,190}.
// In this bottom-up canvas, y = H - 190 = 210.
let slotY: CGFloat = 210

// Coral arrow from the app slot toward the Applications slot.
let arrow = NSBezierPath()
arrow.lineWidth = 7
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
let ax0: CGFloat = 238, ax1: CGFloat = 362
arrow.move(to: NSPoint(x: ax0, y: slotY))
arrow.line(to: NSPoint(x: ax1, y: slotY))
arrow.move(to: NSPoint(x: ax1 - 18, y: slotY + 14))
arrow.line(to: NSPoint(x: ax1, y: slotY))
arrow.line(to: NSPoint(x: ax1 - 18, y: slotY - 14))
col(232, 132, 82).setStroke()
arrow.stroke()

// Text helper (centered).
func drawText(_ s: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: p,
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(in: NSRect(x: 0, y: y, width: CGFloat(W), height: sz.height + 4))
}

// Title near the top (dark indigo).
drawText("ClaudeLights", y: 332, size: 30, weight: .bold, color: col(38, 40, 60))
// Instruction near the bottom (medium grey).
drawText("Zum Installieren in den „Programme\"-Ordner ziehen", y: 46, size: 15, weight: .regular,
         color: col(108, 112, 130))

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments[1]
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
