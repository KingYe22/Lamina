import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct Vec2: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var length: Double { hypot(x, y) }

    public func distance(to other: Vec2) -> Double {
        hypot(x - other.x, y - other.y)
    }

    public func normalized() -> Vec2 {
        let len = length
        if len < 1e-12 { return .zero }
        return self / len
    }

    public func rotated(by radians: Double) -> Vec2 {
        let c = cos(radians)
        let s = sin(radians)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    public static func + (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(lhs.x + rhs.x, lhs.y + rhs.y) }
    public static func - (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(lhs.x - rhs.x, lhs.y - rhs.y) }
    public static func * (lhs: Vec2, rhs: Double) -> Vec2 { Vec2(lhs.x * rhs, lhs.y * rhs) }
    public static func * (lhs: Double, rhs: Vec2) -> Vec2 { rhs * lhs }
    public static func / (lhs: Vec2, rhs: Double) -> Vec2 { Vec2(lhs.x / rhs, lhs.y / rhs) }
    public static func += (lhs: inout Vec2, rhs: Vec2) { lhs = lhs + rhs }
    public static func -= (lhs: inout Vec2, rhs: Vec2) { lhs = lhs - rhs }

    public func almostEqual(_ other: Vec2, eps: Double = 1e-4) -> Bool {
        abs(x - other.x) <= eps && abs(y - other.y) <= eps
    }
}

public struct Rect2: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(origin: Vec2, size: Vec2) {
        self.init(x: origin.x, y: origin.y, width: size.x, height: size.y)
    }

    public init(min: Vec2, max: Vec2) {
        self.init(x: min.x, y: min.y, width: max.x - min.x, height: max.y - min.y)
    }

    public static let zero = Rect2(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var origin: Vec2 { Vec2(x, y) }
    public var center: Vec2 { Vec2(midX, midY) }
    /// Both axes non-positive. A horizontal or vertical line still has a usable bound.
    public var isEmpty: Bool { width <= 0 && height <= 0 }

    public func contains(_ p: Vec2, inset: Double = 0) -> Bool {
        p.x >= minX - inset && p.x <= maxX + inset && p.y >= minY - inset && p.y <= maxY + inset
    }

    public func intersects(_ other: Rect2) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }

    public func union(_ other: Rect2) -> Rect2 {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let nx = min(minX, other.minX)
        let ny = min(minY, other.minY)
        let mx = max(maxX, other.maxX)
        let my = max(maxY, other.maxY)
        return Rect2(x: nx, y: ny, width: mx - nx, height: my - ny)
    }

    public func insetBy(_ dx: Double, _ dy: Double) -> Rect2 {
        Rect2(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    public func expanded(_ pad: Double) -> Rect2 {
        insetBy(-pad, -pad)
    }

    public static func enclosing(_ points: [Vec2]) -> Rect2 {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return Rect2(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public struct Affine: Codable, Equatable, Hashable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public static let identity = Affine(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public func apply(_ p: Vec2) -> Vec2 {
        Vec2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty)
    }

    public func apply(_ r: Rect2) -> Rect2 {
        let corners = [
            Vec2(r.minX, r.minY), Vec2(r.maxX, r.minY),
            Vec2(r.maxX, r.maxY), Vec2(r.minX, r.maxY)
        ].map(apply)
        return Rect2.enclosing(corners)
    }

    public func concatenated(_ other: Affine) -> Affine {
        // self then other: other * self
        Affine(
            a: other.a * a + other.c * b,
            b: other.b * a + other.d * b,
            c: other.a * c + other.c * d,
            d: other.b * c + other.d * d,
            tx: other.a * tx + other.c * ty + other.tx,
            ty: other.b * tx + other.d * ty + other.ty
        )
    }

    public var inverted: Affine? {
        let det = a * d - b * c
        if abs(det) < 1e-12 { return nil }
        let ia = d / det
        let ib = -b / det
        let ic = -c / det
        let id = a / det
        return Affine(
            a: ia, b: ib, c: ic, d: id,
            tx: -(ia * tx + ic * ty),
            ty: -(ib * tx + id * ty)
        )
    }

    public static func translation(_ dx: Double, _ dy: Double) -> Affine {
        Affine(a: 1, b: 0, c: 0, d: 1, tx: dx, ty: dy)
    }

    public static func scale(_ sx: Double, _ sy: Double, around origin: Vec2 = .zero) -> Affine {
        let t1 = translation(-origin.x, -origin.y)
        let s = Affine(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
        let t2 = translation(origin.x, origin.y)
        return t2.concatenated(s.concatenated(t1))
    }

    public static func rotation(_ radians: Double, around origin: Vec2 = .zero) -> Affine {
        let c = cos(radians)
        let s = sin(radians)
        let t1 = translation(-origin.x, -origin.y)
        let r = Affine(a: c, b: s, c: -s, d: c, tx: 0, ty: 0)
        let t2 = translation(origin.x, origin.y)
        return t2.concatenated(r.concatenated(t1))
    }

    public static func skew(x: Double, y: Double, around origin: Vec2 = .zero) -> Affine {
        let t1 = translation(-origin.x, -origin.y)
        let k = Affine(a: 1, b: tan(y), c: tan(x), d: 1, tx: 0, ty: 0)
        let t2 = translation(origin.x, origin.y)
        return t2.concatenated(k.concatenated(t1))
    }

    public var svgMatrix: String {
        String(format: "matrix(%.6f %.6f %.6f %.6f %.6f %.6f)", a, b, c, d, tx, ty)
    }
}

public enum Math2 {
    public static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    public static func signedArea(_ ring: [Vec2]) -> Double {
        guard ring.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<ring.count {
            let p = ring[i]
            let q = ring[(i + 1) % ring.count]
            sum += p.x * q.y - q.x * p.y
        }
        return sum / 2
    }

    public static func polygonContains(_ p: Vec2, ring: [Vec2]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[j]
            let b = ring[i]
            if (a.y > p.y) != (b.y > p.y) {
                let xInt = (b.x - a.x) * (p.y - a.y) / (b.y - a.y + 0) + a.x
                if p.x < xInt { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    public static func segmentsIntersect(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2, eps: Double = 1e-9) -> Vec2? {
        let r = b - a
        let s = d - c
        let denom = r.x * s.y - r.y * s.x
        if abs(denom) < eps {
            return nil
        }
        let qp = c - a
        let t = (qp.x * s.y - qp.y * s.x) / denom
        let u = (qp.x * r.y - qp.y * r.x) / denom
        if t >= -eps && t <= 1 + eps && u >= -eps && u <= 1 + eps {
            return a + r * min(1, max(0, t))
        }
        return nil
    }

    public static func pointSegmentDistance(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let len2 = ab.x * ab.x + ab.y * ab.y
        if len2 < 1e-12 { return p.distance(to: a) }
        var t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len2
        t = min(1, max(0, t))
        let proj = a + ab * t
        return p.distance(to: proj)
    }
}
