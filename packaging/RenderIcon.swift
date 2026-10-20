import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: render-icon AppIcon-1024.png icon.iconset\n", stderr)
    exit(2)
}

let pngURL = URL(fileURLWithPath: args[1])
let iconset = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

struct Seed {
    var state: UInt64 = 0xA11CE
    mutating func unit() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(UInt64(1) << 31)
    }
    mutating func signed() -> CGFloat { unit() * 2 - 1 }
}

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.clear(canvas)
    ctx.saveGState()
    let radius = size * 0.2237
    let mask = CGPath(roundedRect: canvas, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(mask)
    ctx.clip()
    ctx.setFillColor(CGColor(srgbRed: 0xE8 / 255, green: 0xE5 / 255, blue: 0xE0 / 255, alpha: 1))
    ctx.fill(canvas)
    scribble(in: ctx, size: size)
    wordmark(size: size)
    ctx.restoreGState()
    return image
}

func scribble(in ctx: CGContext, size: CGFloat) {
    let count = 6
    for index in 0..<count {
        let strength = 0.34 + 0.66 * (CGFloat(index) / CGFloat(count - 1))
        let width = size * (0.062 + 0.016 * CGFloat(index % 3) / 2)
        let radius = width / 10
        let points = spine(index: index, count: count, size: size)
        var rng = Seed(state: 0xD0B41 &+ UInt64(index) &* 97)
        let blue = index >= 4
            ? CGColor(srgbRed: 0.03, green: 0.16, blue: 0.62, alpha: 1)
            : CGColor(srgbRed: 0x0A / 255, green: 0x3F / 255, blue: 0xD4 / 255, alpha: 1)
        ctx.setFillColor(blue)
        var previous = points[0]
        for point in points.dropFirst() {
            let dx = point.x - previous.x
            let dy = point.y - previous.y
            let length = max(1, hypot(dx, dy))
            let steps = Int(length / max(radius * 0.72, 0.8))
            for step in 0...steps {
                let u = CGFloat(step) / CGFloat(max(steps, 1))
                let x = previous.x + dx * u
                let y = previous.y + dy * u
                let nx = -dy / length
                let ny = dx / length
                for _ in 0..<7 {
                    let lateral = rng.signed() * width * 0.5
                    let along = rng.signed() * radius
                    let edge = min(1.4, abs(lateral) / (width * 0.5))
                    let keep: CGFloat
                    if edge > 1.05 { keep = 0.015 * strength }
                    else if edge > 0.68 { keep = 0.16 * strength }
                    else { keep = 0.42 + 0.58 * strength }
                    if rng.unit() > keep { continue }
                    let px = x + nx * lateral + (dx / length) * along
                    let py = y + ny * lateral + (dy / length) * along
                    let dot = radius * (0.75 + rng.unit() * 0.5)
                    ctx.fillEllipse(in: CGRect(x: px - dot, y: py - dot, width: dot * 2, height: dot * 2))
                }
                if strength < 0.7, rng.unit() < 0.35 {
                    let lateral = rng.signed() * width * 0.55
                    if abs(lateral) > width * 0.28 {
                        let speck = radius * 0.45
                        let px = x + nx * lateral
                        let py = y + ny * lateral
                        ctx.setFillColor(CGColor(srgbRed: 0xE8 / 255, green: 0xE5 / 255, blue: 0xE0 / 255, alpha: 1))
                        ctx.fillEllipse(in: CGRect(x: px - speck, y: py - speck, width: speck * 2, height: speck * 2))
                        ctx.setFillColor(blue)
                    }
                }
            }
            previous = point
        }
    }
}

func spine(index: Int, count: Int, size: CGFloat) -> [CGPoint] {
    let x0 = size * 0.46
    let x1 = size * 0.93
    let x = x0 + (x1 - x0) * (CGFloat(index) + 0.15) / CGFloat(count)
    let top = size * 0.92
    let bot = size * 0.22
    let turns = 4 + (index % 3)
    var points: [CGPoint] = []
    for turn in 0...turns {
        let y = turn % 2 == 0 ? top : bot
        let jog = sin(CGFloat(index) * 1.6 + CGFloat(turn) * 1.15) * size * 0.02
        points.append(CGPoint(x: x + jog, y: y))
    }
    return points
}

func blackFont(_ size: CGFloat) -> NSFont {
    let names = ["HelveticaNeue-CondensedBlack", "SFProDisplay-Black", "HelveticaNeue-Black", "SFPro-Black", ".SFNS-Black", ".SFNSDisplay-Black"]
    for name in names {
        if let font = NSFont(name: name, size: size) { return font }
    }
    return NSFont.systemFont(ofSize: size, weight: .black)
}

func wordmark(size: CGFloat) {
    let word = "Lamina" as NSString
    var point = size * 0.2
    var font = blackFont(point)
    if font.capHeight > 1 {
        point *= (size * 0.14) / font.capHeight
        font = blackFont(point)
    }
    let color = NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let origin = NSPoint(x: size * 0.07, y: size * 0.28)
    word.draw(at: origin, withAttributes: attrs)
    if font.fontName.lowercased().contains("black") == false {
        word.draw(at: NSPoint(x: origin.x + 0.7, y: origin.y), withAttributes: attrs)
    }
}

func writePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

func scaled(_ image: NSImage, to pixels: Int) -> NSImage {
    let out = NSImage(size: NSSize(width: pixels, height: pixels))
    out.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    out.unlockFocus()
    return out
}

let full = render(size: 1024)
writePNG(full, to: pngURL)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]
for (pixels, name) in sizes {
    let image = pixels == 1024 ? full : scaled(full, to: pixels)
    writePNG(image, to: iconset.appendingPathComponent(name))
}
