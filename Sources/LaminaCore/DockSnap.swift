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

    /// `shoulder` is the properties column in the same space as `host`.
    /// A panel docks to that column's outer edge when it overlaps the column,
    /// the pointer is inside the column (outset by `threshold`), or a rightward
    /// drag brings the panel's right edge within `threshold` of the column.
    /// Resting beside the column does not dock. The guide is the outer edge.
    public static func magnet(
        frame: DockFrame,
        others: [DockFrame],
        host: DockFrame,
        threshold: Double = DockSnap.threshold,
        shoulder: DockFrame? = nil,
        pointer: Vec2? = nil,
        dragStartMaxX: Double? = nil
    ) -> (frame: DockFrame, guides: [DockGuide]) {
        var next = frame
        var guides: [DockGuide] = []
        let intoShoulder = shoulder.map {
            shouldDock(frame: frame, shoulder: $0, pointer: pointer, dragStartMaxX: dragStartMaxX, threshold: threshold)
        } ?? false
        if intoShoulder, let shoulder {
            next.x += shoulder.maxX - frame.maxX
            guides.append(DockGuide(.vertical(shoulder.maxX)))
        } else if let x = best(frame: frame, others: others, host: host, threshold: threshold, vertical: false) {
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

    private static func shouldDock(
        frame: DockFrame,
        shoulder: DockFrame,
        pointer: Vec2?,
        dragStartMaxX: Double?,
        threshold: Double
    ) -> Bool {
        let overlaps = frame.maxX > shoulder.minX + 1e-6 && frame.minX < shoulder.maxX - 1e-6
            && frame.maxY > shoulder.minY + 1e-6 && frame.minY < shoulder.maxY - 1e-6
        if overlaps { return true }
        if let pointer,
           pointer.x >= shoulder.minX - threshold, pointer.x <= shoulder.maxX + threshold,
           pointer.y >= shoulder.minY - threshold, pointer.y <= shoulder.maxY + threshold {
            return true
        }
        let stacked = frame.maxY > shoulder.minY + 1e-6 && frame.minY < shoulder.maxY - 1e-6
        let gap = shoulder.minX - frame.maxX
        let movingRight = dragStartMaxX.map { frame.maxX > $0 + 1 } ?? false
        return stacked && movingRight && gap >= -1e-9 && gap <= threshold + 1e-9
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
