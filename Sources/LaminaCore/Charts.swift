import Foundation

public enum ChartBuilder {
    public static let sampleSeries: [[Double]] = [[4, 7, 3, 8, 5], [2, 3, 6, 2, 4]]

    public static func items(kind: ChartKind, frame: Rect2, series input: [[Double]], color: RGBA) -> [ArtItem] {
        let series = input.isEmpty ? [[1.0, 2, 1.5]] : input
        let palette = colors(series.count, base: color)
        switch kind {
        case .column: return columns(frame: frame, series: [series[0]], stacked: false, horizontal: false, palette: palette)
        case .stackedColumn: return columns(frame: frame, series: series, stacked: true, horizontal: false, palette: palette)
        case .bar: return columns(frame: frame, series: [series[0]], stacked: false, horizontal: true, palette: palette)
        case .stackedBar: return columns(frame: frame, series: series, stacked: true, horizontal: true, palette: palette)
        case .line: return lines(frame: frame, series: series, area: false, palette: palette)
        case .area: return lines(frame: frame, series: series, area: true, palette: palette)
        case .scatter: return scatter(frame: frame, series: series, palette: palette)
        case .pie: return pie(frame: frame, values: series[0], palette: palette)
        case .radar: return radar(frame: frame, series: series, palette: palette)
        }
    }

    public static func object(kind: ChartKind, frame: Rect2) -> GraphObject {
        GraphObject(name: kind.title, frame: frame, values: sampleSeries[0], color: RGBA(hex: "#1473E6"), kind: kind, series: sampleSeries)
    }

    private static func colors(_ count: Int, base: RGBA) -> [RGBA] {
        (0..<max(1, count)).map { index in
            let t = Double(index) / Double(max(1, count))
            return base.mixed(with: RGBA(hex: "#E34850"), t: t * 0.85)
        }
    }

    private static func columns(frame: Rect2, series: [[Double]], stacked: Bool, horizontal: Bool, palette: [RGBA]) -> [ArtItem] {
        let count = series.first?.count ?? 0
        guard count > 0 else { return [] }
        let totals = (0..<count).map { index in series.reduce(0) { $0 + (index < $1.count ? $1[index] : 0) } }
        let peak = max(0.01, stacked ? (totals.max() ?? 1) : (series.flatMap { $0 }.max() ?? 1))
        var items: [ArtItem] = []
        for index in 0..<count {
            var offset = 0.0
            for (s, row) in series.enumerated() {
                let value = index < row.count ? row[index] : 0
                let span = (horizontal ? frame.width : frame.height) * value / peak
                let slot = (horizontal ? frame.height : frame.width) / Double(count)
                let rect: Rect2
                if horizontal {
                    rect = Rect2(x: frame.x + offset, y: frame.y + Double(index) * slot + slot * 0.15, width: span, height: slot * 0.7)
                } else {
                    rect = Rect2(x: frame.x + Double(index) * slot + slot * 0.15, y: frame.maxY - offset - span, width: slot * 0.7, height: span)
                }
                offset += stacked ? span : 0
                if !stacked { offset = 0 }
                items.append(.path(PathObject(name: "图表", path: PathBuilder.rectangle(rect), appearance: Appearance(fill: .solid(palette[s % palette.count]), stroke: nil))))
            }
        }
        return items
    }

    private static func lines(frame: Rect2, series: [[Double]], area: Bool, palette: [RGBA]) -> [ArtItem] {
        series.enumerated().map { index, row in
            let peak = max(0.01, row.max() ?? 1)
            let nodes: [PathNode] = row.enumerated().map { i, value in
                let x = frame.x + frame.width * (row.count <= 1 ? 0.5 : Double(i) / Double(row.count - 1))
                let y = frame.maxY - frame.height * (value / peak)
                return .corner(Vec2(x, y))
            }
            if area {
                var closed = nodes
                closed.append(.corner(Vec2(frame.maxX, frame.maxY)))
                closed.append(.corner(Vec2(frame.x, frame.maxY)))
                let path = PathItem(nodes: closed, closed: true, shape: .free)
                return .path(PathObject(name: "面积", path: path, appearance: Appearance(fill: .solid(palette[index % palette.count]), stroke: nil)))
            }
            let path = PathItem(nodes: nodes, closed: false, shape: .free)
            return .path(PathObject(name: "折线", path: path, appearance: Appearance(fill: nil, stroke: StrokeStyle(paint: .solid(palette[index % palette.count]), width: 2))))
        }
    }

    private static func scatter(frame: Rect2, series: [[Double]], palette: [RGBA]) -> [ArtItem] {
        var items: [ArtItem] = []
        for (index, row) in series.enumerated() {
            let peak = max(0.01, row.max() ?? 1)
            for (i, value) in row.enumerated() {
                let x = frame.x + frame.width * (row.count <= 1 ? 0.5 : Double(i) / Double(row.count - 1))
                let y = frame.maxY - frame.height * (value / peak)
                let rect = PathBuilder.rectangle(Rect2(x: x - 3, y: y - 3, width: 6, height: 6))
                items.append(.path(PathObject(name: "散点", path: rect, appearance: Appearance(fill: .solid(palette[index % palette.count]), stroke: nil))))
            }
        }
        return items
    }

    private static func pie(frame: Rect2, values: [Double], palette: [RGBA]) -> [ArtItem] {
        let total = max(0.01, values.reduce(0, +))
        let center = frame.center
        let radius = min(frame.width, frame.height) * 0.45
        var angle = -Double.pi / 2
        return values.enumerated().map { index, value in
            let sweep = value / total * Double.pi * 2
            let path = wedge(center: center, radius: radius, start: angle, end: angle + sweep)
            angle += sweep
            return .path(PathObject(name: "扇区", path: path, appearance: Appearance(fill: .solid(palette[index % palette.count]), stroke: StrokeStyle(paint: .solid(.white), width: 1))))
        }
    }

    private static func wedge(center: Vec2, radius: Double, start: Double, end: Double) -> PathItem {
        var nodes = [PathNode.corner(center)]
            let steps = max(2, Int(((end - start) / (Double.pi / 8)).rounded(.up)))
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let ang = start + (end - start) * t
            nodes.append(.corner(center + Vec2(cos(ang), sin(ang)) * radius))
        }
        return PathItem(nodes: nodes, closed: true, shape: .free)
    }

    private static func radar(frame: Rect2, series: [[Double]], palette: [RGBA]) -> [ArtItem] {
        let center = frame.center
        let radius = min(frame.width, frame.height) * 0.45
        return series.enumerated().map { index, row in
            let peak = max(0.01, row.max() ?? 1)
            let nodes = row.enumerated().map { i, value -> PathNode in
                let ang = -Double.pi / 2 + Double(i) / Double(max(1, row.count)) * Double.pi * 2
                let r = radius * value / peak
                return .corner(center + Vec2(cos(ang), sin(ang)) * r)
            }
            return .path(PathObject(name: "雷达", path: PathItem(nodes: nodes, closed: true, shape: .free), appearance: Appearance(fill: .solid(palette[index].mixed(with: .white, t: 0.4)), stroke: StrokeStyle(paint: .solid(palette[index]), width: 1.5))))
        }
    }
}
