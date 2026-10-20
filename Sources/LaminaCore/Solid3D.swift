import Foundation

public struct Light3D: Equatable, Sendable {
    public var direction: Vec2
    public var ambient: Double
    public init(direction: Vec2 = Vec2(-0.4, -0.8), ambient: Double = 0.28) {
        self.direction = direction
        self.ambient = ambient
    }
}

public enum Solid3D {
    public static func extrude(_ path: PathItem, color: RGBA, depth: Double, light: Light3D = Light3D()) -> [ArtItem] {
        let ring = clean(Bezier.flatten(path))
        guard ring.count >= 3 else { return [] }
        var faces: [(z: Double, item: ArtItem)] = []
        let front = polygon(ring.map { project($0, 0) }, color: shade(color, normal: Vec2(0, -1), light: light))
        faces.append((0, front))
        let backRing = ring.map { project($0, depth) }
        faces.append((depth, polygon(backRing, color: shade(color, normal: Vec2(0, 1), light: light))))
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            let edge = (b - a).normalized()
            let normal = Vec2(-edge.y, edge.x)
            let quad = [project(a, 0), project(b, 0), project(b, depth), project(a, depth)]
            faces.append((depth * 0.5, polygon(quad, color: shade(color, normal: normal, light: light))))
        }
        return faces.sorted { $0.z > $1.z }.map(\.item)
    }

    public static func revolve(_ path: PathItem, color: RGBA, steps: Int = 12, light: Light3D = Light3D()) -> [ArtItem] {
        let profile = clean(Bezier.flatten(path))
        guard profile.count >= 2 else { return [] }
        let origin = profile.map(\.y).reduce(0, +) / Double(profile.count)
        let count = max(6, steps)
        var rings: [[Vec2]] = []
        for step in 0...count {
            let ang = Double(step) / Double(count) * .pi * 2
            let cosine = cos(ang)
            let sine = sin(ang)
            rings.append(profile.map { p in
                let radius = p.x
                let y = p.y
                let x = radius * cosine
                let z = radius * sine
                return project(Vec2(x, y - origin), z) + Vec2(0, origin)
            })
        }
        var items: [ArtItem] = []
        for s in 0..<count {
            for i in 0..<(profile.count - 1) {
                let quad = [rings[s][i], rings[s + 1][i], rings[s + 1][i + 1], rings[s][i + 1]]
                let normal = Vec2(cos(Double(s) / Double(count) * .pi * 2), -0.3)
                items.append(polygon(quad, color: shade(color, normal: normal, light: light)))
            }
        }
        return items
    }

    public static func inflate(_ path: PathItem, color: RGBA, amount: Double, light: Light3D = Light3D()) -> [ArtItem] {
        let ring = clean(Bezier.flatten(path))
        guard ring.count >= 3 else { return [] }
        let center = ring.reduce(Vec2.zero, +) / Double(ring.count)
        let mid = ring.map { $0 + (center - $0) * 0.45 }
        let top = center
        var items: [ArtItem] = []
        items.append(polygon(ring.map { project($0, 0) }, color: shade(color, normal: Vec2(0, 0.2), light: light)))
        for i in 0..<ring.count {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            let c = mid[(i + 1) % ring.count], d = mid[i]
            let quad = [project(a, 0), project(b, 0), project(c, amount * 0.6), project(d, amount * 0.6)]
            items.append(polygon(quad, color: shade(color, normal: (b - a).rotated(by: .pi / 2), light: light)))
        }
        for i in 0..<mid.count {
            let tri = [project(mid[i], amount * 0.6), project(mid[(i + 1) % mid.count], amount * 0.6), project(top, amount)]
            items.append(polygon(tri, color: shade(color, normal: Vec2(0, -1), light: light)))
        }
        return items
    }

    private static func project(_ p: Vec2, _ z: Double) -> Vec2 {
        let perspective = 640.0
        let k = perspective / (perspective + z)
        return Vec2(p.x * k + z * 0.22, p.y * k - z * 0.38)
    }

    private static func shade(_ color: RGBA, normal: Vec2, light: Light3D) -> RGBA {
        let n = normal.normalized()
        let l = light.direction.normalized()
        let diffuse = max(0, -(n.x * l.x + n.y * l.y))
        let gain = min(1, light.ambient + (1 - light.ambient) * diffuse)
        return RGBA(r: color.r * gain, g: color.g * gain, b: color.b * gain, a: color.a)
    }

    private static func polygon(_ points: [Vec2], color: RGBA) -> ArtItem {
        .path(PathObject(name: "三维", path: PathItem(nodes: points.map { .corner($0) }, closed: true, shape: .free), appearance: Appearance(fill: .solid(color), stroke: nil)))
    }

    private static func clean(_ points: [Vec2]) -> [Vec2] {
        var out: [Vec2] = []
        for p in points where out.last?.almostEqual(p, eps: 0.2) != true { out.append(p) }
        if out.count >= 2, out.first?.almostEqual(out.last ?? .zero, eps: 0.2) == true { out.removeLast() }
        return out
    }
}
