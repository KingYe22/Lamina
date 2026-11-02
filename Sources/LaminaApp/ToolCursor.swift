import AppKit
import LaminaCore

/// Zoom, precision, and brush cursors rasterized by `ToolCursorBitmap`.
///
/// Row 0 is the top of the image. The hotspot is in that same top-left space,
/// matching `PenCursorArt`.
enum ToolCursorArt {
    private static var cache: [String: NSCursor] = [:]

    static func cursor(kind: ToolCursorKind, mark: Bool = false) -> NSCursor {
        let key = "\(kind.rawValue)|\(mark)"
        if let cached = cache[key] { return cached }
        let hot = ToolCursorBitmap.hotspot(kind)
        let cursor = NSCursor(
            image: image(kind: kind, mark: mark),
            hotSpot: NSPoint(x: hot.x, y: hot.y)
        )
        cache[key] = cursor
        return cursor
    }

    static func writePNG(kind: ToolCursorKind, mark: Bool = false, to url: URL) {
        let bytes = ToolCursorBitmap.rgba(kind: kind, mark: mark, scale: 1)
        let image = PNGImage(width: ToolCursorBitmap.width, height: ToolCursorBitmap.height, rgba: bytes)
        try? PNGCodec.encode(image).write(to: url)
    }

    private static func image(kind: ToolCursorKind, mark: Bool) -> NSImage {
        let points = NSSize(width: ToolCursorBitmap.width, height: ToolCursorBitmap.height)
        let image = NSImage(size: points)
        for scale in [1, 2] {
            let pixels = ToolCursorBitmap.width * scale
            let bytes = ToolCursorBitmap.rgba(kind: kind, mark: mark, scale: scale)
            guard let cg = cgImage(bytes: bytes, pixels: pixels) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = points
            image.addRepresentation(rep)
        }
        return image
    }

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
