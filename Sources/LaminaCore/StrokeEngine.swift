import Foundation

public enum WidthStroke {
    public static func outline(path: PathItem, widths: [WidthPoint], profile: WidthProfile, base: Double) -> PathItem {
        let flat = Bezier.flatten(path, tolerance: 0.35)
        guard flat.count >= 2 else { return path }
        let samples = resample(flat, path: path)
        var left: [Vec2] = []
        var right: [Vec2] = []
        for (index, sample) in samples.enumerated() {
            let prev = samples[max(0, index - 1)].point
            let next = samples[min(samples.count - 1, index + 1)].point
            var tangent = next - prev
            if tangent.length < 1e-6 { tangent = Vec2(1, 0) }
            let normal = Vec2(-tangent.y, tangent.x).normalized()
            let (l, r) = width(at: sample.t, widths: widths, profile: profile, base: base)
            left.append(sample.point + normal * l)
            right.append(sample.point - normal * r)
        }
        let ring = left + right.reversed()
        return PathItem(nodes: ring.map { .corner($0) }, closed: true, shape: .free)
    }

    private struct Sample { var point: Vec2; var t: Double }

    private static func resample(_ flat: [Vec2], path: PathItem) -> [Sample] {
        var lengths: [Double] = [0]
        for i in 1..<flat.count { lengths.append(lengths[i - 1] + flat[i].distance(to: flat[i - 1])) }
        let total = max(lengths.last ?? 1, 0.001)
        return zip(flat, lengths).map { Sample(point: $0.0, t: path.closed ? $0.1 / total : $0.1 / total) }
    }

    public static func width(at t: Double, widths: [WidthPoint], profile: WidthProfile, base: Double) -> (Double, Double) {
        let shaped = base * profileScale(t, profile)
        let points = widths.sorted { $0.t < $1.t }
        guard let first = points.first else { return (shaped / 2, shaped / 2) }
        if t <= first.t { return (first.left, first.right) }
        if let last = points.last, t >= last.t { return (last.left, last.right) }
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            if t >= a.t && t <= b.t {
                let u = (t - a.t) / max(0.0001, b.t - a.t)
                return (Math2.lerp(a.left, b.left, u), Math2.lerp(a.right, b.right, u))
            }
        }
        return (shaped / 2, shaped / 2)
    }

    private static func profileScale(_ t: Double, _ profile: WidthProfile) -> Double {
        switch profile {
        case .uniform: return 1
        case .linear: return max(0.05, t)
        case .triangular: return max(0.05, 1 - abs(t * 2 - 1))
        case .oval: return max(0.05, sin(t * .pi))
        }
    }
}

public enum GlyphOutline {
    /// Host apps (Core Text on macOS) can replace the built-in Latin outlines.
    public static var provider: ((TextObject) -> [PathItem])?

    public static func outlines(for text: TextObject) -> [PathItem] {
        if let provider {
            let made = provider(text)
            if !made.isEmpty { return made }
        }
        var paths: [PathItem] = []
        var x = text.origin.x
        let baseline = text.origin.y
        for scalar in text.string {
            let glyph = builtin(scalar, size: text.fontSize)
            let moved = PathItem(nodes: glyph.nodes.map { node in
                var copy = node
                copy.anchor = node.anchor + Vec2(x, baseline)
                if let h = node.inHandle { copy.inHandle = h + Vec2(x, baseline) }
                if let h = node.outHandle { copy.outHandle = h + Vec2(x, baseline) }
                return copy
            }, closed: true, shape: .free)
            paths.append(moved)
            x += advance(scalar) * text.fontSize
        }
        return paths
    }

    private static func advance(_ ch: Character) -> Double {
        if ch == " " { return 0.33 }
        if ch == "I" || ch == "i" || ch == "l" { return 0.4 }
        return 0.72
    }

    /// Em-square outlines, y-up from the baseline, then flipped into y-down by adding baseline later.
    /// Coordinates here are y-down already: baseline is 0, glyph extends to -size.
    private static func builtin(_ ch: Character, size: Double) -> PathItem {
        let u = size
        func n(_ pairs: [Double]) -> PathItem {
            var nodes: [PathNode] = []
            var i = 0
            while i + 1 < pairs.count {
                nodes.append(.corner(Vec2(pairs[i] * u, -pairs[i + 1] * u)))
                i += 2
            }
            return PathItem(nodes: nodes, closed: true, shape: .free)
        }
        switch ch {
        case "H":
            return n([0,0, 0.22,0, 0.22,0.4, 0.78,0.4, 0.78,0, 1,0, 1,1, 0.78,1, 0.78,0.6, 0.22,0.6, 0.22,1, 0,1])
        case "O", "o":
            return PathBuilder.ellipse(Rect2(x: 0.08 * u, y: -u, width: 0.84 * u, height: u))
        case "A":
            return n([0.5,1, 1,0, 0.78,0, 0.66,0.28, 0.34,0.28, 0.22,0, 0,0])
        default:
            return n([0.08,0, 0.62,0, 0.62,1, 0.08,1])
        }
    }
}
