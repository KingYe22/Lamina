import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension LaminaDocument {
    public func item(id: UUID) -> ArtItem? {
        for layer in layers {
            if let found = find(id, in: layer.items) { return found }
        }
        return nil
    }

    public func containsItem(_ id: UUID) -> Bool { item(id: id) != nil }

    public mutating func updateItem(_ id: UUID, _ body: (inout ArtItem) -> Void) -> Bool {
        for li in layers.indices {
            if update(id, in: &layers[li].items, body) { return true }
        }
        return false
    }

    @discardableResult
    public mutating func removeItem(_ id: UUID) -> ArtItem? {
        for li in layers.indices {
            if let removed = remove(id, from: &layers[li].items) { return removed }
        }
        return nil
    }

    public mutating func insert(_ item: ArtItem, layerID: UUID? = nil, index: Int? = nil) {
        let li = layerIndex(id: layerID) ?? min(max(0, activeLayer), max(0, layers.count - 1))
        guard layers.indices.contains(li) else { return }
        var items = layers[li].items
        let at = min(max(0, index ?? items.count), items.count)
        items.insert(item, at: at)
        layers[li].items = items
    }

    public func layerID(containing itemID: UUID) -> UUID? {
        for layer in layers where contains(itemID, in: layer.items) {
            return layer.id
        }
        return nil
    }

    public func layerIndex(id: UUID?) -> Int? {
        guard let id else { return nil }
        return layers.firstIndex { $0.id == id }
    }

    public func parentID(of itemID: UUID) -> UUID? {
        for layer in layers {
            if let parent = parent(of: itemID, in: layer.items, parentID: nil) { return parent }
        }
        return nil
    }

    public func flatItems(includingHidden: Bool = true) -> [ArtItem] {
        var result: [ArtItem] = []
        for layer in layers where includingHidden || layer.visible {
            func walk(_ items: [ArtItem]) {
                for item in items {
                    result.append(item)
                    walk(item.children)
                }
            }
            walk(layer.items)
        }
        return result
    }

    private func find(_ id: UUID, in items: [ArtItem]) -> ArtItem? {
        for item in items {
            if item.id == id { return item }
            if let found = find(id, in: item.children) { return found }
        }
        return nil
    }

    private func contains(_ id: UUID, in items: [ArtItem]) -> Bool {
        find(id, in: items) != nil
    }

    private func update(_ id: UUID, in items: inout [ArtItem], _ body: (inout ArtItem) -> Void) -> Bool {
        for i in items.indices {
            if items[i].id == id {
                body(&items[i])
                return true
            }
            if updateChildren(id, of: &items[i], body) { return true }
        }
        return false
    }

    private func updateChildren(_ id: UUID, of item: inout ArtItem, _ body: (inout ArtItem) -> Void) -> Bool {
        switch item {
        case .group(var group):
            if update(id, in: &group.children, body) {
                item = .group(group)
                return true
            }
        case .clip(var clip):
            if clip.clipper.id == id {
                body(&clip.clipper)
                item = .clip(clip)
                return true
            }
            if updateChildren(id, of: &clip.clipper, body) {
                item = .clip(clip)
                return true
            }
            if update(id, in: &clip.contents, body) {
                item = .clip(clip)
                return true
            }
        default:
            break
        }
        return false
    }

    private func remove(_ id: UUID, from items: inout [ArtItem]) -> ArtItem? {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            return items.remove(at: idx)
        }
        for i in items.indices {
            switch items[i] {
            case .group(var group):
                if let removed = remove(id, from: &group.children) {
                    items[i] = .group(group)
                    return removed
                }
            case .clip(var clip):
                if clip.clipper.id == id {
                    let removed = clip.clipper
                    clip.clipper = .path(PathObject(name: "空蒙版", path: PathItem(nodes: [], closed: true)))
                    items[i] = .clip(clip)
                    return removed
                }
                if let removed = removeFromClipper(&clip.clipper, id: id) {
                    items[i] = .clip(clip)
                    return removed
                }
                if let removed = remove(id, from: &clip.contents) {
                    items[i] = .clip(clip)
                    return removed
                }
            default:
                break
            }
        }
        return nil
    }

    private func removeFromClipper(_ item: inout ArtItem, id: UUID) -> ArtItem? {
        switch item {
        case .group(var group):
            if let removed = remove(id, from: &group.children) {
                item = .group(group)
                return removed
            }
        default:
            break
        }
        return nil
    }

    private func parent(of id: UUID, in items: [ArtItem], parentID: UUID?) -> UUID? {
        for item in items {
            if item.id == id { return parentID }
            if let found = parent(of: id, in: item.children, parentID: item.id) { return found }
        }
        return nil
    }
}

public enum PathBuilder {
    public static func rectangle(_ rect: Rect2, radius: Double = 0) -> PathItem {
        let x = rect.x, y = rect.y, w = rect.width, h = rect.height
        if radius <= 0.01 {
            return PathItem(nodes: [
                .corner(Vec2(x, y)), .corner(Vec2(x + w, y)),
                .corner(Vec2(x + w, y + h)), .corner(Vec2(x, y + h))
            ], closed: true, shape: .rectangle)
        }
        let r = min(radius, min(abs(w), abs(h)) / 2)
        let k = r * 0.5522847498
        func node(_ a: Vec2, _ inn: Vec2?, _ out: Vec2?) -> PathNode {
            PathNode(anchor: a, inHandle: inn, outHandle: out, corner: .smooth)
        }
        let nodes = [
            node(Vec2(x + r, y), Vec2(x + r - k, y), Vec2(x + r, y)),
            node(Vec2(x + w - r, y), Vec2(x + w - r, y), Vec2(x + w - r + k, y)),
            node(Vec2(x + w, y + r), Vec2(x + w, y + r - k), Vec2(x + w, y + r)),
            node(Vec2(x + w, y + h - r), Vec2(x + w, y + h - r), Vec2(x + w, y + h - r + k)),
            node(Vec2(x + w - r, y + h), Vec2(x + w - r + k, y + h), Vec2(x + w - r, y + h)),
            node(Vec2(x + r, y + h), Vec2(x + r, y + h), Vec2(x + r - k, y + h)),
            node(Vec2(x, y + h - r), Vec2(x, y + h - r + k), Vec2(x, y + h - r)),
            node(Vec2(x, y + r), Vec2(x, y + r), Vec2(x, y + r - k))
        ]
        // Handles above are a bit awkward; rebuild with correct in/out pairs.
        return roundedRect(rect, radius: r)
    }

    public static func roundedRect(_ rect: Rect2, radius: Double) -> PathItem {
        let x = rect.x, y = rect.y, w = rect.width, h = rect.height
        let r = min(max(0, radius), min(abs(w), abs(h)) / 2)
        let k = r * 0.5522847498
        let pts: [(Vec2, Vec2?, Vec2?)] = [
            (Vec2(x + r, y), Vec2(x + r - k, y), Vec2(x + r, y)),
            (Vec2(x + w - r, y), nil, Vec2(x + w - r + k, y)),
            (Vec2(x + w, y + r), Vec2(x + w, y + r - k), nil),
            (Vec2(x + w, y + h - r), nil, Vec2(x + w, y + h - r + k)),
            (Vec2(x + w - r, y + h), Vec2(x + w - r + k, y + h), nil),
            (Vec2(x + r, y + h), nil, Vec2(x + r - k, y + h)),
            (Vec2(x, y + h - r), Vec2(x, y + h - r + k), nil),
            (Vec2(x, y + r), nil, Vec2(x, y + r - k))
        ]
        // Pair outgoing of previous with incoming of next more carefully.
        let anchors = [
            Vec2(x + r, y),
            Vec2(x + w - r, y),
            Vec2(x + w, y + r),
            Vec2(x + w, y + h - r),
            Vec2(x + w - r, y + h),
            Vec2(x + r, y + h),
            Vec2(x, y + h - r),
            Vec2(x, y + r)
        ]
        let outs: [Vec2] = [
            Vec2(x + r, y), // straight to next, no curve on top edge start — top edge is straight
            Vec2(x + w - r + k, y),
            Vec2(x + w, y + r),
            Vec2(x + w, y + h - r + k),
            Vec2(x + w - r, y + h),
            Vec2(x + r - k, y + h),
            Vec2(x, y + h - r),
            Vec2(x, y + r - k)
        ]
        let inns: [Vec2?] = [
            Vec2(x + r - k, y),
            Vec2(x + w - r, y),
            Vec2(x + w, y + r - k),
            Vec2(x + w, y + h - r),
            Vec2(x + w - r + k, y + h),
            Vec2(x + r, y + h),
            Vec2(x, y + h - r + k),
            Vec2(x, y + r)
        ]
        _ = pts
        var nodes: [PathNode] = []
        for i in 0..<anchors.count {
            let straightIn = inns[i].map { $0.almostEqual(anchors[i]) } ?? true
            let straightOut = outs[i].almostEqual(anchors[i])
            nodes.append(PathNode(
                anchor: anchors[i],
                inHandle: straightIn ? nil : inns[i],
                outHandle: straightOut ? nil : outs[i],
                corner: .smooth
            ))
        }
        return PathItem(nodes: nodes, closed: true, shape: .roundedRectangle(radius: r))
    }

    public static func ellipse(_ rect: Rect2) -> PathItem {
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        let kx = rx * 0.5522847498
        let ky = ry * 0.5522847498
        let nodes = [
            PathNode(anchor: Vec2(cx + rx, cy), inHandle: Vec2(cx + rx, cy - ky), outHandle: Vec2(cx + rx, cy + ky), corner: .smooth),
            PathNode(anchor: Vec2(cx, cy + ry), inHandle: Vec2(cx + kx, cy + ry), outHandle: Vec2(cx - kx, cy + ry), corner: .smooth),
            PathNode(anchor: Vec2(cx - rx, cy), inHandle: Vec2(cx - rx, cy + ky), outHandle: Vec2(cx - rx, cy - ky), corner: .smooth),
            PathNode(anchor: Vec2(cx, cy - ry), inHandle: Vec2(cx - kx, cy - ry), outHandle: Vec2(cx + kx, cy - ry), corner: .smooth)
        ]
        return PathItem(nodes: nodes, closed: true, shape: .ellipse)
    }

    public static func line(_ a: Vec2, _ b: Vec2) -> PathItem {
        PathItem(nodes: [.corner(a), .corner(b)], closed: false, shape: .line)
    }

    public static func polygon(center: Vec2, radius: Double, sides: Int) -> PathItem {
        let n = max(3, sides)
        var nodes: [PathNode] = []
        for i in 0..<n {
            let t = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(n)
            nodes.append(.corner(Vec2(center.x + cos(t) * radius, center.y + sin(t) * radius)))
        }
        return PathItem(nodes: nodes, closed: true, shape: .polygon(sides: n))
    }

    public static func star(center: Vec2, radius: Double, points: Int, innerRatio: Double) -> PathItem {
        let n = max(3, points)
        let inner = radius * innerRatio
        var nodes: [PathNode] = []
        for i in 0..<(n * 2) {
            let t = -Double.pi / 2 + Double(i) * Double.pi / Double(n)
            let rad = i % 2 == 0 ? radius : inner
            nodes.append(.corner(Vec2(center.x + cos(t) * rad, center.y + sin(t) * rad)))
        }
        return PathItem(nodes: nodes, closed: true, shape: .star(points: n, innerRatio: innerRatio))
    }

    public static func arc(center: Vec2, radius: Double, start: Double, end: Double, closed: Bool) -> PathItem {
        let steps = 8
        var nodes: [PathNode] = []
        for i in 0...steps {
            let t = start + (end - start) * Double(i) / Double(steps)
            nodes.append(.corner(Vec2(center.x + cos(t) * radius, center.y + sin(t) * radius)))
        }
        return PathItem(nodes: nodes, closed: closed, shape: .free)
    }

    public static func spiral(center: Vec2, startRadius: Double, endRadius: Double, turns: Double) -> PathItem {
        let steps = max(12, Int(turns * 16))
        var nodes: [PathNode] = []
        for i in 0...steps {
            let u = Double(i) / Double(steps)
            let ang = u * turns * 2 * Double.pi
            let rad = startRadius + (endRadius - startRadius) * u
            nodes.append(.corner(Vec2(center.x + cos(ang) * rad, center.y + sin(ang) * rad)))
        }
        return PathItem(nodes: nodes, closed: false, shape: .free)
    }

    public static func rectGrid(_ rect: Rect2, rows: Int, columns: Int) -> [PathItem] {
        var paths: [PathItem] = []
        let rows = max(1, rows), columns = max(1, columns)
        for r in 0...rows {
            let y = rect.y + rect.height * Double(r) / Double(rows)
            paths.append(line(Vec2(rect.x, y), Vec2(rect.maxX, y)))
        }
        for c in 0...columns {
            let x = rect.x + rect.width * Double(c) / Double(columns)
            paths.append(line(Vec2(x, rect.y), Vec2(x, rect.maxY)))
        }
        return paths
    }
}

public enum Bezier {
    public static func point(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2, t: Double) -> Vec2 {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        return a * (uu * u) + b * (3 * uu * t) + c * (3 * u * tt) + d * (tt * t)
    }

    public static func flatten(_ path: PathItem, tolerance: Double = 0.35) -> [Vec2] {
        guard let first = path.nodes.first else { return [] }
        var pts: [Vec2] = [first.anchor]
        let count = path.nodes.count
        let segments = path.closed ? count : count - 1
        if segments <= 0 { return pts }
        for i in 0..<segments {
            let a = path.nodes[i]
            let b = path.nodes[(i + 1) % count]
            let c1 = a.outHandle ?? a.anchor
            let c2 = b.inHandle ?? b.anchor
            if c1.almostEqual(a.anchor, eps: 1e-6) && c2.almostEqual(b.anchor, eps: 1e-6) {
                pts.append(b.anchor)
            } else {
                flattenCubic(a.anchor, c1, c2, b.anchor, tolerance: tolerance, into: &pts)
            }
        }
        return pts
    }

    private static func flattenCubic(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2, tolerance: Double, into pts: inout [Vec2], depth: Int = 0) {
        if depth > 12 || isFlat(p0, p1, p2, p3, tolerance: tolerance) {
            pts.append(p3)
            return
        }
        let a = p0
        let b = (p0 + p1) * 0.5
        let c = (p0 + p1 * 2 + p2) * 0.25
        let d = (p0 + p1 * 3 + p2 * 3 + p3) * 0.125
        let e = (p1 + p2 * 2 + p3) * 0.25
        let f = (p2 + p3) * 0.5
        let g = p3
        flattenCubic(a, b, c, d, tolerance: tolerance, into: &pts, depth: depth + 1)
        flattenCubic(d, e, f, g, tolerance: tolerance, into: &pts, depth: depth + 1)
    }

    private static func isFlat(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2, tolerance: Double) -> Bool {
        let d1 = Math2.pointSegmentDistance(p1, p0, p3)
        let d2 = Math2.pointSegmentDistance(p2, p0, p3)
        return max(d1, d2) <= tolerance
    }

    public static func bounds(_ path: PathItem, extra: [Vec2] = []) -> Rect2 {
        var points = extra
        for node in path.nodes {
            points.append(node.anchor)
            if let h = node.inHandle { points.append(h) }
            if let h = node.outHandle { points.append(h) }
        }
        return Rect2.enclosing(points)
    }

    public static func hit(_ path: PathItem, point: Vec2, tolerance: Double, filled: Bool) -> Bool {
        let poly = flatten(path, tolerance: 0.8)
        if filled && path.closed && Math2.polygonContains(point, ring: poly) { return true }
        guard poly.count >= 2 else {
            return poly.first?.distance(to: point) ?? .greatestFiniteMagnitude <= tolerance
        }
        for i in 0..<(poly.count - 1) where Math2.pointSegmentDistance(point, poly[i], poly[i + 1]) <= tolerance {
            return true
        }
        if path.closed, let first = poly.first, let last = poly.last,
           Math2.pointSegmentDistance(point, last, first) <= tolerance {
            return true
        }
        return false
    }

    public static func project(_ path: PathItem, point: Vec2) -> (index: Int, t: Double, point: Vec2)? {
        guard path.nodes.count >= 2 else { return nil }
        let count = path.nodes.count
        let segments = path.closed ? count : count - 1
        var best: (Int, Double, Vec2, Double)?
        for i in 0..<segments {
            let a = path.nodes[i]
            let b = path.nodes[(i + 1) % count]
            let c1 = a.outHandle ?? a.anchor
            let c2 = b.inHandle ?? b.anchor
            var t = 0.0
            while t <= 1 {
                let p = Bezier.point(a.anchor, c1, c2, b.anchor, t: t)
                let d = p.distance(to: point)
                if best == nil || d < best!.3 {
                    best = (i, t, p, d)
                }
                t += 0.02
            }
        }
        if let best { return (best.0, best.1, best.2) }
        return nil
    }

    public static func split(_ path: PathItem, segment: Int, t: Double) -> PathItem {
        var path = path
        let count = path.nodes.count
        guard count >= 2 else { return path }
        let i = segment
        let j = (i + 1) % count
        let a = path.nodes[i]
        let b = path.nodes[j]
        let p0 = a.anchor
        let p1 = a.outHandle ?? a.anchor
        let p2 = b.inHandle ?? b.anchor
        let p3 = b.anchor
        let tt = min(0.98, max(0.02, t))
        func lerp(_ u: Vec2, _ v: Vec2, _ t: Double) -> Vec2 { u + (v - u) * t }
        let a1 = lerp(p0, p1, tt)
        let b1 = lerp(p1, p2, tt)
        let c1 = lerp(p2, p3, tt)
        let d1 = lerp(a1, b1, tt)
        let e1 = lerp(b1, c1, tt)
        let p = lerp(d1, e1, tt)
        var left = a
        left.outHandle = a1.almostEqual(a.anchor) ? nil : a1
        var mid = PathNode(anchor: p, inHandle: d1.almostEqual(p) ? nil : d1, outHandle: e1.almostEqual(p) ? nil : e1, corner: .smooth)
        var right = b
        right.inHandle = c1.almostEqual(b.anchor) ? nil : c1
        path.nodes[i] = left
        if path.closed && j == 0 {
            path.nodes.append(mid)
            path.nodes[0] = right
        } else {
            path.nodes[j] = right
            path.nodes.insert(mid, at: j)
        }
        path.shape = .free
        return path
    }

    public static func deleteNode(_ path: PathItem, nodeID: UUID) -> PathItem {
        var path = path
        path.nodes.removeAll { $0.id == nodeID }
        path.shape = .free
        if path.nodes.count < 3 { path.closed = false }
        return path
    }

    /// Smooth open or closed anchors with a Catmull-Rom to Bézier conversion.
    public static func smooth(_ nodes: [PathNode], closed: Bool) -> [PathNode] {
        guard nodes.count >= 2 else { return nodes }
        var result = nodes
        let n = nodes.count
        for i in 0..<n {
            let prev = nodes[(i - 1 + n) % n].anchor
            let next = nodes[(i + 1) % n].anchor
            if !closed && (i == 0 || i == n - 1) {
                result[i].inHandle = nil
                result[i].outHandle = nil
                result[i].corner = .corner
                continue
            }
            let tangent = (next - prev) * (1.0 / 6.0)
            result[i].inHandle = nodes[i].anchor - tangent
            result[i].outHandle = nodes[i].anchor + tangent
            result[i].corner = .smooth
        }
        return result
    }
}

public enum PathOps {
    public static func join(_ paths: [PathItem]) -> PathItem? {
        let open = paths.filter { !$0.closed && $0.nodes.count >= 2 }
        guard var acc = open.first else { return nil }
        var rest = Array(open.dropFirst())
        while !rest.isEmpty {
            guard let a = acc.nodes.first?.anchor, let b = acc.nodes.last?.anchor else { break }
            var best = 0
            var bestD = Double.greatestFiniteMagnitude
            var flip = false
            var append = true
            for (idx, path) in rest.enumerated() {
                guard let c = path.nodes.first?.anchor, let d = path.nodes.last?.anchor else { continue }
                let options: [(Double, Bool, Bool)] = [
                    (b.distance(to: c), false, true),
                    (b.distance(to: d), true, true),
                    (a.distance(to: c), false, false),
                    (a.distance(to: d), true, false)
                ]
                for opt in options where opt.0 < bestD {
                    bestD = opt.0
                    best = idx
                    flip = opt.1
                    append = opt.2
                }
            }
            var next = rest.remove(at: best)
            if flip { next.nodes.reverse() }
            if append {
                if let last = acc.nodes.last?.anchor, let first = next.nodes.first?.anchor, last.distance(to: first) < 0.5 {
                    next.nodes.removeFirst()
                }
                acc.nodes.append(contentsOf: next.nodes)
            } else {
                if let first = acc.nodes.first?.anchor, let last = next.nodes.last?.anchor, first.distance(to: last) < 0.5 {
                    next.nodes.removeLast()
                }
                acc.nodes.insert(contentsOf: next.nodes, at: 0)
            }
        }
        acc.closed = false
        acc.shape = .free
        if let a = acc.nodes.first?.anchor, let b = acc.nodes.last?.anchor, a.distance(to: b) < 1 {
            acc.nodes.removeLast()
            acc.closed = true
        }
        return acc
    }

    public static func average(_ path: PathItem, nodeIDs: Set<UUID>?) -> PathItem {
        var path = path
        let targets = path.nodes.enumerated().filter { nodeIDs == nil || nodeIDs!.contains($0.element.id) }
        guard !targets.isEmpty else { return path }
        let avg = targets.reduce(Vec2.zero) { $0 + $1.element.anchor } / Double(targets.count)
        for (idx, _) in targets {
            let delta = avg - path.nodes[idx].anchor
            path.nodes[idx].anchor = avg
            if let h = path.nodes[idx].inHandle { path.nodes[idx].inHandle = h + delta }
            if let h = path.nodes[idx].outHandle { path.nodes[idx].outHandle = h + delta }
        }
        path.shape = .free
        return path
    }

    public static func simplify(_ path: PathItem, tolerance: Double) -> PathItem {
        var path = path
        let anchors = path.nodes.map(\.anchor)
        let kept = rdp(anchors, tolerance: tolerance, closed: path.closed)
        if kept.count >= 2 {
            path.nodes = kept.map { PathNode.corner($0) }
        }
        path.shape = .free
        return path
    }

    private static func rdp(_ points: [Vec2], tolerance: Double, closed: Bool) -> [Vec2] {
        guard points.count > 2 else { return points }
        var pts = points
        if closed, let first = pts.first { pts.append(first) }
        let mask = rdpMask(pts, tolerance: tolerance)
        var result: [Vec2] = []
        for i in 0..<points.count where mask[i] { result.append(points[i]) }
        return result
    }

    private static func rdpMask(_ points: [Vec2], tolerance: Double) -> [Bool] {
        var keep = Array(repeating: false, count: points.count)
        guard let last = points.indices.last else { return keep }
        keep[0] = true
        keep[last] = true
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
        rec(0, last)
        return keep
    }

    public static func offset(_ ring: [Vec2], distance: Double) -> [Vec2] {
        guard ring.count >= 3 else { return ring }
        var result: [Vec2] = []
        let n = ring.count
        for i in 0..<n {
            let prev = ring[(i - 1 + n) % n]
            let cur = ring[i]
            let next = ring[(i + 1) % n]
            let n1 = normal(prev, cur)
            let n2 = normal(cur, next)
            var bis = n1 + n2
            if bis.length < 1e-6 { bis = n1 }
            let unit = bis.normalized()
            let scale = distance / max(0.2, unit.x * n1.x + unit.y * n1.y)
            result.append(cur + unit * scale)
        }
        return result
    }

    public static func outlineStroke(_ ring: [Vec2], width: Double, closed: Bool) -> [Vec2] {
        if ring.count < 2 { return ring }
        if closed {
            let outer = offset(ring, distance: width / 2)
            let inner = offset(ring, distance: -width / 2)
            return outer + inner.reversed()
        }
        var left: [Vec2] = []
        var right: [Vec2] = []
        for i in 0..<(ring.count - 1) {
            let nrm = normal(ring[i], ring[i + 1]) * (width / 2)
            if i == 0 {
                left.append(ring[i] + nrm)
                right.append(ring[i] - nrm)
            }
            left.append(ring[i + 1] + nrm)
            right.append(ring[i + 1] - nrm)
        }
        return left + right.reversed()
    }

    private static func normal(_ a: Vec2, _ b: Vec2) -> Vec2 {
        let d = b - a
        let len = d.length
        if len < 1e-9 { return Vec2(0, -1) }
        return Vec2(-(d.y / len), d.x / len)
    }

    public static func warp(_ path: PathItem, kind: String, bend: Double) -> PathItem {
        var path = path
        let box = Bezier.bounds(path)
        guard box.width > 0, box.height > 0 else { return path }
        func map(_ p: Vec2) -> Vec2 {
            let u = (p.x - box.x) / box.width
            let v = (p.y - box.y) / box.height
            switch kind {
            case "弧形", "拱形":
                let ang = (u - 0.5) * bend
                let rad = box.height * (1.2 - v) 
                return Vec2(box.midX + sin(ang) * rad, box.maxY - cos(ang) * rad * 0.5 - v * box.height * 0.2)
            case "旗帜", "波形":
                return Vec2(p.x, p.y + sin(u * .pi * 2) * bend * box.height)
            case "鱼眼", "膨胀":
                let dx = u - 0.5, dy = v - 0.5
                let k = 1 + bend * (0.5 - (dx * dx + dy * dy))
                return Vec2(box.midX + dx * box.width * k, box.midY + dy * box.height * k)
            case "扭转":
                let ang = (v - 0.5) * bend
                let c = cos(ang), s = sin(ang)
                let dx = p.x - box.midX, dy = p.y - box.midY
                return Vec2(box.midX + dx * c - dy * s, box.midY + dx * s + dy * c)
            case "波纹":
                return Vec2(p.x + sin(v * .pi * 6) * bend * 8, p.y)
            case "粗糙化":
                let jx = sin(p.x * 12.9898 + p.y * 78.233) * bend
                let jy = cos(p.y * 39.346 + p.x * 11.135) * bend
                return Vec2(p.x + jx, p.y + jy)
            default:
                return Vec2(p.x, p.y + sin(u * .pi) * bend * 20 * (1 - abs(v - 0.5) * 2))
            }
        }
        for i in path.nodes.indices {
            path.nodes[i].anchor = map(path.nodes[i].anchor)
            if let h = path.nodes[i].inHandle { path.nodes[i].inHandle = map(h) }
            if let h = path.nodes[i].outHandle { path.nodes[i].outHandle = map(h) }
        }
        path.shape = .free
        return path
    }
}
