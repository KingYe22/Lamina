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
    var state: UInt64 = 0xC0FFEE
    mutating func unit() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1
        return CGFloat(state >> 33) / CGFloat(UInt64(1) << 31)
    }
    mutating func signed() -> CGFloat { unit() * 2 - 1 }
}

func render(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()
    let radius = CGFloat(size) * 0.2237
    NSBezierPath(roundedRect: canvas, xRadius: radius, yRadius: radius).addClip()
    let paper = NSColor(srgbRed: 0xE8 / 255, green: 0xE5 / 255, blue: 0xE0 / 255, alpha: 1)
    paper.setFill()
    canvas.fill()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    var seed = Seed()
    scribble(context, scale: scale, seed: &seed)
    grain(context, scale: scale, paper: paper, seed: &seed)
    wordmark(scale: scale)
    image.unlockFocus()
    return image
}

func scribble(_ context: CGContext, scale: CGFloat, seed: inout Seed) {
    let blues: [(CGFloat, CGFloat, CGFloat)] = [
        (0x0A, 0x4F, 0xD6),
        (0x14, 0x62, 0xE8),
        (0x08, 0x3A, 0xA4),
        (0x2E, 0x74, 0xF0)
    ]
    for pass in 0..<9 {
        let radius = (46 + seed.unit() * 38) * scale
        let alpha = 0.16 + seed.unit() * 0.22
        let rgb = blues[pass % blues.count]
        let color = NSColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: alpha).cgColor
        let points = zigzag(pass: pass, scale: scale, seed: &seed)
        guard points.count > 1 else { continue }
        for index in 1..<points.count {
            stampSegment(context, from: points[index - 1], to: points[index], radius: radius, color: color, seed: &seed)
        }
    }
}

func zigzag(pass: Int, scale: CGFloat, seed: inout Seed) -> [CGPoint] {
    var points: [CGPoint] = []
    var x = (250 + CGFloat(pass) * 42 + seed.signed() * 24) * scale
    let xEnd = (1040 + seed.signed() * 20) * scale
    let yHigh = (860 + seed.signed() * 50) * scale
    let yLow = (80 + seed.signed() * 40) * scale
    var downward = pass % 2 == 0
    var y = downward ? yHigh : yLow
    points.append(CGPoint(x: x, y: y))
    while x < xEnd {
        downward.toggle()
        x += (16 + seed.unit() * 22) * scale
        y = (downward ? yLow : yHigh) + seed.signed() * 28 * scale
        points.append(CGPoint(x: x + seed.signed() * 12 * scale, y: y))
    }
    return points
}

func stampSegment(_ context: CGContext, from start: CGPoint, to end: CGPoint, radius: CGFloat, color: CGColor, seed: inout Seed) {
    let length = hypot(end.x - start.x, end.y - start.y)
    let step = max(radius * 0.38, 1)
    let count = max(1, Int(length / step))
    for index in 0...count {
        if seed.unit() < 0.07 { continue }
        let t = CGFloat(index) / CGFloat(count)
        let center = CGPoint(
            x: start.x + (end.x - start.x) * t + seed.signed() * radius * 0.22,
            y: start.y + (end.y - start.y) * t + seed.signed() * radius * 0.18
        )
        let stampRadius = radius * (0.72 + seed.unit() * 0.55)
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: center.x - stampRadius, y: center.y - stampRadius, width: stampRadius * 2, height: stampRadius * 2))
        if seed.unit() < 0.8 {
            let speck = stampRadius * (0.18 + seed.unit() * 0.28)
            let offset = CGPoint(x: seed.signed() * stampRadius * 0.7, y: seed.signed() * stampRadius * 0.7)
            context.fillEllipse(in: CGRect(x: center.x + offset.x - speck, y: center.y + offset.y - speck, width: speck * 2, height: speck * 2))
        }
    }
}

func grain(_ context: CGContext, scale: CGFloat, paper: NSColor, seed: inout Seed) {
    let blue = NSColor(srgbRed: 0x0A / 255, green: 0x4F / 255, blue: 0xD6 / 255, alpha: 1)
    for _ in 0..<7000 {
        let x = seed.unit() * 1024 * scale
        let y = seed.unit() * 1024 * scale
        let onScribble = x > 280 * scale
        let punch = seed.unit() < 0.72
        let alpha = (onScribble ? 0.18 : 0.05) + seed.unit() * (onScribble ? 0.45 : 0.08)
        let color = (punch ? paper : blue).withAlphaComponent(alpha)
        let radius = (seed.unit() < 0.92 ? 0.6 + seed.unit() * 1.4 : 2.2 + seed.unit() * 2.4) * scale
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
    }
}

func wordmark(scale: CGFloat) {
    let size = 158 * scale
    let font = blackFont(size)
    let heavy = font.fontName.lowercased().contains("black")
    let offsets: [CGFloat] = [0, -10, 7, -4, 11, -8]
    var cursor = 92 * scale
    let ink = NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
    for (index, character) in Array("Lamina").enumerated() {
        let token = String(character) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let glyph = token.size(withAttributes: attrs)
        let origin = NSPoint(x: cursor, y: 128 * scale + offsets[index] * scale)
        token.draw(at: origin, withAttributes: attrs)
        if !heavy {
            token.draw(at: NSPoint(x: origin.x + 0.8 * scale, y: origin.y), withAttributes: attrs)
        }
        cursor += glyph.width * 0.9
    }
}

func blackFont(_ size: CGFloat) -> NSFont {
    let names = ["HelveticaNeue-Black", "HelveticaNeue-CondensedBlack", "SFProDisplay-Black", "SFPro-Black", ".SFNS-Black"]
    for name in names {
        if let font = NSFont(name: name, size: size) { return font }
    }
    return NSFont.systemFont(ofSize: size, weight: .black)
}

func writePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
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
    let image = pixels == 1024 ? full : render(size: pixels)
    writePNG(image, to: iconset.appendingPathComponent(name))
}
