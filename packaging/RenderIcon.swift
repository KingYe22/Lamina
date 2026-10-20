import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: render-icon AppIcon-1024.png icon.iconset\n", stderr)
    exit(2)
}

let pngURL = URL(fileURLWithPath: args[1])
let iconset = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(srgbRed: 0xE8 / 255, green: 0xE5 / 255, blue: 0xE0 / 255, alpha: 1).setFill()
    NSBezierPath(rect: rect).fill()
    let scale = CGFloat(size) / 1024
    let blue = NSColor(srgbRed: 0x0A / 255, green: 0x4F / 255, blue: 0xD6 / 255, alpha: 1)
    blue.setStroke()
    var state: UInt64 = 0xC0FFEE
    func rand() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1
        return CGFloat((state >> 33) % 1000) / 1000
    }
    for column in stride(from: 0, to: 46, by: 1) {
        let path = NSBezierPath()
        path.lineWidth = (2.2 + rand() * 3.4) * scale
        path.lineCapStyle = .round
        let x = (430 + CGFloat(column) * 12 + rand() * 8) * scale
        var y = 70 * scale
        path.move(to: NSPoint(x: x, y: y))
        var flip = false
        while y < 980 * scale {
            let step = (16 + rand() * 34) * scale
            y += step
            let wobble = (rand() * 18 - 6) * scale
            let tip = flip ? -wobble : wobble
            path.line(to: NSPoint(x: x + tip, y: min(y, 990 * scale)))
            flip.toggle()
        }
        path.stroke()
    }
    let word = Array("Lamina")
    let font = NSFont(name: "Helvetica-Bold", size: 168 * scale) ?? NSFont.systemFont(ofSize: 168 * scale, weight: .black)
    let offsets: [CGFloat] = [0, -6, 4, -3, 7, -5]
    var cursor = 54 * scale
    for (index, character) in word.enumerated() {
        let token = String(character) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
        ]
        let glyph = token.size(withAttributes: attrs)
        token.draw(at: NSPoint(x: cursor, y: 78 * scale + offsets[index] * scale), withAttributes: attrs)
        cursor += glyph.width * 0.92
    }
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
    _ = pixels
}

let full = render(size: 1024)
writePNG(full, to: pngURL, pixels: 1024)

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
    writePNG(image, to: iconset.appendingPathComponent(name), pixels: pixels)
}
