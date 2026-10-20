import Foundation

public enum PerspectivePlane: String, Codable, Equatable, Sendable {
    case left, right, floor
}

public struct PerspectiveGrid: Equatable, Sendable {
    public var leftVanishing: Vec2
    public var rightVanishing: Vec2
    public var horizon: Double
    public var board: Rect2
    public var plane: PerspectivePlane

    public init(board: Rect2, plane: PerspectivePlane = .floor) {
        self.board = board
        self.plane = plane
        horizon = board.minY + board.height * 0.38
        leftVanishing = Vec2(board.minX + board.width * 0.12, horizon)
        rightVanishing = Vec2(board.maxX - board.width * 0.12, horizon)
    }

    public func project(_ rect: Rect2) -> PathItem {
        let domain = control
        func uv(_ p: Vec2) -> (Double, Double) {
            let u = domain.width <= 0 ? 0 : (p.x - domain.x) / domain.width
            let v = domain.height <= 0 ? 0 : (p.y - domain.y) / domain.height
            return (min(1, max(0, u)), min(1, max(0, v)))
        }
        let corners = [
            Vec2(rect.minX, rect.minY), Vec2(rect.maxX, rect.minY),
            Vec2(rect.maxX, rect.maxY), Vec2(rect.minX, rect.maxY)
        ].map { point -> PathNode in
            let (u, v) = uv(point)
            return .corner(map(u, v))
        }
        return PathItem(nodes: corners, closed: true, shape: .free)
    }

    public func lines(steps: Int = 4) -> [PathItem] {
        var paths: [PathItem] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = map(t, 0)
            let b = map(t, 1)
            let c = map(0, t)
            let d = map(1, t)
            paths.append(PathBuilder.line(a, b))
            paths.append(PathBuilder.line(c, d))
        }
        return paths
    }

    public var control: Rect2 {
        switch plane {
        case .floor:
            return Rect2(x: board.minX + board.width * 0.18, y: horizon + 8, width: board.width * 0.64, height: board.maxY - horizon - 24)
        case .left:
            return Rect2(x: board.minX + 16, y: board.minY + 16, width: board.width * 0.42, height: horizon - board.minY - 8)
        case .right:
            return Rect2(x: board.midX, y: board.minY + 16, width: board.width * 0.42, height: horizon - board.minY - 8)
        }
    }

    public func map(_ u: Double, _ v: Double) -> Vec2 {
        switch plane {
        case .floor:
            let nearL = Vec2(board.minX + board.width * 0.2, board.maxY - 16)
            let nearR = Vec2(board.maxX - board.width * 0.2, board.maxY - 16)
            let left = nearL + (leftVanishing - nearL) * v
            let right = nearR + (rightVanishing - nearR) * v
            return left + (right - left) * u
        case .left:
            let foot = Vec2(board.minX + board.width * 0.28, horizon + board.height * 0.08)
            let head = Vec2(foot.x, board.minY + 20)
            let footFar = foot + (leftVanishing - foot) * 0.72
            let headFar = head + (leftVanishing - head) * 0.72
            let bottom = foot + (footFar - foot) * u
            let top = head + (headFar - head) * u
            return bottom + (top - bottom) * (1 - v)
        case .right:
            let foot = Vec2(board.maxX - board.width * 0.28, horizon + board.height * 0.08)
            let head = Vec2(foot.x, board.minY + 20)
            let footFar = foot + (rightVanishing - foot) * 0.72
            let headFar = head + (rightVanishing - head) * 0.72
            let bottom = foot + (footFar - foot) * u
            let top = head + (headFar - head) * u
            return bottom + (top - bottom) * (1 - v)
        }
    }
}
