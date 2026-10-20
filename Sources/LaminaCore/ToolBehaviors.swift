import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum PenCursor: String, Equatable, Sendable {
    case pen, close, continuePath, add, delete, join, convert
}

public enum WarpToolKind: String, CaseIterable, Equatable, Sendable {
    case warp, twirl, pucker, bloat, scallop, crystallize, wrinkle

    public var title: String {
        switch self {
        case .warp: return "变形"
        case .twirl: return "扭转"
        case .pucker: return "收缩"
        case .bloat: return "膨胀"
        case .scallop: return "扇贝"
        case .crystallize: return "晶格化"
        case .wrinkle: return "皱褶"
        }
    }
}

public enum SymbolToolKind: String, CaseIterable, Equatable, Sendable {
    case sprayer, shifter, scruncher, sizer, spinner, stainer, screener, styler

    public var title: String {
        switch self {
        case .sprayer: return "符号喷枪"
        case .shifter: return "符号移位器"
        case .scruncher: return "符号紧缩器"
        case .sizer: return "符号缩放器"
        case .spinner: return "符号旋转器"
        case .stainer: return "符号着色器"
        case .screener: return "符号滤色器"
        case .styler: return "符号样式器"
        }
    }
}

public struct MeasureReading: Equatable, Sendable {
    public var distance: Double
    public var dx: Double
    public var dy: Double
    public var angle: Double

    public init(distance: Double, dx: Double, dy: Double, angle: Double) {
        self.distance = distance
        self.dx = dx
        self.dy = dy
        self.angle = angle
    }
}

public enum ToolBehaviors {
    public static func constrain45(_ point: Vec2, from origin: Vec2) -> Vec2 {
        let delta = point - origin
        let length = delta.length
        if length < 1e-9 { return point }
        let step = Double.pi / 4
        let angle = atan2(delta.y, delta.x)
        let snapped = (angle / step).rounded() * step
        return origin + Vec2(cos(snapped), sin(snapped)) * length
    }

    public static func snap(_ point: Vec2, anchors: [Vec2], guides: [Guide], grid: Double?, tolerance: Double) -> Vec2 {
        var best = point
        var score = tolerance
        if let grid, grid > 0.1 {
            let g = Vec2((point.x / grid).rounded() * grid, (point.y / grid).rounded() * grid)
            if g.distance(to: point) <= tolerance { best = g; score = g.distance(to: point) }
        }
        for anchor in anchors where anchor.distance(to: point) < score {
            score = anchor.distance(to: point)
            best = anchor
        }
        for guide in guides {
            switch guide.axis {
            case .vertical where abs(point.x - guide.position) < score:
                score = abs(point.x - guide.position)
                best.x = guide.position
            case .horizontal where abs(point.y - guide.position) < score:
                score = abs(point.y - guide.position)
                best.y = guide.position
            default:
                break
            }
        }
        return best
    }

    public static func penCursor(nodes: [PathNode], hover: Vec2, zoom: Double, nearAnchor: Bool, nearSegment: Bool, nearForeignEnd: Bool) -> PenCursor {
        let slop = 8 / max(zoom, 0.05)
        if let first = nodes.first, nodes.count >= 3, first.anchor.distance(to: hover) <= slop { return .close }
        if nearForeignEnd, nodes.count >= 2 { return .join }
        if nodes.isEmpty, nearForeignEnd { return .continuePath }
        if nodes.isEmpty, nearAnchor { return .delete }
        if nodes.isEmpty, nearSegment { return .add }
        return .pen
    }

    public static func placeHandle(anchor: Vec2, drag: Vec2, shift: Bool, option: Bool) -> (inHandle: Vec2?, outHandle: Vec2?) {
        let tip = shift ? constrain45(drag, from: anchor) : drag
        if option { return (nil, tip) }
        return (Vec2(anchor.x * 2 - tip.x, anchor.y * 2 - tip.y), tip)
    }

    public static func moveAnchor(_ node: PathNode, by delta: Vec2) -> PathNode {
        var copy = node
        copy.anchor += delta
        if let h = copy.inHandle { copy.inHandle = h + delta }
        if let h = copy.outHandle { copy.outHandle = h + delta }
        return copy
    }

    /// Click on a smooth point clears both handles. Dragging a corner pulls a symmetric pair. Dragging one handle leaves the other where it was.
    public static func convert(node: PathNode, drag: Vec2?, breakHandle: Bool) -> PathNode {
        var copy = node
        guard let drag else {
            if copy.outHandle != nil || copy.inHandle != nil || copy.corner == .smooth {
                copy.inHandle = nil
                copy.outHandle = nil
                copy.corner = .corner
            } else {
                copy.inHandle = copy.anchor - Vec2(18, 0)
                copy.outHandle = copy.anchor + Vec2(18, 0)
                copy.corner = .smooth
            }
            return copy
        }
        if breakHandle {
            copy.outHandle = drag
            copy.corner = .corner
            return copy
        }
        copy.outHandle = drag
        copy.inHandle = Vec2(copy.anchor.x * 2 - drag.x, copy.anchor.y * 2 - drag.y)
        copy.corner = .smooth
        return copy
    }

    public static func curvature(_ nodes: [PathNode], toggle index: Int?) -> [PathNode] {
        var copy = nodes
        if let index, copy.indices.contains(index) {
            if copy[index].corner == .smooth {
                copy[index].corner = .corner
                copy[index].inHandle = nil
                copy[index].outHandle = nil
                return copy
            }
        }
        return Bezier.smooth(copy, closed: false)
    }

    public static func rubber(from node: PathNode, to hover: Vec2) -> [Vec2] {
        let flat = Bezier.flatten(PathItem(nodes: [node, .corner(hover)], closed: false), tolerance: 0.8)
        return flat
    }

    public static func scissors(_ path: PathItem, segment: Int, t: Double) -> [PathItem] {
        let split = Bezier.split(path, segment: segment, t: t)
        guard split.nodes.count >= 2 else { return [path] }
        if !path.closed {
            let cut = min(split.nodes.count - 1, segment + 1)
            let head = PathItem(nodes: Array(split.nodes[0...cut]), closed: false, shape: .free)
            let tail = PathItem(nodes: Array(split.nodes[cut...]), closed: false, shape: .free)
            return [head, tail].filter { $0.nodes.count >= 2 }
        }
        var open = split
        open.closed = false
        open.shape = .free
        if let first = open.nodes.first {
            let rotated = Array(open.nodes.dropFirst()) + [first]
            return [PathItem(nodes: rotated, closed: false, shape: .free)]
        }
        return [open]
    }

    public static func knife(_ path: PathItem, stroke: [Vec2]) -> [PathItem] {
        let flat = Bezier.flatten(path, tolerance: 0.8)
        guard flat.count >= 2, stroke.count >= 2 else { return [path] }
        var hits: [(index: Int, t: Double, point: Vec2)] = []
        for i in 0..<(flat.count - 1) {
            for j in 0..<(stroke.count - 1) {
                if let hit = segmentCross(flat[i], flat[i + 1], stroke[j], stroke[j + 1]) {
                    hits.append((i, hit.t, hit.point))
                }
            }
        }
        let unique = dedupeHits(hits)
        guard unique.count >= 2 else { return [path] }
        let a = unique[0], b = unique[1]
        let forward = chain(flat, from: a, to: b)
        let back = chain(flat, from: b, to: a)
        return [forward, back].filter { $0.nodes.count >= 2 }
    }

    public static func eraserRibbon(_ stroke: [Vec2], diameter: Double) -> [Vec2] {
        guard let first = stroke.first, let last = stroke.last, stroke.count >= 2 else { return [] }
        var direction = last - first
        if direction.length < 1e-6 { return [] }
        direction = direction.normalized()
        let normal = Vec2(-direction.y, direction.x) * (diameter / 2)
        let pad = direction * (diameter / 2)
        return [first - pad + normal, last + pad + normal, last + pad - normal, first - pad - normal]
    }

    public static func erase(_ subject: [Vec2], ribbon: [Vec2]) -> [[Vec2]] {
        guard subject.count >= 3, ribbon.count >= 3 else { return subject.count >= 3 ? [subject] : [] }
        let parts = Pathfinder.apply(.minusFront, subject: subject, clip: ribbon)
        return parts.isEmpty ? [subject] : parts
    }

    public static func shapeFaces(paths: [PathItem], stroke: [Vec2], subtract: Bool) -> [PathItem] {
        let faces = LivePaint.faces(paths: paths, gap: 0.5)
        guard !faces.isEmpty else { return [] }
        let hit = faces.filter { face in
            let ring = face.nodes.map(\.anchor)
            return stroke.contains { Math2.polygonContains($0, ring: ring) }
        }
        if subtract { return faces.filter { face in !hit.contains { $0.nodes.map(\.anchor) == face.nodes.map(\.anchor) } } }
        return hit.isEmpty ? faces : hit
    }

    public static func rotateAngle(center: Vec2, from: Vec2, to: Vec2, shift: Bool) -> Double {
        var delta = atan2(to.y - center.y, to.x - center.x) - atan2(from.y - center.y, from.x - center.x)
        if shift {
            let step = Double.pi / 4
            delta = (delta / step).rounded() * step
        }
        return delta
    }

    public static func reflection(axisStart: Vec2, axisEnd: Vec2) -> Affine {
        let angle = atan2(axisEnd.y - axisStart.y, axisEnd.x - axisStart.x)
        let toAxis = Affine.rotation(-angle, around: axisStart)
        let flip = Affine.scale(1, -1, around: axisStart)
        let back = Affine.rotation(angle, around: axisStart)
        return back.concatenated(flip.concatenated(toAxis))
    }

    public static func scaleFactors(center: Vec2, from: Vec2, to: Vec2, shift: Bool) -> (Double, Double) {
        let sx = abs(from.x - center.x) < 0.5 ? 1 : (to.x - center.x) / (from.x - center.x)
        let sy = abs(from.y - center.y) < 0.5 ? 1 : (to.y - center.y) / (from.y - center.y)
        if shift {
            let u = max(abs(sx), abs(sy))
            return (u * (sx < 0 ? -1 : 1), u * (sy < 0 ? -1 : 1))
        }
        return (sx, sy)
    }

    public static func reshape(_ points: [Vec2], origin: Vec2, delta: Vec2, radius: Double) -> [Vec2] {
        points.map { point in
            let d = point.distance(to: origin)
            let fall = d >= radius ? 0 : exp(-(d * d) / max(1, radius * radius * 0.18))
            return point + delta * fall
        }
    }

    public static func warp(_ points: [Vec2], origin: Vec2, current: Vec2, kind: WarpToolKind, radius: Double, intensity: Double) -> [Vec2] {
        let delta = current - origin
        return points.map { point in
            let offset = point - origin
            let d = offset.length
            let fall = d >= radius ? 0 : pow(1 - d / radius, 2) * intensity
            if fall <= 0 { return point }
            switch kind {
            case .warp:
                return point + delta * fall
            case .twirl:
                return origin + offset.rotated(by: fall * 2.2)
            case .pucker:
                return point - offset * min(0.85, fall)
            case .bloat:
                return point + offset * min(0.85, fall)
            case .scallop:
                let n = offset.length < 1e-6 ? Vec2(0, 1) : offset.normalized()
                return point + n * sin(d * 0.35) * radius * 0.15 * fall
            case .crystallize:
                let cell = max(4, radius * 0.18)
                let snapped = Vec2((point.x / cell).rounded() * cell, (point.y / cell).rounded() * cell)
                return point + (snapped - point) * fall
            case .wrinkle:
                let n = sin(point.x * 0.7 + point.y * 0.3) 
                let m = cos(point.y * 0.5)
                return point + Vec2(n, m) * radius * 0.12 * fall
            }
        }
    }

    public static func bilinear(_ points: [Vec2], from rect: Rect2, corner: EditorModel.Handle, to point: Vec2) -> [Vec2] {
        guard rect.width > 0.5, rect.height > 0.5 else { return points }
        var tl = Vec2(rect.minX, rect.minY)
        var tr = Vec2(rect.maxX, rect.minY)
        var br = Vec2(rect.maxX, rect.maxY)
        var bl = Vec2(rect.minX, rect.maxY)
        switch corner {
        case .nw: tl = point
        case .ne: tr = point
        case .se: br = point
        case .sw: bl = point
        case .n: tl.y = point.y; tr.y = point.y
        case .e: tr.x = point.x; br.x = point.x
        case .s: bl.y = point.y; br.y = point.y
        case .w: tl.x = point.x; bl.x = point.x
        case .rotate: br = point
        }
        return points.map { p in
            let u = (p.x - rect.minX) / rect.width
            let v = (p.y - rect.minY) / rect.height
            let top = tl + (tr - tl) * u
            let bottom = bl + (br - bl) * u
            return top + (bottom - top) * v
        }
    }

    /// Moving-least-squares similarity (Schaefer). A point sitting on a pin follows that pin.
    public static func puppet(_ points: [Vec2], rest: [Vec2], moved: [Vec2]) -> [Vec2] {
        guard rest.count == moved.count, rest.count >= 2 else { return points }
        return points.map { v in
            if let index = rest.indices.min(by: { rest[$0].distance(to: v) < rest[$1].distance(to: v) }),
               rest[index].distance(to: v) < 0.4 {
                return moved[index]
            }
            var weightSum = 0.0
            var pStar = Vec2.zero
            var qStar = Vec2.zero
            var weights: [Double] = []
            for pin in rest {
                let d2 = max(1e-4, pin.distance(to: v) * pin.distance(to: v))
                let w = 1 / d2
                weights.append(w)
                weightSum += w
                pStar += pin * w
            }
            guard weightSum > 0 else { return v }
            pStar = pStar / weightSum
            for i in moved.indices { qStar += moved[i] * weights[i] }
            qStar = qStar / weightSum
            var mu = 0.0
            var sum = Vec2.zero
            for i in rest.indices {
                let ph = rest[i] - pStar
                let qh = moved[i] - qStar
                mu += weights[i] * (ph.x * ph.x + ph.y * ph.y)
                let vh = v - pStar
                // (q̂) * conjugate(p̂) * (v - p*) as complex multiplication of qh * conj(ph) * vh
                let conj = Vec2(ph.x, -ph.y)
                let qp = complexMul(qh, conj)
                sum += complexMul(qp, vh) * weights[i]
            }
            if mu < 1e-8 { return v + (qStar - pStar) }
            return sum / mu + qStar
        }
    }

    public static func widthSides(path: PathItem, at t: Double, point: Vec2, total: Double, option: Bool) -> (Double, Double, Double) {
        let flat = Bezier.flatten(path, tolerance: 0.5)
        guard flat.count >= 2 else { return (total, total, t) }
        var bestT = t
        var bestD = Double.greatestFiniteMagnitude
        var normal = Vec2(0, 1)
        var walked = 0.0
        var length = 0.0
        for i in 1..<flat.count { length += flat[i].distance(to: flat[i - 1]) }
        for i in 1..<flat.count {
            let seg = flat[i].distance(to: flat[i - 1])
            let d = Math2.pointSegmentDistance(point, flat[i - 1], flat[i])
            if d < bestD {
                bestD = d
                bestT = length < 0.001 ? 0 : (walked + seg * 0.5) / length
                let dir = (flat[i] - flat[i - 1]).normalized()
                normal = Vec2(-dir.y, dir.x)
            }
            walked += seg
        }
        let side = (point - flat[min(flat.count - 1, 1)]) 
        _ = side
        let signed = (point.x) * normal.x + (point.y) * normal.y
        let magnitude = max(0.5, bestD)
        if option {
            if signed >= 0 { return (magnitude, total, bestT) }
            return (total, magnitude, bestT)
        }
        return (magnitude, magnitude, bestT)
    }

    public static func symbolInstances(kind: SymbolToolKind, at point: Vec2, diameter: Double, existing: [Vec2], tint: RGBA) -> (places: [Vec2], moved: [Vec2], scale: Double, rotation: Double, color: RGBA?, opacity: Double?) {
        switch kind {
        case .sprayer:
            let count = 5
            let places = (0..<count).map { i -> Vec2 in
                let ang = Double(i) / Double(count) * Double.pi * 2
                let rad = diameter * (0.15 + 0.35 * Double(i % 3) / 2)
                return point + Vec2(cos(ang), sin(ang)) * rad
            }
            return (places, existing, 1, 0, nil, nil)
        case .shifter:
            return ([], existing.map { $0 + (point - $0) * ( $0.distance(to: point) < diameter ? 0.35 : 0) }, 1, 0, nil, nil)
        case .scruncher:
            return ([], existing.map { origin in
                origin.distance(to: point) < diameter ? origin + (point - origin) * 0.25 : origin
            }, 1, 0, nil, nil)
        case .sizer:
            return ([], existing, 1.25, 0, nil, nil)
        case .spinner:
            return ([], existing, 1, 0.4, nil, nil)
        case .stainer:
            return ([], existing, 1, 0, tint, nil)
        case .screener:
            return ([], existing, 1, 0, nil, 0.45)
        case .styler:
            return ([], existing, 1, 0, nil, nil)
        }
    }

    public static func subdivideMesh(_ mesh: MeshObject) -> MeshObject {
        var copy = mesh
        let nextCols = mesh.columns + 1
        var colors: [RGBA] = []
        for row in 0..<mesh.rows {
            for col in 0..<nextCols {
                let left = min(mesh.columns - 1, col)
                let prev = max(0, col - 1)
                let a = mesh.colors[min(mesh.colors.count - 1, row * mesh.columns + prev)]
                let b = mesh.colors[min(mesh.colors.count - 1, row * mesh.columns + left)]
                colors.append(a.mixed(with: b, t: col == prev ? 0 : 0.5))
            }
        }
        copy.columns = nextCols
        copy.colors = colors
        copy.cell.x = mesh.cell.x * Double(mesh.columns) / Double(nextCols)
        return copy
    }

    public static func gradient(existing: GradientPaint?, from a: Vec2, to b: Vec2, box: Rect2, shift: Bool) -> GradientPaint {
        var end = b
        if shift {
            end = abs(b.x - a.x) >= abs(b.y - a.y) ? Vec2(b.x, a.y) : Vec2(a.x, b.y)
        }
        let stops = existing?.stops ?? [GradientStop(color: .black, location: 0), GradientStop(color: .white, location: 1)]
        return GradientPaint(
            stops: stops,
            start: Vec2((a.x - box.x) / max(box.width, 0.001), (a.y - box.y) / max(box.height, 0.001)),
            end: Vec2((end.x - box.x) / max(box.width, 0.001), (end.y - box.y) / max(box.height, 0.001))
        )
    }

    public static func measure(from a: Vec2, to b: Vec2) -> MeasureReading {
        let d = b - a
        return MeasureReading(distance: d.length, dx: d.x, dy: d.y, angle: atan2(d.y, d.x) * 180 / Double.pi)
    }

    public static func blend(from a: PathItem, to b: PathItem, steps: Int, fillA: RGBA?, fillB: RGBA?) -> [PathObject] {
        let count = max(2, steps)
        return (0...count).map { i in
            let t = Double(i) / Double(count)
            var path = a
            for n in path.nodes.indices {
                let other = b.nodes[min(n, b.nodes.count - 1)].anchor
                path.nodes[n].anchor = path.nodes[n].anchor + (other - path.nodes[n].anchor) * t
            }
            var appearance = Appearance()
            if let c1 = fillA, let c2 = fillB {
                appearance.fill = .solid(c1.mixed(with: c2, t: t))
            }
            return PathObject(name: "混合", path: path, appearance: appearance)
        }
    }

    public static func colorDistance(_ a: RGBA, _ b: RGBA) -> Double {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return sqrt(dr * dr + dg * dg + db * db) / sqrt(3)
    }

    public static func lassoHits(anchors: [Vec2], center: Vec2, ring: [Vec2]) -> Bool {
        if anchors.contains(where: { Math2.polygonContains($0, ring: ring) }) { return true }
        return Math2.polygonContains(center, ring: ring)
    }

    public static func smooth(nodes: [PathNode], near stroke: [Vec2], radius: Double, closed: Bool) -> [PathNode] {
        var copy = nodes
        for i in copy.indices {
            let close = stroke.contains { copy[i].anchor.distance(to: $0) <= radius }
            if !close { continue }
            if !closed && (i == 0 || i == copy.count - 1) { continue }
            let prev = copy[(i + copy.count - 1) % copy.count].anchor
            let next = copy[(i + 1) % copy.count].anchor
            let delta = (next - prev) * 0.25
            copy[i].inHandle = copy[i].anchor - delta
            copy[i].outHandle = copy[i].anchor + delta
            copy[i].corner = .smooth
        }
        return copy
    }

    public static func eraseSpan(_ path: PathItem, stroke: [Vec2], radius: Double) -> [PathItem] {
        guard !stroke.isEmpty else { return [path] }
        let kept = path.nodes.enumerated().filter { _, node in
            !stroke.contains { node.anchor.distance(to: $0) <= radius }
        }.map(\.element)
        if kept.count == path.nodes.count { return [path] }
        if kept.count < 2 { return [] }
        var runs: [[PathNode]] = []
        var current: [PathNode] = []
        for node in path.nodes {
            if stroke.contains(where: { node.anchor.distance(to: $0) <= radius }) {
                if current.count >= 2 { runs.append(current) }
                current = []
            } else {
                current.append(node)
            }
        }
        if current.count >= 2 { runs.append(current) }
        return runs.map { PathItem(nodes: $0, closed: false, shape: .free) }
    }

    public static func joinUnder(stroke: [Vec2], paths: [PathItem], radius: Double) -> PathItem? {
        let open = paths.filter { !$0.closed && $0.nodes.count >= 2 }
        guard open.count >= 2 else { return PathOps.join(open) }
        let touched = open.filter { path in
            guard let a = path.nodes.first?.anchor, let b = path.nodes.last?.anchor else { return false }
            return stroke.contains { $0.distance(to: a) <= radius || $0.distance(to: b) <= radius }
        }
        return PathOps.join(touched.isEmpty ? open : touched)
    }

    public static func recognize(_ points: [Vec2]) -> ShapeKind? {
        guard points.count >= 6 else { return nil }
        let box = Rect2.enclosing(points)
        guard box.width > 6, box.height > 6 else { return nil }
        let limit = max(box.width, box.height) * 0.14
        let edge = points.filter { p in
            min(abs(p.x - box.minX), abs(p.x - box.maxX), abs(p.y - box.minY), abs(p.y - box.maxY)) < limit
        }
        if Double(edge.count) / Double(points.count) > 0.72 { return .rectangle }
        let c = box.center
        let rx = box.width / 2, ry = box.height / 2
        let oval = points.filter { p in
            let nx = (p.x - c.x) / rx, ny = (p.y - c.y) / ry
            return abs(nx * nx + ny * ny - 1) < 0.35
        }
        if Double(oval.count) / Double(points.count) > 0.62 { return .ellipse }
        return nil
    }

    public static func flare(center: Vec2, radius: Double, rays: Int) -> [PathItem] {
        var paths = [PathBuilder.ellipse(Rect2(x: center.x - radius * 0.18, y: center.y - radius * 0.18, width: radius * 0.36, height: radius * 0.36))]
        let count = max(4, rays)
        for i in 0..<count {
            let ang = Double(i) / Double(count) * Double.pi * 2
            let tip = center + Vec2(cos(ang), sin(ang)) * radius
            paths.append(PathBuilder.line(center, tip))
        }
        paths.append(PathBuilder.ellipse(Rect2(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)))
        return paths
    }

    public static func polarGrid(_ rect: Rect2, rings: Int, divisions: Int) -> [PathItem] {
        let c = rect.center
        let rx = rect.width / 2, ry = rect.height / 2
        var paths: [PathItem] = []
        let ringCount = max(1, rings)
        for i in 1...ringCount {
            let t = Double(i) / Double(ringCount)
            paths.append(PathBuilder.ellipse(Rect2(x: c.x - rx * t, y: c.y - ry * t, width: rx * 2 * t, height: ry * 2 * t)))
        }
        let slices = max(2, divisions)
        for i in 0..<slices {
            let ang = Double(i) / Double(slices) * Double.pi * 2
            paths.append(PathBuilder.line(c, c + Vec2(cos(ang) * rx, sin(ang) * ry)))
        }
        return paths
    }

    public static func arcPath(rect: Rect2, sweep: Double) -> PathItem {
        PathBuilder.arc(center: rect.center, radius: max(rect.width, rect.height) / 2, start: 0, end: sweep, closed: false)
    }

    public static func optionsDialog(tool: Tool, fidelity: Double, smoothness: Double, diameter: Double, tolerance: Double) -> DialogRequest {
        DialogRequest(action: "工具选项", title: "\(tool.title) 选项", fields: [
            DialogField(key: "fidelity", label: "保真度", value: String(format: "%.2f", fidelity)),
            DialogField(key: "smoothness", label: "平滑度", value: String(format: "%.2f", smoothness)),
            DialogField(key: "diameter", label: "直径", value: String(format: "%.1f", diameter)),
            DialogField(key: "tolerance", label: "容差", value: String(format: "%.2f", tolerance))
        ])
    }

    public static func planeDelta(_ grid: PerspectiveGrid, from: Vec2, to: Vec2) -> Vec2 {
        let a = grid.project(Rect2(x: from.x, y: from.y, width: 1, height: 1)).nodes.first?.anchor ?? from
        let b = grid.project(Rect2(x: to.x, y: to.y, width: 1, height: 1)).nodes.first?.anchor ?? to
        return b - a
    }

    private static func complexMul(_ a: Vec2, _ b: Vec2) -> Vec2 {
        Vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)
    }

    private static func segmentCross(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> (t: Double, point: Vec2)? {
        let r = b - a, s = d - c
        let denom = r.x * s.y - r.y * s.x
        if abs(denom) < 1e-8 { return nil }
        let qp = c - a
        let t = (qp.x * s.y - qp.y * s.x) / denom
        let u = (qp.x * r.y - qp.y * r.x) / denom
        if t < 0.02 || t > 0.98 || u < 0 || u > 1 { return nil }
        return (t, a + r * t)
    }

    private static func dedupeHits(_ hits: [(index: Int, t: Double, point: Vec2)]) -> [(index: Int, t: Double, point: Vec2)] {
        var out: [(index: Int, t: Double, point: Vec2)] = []
        for hit in hits.sorted(by: { $0.index == $1.index ? $0.t < $1.t : $0.index < $1.index }) {
            if out.contains(where: { $0.point.distance(to: hit.point) < 1.5 }) { continue }
            out.append(hit)
        }
        return out
    }

    private static func chain(_ flat: [Vec2], from: (index: Int, t: Double, point: Vec2), to: (index: Int, t: Double, point: Vec2)) -> PathItem {
        var nodes = [PathNode.corner(from.point)]
        var i = from.index + 1
        let guardMax = flat.count + 2
        var steps = 0
        while steps < guardMax {
            if i == to.index + 1 || (i == to.index && false) {
                break
            }
            if i >= flat.count { i = 0 }
            nodes.append(.corner(flat[i]))
            if i == to.index { break }
            i += 1
            steps += 1
        }
        nodes.append(.corner(to.point))
        return PathItem(nodes: nodes, closed: false, shape: .free)
    }
}
