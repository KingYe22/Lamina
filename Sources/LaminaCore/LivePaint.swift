import Foundation

public enum LivePaint {
    /// Planar faces of the supplied paths. Open endpoints within `gap` are joined,
    /// and an endpoint within `gap` of another segment is split onto that segment.
    public static func faces(paths: [PathItem], gap: Double = 0) -> [PathItem] {
        var segments: [(Vec2, Vec2)] = []
        for path in paths {
            let flat = Bezier.flatten(path, tolerance: 0.4)
            guard flat.count >= 2 else { continue }
            let count = path.closed ? flat.count : flat.count - 1
            for i in 0..<count {
                let a = flat[i]
                let b = flat[(i + 1) % flat.count]
                if a.distance(to: b) > 0.05 { segments.append((a, b)) }
            }
        }
        if gap > 0 { segments = closeGaps(segments, gap: gap) }
        let pieces = split(segments)
        return cycles(pieces)
    }

    public static func group(paths: [PathObject], gap: Double) -> GroupObject {
        let faces = faces(paths: paths.map(\.path), gap: gap)
        let paint = paths.first?.appearance.fill ?? .solid(.white)
        let children = faces.map { path in
            ArtItem.path(PathObject(name: "上色面", path: path, appearance: Appearance(fill: paint, stroke: StrokeStyle(width: 0.5))))
        }
        return GroupObject(name: "实时上色", children: children, isLivePaint: true)
    }

    public static func paint(_ group: GroupObject, at point: Vec2, color: Paint) -> GroupObject {
        var copy = group
        for index in copy.children.indices {
            guard case .path(var object) = copy.children[index] else { continue }
            let ring = object.path.nodes.map(\.anchor)
            if Math2.polygonContains(point, ring: ring) {
                object.appearance.fill = color
                copy.children[index] = .path(object)
                return copy
            }
        }
        return copy
    }

    private static func closeGaps(_ segments: [(Vec2, Vec2)], gap: Double) -> [(Vec2, Vec2)] {
        var ends: [Vec2] = []
        for seg in segments { ends.append(seg.0); ends.append(seg.1) }
        func snap(_ p: Vec2) -> Vec2 {
            var best = p
            var bestD = gap
            for other in ends where other.distance(to: p) <= bestD && other.distance(to: p) > 0.01 {
                best = other
                bestD = other.distance(to: p)
            }
            for seg in segments {
                let d = Math2.pointSegmentDistance(p, seg.0, seg.1)
                if d < bestD && d > 0.01 {
                    let ab = seg.1 - seg.0
                    let len2 = ab.x * ab.x + ab.y * ab.y
                    if len2 > 1e-8 {
                        var t = ((p.x - seg.0.x) * ab.x + (p.y - seg.0.y) * ab.y) / len2
                        t = min(1, max(0, t))
                        best = seg.0 + ab * t
                        bestD = d
                    }
                }
            }
            return best
        }
        return segments.map { (snap($0.0), snap($0.1)) }.filter { $0.0.distance(to: $0.1) > 0.05 }
    }

    private static func split(_ segments: [(Vec2, Vec2)]) -> [(Vec2, Vec2)] {
        var cuts: [[Vec2]] = segments.map { [$0.0, $0.1] }
        for i in segments.indices {
            for j in (i + 1)..<segments.count {
                if let hit = Math2.segmentsIntersect(segments[i].0, segments[i].1, segments[j].0, segments[j].1) {
                    if hit.distance(to: segments[i].0) > 0.05 && hit.distance(to: segments[i].1) > 0.05 { cuts[i].append(hit) }
                    if hit.distance(to: segments[j].0) > 0.05 && hit.distance(to: segments[j].1) > 0.05 { cuts[j].append(hit) }
                }
            }
        }
        var pieces: [(Vec2, Vec2)] = []
        for (index, seg) in segments.enumerated() {
            let origin = seg.0
            let dir = seg.1 - seg.0
            let ordered = cuts[index].sorted { lhs, rhs in
                (lhs.x - origin.x) * dir.x + (lhs.y - origin.y) * dir.y < (rhs.x - origin.x) * dir.x + (rhs.y - origin.y) * dir.y
            }
            for k in 0..<(ordered.count - 1) where ordered[k].distance(to: ordered[k + 1]) > 0.05 {
                pieces.append((ordered[k], ordered[k + 1]))
            }
        }
        return pieces
    }

    private static func cycles(_ pieces: [(Vec2, Vec2)]) -> [PathItem] {
        struct Half { var origin: Int; var dest: Int; var angle: Double; var twin: Int; var next: Int; var used: Bool }
        var verts: [Vec2] = []
        func index(_ p: Vec2) -> Int {
            if let found = verts.firstIndex(where: { $0.almostEqual(p, eps: 0.05) }) { return found }
            verts.append(p)
            return verts.count - 1
        }
        var halfs: [Half] = []
        for piece in pieces {
            let a = index(piece.0), b = index(piece.1)
            guard a != b else { continue }
            let ang = atan2(verts[b].y - verts[a].y, verts[b].x - verts[a].x)
            let back = atan2(verts[a].y - verts[b].y, verts[a].x - verts[b].x)
            let i0 = halfs.count
            halfs.append(Half(origin: a, dest: b, angle: ang, twin: i0 + 1, next: -1, used: false))
            halfs.append(Half(origin: b, dest: a, angle: back, twin: i0, next: -1, used: false))
        }
        var outgoing: [Int: [Int]] = [:]
        for (i, half) in halfs.enumerated() { outgoing[half.origin, default: []].append(i) }
        for key in outgoing.keys {
            outgoing[key]?.sort { halfs[$0].angle < halfs[$1].angle }
        }
        for i in halfs.indices {
            let dest = halfs[i].dest
            guard let outs = outgoing[dest], !outs.isEmpty else { continue }
            let twin = halfs[i].twin
            guard let idx = outs.firstIndex(of: twin) else { continue }
            // Same turn as Pathfinder: previous outgoing edge, so interior faces stay positive in y-down.
            halfs[i].next = outs[(idx + outs.count - 1) % outs.count]
        }
        var faces: [PathItem] = []
        for start in halfs.indices where !halfs[start].used {
            var loop: [Vec2] = []
            var cursor = start
            var guardCount = 0
            repeat {
                halfs[cursor].used = true
                loop.append(verts[halfs[cursor].origin])
                cursor = halfs[cursor].next
                guardCount += 1
            } while cursor != start && cursor >= 0 && guardCount < halfs.count + 2
            let area = Math2.signedArea(loop)
            if loop.count >= 3 && area > 0.25 {
                faces.append(PathItem(nodes: loop.map { .corner($0) }, closed: true, shape: .free))
            }
        }
        return faces
    }
}
