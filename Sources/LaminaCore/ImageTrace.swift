import Foundation

public struct TracePreset: Equatable, Sendable {
    public var name: String
    public var colors: Int
    public var threshold: Int
    public var grayscale: Bool
    public var edges: Bool
    public var simplify: Double
    public var cornerDegrees: Double

    public init(name: String, colors: Int, threshold: Int, grayscale: Bool, edges: Bool, simplify: Double, cornerDegrees: Double) {
        self.name = name
        self.colors = colors
        self.threshold = threshold
        self.grayscale = grayscale
        self.edges = edges
        self.simplify = simplify
        self.cornerDegrees = cornerDegrees
    }

    public static let highFidelityPhoto = TracePreset(name: "高保真照片", colors: 30, threshold: 128, grayscale: false, edges: false, simplify: 0.8, cornerDegrees: 40)
    public static let lowFidelityPhoto = TracePreset(name: "低保真照片", colors: 16, threshold: 128, grayscale: false, edges: false, simplify: 1.6, cornerDegrees: 50)
    public static let threeColors = TracePreset(name: "3 色", colors: 3, threshold: 128, grayscale: false, edges: false, simplify: 0.8, cornerDegrees: 45)
    public static let sixColors = TracePreset(name: "6 色", colors: 6, threshold: 128, grayscale: false, edges: false, simplify: 0.8, cornerDegrees: 45)
    public static let sixteenColors = TracePreset(name: "16 色", colors: 16, threshold: 128, grayscale: false, edges: false, simplify: 0.8, cornerDegrees: 45)
    public static let shadesOfGray = TracePreset(name: "灰度", colors: 6, threshold: 128, grayscale: true, edges: false, simplify: 0.8, cornerDegrees: 45)
    public static let blackAndWhiteLogo = TracePreset(name: "黑白徽标", colors: 2, threshold: 160, grayscale: true, edges: false, simplify: 0.6, cornerDegrees: 55)
    public static let sketch = TracePreset(name: "素描", colors: 2, threshold: 48, grayscale: true, edges: true, simplify: 0.7, cornerDegrees: 35)
    public static let silhouettes = TracePreset(name: "剪影", colors: 2, threshold: 200, grayscale: true, edges: false, simplify: 1.2, cornerDegrees: 50)
    public static let lineArt = TracePreset(name: "线条稿", colors: 2, threshold: 40, grayscale: true, edges: true, simplify: 0.5, cornerDegrees: 30)
    public static let technicalDrawing = TracePreset(name: "技术绘图", colors: 2, threshold: 24, grayscale: true, edges: true, simplify: 0.35, cornerDegrees: 25)
    public static let all: [TracePreset] = [highFidelityPhoto, lowFidelityPhoto, threeColors, sixColors, sixteenColors, shadesOfGray, blackAndWhiteLogo, sketch, silhouettes, lineArt, technicalDrawing]

    public static func named(_ name: String) -> TracePreset {
        all.first { $0.name == name || name.contains($0.name) } ?? blackAndWhiteLogo
    }
}

public enum ImageTrace {
    public static func trace(rgba: [UInt8], width: Int, height: Int, preset: TracePreset) -> [PathObject] {
        guard width > 1, height > 1, rgba.count >= width * height * 4 else { return [] }
        let samples = palette(rgba: rgba, width: width, height: height, preset: preset)
        if preset.edges {
            let mask = sobel(samples.luma, width: width, height: height, threshold: preset.threshold)
            return contours(mask: mask, width: width, height: height, preset: preset).map { ring in
                let path = fit(ring, preset: preset, closed: true)
                return PathObject(name: "描摹", path: path, appearance: Appearance(fill: nil, stroke: StrokeStyle(width: 1)))
            }
        }
        var objects: [PathObject] = []
        for (color, mask) in samples.masks {
            for ring in contours(mask: mask, width: width, height: height, preset: preset) where ring.count >= 4 {
                let path = fit(ring, preset: preset, closed: true)
                guard path.nodes.count >= 3 else { continue }
                objects.append(PathObject(name: "描摹", path: path, appearance: Appearance(fill: .solid(color), stroke: nil)))
            }
        }
        return objects
    }

    public static func trace(png: Data, preset: TracePreset) -> [PathObject] {
        guard let image = PNGCodec.decode(png) else { return [] }
        return trace(rgba: image.rgba, width: image.width, height: image.height, preset: preset)
    }

    private struct Samples {
        var luma: [UInt8]
        var masks: [(RGBA, [Bool])]
    }

    private static func palette(rgba: [UInt8], width: Int, height: Int, preset: TracePreset) -> Samples {
        let count = width * height
        var luma = [UInt8](repeating: 0, count: count)
        var colors = [RGBA](repeating: .black, count: count)
        for i in 0..<count {
            let o = i * 4
            let r = Int(rgba[o]), g = Int(rgba[o + 1]), b = Int(rgba[o + 2])
            let y = (2126 * r + 7152 * g + 722 * b) / 10000
            luma[i] = UInt8(max(0, min(255, y)))
            if preset.grayscale {
                let buckets = max(2, preset.colors)
                let step = 255 / (buckets - 1)
                let q = UInt8(((y + step / 2) / max(step, 1)) * step)
                colors[i] = RGBA(r: Double(q) / 255, g: Double(q) / 255, b: Double(q) / 255)
            } else if preset.colors <= 2 {
                let on = y < preset.threshold
                colors[i] = on ? .black : .white
            } else {
                let steps = max(2, Int(Double(preset.colors).squareRoot().rounded(.up)))
                func q(_ v: Int) -> Double {
                    let band = 255 / max(1, steps - 1)
                    return Double(((v + band / 2) / band) * band) / 255
                }
                colors[i] = RGBA(r: q(r), g: q(g), b: q(b))
            }
        }
        var order: [RGBA] = []
        var masks: [String: [Bool]] = [:]
        var lookup: [String: RGBA] = [:]
        for i in 0..<count {
            let key = colors[i].hex
            if masks[key] == nil {
                masks[key] = [Bool](repeating: false, count: count)
                order.append(colors[i])
                lookup[key] = colors[i]
            }
            masks[key]?[i] = true
        }
        let pairs = order.filter { $0.a > 0 && ($0.hex != "#FFFFFF" || preset.colors > 2) }.map { color in
            (color, masks[color.hex] ?? [])
        }
        return Samples(luma: luma, masks: pairs)
    }

    private static func sobel(_ luma: [UInt8], width: Int, height: Int, threshold: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: width * height)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                func at(_ dx: Int, _ dy: Int) -> Int { Int(luma[(y + dy) * width + (x + dx)]) }
                let gx = -at(-1, -1) + at(1, -1) - 2 * at(-1, 0) + 2 * at(1, 0) - at(-1, 1) + at(1, 1)
                let gy = -at(-1, -1) - 2 * at(0, -1) - at(1, -1) + at(-1, 1) + 2 * at(0, 1) + at(1, 1)
                mask[y * width + x] = gx * gx + gy * gy > threshold * threshold
            }
        }
        return mask
    }

    /// Crack-following contour. A filled pixel covers [x, x+1] × [y, y+1].
    private static func contours(mask: [Bool], width: Int, height: Int, preset: TracePreset) -> [[Vec2]] {
        func black(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x]
        }
        let dirs = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        func rightPixel(_ x: Int, _ y: Int, _ dir: Int) -> (Int, Int) {
            switch dir {
            case 0: return (x, y)
            case 1: return (x - 1, y)
            case 2: return (x - 1, y - 1)
            default: return (x, y - 1)
            }
        }
        func leftPixel(_ x: Int, _ y: Int, _ dir: Int) -> (Int, Int) {
            switch dir {
            case 0: return (x, y - 1)
            case 1: return (x, y)
            case 2: return (x - 1, y)
            default: return (x - 1, y - 1)
            }
        }
        func boundary(_ x: Int, _ y: Int, _ dir: Int) -> Bool {
            let r = rightPixel(x, y, dir)
            let l = leftPixel(x, y, dir)
            return black(r.0, r.1) && !black(l.0, l.1)
        }
        var used = Set<Int>()
        func key(_ x: Int, _ y: Int, _ dir: Int) -> Int { ((y + 1) * (width + 2) + (x + 1)) * 4 + dir }
        var rings: [[Vec2]] = []
        for y in 0..<height {
            for x in 0..<width where black(x, y) && !black(x, y - 1) {
                let startKey = key(x, y, 0)
                if used.contains(startKey) || !boundary(x, y, 0) { continue }
                var cx = x, cy = y, dir = 0
                var ring: [Vec2] = []
                var guardCount = 0
                repeat {
                    used.insert(key(cx, cy, dir))
                    ring.append(Vec2(Double(cx), Double(cy)))
                    cx += dirs[dir].0
                    cy += dirs[dir].1
                    var turned = dir
                    for turn in [1, 0, 3, 2] {
                        let nd = (dir + turn) % 4
                        if boundary(cx, cy, nd), !used.contains(key(cx, cy, nd)) || (cx == x && cy == y && nd == 0) {
                            turned = nd
                            break
                        }
                    }
                    dir = turned
                    guardCount += 1
                } while !(cx == x && cy == y && dir == 0) && guardCount < (width + height) * 8
                if ring.count >= 4 { rings.append(ring) }
            }
        }
        _ = preset
        return rings
    }

    private static func fit(_ ring: [Vec2], preset: TracePreset, closed: Bool) -> PathItem {
        let simplified = rdp(ring, tolerance: preset.simplify)
        let corners = cornerIndexes(simplified, degrees: preset.cornerDegrees, closed: closed)
        var nodes: [PathNode] = []
        if corners.count < 2 {
            nodes = simplified.map { .corner($0) }
        } else {
            for (index, corner) in corners.enumerated() {
                let next = corners[(index + 1) % corners.count]
                let run = slice(simplified, from: corner, to: next, closed: closed)
                guard let first = run.first else { continue }
                if nodes.isEmpty { nodes.append(.corner(first)) }
                if run.count <= 2 {
                    nodes.append(.corner(run.last ?? first))
                } else {
                    let end = run[run.count - 1]
                    let c1 = run[0] + (run[1] - run[0]) * 0.8
                    let c2 = end + (run[run.count - 2] - end) * 0.8
                    nodes[nodes.count - 1].outHandle = c1
                    var node = PathNode.corner(end)
                    node.inHandle = c2
                    node.corner = .smooth
                    nodes.append(node)
                }
                if !closed && index == corners.count - 2 { break }
                if closed && index == corners.count - 1 { break }
            }
        }
        if closed, nodes.count >= 2, let a = nodes.first?.anchor, let b = nodes.last?.anchor, a.almostEqual(b, eps: 0.05) {
            nodes.removeLast()
        }
        return PathItem(nodes: nodes, closed: closed, shape: .free)
    }

    private static func slice(_ points: [Vec2], from: Int, to: Int, closed: Bool) -> [Vec2] {
        if from == to { return [points[from]] }
        if from < to { return Array(points[from...to]) }
        if closed { return Array(points[from...]) + Array(points[0...to]) }
        return Array(points[from...])
    }

    private static func cornerIndexes(_ points: [Vec2], degrees: Double, closed: Bool) -> [Int] {
        guard points.count >= 3 else { return Array(points.indices) }
        var indexes = [0]
        let limit = degrees * .pi / 180
        let last = closed ? points.count : points.count - 1
        for i in 1..<last {
            let prev = points[(i - 1 + points.count) % points.count]
            let cur = points[i]
            let next = points[(i + 1) % points.count]
            let a = (prev - cur).normalized()
            let b = (next - cur).normalized()
            let dot = max(-1, min(1, a.x * b.x + a.y * b.y))
            let angle = acos(dot)
            if angle < .pi - limit { indexes.append(i) }
        }
        if !closed { indexes.append(points.count - 1) }
        else if indexes.count == 1 { indexes.append(points.count / 2) }
        return indexes
    }

    private static func rdp(_ points: [Vec2], tolerance: Double) -> [Vec2] {
        guard points.count > 3 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        func rec(_ a: Int, _ b: Int) {
            var maxD = 0.0
            var idx = -1
            for i in (a + 1)..<b {
                let d = Math2.pointSegmentDistance(points[i], points[a], points[b])
                if d > maxD { maxD = d; idx = i }
            }
            if idx >= 0 && maxD > tolerance {
                keep[idx] = true
                rec(a, idx)
                rec(idx, b)
            }
        }
        rec(0, points.count - 1)
        return points.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }
}
