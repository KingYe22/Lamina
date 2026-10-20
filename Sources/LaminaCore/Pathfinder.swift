import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum BooleanOp: String, Codable, Sendable {
    case unite, minusFront, intersect, exclude, divide, trim, merge, crop, outline, minusBack
}

public enum Pathfinder {
    public static func apply(_ op: BooleanOp, subject: [Vec2], clip: [Vec2]) -> [[Vec2]] {
        let a = clean(subject)
        let b = clean(clip)
        guard a.count >= 3 else { return [] }
        guard b.count >= 3 else {
            switch op {
            case .unite, .minusFront, .minusBack, .divide, .trim, .merge, .crop, .outline:
                return [a]
            case .intersect, .exclude:
                return op == .exclude ? [a] : []
            }
        }
        let faces = arrangement(a, b)
        let selected: [Ring] = faces.filter { face in
            let insideA = Math2.polygonContains(face.sample, ring: a)
            let insideB = Math2.polygonContains(face.sample, ring: b)
            switch op {
            case .unite, .merge, .crop:
                return insideA || insideB
            case .minusFront:
                return insideA && !insideB
            case .minusBack:
                return insideB && !insideA
            case .intersect, .trim:
                return insideA && insideB
            case .exclude, .divide:
                return insideA != insideB
            case .outline:
                return false
            }
        }
        if op == .outline {
            return [a, b]
        }
        var rings = merge(selected.map(\.points))
        if op == .divide || op == .trim {
            rings = selected.map(\.points).filter { abs(Math2.signedArea($0)) > 0.5 }
        }
        return rings.filter { abs(Math2.signedArea($0)) > 0.5 }
    }

    public static func boundsArea(_ rings: [[Vec2]]) -> (Rect2, Double) {
        let pts = rings.flatMap { $0 }
        let area = rings.reduce(0) { $0 + abs(Math2.signedArea($1)) }
        return (Rect2.enclosing(pts), area)
    }

    private struct Ring {
        var points: [Vec2]
        var sample: Vec2
    }

    private struct Half {
        var origin: Int
        var dest: Int
        var twin: Int
        var next: Int
        var angle: Double
    }

    private static func clean(_ ring: [Vec2]) -> [Vec2] {
        var pts: [Vec2] = []
        for p in ring {
            let q = Vec2((p.x * 10000).rounded() / 10000, (p.y * 10000).rounded() / 10000)
            if let last = pts.last, last.almostEqual(q, eps: 1e-6) { continue }
            pts.append(q)
        }
        if pts.count >= 2, let first = pts.first, let last = pts.last, first.almostEqual(last, eps: 1e-6) {
            pts.removeLast()
        }
        return pts
    }

    private static func arrangement(_ a: [Vec2], _ b: [Vec2]) -> [Ring] {
        struct E { var a: Int; var b: Int }
        var verts: [Vec2] = []
        var index: [String: Int] = [:]
        func vid(_ p: Vec2) -> Int {
            let q = Vec2((p.x * 10000).rounded() / 10000, (p.y * 10000).rounded() / 10000)
            let key = "\(q.x),\(q.y)"
            if let i = index[key] { return i }
            index[key] = verts.count
            verts.append(q)
            return verts.count - 1
        }
        func addRing(_ ring: [Vec2], into edges: inout [E]) {
            for i in 0..<ring.count {
                let u = vid(ring[i])
                let v = vid(ring[(i + 1) % ring.count])
                if u != v { edges.append(E(a: u, b: v)) }
            }
        }
        var edges: [E] = []
        addRing(a, into: &edges)
        addRing(b, into: &edges)

        // Split edges at crossings.
        var params: [[Double]] = Array(repeating: [0, 1], count: edges.count)
        for i in 0..<edges.count {
            for j in (i + 1)..<edges.count {
                let a1 = verts[edges[i].a], a2 = verts[edges[i].b]
                let b1 = verts[edges[j].a], b2 = verts[edges[j].b]
                if let hit = segmentHit(a1, a2, b1, b2) {
                    params[i].append(hit.0)
                    params[j].append(hit.1)
                }
            }
        }
        var atomic: [E] = []
        for (idx, edge) in edges.enumerated() {
            let p0 = verts[edge.a], p1 = verts[edge.b]
            let ts = Array(Set(params[idx].map { min(1, max(0, ($0 * 1e8).rounded() / 1e8)) })).sorted()
            var ids: [Int] = ts.map { t in vid(p0 + (p1 - p0) * t) }
            // unique consecutive
            var collapsed: [Int] = []
            for id in ids where collapsed.last != id { collapsed.append(id) }
            ids = collapsed
            if ids.count < 2 { continue }
            for k in 0..<(ids.count - 1) where ids[k] != ids[k + 1] {
                atomic.append(E(a: ids[k], b: ids[k + 1]))
            }
        }
        // Unique undirected edges.
        var seen = Set<String>()
        var unique: [E] = []
        for e in atomic {
            let key = e.a < e.b ? "\(e.a)-\(e.b)" : "\(e.b)-\(e.a)"
            if seen.insert(key).inserted { unique.append(e) }
        }
        if unique.isEmpty { return [] }

        var halfs: [Half] = []
        for e in unique {
            let ang = atan2(verts[e.b].y - verts[e.a].y, verts[e.b].x - verts[e.a].x)
            let ang2 = atan2(verts[e.a].y - verts[e.b].y, verts[e.a].x - verts[e.b].x)
            let i0 = halfs.count
            halfs.append(Half(origin: e.a, dest: e.b, twin: i0 + 1, next: -1, angle: ang))
            halfs.append(Half(origin: e.b, dest: e.a, twin: i0, next: -1, angle: ang2))
        }
        var outgoing: [Int: [Int]] = [:]
        for i in halfs.indices {
            outgoing[halfs[i].origin, default: []].append(i)
        }
        for key in outgoing.keys {
            outgoing[key]?.sort { halfs[$0].angle < halfs[$1].angle }
        }
        for i in halfs.indices {
            let dest = halfs[i].dest
            guard let outs = outgoing[dest], !outs.isEmpty else { continue }
            let twin = halfs[i].twin
            guard let idx = outs.firstIndex(of: twin) else { continue }
            // atan2 increases clockwise on a y-down canvas. Stepping to the
            // previous outgoing edge keeps bounded faces clockwise, which is
            // the positive shoelace orientation used by the rest of the model.
            halfs[i].next = outs[(idx + outs.count - 1) % outs.count]
        }

        var used = Array(repeating: false, count: halfs.count)
        var faces: [Ring] = []
        for start in halfs.indices where !used[start] && halfs[start].next >= 0 {
            var cycle: [Int] = []
            var k = start
            var guardN = 0
            var ok = true
            while !used[k] && guardN <= halfs.count {
                used[k] = true
                cycle.append(halfs[k].origin)
                let n = halfs[k].next
                if n < 0 { ok = false; break }
                k = n
                guardN += 1
                if k == start { break }
            }
            if !ok || k != start || cycle.count < 3 { continue }
            let pts = cycle.map { verts[$0] }
            let area = Math2.signedArea(pts)
            if area <= 0.25 { continue }
            let sample = interiorPoint(pts)
            faces.append(Ring(points: pts, sample: sample))
        }
        return faces
    }

    private static func segmentHit(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> (Double, Double)? {
        let r = b - a
        let s = d - c
        let denom = r.x * s.y - r.y * s.x
        if abs(denom) < 1e-12 { return nil }
        let qp = c - a
        let t = (qp.x * s.y - qp.y * s.x) / denom
        let u = (qp.x * r.y - qp.y * r.x) / denom
        let eps = 1e-8
        if t > eps && t < 1 - eps && u > eps && u < 1 - eps {
            return (t, u)
        }
        // T-junctions: endpoint of one lies on the other.
        if let t = parameterOn(c, a, b), t > eps && t < 1 - eps { return (t, 0) }
        if let t = parameterOn(d, a, b), t > eps && t < 1 - eps { return (t, 1) }
        if let u = parameterOn(a, c, d), u > eps && u < 1 - eps { return (0, u) }
        if let u = parameterOn(b, c, d), u > eps && u < 1 - eps { return (1, u) }
        return nil
    }

    private static func parameterOn(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double? {
        let ab = b - a
        let len2 = ab.x * ab.x + ab.y * ab.y
        if len2 < 1e-12 { return nil }
        let t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len2
        if t < -1e-6 || t > 1 + 1e-6 { return nil }
        let proj = a + ab * t
        if proj.distance(to: p) > 1e-5 { return nil }
        return t
    }

    private static func interiorPoint(_ ring: [Vec2]) -> Vec2 {
        guard ring.count >= 3 else { return ring.first ?? .zero }
        let a = ring[0], b = ring[1]
        let mid = (a + b) * 0.5
        let dir = b - a
        let left = Vec2(-dir.y, dir.x).normalized()
        let candidate = mid + left * 0.05
        if Math2.polygonContains(candidate, ring: ring) { return candidate }
        let other = mid - left * 0.05
        if Math2.polygonContains(other, ring: ring) { return other }
        var c = Vec2.zero
        for p in ring { c += p }
        return c / Double(ring.count)
    }

    private static func merge(_ faces: [[Vec2]]) -> [[Vec2]] {
        if faces.isEmpty { return [] }
        struct Dir: Hashable { var ax: Int; var ay: Int; var bx: Int; var by: Int }
        func key(_ p: Vec2) -> (Int, Int) {
            (Int((p.x * 10000).rounded()), Int((p.y * 10000).rounded()))
        }
        var bag: [Dir: Int] = [:]
        var point: [Dir: (Vec2, Vec2)] = [:]
        for face in faces {
            for i in 0..<face.count {
                let a = face[i]
                let b = face[(i + 1) % face.count]
                let ka = key(a), kb = key(b)
                let d = Dir(ax: ka.0, ay: ka.1, bx: kb.0, by: kb.1)
                bag[d, default: 0] += 1
                point[d] = (a, b)
            }
        }
        var boundary: [Dir: (Vec2, Vec2)] = [:]
        for (d, count) in bag {
            let rev = Dir(ax: d.bx, ay: d.by, bx: d.ax, by: d.ay)
            let other = bag[rev] ?? 0
            let net = count - other
            if net > 0, let seg = point[d] {
                boundary[d] = seg
            }
        }
        // Cancel was double-counted because we look at both directions.
        // Rebuild with cancellation of pairs.
        var forward: [Dir: Int] = [:]
        for (d, count) in bag { forward[d] = count }
        var used = Set<Dir>()
        var adj: [String: [(String, Vec2, Vec2)]] = [:]
        func id(_ p: Vec2) -> String {
            let k = key(p)
            return "\(k.0),\(k.1)"
        }
        for (d, count) in forward {
            let rev = Dir(ax: d.bx, ay: d.by, bx: d.ax, by: d.ay)
            if used.contains(d) || used.contains(rev) { continue }
            let rc = forward[rev] ?? 0
            let keep = count - rc
            if keep == 0 {
                used.insert(d); used.insert(rev)
                continue
            }
            if let seg = point[d] {
                let from = keep > 0 ? seg.0 : seg.1
                let to = keep > 0 ? seg.1 : seg.0
                adj[id(from), default: []].append((id(to), from, to))
            }
            used.insert(d); used.insert(rev)
        }
        var rings: [[Vec2]] = []
        var remaining = adj
        while let start = remaining.first(where: { !$0.value.isEmpty })?.key {
            var ring: [Vec2] = []
            var current = start
            var guardN = 0
            while guardN < 10000 {
                guard var outs = remaining[current], !outs.isEmpty else { break }
                let next = outs.removeFirst()
                remaining[current] = outs
                if ring.isEmpty { ring.append(next.1) }
                ring.append(next.2)
                current = next.0
                guardN += 1
                if current == start { break }
            }
            if ring.count >= 4, let first = ring.first, let last = ring.last, first.almostEqual(last, eps: 1e-4) {
                ring.removeLast()
            }
            if abs(Math2.signedArea(ring)) > 0.5 {
                if Math2.signedArea(ring) < 0 { ring.reverse() }
                rings.append(ring)
            }
        }
        return rings
    }
}
