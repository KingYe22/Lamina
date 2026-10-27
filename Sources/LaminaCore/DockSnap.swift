import Foundation

/// A panel or host rectangle in one coordinate space. Values are points.
public struct DockFrame: Equatable, Sendable {
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

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public struct DockGuide: Equatable, Sendable {
    public enum Axis: Equatable, Sendable {
        case vertical(Double)
        case horizontal(Double)
    }

    public var axis: Axis

    public init(_ axis: Axis) { self.axis = axis }
}

/// Magnetic edges for a floating panel. The guide is shown while an edge is
/// inside the threshold; the returned frame is what mouse-up should apply.
public enum DockSnap {
    /// Lock range is 6–8 pt. 8 is the inclusive end of that range.
    public static let threshold: Double = 8
    /// Snap guide. RGB(0, 114, 239).
    public static let guideHex = 0x0072EF

    public static func magnet(
        frame: DockFrame,
        others: [DockFrame],
        host: DockFrame,
        threshold: Double = DockSnap.threshold
    ) -> (frame: DockFrame, guides: [DockGuide]) {
        var next = frame
        var guides: [DockGuide] = []
        if let x = best(frame: frame, others: others, host: host, threshold: threshold, vertical: false) {
            next.x += x.delta
            guides.append(DockGuide(.vertical(x.guide)))
        }
        if let y = best(frame: frame, others: others, host: host, threshold: threshold, vertical: true) {
            next.y += y.delta
            guides.append(DockGuide(.horizontal(y.guide)))
        }
        next.x = clamp(next.x, low: host.minX, room: host.width - next.width)
        next.y = clamp(next.y, low: host.minY, room: host.height - next.height)
        return (next, guides)
    }

    private struct Candidate {
        var delta: Double
        var guide: Double
    }

    private static func best(
        frame: DockFrame,
        others: [DockFrame],
        host: DockFrame,
        threshold: Double,
        vertical: Bool
    ) -> Candidate? {
        var pairs: [(Double, Double)] = []
        if vertical {
            pairs.append((host.minY - frame.minY, host.minY))
            pairs.append((host.maxY - frame.maxY, host.maxY))
            for other in others {
                pairs.append((other.minY - frame.minY, other.minY))
                pairs.append((other.maxY - frame.maxY, other.maxY))
                pairs.append((other.maxY - frame.minY, other.maxY))
                pairs.append((other.minY - frame.maxY, other.minY))
            }
        } else {
            pairs.append((host.minX - frame.minX, host.minX))
            pairs.append((host.maxX - frame.maxX, host.maxX))
            for other in others {
                pairs.append((other.minX - frame.minX, other.minX))
                pairs.append((other.maxX - frame.maxX, other.maxX))
                pairs.append((other.maxX - frame.minX, other.maxX))
                pairs.append((other.minX - frame.maxX, other.minX))
            }
        }
        var winner: Candidate?
        for pair in pairs {
            let delta = pair.0
            guard abs(delta) <= threshold + 1e-9 else { continue }
            if let current = winner, abs(delta) >= abs(current.delta) - 1e-9 { continue }
            winner = Candidate(delta: delta, guide: pair.1)
        }
        return winner
    }

    private static func clamp(_ origin: Double, low: Double, room: Double) -> Double {
        if room <= 0 { return low }
        return min(max(origin, low), low + room)
    }
}
