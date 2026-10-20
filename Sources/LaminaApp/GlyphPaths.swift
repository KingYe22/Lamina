import AppKit
import CoreText
import LaminaCore

enum MacGlyphs {
    static func install() {
        GlyphOutline.provider = { text in
            outlines(for: text)
        }
    }

    /// Core Text glyph paths. Y-up font units are flipped onto the y-down baseline.
    /// An empty result lets the built-in Latin outlines stand in.
    static func outlines(for text: TextObject) -> [PathItem] {
        let font = CTFontCreateWithName(text.fontName as CFString, CGFloat(text.fontSize), nil)
        let attributed = NSAttributedString(string: text.string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }
        var items: [PathItem] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let attribute = attributes[kCTFontAttributeName] else { continue }
            let cfFont = attribute as CFTypeRef
            guard CFGetTypeID(cfFont) == CTFontGetTypeID() else { continue }
            let runFont = cfFont as! CTFont
            for index in 0..<count {
                var transform = CGAffineTransform(translationX: CGFloat(text.origin.x) + positions[index].x, y: CGFloat(text.origin.y))
                transform = transform.scaledBy(x: 1, y: -1)
                guard let cg = CTFontCreatePathForGlyph(runFont, glyphs[index], &transform) else { continue }
                items.append(contentsOf: pathItems(from: cg))
            }
        }
        return items
    }

    private static func pathItems(from path: CGPath) -> [PathItem] {
        var items: [PathItem] = []
        var nodes: [PathNode] = []
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                if nodes.count >= 2 {
                    items.append(PathItem(nodes: nodes, closed: false, shape: .free))
                }
                nodes = [.corner(Vec2(Double(points[0].x), Double(points[0].y)))]
            case .addLineToPoint:
                nodes.append(.corner(Vec2(Double(points[0].x), Double(points[0].y))))
            case .addQuadCurveToPoint:
                let current = nodes.last?.anchor ?? Vec2(Double(points[0].x), Double(points[0].y))
                let control = Vec2(Double(points[0].x), Double(points[0].y))
                let end = Vec2(Double(points[1].x), Double(points[1].y))
                if !nodes.isEmpty {
                    nodes[nodes.count - 1].outHandle = current + (control - current) * (2.0 / 3.0)
                }
                var node = PathNode.corner(end)
                node.inHandle = end + (control - end) * (2.0 / 3.0)
                nodes.append(node)
            case .addCurveToPoint:
                if !nodes.isEmpty {
                    nodes[nodes.count - 1].outHandle = Vec2(Double(points[0].x), Double(points[0].y))
                }
                var node = PathNode.corner(Vec2(Double(points[2].x), Double(points[2].y)))
                node.inHandle = Vec2(Double(points[1].x), Double(points[1].y))
                nodes.append(node)
            case .closeSubpath:
                if nodes.count >= 2 {
                    items.append(PathItem(nodes: nodes, closed: true, shape: .free))
                }
                nodes = []
            default:
                break
            }
        }
        if nodes.count >= 2 {
            items.append(PathItem(nodes: nodes, closed: false, shape: .free))
        }
        return items
    }
}
