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
    let base = spine(size)
    let count = 6
    let pitch = size * 0.015
    let half = size * 0.011
    for index in 0..<count {
        var rng = Seed(state: 0xC0A7E &+ UInt64(index) &* 131)
        let offset = (CGFloat(index) - CGFloat(count - 1) / 2) * pitch
        let path = offsetPath(base, offset: offset, rng: &rng)
        paint(ctx, path: path, rng: &rng, half: half, size: size)
    }
}

/// One tall W. Six crayon passes sit side by side on it, with paper left between them.
func spine(_ size: CGFloat) -> [CGPoint] {
    let top = size * 0.945
    let bot = size * 0.36
    let xs: [CGFloat] = [0.28, 0.45, 0.62, 0.80, 0.96]
    let ys: [CGFloat] = [top, bot, top - size * 0.015, bot + size * 0.02, top - size * 0.03]
    return zip(xs, ys).map { CGPoint(x: $0.0 * size, y: $0.1) }
}

func normals(of points: [CGPoint]) -> [CGPoint] {
    var out: [CGPoint] = []
    for index in points.indices {
        let dx: CGFloat
        let dy: CGFloat
        if index == 0 {
            dx = points[1].x - points[0].x
            dy = points[1].y - points[0].y
        } else if index == points.count - 1 {
            dx = points[index].x - points[index - 1].x
            dy = points[index].y - points[index - 1].y
        } else {
            let dx1 = points[index].x - points[index - 1].x
            let dy1 = points[index].y - points[index - 1].y
            let dx2 = points[index + 1].x - points[index].x
            let dy2 = points[index + 1].y - points[index].y
            let l1 = max(1, hypot(dx1, dy1))
            let l2 = max(1, hypot(dx2, dy2))
            dx = dx1 / l1 + dx2 / l2
            dy = dy1 / l1 + dy2 / l2
        }
        let length = max(1, hypot(dx, dy))
        out.append(CGPoint(x: -dy / length, y: dx / length))
    }
    return out
}

func offsetPath(_ points: [CGPoint], offset: CGFloat, rng: inout Seed) -> [CGPoint] {
    let dirs = normals(of: points)
    var shifted: [CGPoint] = []
    for (point, normal) in zip(points, dirs) {
        shifted.append(CGPoint(
            x: point.x + normal.x * offset + rng.signed() * 1.4,
            y: point.y + normal.y * offset + rng.signed() * 1.4
        ))
    }
    var dense = [shifted[0]]
    for index in 1..<shifted.count {
        let a = shifted[index - 1]
        let b = shifted[index]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(1, hypot(dx, dy))
        let nx = -dy / length
        let ny = dx / length
        let steps = max(2, Int(length / 18))
        if steps > 1 {
            for step in 1..<steps {
                let u = CGFloat(step) / CGFloat(steps)
                let wob = sin(u * .pi) * (5 + rng.unit() * 3)
                dense.append(CGPoint(
                    x: a.x + dx * u + nx * rng.signed() * wob,
                    y: a.y + dy * u + ny * rng.signed() * wob * 0.3
                ))
            }
        }
        dense.append(b)
    }
    return dense
}

func paint(_ ctx: CGContext, path: [CGPoint], rng: inout Seed, half: CGFloat, size: CGFloat) {
    let inkR: CGFloat = 0x0A / 255
    let inkG: CGFloat = 0x3F / 255
    let inkB: CGFloat = 0xD4 / 255
    guard path.count > 1 else { return }
    for index in 1..<path.count {
        let a = path[index - 1]
        let b = path[index]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(1, hypot(dx, dy))
        let nx = -dy / length
        let ny = dx / length
        let tx = dx / length
        let ty = dy / length
        let steps = max(1, Int(length / 1.35))
        for step in 0...steps {
            let u = CGFloat(step) / CGFloat(steps)
            let x = a.x + dx * u
            let y = a.y + dy * u
            if rng.unit() < 0.055 { continue }
            for _ in 0..<8 {
                let cube = rng.signed()
                let lateral = cube * cube * cube * half
                let edge = abs(lateral) / half
                if edge > 0.86, rng.unit() < 0.75 { continue }
                if rng.unit() < 0.04 { continue }
                let along = rng.signed() * 1.5
                let x0 = x + nx * lateral + tx * along
                let y0 = y + ny * lateral + ty * along
                let reach = 2.8 + rng.unit() * 4.2
                let x1 = x0 + tx * reach + nx * rng.signed() * 1.1
                let y1 = y0 + ty * reach + ny * rng.signed() * 1.1
                let center = max(0, 1 - edge)
                let alpha = (0.28 + 0.62 * center * center) * (0.82 + 0.18 * rng.unit())
                ctx.setFillColor(CGColor(srgbRed: inkR, green: inkG, blue: inkB, alpha: alpha))
                for dot in 0..<5 {
                    let t = CGFloat(dot) / 4
                    let px = x0 + (x1 - x0) * t
                    let py = y0 + (y1 - y0) * t
                    if px < 0 || py < 0 || px >= size || py >= size { continue }
                    ctx.fill(CGRect(x: floor(px), y: floor(py), width: 1, height: 1))
                }
            }
        }
    }
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
    var point = size * 0.22
    var font = blackFont(point)
    if font.capHeight > 1 {
        point *= (size * 0.15) / font.capHeight
        font = blackFont(point)
    }
    let color = NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    // One string, so every letter sits on this baseline.
    word.draw(at: NSPoint(x: size * 0.05, y: size * 0.065), withAttributes: attrs)
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
