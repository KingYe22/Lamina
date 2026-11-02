import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Which Illustrator cursor a tool shows on the canvas.
///
/// Zoom is a magnifier (the plus or minus sits inside the lens). Shape tools use
/// the precision cross, whose hotspot is the empty center. The brush hotspot is
/// the bristle tip. Pen cursors stay in `PenCursorBitmap`.
public enum ToolCursorKind: String, Equatable, Sendable {
    case zoomIn
    case zoomOut
    case precision
    case brush
}

public struct ToolCursorHotspot: Equatable, Sendable {
    public var x: Double
    public var y: Double
}

public enum ToolCursors {
    /// Canvas cursor for tools whose artwork is not the system arrow, hand, or pen.
    public static func kind(for tool: Tool) -> ToolCursorKind? {
        switch tool {
        case .zoom:
            return .zoomIn
        case .brush:
            return .brush
        case .rectangle, .roundedRectangle, .ellipse, .polygon, .star, .flare,
             .line, .arc, .spiral, .rectGrid, .polarGrid:
            return .precision
        default:
            return nil
        }
    }
}

/// 32×32 tool cursors, top row first. Hotspots use the same top-left, y-down
/// space as `PenCursorBitmap` (the space AppKit applied on the Mac retest).
public enum ToolCursorBitmap {
    public static let width = 32
    public static let height = 32

    /// Center of the plus or minus, which is the center of the lens.
    public static let zoomHotspot = ToolCursorHotspot(x: 11.5, y: 11.5)
    /// Empty middle of the precision cross.
    public static let precisionHotspot = ToolCursorHotspot(x: 16, y: 16)
    /// Bristle tip. The upper-left of this pixel is the contact point.
    public static let brushHotspot = ToolCursorHotspot(x: 5, y: 23)

    public static func hotspot(_ kind: ToolCursorKind) -> ToolCursorHotspot {
        switch kind {
        case .zoomIn, .zoomOut: return zoomHotspot
        case .precision: return precisionHotspot
        case .brush: return brushHotspot
        }
    }

    /// `mark` draws the new-stroke asterisk beside the brush. Ignored for other kinds.
    public static func rgba(kind: ToolCursorKind, mark: Bool = false, scale: Int = 1) -> [UInt8] {
        let scale = max(1, scale)
        let pixels = width * scale
        var buffer = [UInt8](repeating: 0, count: pixels * pixels * 4)
        for y in 0..<pixels {
            for x in 0..<pixels {
                let lx = (Double(x) + 0.5) / Double(scale)
                let ly = (Double(y) + 0.5) / Double(scale)
                guard let sample = color(kind, x: lx, y: ly) else { continue }
                let offset = (y * pixels + x) * 4
                buffer[offset] = sample.0
                buffer[offset + 1] = sample.1
                buffer[offset + 2] = sample.2
                buffer[offset + 3] = 255
            }
        }
        if kind == .brush {
            protectBrushTip(&buffer, scale: scale)
            if mark {
                stamp(&buffer, glyph: asterisk, center: (26.5, 26.5), scale: scale)
            }
        }
        return buffer
    }

    // MARK: - Shapes

    private static func color(_ kind: ToolCursorKind, x: Double, y: Double) -> (UInt8, UInt8, UInt8)? {
        switch kind {
        case .zoomIn:
            return magnifier(x, y, plus: true)
        case .zoomOut:
            return magnifier(x, y, plus: false)
        case .precision:
            return crosshair(x, y)
        case .brush:
            return brush(x, y)
        }
    }

    /// White lens, black rim, white outer edge, black + or −, handle down-right.
    private static func magnifier(_ x: Double, _ y: Double, plus: Bool) -> (UInt8, UInt8, UInt8)? {
        let cx = zoomHotspot.x
        let cy = zoomHotspot.y
        let distance = hypot(x - cx, y - cy)
        let onBar = abs(y - cy) <= 1.05 && abs(x - cx) <= 4.35
        let onStem = plus && abs(x - cx) <= 1.05 && abs(y - cy) <= 4.35
        if (onBar || onStem) && distance <= 5.35 { return black }
        if distance <= 5.45 { return white }
        if distance <= 7.05 { return black }
        if distance <= 8.15 { return white }
        let handle = segmentDistance(x, y, (17.4, 17.4), (28.2, 28.2))
        if handle.clamped && handle.distance <= 1.65 { return black }
        if handle.clamped && handle.distance <= 2.75 { return white }
        return nil
    }

    /// Four rounded arms and a clear center. The click is the hole, not an arrow tip.
    private static func crosshair(_ x: Double, _ y: Double) -> (UInt8, UInt8, UInt8)? {
        if hypot(x - precisionHotspot.x, y - precisionHotspot.y) < 2.05 { return nil }
        let arms = [
            ((3.2, 16.0), (11.5, 16.0)),
            ((20.5, 16.0), (28.8, 16.0)),
            ((16.0, 3.2), (16.0, 11.5)),
            ((16.0, 20.5), (16.0, 28.8))
        ]
        var halo = false
        for arm in arms {
            let hit = segmentDistance(x, y, arm.0, arm.1)
            guard hit.clamped else { continue }
            if hit.distance <= 1.45 { return black }
            if hit.distance <= 2.45 { halo = true }
        }
        return halo ? white : nil
    }

    /// Brush pointing down-left. The tip pixel is forced black after this pass.
    private static func brush(_ x: Double, _ y: Double) -> (UInt8, UInt8, UInt8)? {
        let ink = brushInk(x, y)
        if ink { return black }
        let reach = 1.2
        for index in 0..<10 {
            let angle = Double(index) / 10 * Double.pi * 2
            if brushInk(x + cos(angle) * reach, y + sin(angle) * reach) { return white }
        }
        return nil
    }

    private static func brushInk(_ x: Double, _ y: Double) -> Bool {
        if tapered(x, y, a: (5.2, 23.0), b: (13.4, 15.4), r0: 1.15, r1: 3.35) { return true }
        if capsule(x, y, a: (12.6, 15.6), b: (25.4, 6.2), radius: 2.15) { return true }
        return false
    }

    private static func protectBrushTip(_ buffer: inout [UInt8], scale: Int) {
        let pixels = width * scale
        let originX = Int(brushHotspot.x) * scale
        let originY = Int(brushHotspot.y) * scale
        for dy in 0..<scale {
            for dx in 0..<scale {
                let x = originX + dx
                let y = originY + dy
                guard x >= 0, y >= 0, x < pixels, y < pixels else { continue }
                let offset = (y * pixels + x) * 4
                buffer[offset] = 0
                buffer[offset + 1] = 0
                buffer[offset + 2] = 0
                buffer[offset + 3] = 255
            }
        }
    }

    // MARK: - Geometry

    private static let black: (UInt8, UInt8, UInt8) = (0, 0, 0)
    private static let white: (UInt8, UInt8, UInt8) = (255, 255, 255)

    private static func capsule(_ x: Double, _ y: Double, a: (Double, Double), b: (Double, Double), radius: Double) -> Bool {
        let hit = segmentDistance(x, y, a, b)
        return hit.clamped && hit.distance <= radius
    }

    private static func tapered(
        _ x: Double,
        _ y: Double,
        a: (Double, Double),
        b: (Double, Double),
        r0: Double,
        r1: Double
    ) -> Bool {
        let dx = b.0 - a.0
        let dy = b.1 - a.1
        let length = dx * dx + dy * dy
        if length < 1e-9 { return hypot(x - a.0, y - a.1) <= r0 }
        let t = min(1, max(0, ((x - a.0) * dx + (y - a.1) * dy) / length))
        let px = a.0 + t * dx
        let py = a.1 + t * dy
        return hypot(x - px, y - py) <= (r0 + (r1 - r0) * t)
    }

    private static func segmentDistance(
        _ x: Double,
        _ y: Double,
        _ a: (Double, Double),
        _ b: (Double, Double)
    ) -> (distance: Double, clamped: Bool) {
        let dx = b.0 - a.0
        let dy = b.1 - a.1
        let length = dx * dx + dy * dy
        if length < 1e-12 {
            return (hypot(x - a.0, y - a.1), true)
        }
        let t = ((x - a.0) * dx + (y - a.1) * dy) / length
        let clamped = min(1, max(0, t))
        let px = a.0 + clamped * dx
        let py = a.1 + clamped * dy
        return (hypot(x - px, y - py), t >= -0.02 && t <= 1.02)
    }

    // MARK: - Asterisk

    private static let asterisk = [
        "#..#..#",
        ".#.#.#.",
        "..###..",
        "#######",
        "..###..",
        ".#.#.#.",
        "#..#..#",
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
