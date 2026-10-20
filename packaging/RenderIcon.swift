import AppKit

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("usage: render-icon lamina-icon.jpg AppIcon-1024.png icon.iconset\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: args[1])
let pngURL = URL(fileURLWithPath: args[2])
let iconset = URL(fileURLWithPath: args[3], isDirectory: true)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

guard let source = NSImage(contentsOf: sourceURL), source.isValid, source.size.width > 1, source.size.height > 1 else {
    fputs("could not read \(sourceURL.path)\n", stderr)
    exit(1)
}

/// Scale the supplied artwork into a square icon and clip it with the macOS
/// rounded-rect mask. The picture itself is not redrawn, filtered, or cropped.
func masked(_ source: NSImage, pixels: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let size = CGFloat(pixels)
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let ctx = graphics.cgContext
    ctx.clear(canvas)
    ctx.interpolationQuality = .high
    ctx.saveGState()
    let radius = size * 0.2237
    ctx.addPath(CGPath(roundedRect: canvas, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let from = NSRect(origin: .zero, size: source.size)
    source.draw(in: canvas, from: from, operation: .copy, fraction: 1)
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("could not encode \(url.path)\n", stderr)
        exit(1)
    }
    do {
        try data.write(to: url)
    } catch {
        fputs("could not write \(url.path): \(error)\n", stderr)
        exit(1)
    }
}

guard let full = masked(source, pixels: 1024) else {
    fputs("could not mask icon\n", stderr)
    exit(1)
}
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
    let rep = pixels == 1024 ? full : masked(source, pixels: pixels)
    guard let rep else {
        fputs("could not mask \(name)\n", stderr)
        exit(1)
    }
    writePNG(rep, to: iconset.appendingPathComponent(name))
}
