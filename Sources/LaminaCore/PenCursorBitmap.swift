import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 32×32 pen cursor, top row first. The hotspot is the nib tip.
///
/// v0.4.1 stored the tip at `(3.5, 5.5)` and passed NSCursor `y = 32 - 5.5 = 26.5`,
/// on the assumption that AppKit measures the hotspot from the lower-left. The Mac
/// retest (crop center 80,80, tip upper-left ≈ 84,41 at 2×) put the nib 19.5 logical
/// points above the click: the `26.5` was applied from the top of this upright image.
/// The hotspot is therefore the tip in the same top-left, y-down space as the bytes.
///
/// The nib is solid black with a white slit and no sticker outline. The foremost
/// opaque pixel is the tip; its upper-left corner is the hotspot at 1× and 2×.
public enum PenCursorBitmap {
    public static let width = 32
    public static let height = 32

    /// Tip pixel. `tipX` / `tipY` are that pixel's upper-left in logical points.
    public static let tipPixel = (x: 1, y: 1)
    public static let tipX = Double(tipPixel.x)
    public static let tipY = Double(tipPixel.y)

    /// NSCursor hotspot, top-left origin, y down. Same numbers as the tip corner.
    public static var hotspotX: Double { tipX }
    public static var hotspotY: Double { tipY }

    /// Larger of the 1× and 2× absolute errors. The Mac method: upper-left of the
    /// foremost opaque pixel minus the hotspot, in logical points.
    public static var tipError: Double {
        max(measureTip(scale: 1).absolute, measureTip(scale: 2).absolute)
    }

    public static func measureTip(scale: Int) -> PenTipMeasure {
        let scale = max(1, scale)
        let bytes = rgba(state: .pen, newPath: false, scale: scale)
        let pixels = width * scale
        var bestX = 0
        var bestY = 0
        var best = Int.max
        var found = false
        for y in 0..<pixels {
            for x in 0..<pixels {
                if bytes[(y * pixels + x) * 4 + 3] <= 16 { continue }
                let score = x + y
                if score < best {
                    best = score
                    bestX = x
                    bestY = y
                    found = true
                }
            }
        }
        let ulX = found ? Double(bestX) / Double(scale) : 0
        let ulY = found ? Double(bestY) / Double(scale) : 0
        let dx = ulX - hotspotX
        let dy = ulY - hotspotY
        return PenTipMeasure(
            scale: scale,
            ulX: ulX,
            ulY: ulY,
            dx: dx,
            dy: dy,
            absolute: max(abs(dx), abs(dy))
        )
    }

    public static func rgba(state: PenCursor, newPath: Bool, scale: Int = 1) -> [UInt8] {
        let scale = max(1, scale)
        let pixels = width * scale
        var buffer = [UInt8](repeating: 0, count: pixels * pixels * 4)
        if state == .convert {
            fill(caret, into: &buffer, scale: scale, slit: nil)
        } else {
            let shape = nib
            fill(shape, into: &buffer, scale: scale, slit: nibSlit(shape))
            if let glyph = badge(state, newPath: newPath) {
                stamp(&buffer, glyph: glyph, center: (27, 27), scale: scale)
            }
        }
        protectTip(&buffer, scale: scale)
        return buffer
    }

    // MARK: - Geometry

    /// Fountain-pen nib. Both edges leave the tip toward the lower right, so the
    /// tip pixel stays the unique upper-left point. No offset outline.
    private static let nib: [(Double, Double)] = [
        (1.05, 1.05),
        (5.4, 3.2),
        (11.8, 6.0),
        (16.6, 11.4),
        (16.2, 16.2),
        (8.4, 16.8),
        (4.6, 12.6)
    ]

    /// Convert-point caret. Same tip pixel as the nib.
    private static let caret: [(Double, Double)] = [
        (1.0, 1.0),
        (11.2, 4.4),
        (5.2, 11.4)
    ]

    /// White slit behind the tip, stopping before the middle so the body stays black.
    private static func nibSlit(_ black: [(Double, Double)]) -> ((Double, Double), (Double, Double)) {
        let tip = black[0]
        let cx = black.reduce(0) { $0 + $1.0 } / Double(black.count)
        let cy = black.reduce(0) { $0 + $1.1 } / Double(black.count)
        let a = (tip.0 + (cx - tip.0) * 0.34, tip.1 + (cy - tip.1) * 0.34)
        let b = (tip.0 + (cx - tip.0) * 0.78, tip.1 + (cy - tip.1) * 0.78)
        return (a, b)
    }

    // MARK: - Raster

    private static func fill(
        _ shape: [(Double, Double)],
        into buffer: inout [UInt8],
        scale: Int,
        slit: ((Double, Double), (Double, Double))?
    ) {
        let pixels = width * scale
        for y in 0..<pixels {
            for x in 0..<pixels {
                let px = (Double(x) + 0.5) / Double(scale)
                let py = (Double(y) + 0.5) / Double(scale)
                guard contains(shape, px, py) else { continue }
                let onSlit = slit.map { distance(px, py, $0.0, $0.1) <= 0.72 } == true
                let offset = (y * pixels + x) * 4
                if onSlit {
                    buffer[offset] = 255
                    buffer[offset + 1] = 255
                    buffer[offset + 2] = 255
                    buffer[offset + 3] = 255
                } else {
                    buffer[offset] = 0
                    buffer[offset + 1] = 0
                    buffer[offset + 2] = 0
                    buffer[offset + 3] = 255
                }
            }
        }
    }

    /// Drop anything above or left of the tip, then paint the tip pixel black.
    /// At 2× the logical tip is the 2×2 block whose upper-left is the hotspot.
    private static func protectTip(_ buffer: inout [UInt8], scale: Int) {
        let pixels = width * scale
        let originX = tipPixel.x * scale
        let originY = tipPixel.y * scale
        for y in 0..<pixels {
            for x in 0..<pixels where x < originX || y < originY {
                let offset = (y * pixels + x) * 4
                buffer[offset] = 0
                buffer[offset + 1] = 0
                buffer[offset + 2] = 0
                buffer[offset + 3] = 0
            }
        }
        for dy in 0..<scale {
            for dx in 0..<scale {
                let offset = ((originY + dy) * pixels + originX + dx) * 4
                buffer[offset] = 0
                buffer[offset + 1] = 0
                buffer[offset + 2] = 0
                buffer[offset + 3] = 255
            }
        }
    }

    private static func contains(_ poly: [(Double, Double)], _ x: Double, _ y: Double) -> Bool {
        var inside = false
        var previous = poly.count - 1
        for index in poly.indices {
            let a = poly[index]
            let b = poly[previous]
            if (a.1 > y) != (b.1 > y), x < (b.0 - a.0) * (y - a.1) / (b.1 - a.1) + a.0 {
                inside.toggle()
            }
            previous = index
        }
        return inside
    }

    private static func distance(_ px: Double, _ py: Double, _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dx = b.0 - a.0
        let dy = b.1 - a.1
        let length = dx * dx + dy * dy
        if length < 1e-12 { return hypot(px - a.0, py - a.1) }
        let t = min(1, max(0, ((px - a.0) * dx + (py - a.1) * dy) / length))
        return hypot(px - (a.0 + t * dx), py - (a.1 + t * dy))
    }

    // MARK: - Badges

    /// Lower-right marks. `#` is black; the stamp adds a one-point white outline.
    private static func badge(_ state: PenCursor, newPath: Bool) -> [String]? {
        switch state {
        case .pen:
            return newPath ? star : nil
        case .add:
            return plus
        case .delete:
            return minus
        case .close:
            return ring
        case .continuePath:
            return slash
        case .join:
            return square
        case .convert:
            return nil
        }
    }

    private static let star = [
        "#..#..#",
        ".#.#.#.",
        "..###..",
        "#######",
        "..###..",
        ".#.#.#.",
        "#..#..#",
    ]
    private static let plus = [
        ". . # . .",
        ". . # . .",
        "# # # # #",
        ". . # . .",
        ". . # . .",
    ]
    private static let minus = [
        "       ",
        "#####  ",
        "       ",
    ]
    private static let ring = [
        " ### ",
        "#   #",
        "#   #",
        "#   #",
        " ### ",
    ]
    private static let slash = [
        "#    ",
        " #   ",
        "  #  ",
        "   # ",
        "    #",
    ]
    private static let square = [
        "#####",
        "#   #",
        "#   #",
        "#   #",
        "#####",
    ]

    private static func stamp(_ buffer: inout [UInt8], glyph: [String], center: (Double, Double), scale: Int) {
        let pixels = width * scale
        let rows = glyph.count
        let cols = glyph[0].count
        let originX = Int((center.0 * Double(scale)).rounded()) - (cols * scale) / 2
        let originY = Int((center.1 * Double(scale)).rounded()) - (rows * scale) / 2
        var ink: [(Int, Int)] = []
        for (row, line) in glyph.enumerated() {
            for (col, character) in line.enumerated() where character == "#" {
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        ink.append((originX + col * scale + dx, originY + row * scale + dy))
                    }
                }
            }
        }
        let reach = scale
        var halo = Set<Int>()
        for (x, y) in ink {
            for dy in -reach...reach {
                for dx in -reach...reach {
                    let xx = x + dx
                    let yy = y + dy
                    if xx >= 0, yy >= 0, xx < pixels, yy < pixels {
                        halo.insert(yy * pixels + xx)
                    }
                }
            }
        }
        for index in halo {
            let offset = index * 4
            buffer[offset] = 255
            buffer[offset + 1] = 255
            buffer[offset + 2] = 255
            buffer[offset + 3] = 255
        }
        for (x, y) in ink where x >= 0 && y >= 0 && x < pixels && y < pixels {
            let offset = (y * pixels + x) * 4
            buffer[offset] = 0
            buffer[offset + 1] = 0
            buffer[offset + 2] = 0
            buffer[offset + 3] = 255
        }
    }
}

/// Tip upper-left against the hotspot, in logical points. `absolute` is
/// `max(|dx|, |dy|)`, the same reading as the Mac crop (`|tip − hotspot|`).
public struct PenTipMeasure: Equatable, Sendable {
    public var scale: Int
    public var ulX: Double
    public var ulY: Double
    public var dx: Double
    public var dy: Double
    public var absolute: Double
}
