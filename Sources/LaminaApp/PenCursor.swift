import AppKit
import LaminaCore

/// 32×32 pen cursor. The nib tip is bitmap pixel (0, 25) from the top-left.
/// NSCursor's hotspot is that same pixel measured from the lower-left.
enum PenCursor {
    static let image: NSImage = {
        let rep = makeRep()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }()

    static let cursor = NSCursor(
        image: image,
        hotSpot: NSPoint(x: PenHotSpot.cursorX, y: PenHotSpot.cursorY)
    )

    static func writePNG(to url: URL) {
        guard let data = makeRep().representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    static func makeRep() -> NSBitmapImageRep {
        let width = PenHotSpot.width
        let height = PenHotSpot.height
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return rep }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = context
        context.shouldAntialias = true
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        // y grows up. The tip pixel is stamped after the body so column 0 stays the tip.
        let nib = NSBezierPath()
        nib.move(to: NSPoint(x: 2, y: 9))
        nib.line(to: NSPoint(x: 10, y: 16))
        nib.line(to: NSPoint(x: 22, y: 28))
        nib.line(to: NSPoint(x: 28, y: 22))
        nib.line(to: NSPoint(x: 14, y: 8))
        nib.close()
        NSColor.white.setFill()
        nib.fill()
        NSColor.black.setStroke()
        nib.lineWidth = 1
        nib.stroke()
        let slit = NSBezierPath()
        slit.move(to: NSPoint(x: 4, y: 10))
        slit.line(to: NSPoint(x: 16, y: 22))
        slit.lineWidth = 0.8
        NSColor.black.setStroke()
        slit.stroke()
        context.shouldAntialias = false
        NSColor.black.setFill()
        // PNG row 25 from the top is y = 6 in this bottom-left buffer (31 - 25 = 6).
        NSRect(x: 0, y: CGFloat(height - 1 - PenHotSpot.y), width: 1, height: 1).fill()
        NSGraphicsContext.current = previous
        return rep
    }
}
