import AppKit
import LaminaCore

/// Pen cursors rasterized by `PenCursorBitmap`.
///
/// Row 0 of the buffer is the top of the image. The hotspot is the nib tip in
/// that same top-left space (`PenHotSpot.cursorX`, `PenHotSpot.cursorY`). v0.4.1
/// flipped Y for a lower-left hotspot; on the Mac that value was measured from
/// the top, so the tip sat ~19.5 pt above the click.
enum PenCursorArt {
    private static var cache: [String: NSCursor] = [:]

    static func cursor(state: PenCursor, newPath: Bool) -> NSCursor {
        let key = "\(state.rawValue)|\(newPath)"
        if let cached = cache[key] { return cached }
        let cursor = NSCursor(
            image: image(state: state, newPath: newPath),
            hotSpot: NSPoint(x: PenHotSpot.cursorX, y: PenHotSpot.cursorY)
        )
        cache[key] = cursor
        return cursor
    }

    static func writePNG(to url: URL) {
        write(state: .pen, newPath: false, to: url)
    }

    static func writeNewPathPNG(to url: URL) {
        write(state: .pen, newPath: true, to: url)
    }

    private static func write(state: PenCursor, newPath: Bool, to url: URL) {
        let bytes = PenCursorBitmap.rgba(state: state, newPath: newPath, scale: 1)
        let image = PNGImage(width: PenCursorBitmap.width, height: PenCursorBitmap.height, rgba: bytes)
        try? PNGCodec.encode(image).write(to: url)
    }

    private static func image(state: PenCursor, newPath: Bool) -> NSImage {
        let points = NSSize(width: PenCursorBitmap.width, height: PenCursorBitmap.height)
        let image = NSImage(size: points)
        for scale in [1, 2] {
            let pixels = PenCursorBitmap.width * scale
            let bytes = PenCursorBitmap.rgba(state: state, newPath: newPath, scale: scale)
            guard let cg = cgImage(bytes: bytes, pixels: pixels) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = points
            image.addRepresentation(rep)
        }
        return image
    }

    /// Straight RGBA, top row first. `byteOrder32Big` with alpha last keeps the
    /// bytes in R, G, B, A order, matching `PenCursorBitmap`.
    private static func cgImage(bytes: [UInt8], pixels: Int) -> CGImage? {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        return CGImage(
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: pixels * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
