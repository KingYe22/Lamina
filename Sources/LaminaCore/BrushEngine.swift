import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct BrushPreset: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var brush: BrushDefinition

    public init(id: UUID = UUID(), name: String, brush: BrushDefinition) {
        self.id = id
        self.name = name
        self.brush = brush
    }
}

public enum BrushLibrary {
    public static let defaults: [BrushPreset] = [
        BrushPreset(name: "书法 3 pt", brush: .calligraphic(angle: .pi / 4, roundness: 0.35, diameter: 3)),
        BrushPreset(name: "书法 压感", brush: .calligraphic(CalligraphicBrush(
            angle: BrushVariation(source: .bearing, minimum: 0, maximum: .pi),
            roundness: .fixed(0.3),
            diameter: BrushVariation(source: .pressure, minimum: 1, maximum: 14)
        ))),
        BrushPreset(name: "散点", brush: .scatter(ScatterBrush(
            size: BrushVariation(source: .random, minimum: 4, maximum: 10),
            spacing: .fixed(18),
            scatter: BrushVariation(source: .random, minimum: -8, maximum: 8),
            rotation: BrushVariation(source: .random, minimum: 0, maximum: .pi),
            colorization: .tints,
            artwork: BrushArtwork.star(radius: 6)
        ))),
        BrushPreset(name: "艺术画笔", brush: .art(ArtBrush(width: 10, fit: .stretchToFit, adjustCorners: true, artwork: BrushArtwork.taper))),
        BrushPreset(name: "图案画笔", brush: .pattern(PatternBrush(side: BrushArtwork.tile(12), fit: .stretchToFit, autoCorners: true))),
        BrushPreset(name: "毛刷", brush: .bristle(BristleBrush(shape: .roundPoint, size: 14, density: 0.55, thickness: 0.35, paintOpacity: 0.75, stiffness: 0.4)))
    ]
}

public enum BrushColor {
    public static func apply(_ method: BrushColorization, artwork: RGBA, stroke: RGBA) -> RGBA {
        switch method {
        case .none:
            return artwork
        case .tints:
            let shade = 1 - (0.2126 * artwork.r + 0.7152 * artwork.g + 0.0722 * artwork.b)
            return RGBA(r: Math2.lerp(1, stroke.r, shade), g: Math2.lerp(1, stroke.g, shade), b: Math2.lerp(1, stroke.b, shade), a: artwork.a * stroke.a)
        case .tintsAndShades:
            let luma = 0.2126 * artwork.r + 0.7152 * artwork.g + 0.0722 * artwork.b
            if luma >= 0.5 {
                let t = (luma - 0.5) * 2
                return RGBA(r: Math2.lerp(stroke.r, 1, t), g: Math2.lerp(stroke.g, 1, t), b: Math2.lerp(stroke.b, 1, t), a: artwork.a)
            }
            let t = luma * 2
            return RGBA(r: stroke.r * t, g: stroke.g * t, b: stroke.b * t, a: artwork.a)
        case .hueShift:
            var sH = 0.0, sS = 0.0, sB = 0.0
            var aH = 0.0, aS = 0.0, aB = 0.0
            rgbToHSB(stroke, h: &sH, s: &sS, b: &sB)
            rgbToHSB(artwork, h: &aH, s: &aS, b: &aB)
            return hsbToRGB(sH, aS, aB, artwork.a)
        }
    }

    private static func rgbToHSB(_ c: RGBA, h: inout Double, s: inout Double, b: inout Double) {
        let maxV = max(c.r, max(c.g, c.b))
        let minV = min(c.r, min(c.g, c.b))
        b = maxV
        let d = maxV - minV
        s = maxV <= 0.0001 ? 0 : d / maxV
        if d <= 0.0001 { h = 0; return }
        if maxV == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
        else if maxV == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h /= 6
        if h < 0 { h += 1 }
    }

    private static func hsbToRGB(_ h: Double, _ s: Double, _ b: Double, _ a: Double) -> RGBA {
        let hue = h * 6
        let i = Int(hue) % 6
        let f = hue - Double(Int(hue))
        let p = b * (1 - s)
        let q = b * (1 - f * s)
        let t = b * (1 - (1 - f) * s)
        switch i {
        case 0: return RGBA(r: b, g: t, b: p, a: a)
        case 1: return RGBA(r: q, g: b, b: p, a: a)
        case 2: return RGBA(r: p, g: b, b: t, a: a)
        case 3: return RGBA(r: p, g: q, b: b, a: a)
        case 4: return RGBA(r: t, g: p, b: b, a: a)
        default: return RGBA(r: b, g: p, b: q, a: a)
        }
    }
}

enum BrushVary {
    static func resolve(_ variation: BrushVariation, t: Double, stylus: StrokeSample, seed: Double) -> Double {
        let u: Double
        switch variation.source {
        case .fixed: return variation.minimum
        case .random:
            u = hashUnit(seed + t * 12.9898)
        case .pressure: u = stylus.pressure
        case .stylusWheel: u = stylus.wheel
        case .tilt: u = stylus.tilt
        case .bearing:
            return variation.minimum + stylus.bearing
        case .rotation:
            return variation.minimum + stylus.rotation
        }
        return Math2.lerp(variation.minimum, variation.maximum, min(1, max(0, u)))
    }

    private static func hashUnit(_ x: Double) -> Double {
        let s = sin(x * 78.233) * 43758.5453
        return s - s.rounded(.down)
    }
}

struct SpineSample {
    var point: Vec2
    var tangent: Vec2
    var normal: Vec2
    var t: Double
    var distance: Double
    var stylus: StrokeSample
}

enum Spine {
    static func samples(path: PathItem, stroke: StrokeStyle, step: Double) -> [SpineSample] {
        let flat = Bezier.flatten(path, tolerance: 0.6)
        guard flat.count >= 2 else { return [] }
        var lengths = [0.0]
        for i in 1..<flat.count { lengths.append(lengths[i - 1] + flat[i].distance(to: flat[i - 1])) }
        let total = max(lengths.last ?? 0, 0.001)
        var out: [SpineSample] = []
        var cursor = 0.0
        while cursor <= total + 0.001 {
            let point = pointAt(flat, lengths, cursor)
            let ahead = pointAt(flat, lengths, min(total, cursor + 0.8))
            let behind = pointAt(flat, lengths, max(0, cursor - 0.8))
            var tangent = (ahead - behind)
            if tangent.length < 1e-6 { tangent = Vec2(1, 0) }
            tangent = tangent.normalized()
            let stylus = stylusAt(stroke.samples, flat, lengths, cursor, total)
            out.append(SpineSample(point: point, tangent: tangent, normal: Vec2(-tangent.y, tangent.x), t: cursor / total, distance: cursor, stylus: stylus))
            if cursor >= total { break }
            cursor = min(total, cursor + max(0.4, step))
        }
        return out
    }

    private static func pointAt(_ flat: [Vec2], _ lengths: [Double], _ distance: Double) -> Vec2 {
        guard let last = lengths.last else { return flat[0] }
        if distance <= 0 { return flat[0] }
        if distance >= last { return flat[flat.count - 1] }
        var i = 1
        while i < lengths.count && lengths[i] < distance { i += 1 }
        let span = max(0.0001, lengths[i] - lengths[i - 1])
        let u = (distance - lengths[i - 1]) / span
        return flat[i - 1] + (flat[i] - flat[i - 1]) * u
    }

    private static func stylusAt(_ samples: [StrokeSample], _ flat: [Vec2], _ lengths: [Double], _ distance: Double, _ total: Double) -> StrokeSample {
        guard !samples.isEmpty else {
            return StrokeSample(point: pointAt(flat, lengths, distance), pressure: 1, tilt: 0, bearing: 0, rotation: 0, wheel: 0.5)
        }
        let t = distance / total
        if samples.count == 1 { return samples[0] }
        let index = t * Double(samples.count - 1)
        let i = min(samples.count - 2, max(0, Int(index)))
        let u = index - Double(i)
        let a = samples[i], b = samples[i + 1]
        return StrokeSample(
            point: pointAt(flat, lengths, distance),
            pressure: Math2.lerp(a.pressure, b.pressure, u),
            tilt: Math2.lerp(a.tilt, b.tilt, u),
            bearing: Math2.lerp(a.bearing, b.bearing, u),
            rotation: Math2.lerp(a.rotation, b.rotation, u),
            wheel: Math2.lerp(a.wheel, b.wheel, u)
        )
    }
}

public enum BrushEngine {
    public static func expand(path: PathItem, stroke: StrokeStyle) -> [ArtItem] {
        guard let brush = stroke.brush else { return [] }
        let tint = stroke.paint.solidColor ?? .black
        switch brush {
        case .calligraphic(let brush):
            return calligraphic(path, stroke: stroke, brush: brush, tint: tint)
        case .scatter(let brush):
            return scatter(path, stroke: stroke, brush: brush, tint: tint)
        case .art(let brush):
            return art(path, stroke: stroke, brush: brush, tint: tint)
        case .pattern(let brush):
            return pattern(path, stroke: stroke, brush: brush, tint: tint)
        case .bristle(let brush):
            return bristleStrokes(path, stroke: stroke, brush: brush, tint: tint)
        }
    }

    public static func bristlePreview(path: PathItem, stroke: StrokeStyle, brush: BristleBrush) -> PNGImage? {
        let tint = stroke.paint.solidColor ?? .black
        let hairs = bristleTips(path, stroke: stroke, brush: brush)
        guard !hairs.isEmpty else { return nil }
        var minX = Double.greatestFiniteMagnitude, minY = minX, maxX = -minX, maxY = -minY
        for hair in hairs {
            for p in hair {
                minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
        }
        let pad = brush.size
        minX -= pad; minY -= pad; maxX += pad; maxY += pad
        let width = max(1, Int(maxX - minX))
        let height = max(1, Int(maxY - minY))
        if width * height > 1_200_000 { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let radius = max(0.6, brush.size * brush.thickness * 0.35)
        let ink = min(1, brush.paintOpacity)
        for hair in hairs {
            for point in hair {
                splat(&rgba, width: width, height: height, origin: Vec2(minX, minY), at: point, radius: radius, color: tint, opacity: ink * 0.45)
            }
        }
        return PNGImage(width: width, height: height, rgba: rgba)
    }

    private static func calligraphic(_ path: PathItem, stroke: StrokeStyle, brush: CalligraphicBrush, tint: RGBA) -> [ArtItem] {
        let spine = Spine.samples(path: path, stroke: stroke, step: 1.2)
        guard spine.count >= 2 else { return [] }
        var left: [Vec2] = []
        var right: [Vec2] = []
        for sample in spine {
            let diameter = max(0.2, BrushVary.resolve(brush.diameter, t: sample.t, stylus: sample.stylus, seed: 1))
            let roundness = min(1, max(0.05, BrushVary.resolve(brush.roundness, t: sample.t, stylus: sample.stylus, seed: 2)))
            let angle = BrushVary.resolve(brush.angle, t: sample.t, stylus: sample.stylus, seed: 3)
            let rx = diameter / 2
            let ry = rx * roundness
            let leftDir = sample.normal
            let rightDir = sample.normal * -1
            left.append(sample.point + leftDir * ellipseSupport(leftDir, rx: rx, ry: ry, angle: angle))
            right.append(sample.point + rightDir * ellipseSupport(rightDir, rx: rx, ry: ry, angle: angle))
        }
        var ring = left
        ring.append(contentsOf: right.reversed())
        let outline = PathItem(nodes: ring.map { .corner($0) }, closed: true, shape: .free)
        return [.path(PathObject(name: "书法", path: outline, appearance: Appearance(fill: .solid(tint), stroke: nil)))]
    }

    /// Support of a rotated ellipse in a unit direction, returned as a scalar distance.
    private static func ellipseSupport(_ direction: Vec2, rx: Double, ry: Double, angle: Double) -> Double {
        let local = direction.rotated(by: -angle)
        return hypot(rx * local.x, ry * local.y)
    }

    private static func scatter(_ path: PathItem, stroke: StrokeStyle, brush: ScatterBrush, tint: RGBA) -> [ArtItem] {
        let spine = Spine.samples(path: path, stroke: stroke, step: 2)
        guard let first = spine.first else { return [] }
        var items: [ArtItem] = []
        var next = 0.0
        var index = 0
        for sample in spine {
            let spacing = max(1, BrushVary.resolve(brush.spacing, t: sample.t, stylus: sample.stylus, seed: 4 + Double(index)))
            if sample.distance + 0.01 < next && sample.distance > 0 { continue }
            next = sample.distance + spacing
            let size = max(0.4, BrushVary.resolve(brush.size, t: sample.t, stylus: sample.stylus, seed: 8 + Double(index)))
            let scatter = BrushVary.resolve(brush.scatter, t: sample.t, stylus: sample.stylus, seed: 12 + Double(index))
            var rotation = BrushVary.resolve(brush.rotation, t: sample.t, stylus: sample.stylus, seed: 16 + Double(index))
            if brush.rotationRelativeToPath { rotation += atan2(sample.tangent.y, sample.tangent.x) }
            let center = sample.point + sample.normal * scatter
            let box = Bezier.bounds(brush.artwork)
            let base = max(1, max(box.width, box.height))
            let scale = size / base
            let spin = Affine.rotation(rotation, around: .zero)
            var nodes = brush.artwork.nodes.map { node -> PathNode in
                var copy = node
                copy.anchor = spin.apply((node.anchor - box.center) * scale) + center
                if let h = node.inHandle { copy.inHandle = spin.apply((h - box.center) * scale) + center }
                if let h = node.outHandle { copy.outHandle = spin.apply((h - box.center) * scale) + center }
                return copy
            }
            let painted = BrushColor.apply(brush.colorization, artwork: .black, stroke: tint)
            items.append(.path(PathObject(name: "散点", path: PathItem(nodes: nodes, closed: true, shape: .free), appearance: Appearance(fill: .solid(painted), stroke: nil))))
            index += 1
            if sample.point.distance(to: first.point) > 1e9 { break }
        }
        return items
    }

    private static func art(_ path: PathItem, stroke: StrokeStyle, brush: ArtBrush, tint: RGBA) -> [ArtItem] {
        let flat = Bezier.flatten(path, tolerance: 0.7)
        guard flat.count >= 2 else { return [] }
        let artBox = Bezier.bounds(brush.artwork)
        let artW = max(0.001, artBox.width)
        let artH = max(0.001, artBox.height)
        var length = 0.0
        var lengths = [0.0]
        for i in 1..<flat.count {
            length += flat[i].distance(to: flat[i - 1])
            lengths.append(length)
        }
        let usable = usableLength(brush, artW: artW, artH: artH, pathLength: length)
        let outline = brush.artwork.nodes.map(\.anchor)
        var mapped: [Vec2] = []
        for point in outline {
            var u = (point.x - artBox.minX) / artW
            var v = (point.y - artBox.midY) / artH
            if brush.flipAlong { u = 1 - u }
            if brush.flipAcross { v = -v }
            let distance = mapU(u, fit: brush.fit, start: brush.startGuide, end: brush.endGuide, pathLength: length, usable: usable, artLength: artW * (brush.width / artH))
            let on = pointAlong(flat, lengths, min(length, max(0, distance)))
            let ahead = pointAlong(flat, lengths, min(length, distance + 0.5))
            let behind = pointAlong(flat, lengths, max(0, distance - 0.5))
            var tangent = ahead - behind
            if tangent.length < 1e-6 { tangent = Vec2(1, 0) }
            tangent = tangent.normalized()
            let normal = Vec2(-tangent.y, tangent.x)
            mapped.append(on + normal * v * brush.width)
        }
        let ring = brush.adjustCorners ? miter(mapped) : mapped
        let painted = BrushColor.apply(brush.colorization, artwork: .black, stroke: tint)
        return [.path(PathObject(name: "艺术画笔", path: PathItem(nodes: ring.map { .corner($0) }, closed: true, shape: .free), appearance: Appearance(fill: .solid(painted), stroke: nil)))]
    }

    private static func usableLength(_ brush: ArtBrush, artW: Double, artH: Double, pathLength: Double) -> Double {
        switch brush.fit {
        case .stretchToFit, .betweenGuides: return pathLength
        case .proportional: return min(pathLength, artW * (brush.width / artH))
        }
    }

    private static func mapU(_ u: Double, fit: ArtBrushFit, start: Double, end: Double, pathLength: Double, usable: Double, artLength: Double) -> Double {
        switch fit {
        case .stretchToFit:
            return u * usable
        case .proportional:
            return u * artLength
        case .betweenGuides:
            // Head and tail keep their scaled artwork length. The span between guides stretches over the path that is left.
            let a = min(max(0, start), 1)
            let b = min(max(a + 0.001, end), 1)
            let head = a * artLength
            let tail = (1 - b) * artLength
            if head + tail >= pathLength - 0.5 { return u * pathLength }
            let middle = pathLength - head - tail
            if u <= a { return a <= 1e-6 ? 0 : (u / a) * head }
            if u >= b {
                let tailSpan = max(1e-6, 1 - b)
                return pathLength - tail + ((u - b) / tailSpan) * tail
            }
            return head + ((u - a) / max(1e-6, b - a)) * middle
        }
    }

    private static func pointAlong(_ flat: [Vec2], _ lengths: [Double], _ distance: Double) -> Vec2 {
        guard let last = lengths.last, flat.count >= 2 else { return flat.first ?? .zero }
        if distance <= 0 { return flat[0] }
        if distance >= last { return flat[flat.count - 1] }
        var i = 1
        while i < lengths.count && lengths[i] < distance { i += 1 }
        let span = max(0.0001, lengths[i] - lengths[i - 1])
        let u = (distance - lengths[i - 1]) / span
        return flat[i - 1] + (flat[i] - flat[i - 1]) * u
    }

    private static func miter(_ points: [Vec2]) -> [Vec2] {
        guard points.count >= 3 else { return points }
        var out: [Vec2] = []
        for i in points.indices {
            let prev = points[(i + points.count - 1) % points.count]
            let cur = points[i]
            let next = points[(i + 1) % points.count]
            let a = (cur - prev).normalized()
            let b = (next - cur).normalized()
            let turn = atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
            if abs(turn) > 0.6 {
                let bis = (a + b)
                let inset = bis.length < 1e-4 ? cur : cur + bis.normalized() * min(6, abs(turn) * 2)
                out.append(inset)
            } else {
                out.append(cur)
            }
        }
        return out
    }

    private static func pattern(_ path: PathItem, stroke: StrokeStyle, brush: PatternBrush, tint: RGBA) -> [ArtItem] {
        let flat = Bezier.flatten(path, tolerance: 0.8)
        guard flat.count >= 2 else { return [] }
        var length = 0.0
        var lengths = [0.0]
        for i in 1..<flat.count {
            length += flat[i].distance(to: flat[i - 1])
            lengths.append(length)
        }
        let tileBox = Bezier.bounds(brush.side)
        let natural = max(2, tileBox.width)
        let count: Int
        let tileLength: Double
        let gap: Double
        switch brush.fit {
        case .stretchToFit:
            count = max(1, Int((length / natural).rounded()))
            tileLength = length / Double(count)
            gap = 0
        case .addSpace:
            count = max(1, Int(length / natural))
            tileLength = natural
            gap = max(0, (length - Double(count) * natural) / Double(count))
        case .approximatePath:
            count = max(1, Int((length / natural).rounded()))
            tileLength = natural
            gap = 0
        }
        let painted = BrushColor.apply(brush.colorization, artwork: .black, stroke: tint)
        var items: [ArtItem] = []
        var cursor = 0.0
        if let start = brush.start {
            items.append(placeTile(start, at: 0, length: Bezier.bounds(start).width, flat: flat, lengths: lengths, tint: painted, flipAlong: brush.flipAlong, flipAcross: brush.flipAcross, name: "起点"))
            cursor += max(2, Bezier.bounds(start).width)
        }
        var placed = 0
        while placed < count && cursor < length - 0.5 {
            let turn = turnAt(flat, lengths, cursor + tileLength * 0.5)
            let tile: PathItem
            let name: String
            if abs(turn) > 0.45 {
                if turn > 0 {
                    tile = brush.outerCorner ?? (brush.autoCorners ? brush.side : brush.side)
                    name = "外角"
                } else {
                    tile = brush.innerCorner ?? (brush.autoCorners ? brush.side : brush.side)
                    name = "内角"
                }
            } else {
                tile = brush.side
                name = "边"
            }
            items.append(placeTile(tile, at: cursor, length: tileLength, flat: flat, lengths: lengths, tint: painted, flipAlong: brush.flipAlong, flipAcross: brush.flipAcross, name: name, spin: brush.autoCorners && abs(turn) > 0.45 ? turn / 2 : 0))
            cursor += tileLength + gap + brush.spacing
            placed += 1
        }
        if let end = brush.end {
            items.append(placeTile(end, at: max(0, length - Bezier.bounds(end).width), length: Bezier.bounds(end).width, flat: flat, lengths: lengths, tint: painted, flipAlong: brush.flipAlong, flipAcross: brush.flipAcross, name: "终点"))
        }
        return items
    }

    private static func turnAt(_ flat: [Vec2], _ lengths: [Double], _ distance: Double) -> Double {
        let a = pointAlong(flat, lengths, max(0, distance - 4))
        let b = pointAlong(flat, lengths, distance)
        let c = pointAlong(flat, lengths, distance + 4)
        let u = (b - a).normalized()
        let v = (c - b).normalized()
        return atan2(u.x * v.y - u.y * v.x, max(-1, min(1, u.x * v.x + u.y * v.y)))
    }

    private static func placeTile(_ tile: PathItem, at distance: Double, length: Double, flat: [Vec2], lengths: [Double], tint: RGBA, flipAlong: Bool, flipAcross: Bool, name: String, spin: Double = 0) -> ArtItem {
        let box = Bezier.bounds(tile)
        let origin = pointAlong(flat, lengths, distance)
        let ahead = pointAlong(flat, lengths, distance + max(0.5, length))
        var tangent = ahead - origin
        if tangent.length < 1e-6 { tangent = Vec2(1, 0) }
        tangent = tangent.normalized().rotated(by: spin)
        let normal = Vec2(-tangent.y, tangent.x)
        let scaleX = length / max(0.001, box.width)
        let scaleY = scaleX
        let nodes = tile.nodes.map { node -> PathNode in
            var u = (node.anchor.x - box.minX) / max(0.001, box.width)
            var v = (node.anchor.y - box.midY) / max(0.001, box.height)
            if flipAlong { u = 1 - u }
            if flipAcross { v = -v }
            let p = origin + tangent * (u * length) + normal * (v * box.height * scaleY / max(0.001, scaleX) * 0.5)
            return .corner(p)
        }
        return .path(PathObject(name: name, path: PathItem(nodes: nodes, closed: true, shape: .free), appearance: Appearance(fill: .solid(tint), stroke: nil)))
    }

    private static func bristleStrokes(_ path: PathItem, stroke: StrokeStyle, brush: BristleBrush, tint: RGBA) -> [ArtItem] {
        bristleTips(path, stroke: stroke, brush: brush).map { hair in
            let path = PathItem(nodes: hair.map { .corner($0) }, closed: false, shape: .free)
            let width = max(0.2, brush.size * brush.thickness * 0.25)
            var style = StrokeStyle(paint: .solid(RGBA(r: tint.r, g: tint.g, b: tint.b, a: tint.a * brush.paintOpacity)), width: width)
            style.cap = .round
            return .path(PathObject(name: "毛刷", path: path, appearance: Appearance(fill: nil, stroke: style)))
        }
    }

    private static func bristleTips(_ path: PathItem, stroke: StrokeStyle, brush: BristleBrush) -> [[Vec2]] {
        let spine = Spine.samples(path: path, stroke: stroke, step: max(1, brush.size * 0.15))
        guard spine.count >= 2 else { return [] }
        let count = max(1, Int((8 + brush.density * 40).rounded()))
        let roots = crossSection(brush, count: count)
        var hairs = Array(repeating: [Vec2](), count: roots.count)
        var tips = roots.map { $0 * brush.size * 0.5 }
        let follow = 1 - min(0.95, max(0, brush.stiffness))
        for sample in spine {
            let frame = Affine.rotation(atan2(sample.tangent.y, sample.tangent.x), around: .zero)
            for i in roots.indices {
                let target = frame.apply(roots[i] * brush.size * 0.5)
                tips[i] = tips[i] + (target - tips[i]) * follow
                hairs[i].append(sample.point + tips[i])
            }
        }
        return hairs
    }

    private static func crossSection(_ brush: BristleBrush, count: Int) -> [Vec2] {
        (0..<count).map { index in
            let u = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let x = u * 2 - 1
            switch brush.shape {
            case .roundPoint:
                let y = (1 - x * x) * (index.isMultiple(of: 2) ? 0.35 : -0.35)
                return Vec2(x * 0.45, y)
            case .roundBlunt:
                return Vec2(cos(u * .pi * 2) * 0.5, sin(u * .pi * 2) * 0.5)
            case .roundCurve:
                return Vec2(x * 0.5, sin(u * .pi) * 0.25 - 0.1)
            case .flatPoint:
                return Vec2(x * 0.7, (1 - abs(x)) * 0.15 * (index.isMultiple(of: 2) ? 1 : -1))
            case .flatBlunt:
                return Vec2(x * 0.75, index.isMultiple(of: 2) ? 0.12 : -0.12)
            case .flatCurve:
                return Vec2(x * 0.7, sin(u * .pi) * 0.2)
            case .fan:
                let ang = Math2.lerp(-0.8, 0.8, u)
                return Vec2(sin(ang) * 0.7, -cos(ang) * 0.35)
            }
        }
    }

    private static func splat(_ rgba: inout [UInt8], width: Int, height: Int, origin: Vec2, at: Vec2, radius: Double, color: RGBA, opacity: Double) {
        let cx = Int(at.x - origin.x)
        let cy = Int(at.y - origin.y)
        let r = max(1, Int(radius.rounded(.up)))
        for y in (cy - r)...(cy + r) {
            guard y >= 0, y < height else { continue }
            for x in (cx - r)...(cx + r) {
                guard x >= 0, x < width else { continue }
                let dx = Double(x - cx), dy = Double(y - cy)
                let d = hypot(dx, dy) / radius
                if d > 1 { continue }
                let add = opacity * (1 - d)
                let i = (y * width + x) * 4
                let existing = Double(rgba[i + 3]) / 255
                let alpha = min(1, existing + add * (1 - existing))
                rgba[i] = UInt8(min(255, color.r * 255))
                rgba[i + 1] = UInt8(min(255, color.g * 255))
                rgba[i + 2] = UInt8(min(255, color.b * 255))
                rgba[i + 3] = UInt8(min(255, alpha * 255))
            }
        }
    }
}

public enum FreehandFit {
    /// Fidelity is the Illustrator tolerance in points (0.5 follows the pointer, 20 smooths hard).
    public static func fit(_ points: [Vec2], fidelity: Double, smoothness: Double, closed: Bool) -> PathItem {
        guard points.count >= 2 else {
            return PathItem(nodes: points.map { .corner($0) }, closed: false, shape: .free)
        }
        let simplified = rdp(points, tolerance: max(0.2, fidelity))
        var nodes = simplified.map { PathNode.corner($0) }
        if smoothness > 0.01, nodes.count >= 3 {
            let gain = min(1, smoothness) * 0.35
            for i in nodes.indices {
                if !closed && (i == 0 || i == nodes.count - 1) { continue }
                let prev = nodes[(i + nodes.count - 1) % nodes.count].anchor
                let next = nodes[(i + 1) % nodes.count].anchor
                let delta = (next - prev) * gain
                nodes[i].inHandle = nodes[i].anchor - delta
                nodes[i].outHandle = nodes[i].anchor + delta
                nodes[i].corner = .smooth
            }
        }
        return PathItem(nodes: nodes, closed: closed, shape: .free)
    }

    private static func rdp(_ points: [Vec2], tolerance: Double) -> [Vec2] {
        guard points.count > 2 else { return points }
        var maxD = 0.0
        var index = 0
        let a = points[0], b = points[points.count - 1]
        for i in 1..<(points.count - 1) {
            let d = Math2.pointSegmentDistance(points[i], a, b)
            if d > maxD { maxD = d; index = i }
        }
        if maxD > tolerance {
            let left = rdp(Array(points[0...index]), tolerance: tolerance)
            let right = rdp(Array(points[index...]), tolerance: tolerance)
            return left.dropLast() + right
        }
        return [a, b]
    }
}
