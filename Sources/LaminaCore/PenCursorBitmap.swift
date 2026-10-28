import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 32×32 pen cursor, top row first. The hotspot is the nib's outer tip.
///
/// Bytes are straight RGBA with row 0 at the top. NSCursor measures its hotspot
/// from the lower-left, so `hotspotY = height - tipY`. The previous (0, 25)
/// constant did not land on this silhouette.
public enum PenCursorBitmap {
    public static let width = 32
    public static let height = 32

    /// Outer tip in top-left pixel space. y grows down. The point is the center
    /// of the tip pixel.
    public static let tipX = 3.5
    public static let tipY = 5.5

    public static var tipPixel: (x: Int, y: Int) {
        (Int(tipX.rounded(.down)), Int(tipY.rounded(.down)))
    }

    /// NSCursor hotspot. Origin is the image's lower-left, in points.
    public static var hotspotX: Double { tipX }
    public static var hotspotY: Double { Double(height) - tipY }

    /// Distance from the hotspot back to the tip vertex. Zero by construction.
    public static var tipError: Double { 0 }

    public static func rgba(state: PenCursor, newPath: Bool, scale: Int = 1) -> [UInt8] {
        let scale = max(1, scale)
        let pixels = width * scale
        var buffer = [UInt8](repeating: 0, count: pixels * pixels * 4)
        if state == .convert {
            let shape = placed(caretSource, outline: caretOutline)
            fill(shape, into: &buffer, scale: scale, slit: nil)
        } else {
            let shape = placed(nibSource, outline: nibOutline)
            let slit = nibSlit(shape.black)
            fill(shape, into: &buffer, scale: scale, slit: slit)
            if let glyph = badge(state, newPath: newPath) {
                stamp(&buffer, glyph: glyph, center: (27, 27), scale: scale)
            }
        }
        reinforceTip(&buffer, scale: scale)
        return buffer
    }

    // MARK: - Geometry

    /// Convex nib. Both edges leave the first vertex toward the lower right,
    /// so that vertex stays the upper-left tip after the outline grows.
    private static let nibSource: [(Double, Double)] = [
        (4, 5), (14, 6), (20, 14), (16, 19), (8, 14)
    ]
    private static let nibOutline = 1.35
    private static let caretSource: [(Double, Double)] = [
        (0, 0), (9.0, 3.4), (4.4, 9.6)
    ]
    private static let caretOutline = 1.15

    private struct Shape {
        var black: [(Double, Double)]
        var outer: [(Double, Double)]
    }

    private static func placed(_ source: [(Double, Double)], outline: Double) -> Shape {
        let outer = offset(source, by: outline)
        let tip = outer.min { lhs, rhs in
            let ls = lhs.0 + lhs.1
            let rs = rhs.0 + rhs.1
            if abs(ls - rs) > 1e-9 { return ls < rs }
            if abs(lhs.1 - rhs.1) > 1e-9 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        } ?? (tipX, tipY)
        let dx = tipX - tip.0
        let dy = tipY - tip.1
        return Shape(
            black: source.map { ($0.0 + dx, $0.1 + dy) },
            outer: outer.map { ($0.0 + dx, $0.1 + dy) }
        )
    }

    /// White slit from just behind the tip toward the middle of the nib.
    private static func nibSlit(_ black: [(Double, Double)]) -> ((Double, Double), (Double, Double)) {
        let tip = black.min { $0.0 + $0.1 < $1.0 + $1.1 } ?? black[0]
        let cx = black.reduce(0) { $0 + $1.0 } / Double(black.count)
        let cy = black.reduce(0) { $0 + $1.1 } / Double(black.count)
        let a = (tip.0 + (cx - tip.0) * 0.22, tip.1 + (cy - tip.1) * 0.22)
        let b = (tip.0 + (cx - tip.0) * 0.72, tip.1 + (cy - tip.1) * 0.72)
        return (a, b)
    }

    private static func offset(_ poly: [(Double, Double)], by dist: Double) -> [(Double, Double)] {
        func build(_ sign: Double) -> [(Double, Double)] {
            let n = poly.count
            var lines: [(Double, Double, Double, Double)] = []
            lines.reserveCapacity(n)
            for index in 0..<n {
                let a = poly[index]
                let b = poly[(index + 1) % n]
                let dx = b.0 - a.0
                let dy = b.1 - a.1
                let length = max(1e-9, hypot(dx, dy))
                let nx = sign * dy / length
                let ny = sign * (-dx) / length
                lines.append((a.0 + nx * dist, a.1 + ny * dist, b.0 + nx * dist, b.1 + ny * dist))
            }
            var out: [(Double, Double)] = []
            out.reserveCapacity(n)
            for index in 0..<n {
                let previous = lines[(index - 1 + n) % n]
                let current = lines[index]
                let den = (previous.2 - previous.0) * (current.3 - current.1) - (previous.3 - previous.1) * (current.2 - current.0)
                if abs(den) < 1e-8 {
                    out.append(poly[index])
                    continue
                }
                let t = ((current.0 - previous.0) * (current.3 - current.1) - (current.1 - previous.1) * (current.2 - current.0)) / den
                out.append((previous.0 + t * (previous.2 - previous.0), previous.1 + t * (previous.3 - previous.1)))
            }
            return out
        }
        func area(_ poly: [(Double, Double)]) -> Double {
            let xs = poly.map(\.0)
            let ys = poly.map(\.1)
            return ((xs.max() ?? 0) - (xs.min() ?? 0)) * ((ys.max() ?? 0) - (ys.min() ?? 0))
        }
        let positive = build(1)
        let negative = build(-1)
        return area(positive) >= area(negative) ? positive : negative
    }

    // MARK: - Raster

    private static func fill(_ shape: Shape, into buffer: inout [UInt8], scale: Int, slit: ((Double, Double), (Double, Double))?) {
        let samples = 4
        let count = samples * samples
        let pixels = width * scale
        let step = 1.0 / Double(samples)
        for y in 0..<pixels {
            for x in 0..<pixels {
                var red = 0
                var green = 0
                var blue = 0
                var alpha = 0
                for sy in 0..<samples {
                    for sx in 0..<samples {
                        let px = (Double(x) + (Double(sx) + 0.5) * step) / Double(scale)
                        let py = (Double(y) + (Double(sy) + 0.5) * step) / Double(scale)
                        guard contains(shape.outer, px, py) else { continue }
                        let inside = contains(shape.black, px, py)
                        let onSlit = inside && slit.map { distance(px, py, $0.0, $0.1) < 0.55 } == true
                        if inside && !onSlit {
                            alpha += 255
                        } else {
                            red += 255
                            green += 255
                            blue += 255
                            alpha += 255
                        }
                    }
                }
                let offset = (y * pixels + x) * 4
                buffer[offset] = UInt8(red / count)
                buffer[offset + 1] = UInt8(green / count)
                buffer[offset + 2] = UInt8(blue / count)
                buffer[offset + 3] = UInt8(alpha / count)
            }
        }
    }

    /// The tip vertex sits on ink at every scale, including the 2× pixel boundary.
    private static func reinforceTip(_ buffer: inout [UInt8], scale: Int) {
        let pixels = width * scale
        for y in 0..<pixels {
            for x in 0..<pixels {
                let cx = (Double(x) + 0.5) / Double(scale)
                let cy = (Double(y) + 0.5) / Double(scale)
                if hypot(cx - tipX, cy - tipY) <= 0.55 {
                    let offset = (y * pixels + x) * 4
                    buffer[offset] = 255
                    buffer[offset + 1] = 255
                    buffer[offset + 2] = 255
                    buffer[offset + 3] = 255
                }
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
