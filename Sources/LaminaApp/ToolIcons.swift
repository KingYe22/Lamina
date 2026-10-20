import AppKit
import LaminaCore

/// Original vectors whose silhouettes follow the public Illustrator tool shapes.
enum ToolIcons {
    static func draw(_ tool: Tool, in rect: NSRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        let box = rect.insetBy(dx: 2, dy: 2)
        switch tool {
        case .selection: arrow(box)
        case .directSelection: directArrow(box)
        case .groupSelection: arrow(box); plus(NSRect(x: box.maxX - 7, y: box.maxY - 7, width: 6, height: 6), color: color)
        case .magicWand: wand(box)
        case .lasso: lasso(box)
        case .pen: nib(box, mark: nil, color: color)
        case .addAnchor: nib(box, mark: .plus, color: color)
        case .deleteAnchor: nib(box, mark: .minus, color: color)
        case .convertAnchor: caret(box)
        case .curvature: curvePen(box)
        case .text: glyph("T", box, color: color)
        case .areaText: glyph("T", box.insetBy(dx: 2, dy: 1), color: color); NSBezierPath(rect: box.insetBy(dx: 0, dy: 1)).stroke(1)
        case .pathText: pathType(box, color: color)
        case .verticalText: glyph("T", box, color: color, vertical: true)
        case .touchType: glyph("T", box, color: color); plus(NSRect(x: box.maxX - 6, y: box.minY, width: 6, height: 6), color: color)
        case .line: line(box.minX + 1, box.minY + 1, box.maxX - 1, box.maxY - 1)
        case .arc: arc(box)
        case .spiral: spiral(box)
        case .rectGrid: grid(box, polar: false)
        case .polarGrid: grid(box, polar: true)
        case .rectangle: filledShape(NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 1.5)), color: color)
        case .roundedRectangle: filledShape(NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 1.5), xRadius: 4, yRadius: 4), color: color)
        case .ellipse: filledShape(NSBezierPath(ovalIn: box.insetBy(dx: 0.5, dy: 1)), color: color, solid: true)
        case .polygon: filledShape(poly(box, sides: 6), color: color)
        case .star: star(box).stroke(1.5)
        case .flare: flare(box)
        case .brush: brush(box)
        case .blobBrush: blob(box)
        case .pencil: pencil(box)
        case .smooth: wave(box)
        case .pathEraser: pencil(box); minus(NSRect(x: box.minX, y: box.maxY - 6, width: 7, height: 4))
        case .joinTool: join(box)
        case .shaper: shaper(box)
        case .shapeBuilder: shapeBuilder(box)
        case .blend: blendMark(box)
        case .rotateView: rotateView(box)
        case .eraser: eraser(box)
        case .scissors: scissors(box)
        case .knife: knife(box)
        case .rotate: rotate(box)
        case .reflect: reflect(box)
        case .scale: scale(box)
        case .shear: shear(box)
        case .reshape: wave(box)
        case .width: widthMark(box)
        case .freeTransform: free(box)
        case .gradient: fade(box)
        case .mesh: grid(box, polar: false)
        case .eyedropper: dropper(box)
        case .measure: measure(box)
        case .hand: hand(box)
        case .zoom: zoom(box)
        case .artboard: NSBezierPath(rect: box.insetBy(dx: 2, dy: 2)).stroke(1.4)
        default: arrow(box)
        }
    }

    private enum NibMark { case plus, minus }

    /// Toolbar hosts are flipped, so y grows downward. Coordinates below are fractions of the box from the top-left.
    private static func at(_ box: NSRect, _ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: box.minX + x * box.width, y: box.minY + y * box.height)
    }

    /// Selection arrow: hollow cursor, tip at the top, notch in the tail.
    private static func arrow(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: at(box, 0.16, 0.04))
        path.line(to: at(box, 0.16, 0.58))
        path.line(to: at(box, 0.34, 0.42))
        path.line(to: at(box, 0.50, 0.96))
        path.line(to: at(box, 0.66, 0.82))
        path.line(to: at(box, 0.46, 0.40))
        path.line(to: at(box, 0.90, 0.40))
        path.close()
        path.stroke(1.15)
    }

    /// Direct-selection arrow: solid white, tip toward the lower right, notch in the tail.
    private static func directArrow(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: at(box, 0.18, 0.02))
        path.line(to: at(box, 0.18, 0.62))
        path.line(to: at(box, 0.34, 0.50))
        path.line(to: at(box, 0.08, 0.78))
        path.line(to: at(box, 0.08, 0.96))
        path.line(to: at(box, 0.96, 0.96))
        path.line(to: at(box, 0.42, 0.42))
        path.line(to: at(box, 0.78, 0.42))
        path.line(to: at(box, 0.62, 0.22))
        path.close()
        path.fill()
    }

    /// Gray body. Ellipse is solid gray; rectangle and hexagon keep a light edge.
    private static func filledShape(_ path: NSBezierPath, color: NSColor, solid: Bool = false) {
        NSColor(srgbRed: 109.0 / 255, green: 109.0 / 255, blue: 109.0 / 255, alpha: 1).setFill()
        path.fill()
        guard !solid else { return }
        color.setStroke()
        path.lineWidth = 1.7
        path.stroke()
    }

    private static func plus(_ rect: NSRect, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX, y: rect.minY))
        path.line(to: NSPoint(x: rect.midX, y: rect.maxY))
        path.move(to: NSPoint(x: rect.minX, y: rect.midY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        path.stroke(1.3)
    }

    private static func minus(_ rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.midY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        path.stroke(1.4)
    }

    private static func wand(_ box: NSRect) {
        line(box.minX + 2, box.minY + 2, box.maxX - 5, box.maxY - 4)
        star(NSRect(x: box.maxX - 9, y: box.maxY - 9, width: 8, height: 8)).fill()
    }

    private static func lasso(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: at(box, 0.46, 0.62))
        path.curve(to: at(box, 0.18, 0.22), controlPoint1: at(box, 0.08, 0.62), controlPoint2: at(box, 0.04, 0.18))
        path.curve(to: at(box, 0.55, 0.18), controlPoint1: at(box, 0.32, 0.02), controlPoint2: at(box, 0.55, 0.02))
        path.curve(to: at(box, 0.48, 0.48), controlPoint1: at(box, 0.92, 0.16), controlPoint2: at(box, 0.78, 0.42))
        path.stroke(1.2)
        let tail = NSBezierPath()
        tail.move(to: at(box, 0.52, 0.55))
        tail.line(to: at(box, 0.92, 0.96))
        tail.stroke(1.2)
    }

    private static func nib(_ box: NSRect, mark: NibMark?, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: at(box, 0.06, 0.94))
        path.line(to: at(box, 0.40, 0.52))
        path.line(to: at(box, 0.90, 0.10))
        path.line(to: at(box, 0.74, 0.04))
        path.line(to: at(box, 0.28, 0.46))
        path.close()
        path.fill()
        if mark == .plus { plus(NSRect(x: box.minX, y: box.minY, width: 7, height: 7), color: color) }
        if mark == .minus { minus(NSRect(x: box.minX, y: box.minY + 2, width: 7, height: 3)) }
    }

    private static func caret(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 3, y: box.minY + 4))
        path.line(to: NSPoint(x: box.midX, y: box.maxY - 3))
        path.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 4))
        path.stroke(1.7)
    }

    private static func curvePen(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: at(box, 0.12, 0.78))
        path.curve(to: at(box, 0.88, 0.22), controlPoint1: at(box, 0.08, 0.18), controlPoint2: at(box, 0.92, 0.82))
        path.stroke(1.35)
        NSBezierPath(ovalIn: NSRect(x: box.minX + box.width * 0.06, y: box.minY + box.height * 0.68, width: 3.5, height: 3.5)).stroke(1)
        NSBezierPath(ovalIn: NSRect(x: box.maxX - box.width * 0.22, y: box.minY + box.height * 0.12, width: 3.5, height: 3.5)).stroke(1)
    }

    private static func glyph(_ text: String, _ box: NSRect, color: NSColor, vertical: Bool = false) {
        let font = NSFont(name: "Times-Bold", size: box.height * 0.92) ?? NSFont.systemFont(ofSize: box.height * 0.9, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2 + 1), withAttributes: attrs)
        if vertical {
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: box.minX + 2, y: box.minY + 2))
            bar.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 2))
            bar.move(to: NSPoint(x: box.midX, y: box.minY + 2))
            bar.line(to: NSPoint(x: box.midX, y: box.maxY - 2))
            bar.stroke(1.15)
        }
    }

    private static func pathType(_ box: NSRect, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 1, y: box.minY + 4))
        path.curve(to: NSPoint(x: box.maxX - 1, y: box.minY + 6), controlPoint1: NSPoint(x: box.midX, y: box.maxY - 2), controlPoint2: NSPoint(x: box.midX, y: box.minY))
        path.stroke(1.3)
        glyph("T", NSRect(x: box.minX + 3, y: box.midY - 2, width: box.width - 6, height: box.height * 0.55), color: color)
    }

    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x1, y: y1))
        path.line(to: NSPoint(x: x2, y: y2))
        path.stroke(1.6)
    }

    private static func arc(_ box: NSRect) {
        let path = NSBezierPath()
        path.appendArc(withCenter: NSPoint(x: box.minX + 2, y: box.minY + 2), radius: box.width * 0.72, startAngle: 10, endAngle: 80, clockwise: false)
        path.stroke(1.6)
    }

    private static func spiral(_ box: NSRect) {
        let path = NSBezierPath()
        let c = NSPoint(x: box.midX, y: box.midY)
        var r: CGFloat = 1
        path.move(to: c)
        for i in 0..<28 {
            let a = CGFloat(i) / 28 * .pi * 5
            r = 1 + CGFloat(i) * (min(box.width, box.height) * 0.42) / 28
            path.line(to: NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
        }
        path.stroke(1.2)
    }

    private static func grid(_ box: NSRect, polar: Bool) {
        let rect = box.insetBy(dx: 2, dy: 2)
        if polar {
            NSBezierPath(ovalIn: rect).stroke(1.2)
            NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)).stroke(1.1)
            line(rect.midX, rect.minY, rect.midX, rect.maxY)
            line(rect.minX, rect.midY, rect.maxX, rect.midY)
        } else {
            NSBezierPath(rect: rect).stroke(1.3)
            line(rect.minX + rect.width / 3, rect.minY, rect.minX + rect.width / 3, rect.maxY)
            line(rect.minX + rect.width * 2 / 3, rect.minY, rect.minX + rect.width * 2 / 3, rect.maxY)
            line(rect.minX, rect.minY + rect.height / 3, rect.maxX, rect.minY + rect.height / 3)
            line(rect.minX, rect.minY + rect.height * 2 / 3, rect.maxX, rect.minY + rect.height * 2 / 3)
        }
    }

    private static func poly(_ box: NSRect, sides: Int) -> NSBezierPath {
        let path = NSBezierPath()
        let c = NSPoint(x: box.midX, y: box.midY)
        let r = min(box.width, box.height) / 2 - 1
        for i in 0..<sides {
            let a = CGFloat(i) / CGFloat(sides) * .pi * 2 - .pi / 2
            let p = NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
    }

    private static func star(_ box: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let c = NSPoint(x: box.midX, y: box.midY)
        let outer = min(box.width, box.height) / 2 - 0.5
        let inner = outer * 0.42
        for i in 0..<10 {
            let a = CGFloat(i) / 10 * .pi * 2 - .pi / 2
            let r = i % 2 == 0 ? outer : inner
            let p = NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
    }

    private static func flare(_ box: NSRect) {
        NSBezierPath(ovalIn: NSRect(x: box.midX - 3, y: box.midY - 3, width: 6, height: 6)).fill()
        for i in 0..<8 {
            let a = CGFloat(i) / 8 * .pi * 2
            line(box.midX + cos(a) * 4, box.midY + sin(a) * 4, box.midX + cos(a) * (box.width * 0.46), box.midY + sin(a) * (box.height * 0.46))
        }
    }

    private static func brush(_ box: NSRect) {
        let handle = NSRect(x: box.minX, y: box.minY, width: box.width * 0.46, height: box.height * 0.32)
        NSColor(srgbRed: 45.0 / 255, green: 140.0 / 255, blue: 235.0 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: handle, xRadius: 1.2, yRadius: 1.2).fill()
        let path = NSBezierPath()
        path.lineWidth = 1.05
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: handle.maxX - 1, y: handle.midY))
        path.line(to: at(box, 0.96, 0.92))
        path.move(to: NSPoint(x: handle.minX + 2, y: handle.maxY - 1))
        path.curve(to: at(box, 0.88, 0.96), controlPoint1: at(box, 0.4, 0.55), controlPoint2: at(box, 0.7, 0.9))
        path.move(to: NSPoint(x: handle.midX, y: handle.maxY - 1))
        path.line(to: at(box, 0.78, 0.78))
        path.stroke()
    }

    private static func blob(_ box: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.move(to: at(box, 0.15, 0.2))
        path.curve(to: at(box, 0.82, 0.84), controlPoint1: at(box, 0.05, 0.7), controlPoint2: at(box, 0.7, 0.15))
        path.stroke()
        let edge = NSBezierPath()
        edge.lineWidth = 1.05
        edge.move(to: at(box, 0.28, 0.16))
        edge.curve(to: at(box, 0.9, 0.7), controlPoint1: at(box, 0.2, 0.55), controlPoint2: at(box, 0.75, 0.2))
        edge.stroke()
    }

    private static func pencil(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 2, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.maxX - 6, y: box.minY + 6))
        path.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 3))
        path.line(to: NSPoint(x: box.maxX - 7, y: box.minY + 2))
        path.close()
        path.stroke(1.4)
    }

    private static func wave(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 1, y: box.midY))
        path.curve(to: NSPoint(x: box.maxX - 1, y: box.midY + 2), controlPoint1: NSPoint(x: box.minX + box.width * 0.3, y: box.maxY - 1), controlPoint2: NSPoint(x: box.minX + box.width * 0.7, y: box.minY + 1))
        path.stroke(1.5)
    }

    private static func join(_ box: NSRect) {
        NSBezierPath(ovalIn: NSRect(x: box.minX + 2, y: box.maxY - 7, width: 4, height: 4)).stroke(1.2)
        NSBezierPath(ovalIn: NSRect(x: box.maxX - 6, y: box.minY + 2, width: 4, height: 4)).stroke(1.2)
        line(box.minX + 6, box.maxY - 5, box.maxX - 6, box.minY + 4)
    }

    private static func eraser(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: at(box, 0.38, 0.06))
        path.line(to: at(box, 0.94, 0.28))
        path.line(to: at(box, 0.62, 0.94))
        path.line(to: at(box, 0.06, 0.72))
        path.close()
        path.fill()
        let band = NSBezierPath()
        band.move(to: at(box, 0.22, 0.4))
        band.line(to: at(box, 0.78, 0.6))
        NSColor(white: 0.45, alpha: 1).setStroke()
        band.lineWidth = 1.4
        band.stroke()
    }

    private static func scissors(_ box: NSRect) {
        NSBezierPath(ovalIn: NSRect(x: box.minX + 1, y: box.maxY - 8, width: 6, height: 6)).stroke(1.3)
        NSBezierPath(ovalIn: NSRect(x: box.minX + 1, y: box.minY + 2, width: 6, height: 6)).stroke(1.3)
        line(box.minX + 6, box.maxY - 5, box.maxX - 2, box.minY + 4)
        line(box.minX + 6, box.minY + 5, box.maxX - 2, box.maxY - 4)
    }

    private static func knife(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 2, y: box.minY + 2))
        path.line(to: NSPoint(x: box.maxX - 2, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.maxX - 6, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.minX + 2, y: box.minY + 6))
        path.close()
        path.stroke(1.25)
    }

    private static func rotate(_ box: NSRect) {
        let path = NSBezierPath()
        path.appendArc(withCenter: NSPoint(x: box.midX, y: box.midY + 1), radius: box.width * 0.32, startAngle: 30, endAngle: 300, clockwise: false)
        path.stroke(1.25)
        let head = NSBezierPath()
        head.move(to: at(box, 0.62, 0.08))
        head.line(to: at(box, 0.92, 0.18))
        head.line(to: at(box, 0.7, 0.32))
        head.stroke(1.15)
    }

    private static func reflect(_ box: NSRect) {
        let left = NSBezierPath()
        left.move(to: NSPoint(x: box.midX - 2, y: box.minY + 3))
        left.line(to: NSPoint(x: box.minX + 3, y: box.midY))
        left.line(to: NSPoint(x: box.midX - 2, y: box.maxY - 3))
        left.close()
        left.stroke(1.4)
        let right = NSBezierPath()
        right.move(to: NSPoint(x: box.midX + 2, y: box.minY + 3))
        right.line(to: NSPoint(x: box.maxX - 3, y: box.midY))
        right.line(to: NSPoint(x: box.midX + 2, y: box.maxY - 3))
        right.close()
        right.fill()
    }

    private static func scale(_ box: NSRect) {
        line(box.minX + 2, box.maxY - 2, box.minX + 2, box.midY)
        line(box.minX + 2, box.maxY - 2, box.midX, box.maxY - 2)
        line(box.maxX - 2, box.minY + 2, box.maxX - 2, box.midY)
        line(box.maxX - 2, box.minY + 2, box.midX, box.minY + 2)
    }

    private static func shear(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 5, y: box.minY + 3))
        path.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 3))
        path.line(to: NSPoint(x: box.maxX - 6, y: box.maxY - 3))
        path.line(to: NSPoint(x: box.minX + 1, y: box.maxY - 3))
        path.close()
        path.stroke(1.5)
    }

    private static func widthMark(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 2, y: box.midY))
        path.curve(to: NSPoint(x: box.maxX - 2, y: box.midY), controlPoint1: NSPoint(x: box.midX, y: box.maxY - 1), controlPoint2: NSPoint(x: box.midX, y: box.minY + 1))
        path.lineWidth = 1.4
        path.stroke()
        NSBezierPath(ovalIn: NSRect(x: box.midX - 2, y: box.midY - 2, width: 4, height: 4)).fill()
    }

    private static func free(_ box: NSRect) {
        let rect = box.insetBy(dx: 3, dy: 3)
        NSBezierPath(rect: rect).stroke(1.3)
        for p in [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)] {
            NSBezierPath(rect: NSRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)).fill()
        }
    }

    private static func fade(_ box: NSRect) {
        let rect = box.insetBy(dx: 1, dy: 2)
        if let gradient = NSGradient(colors: [NSColor.black, NSColor.white]) {
            gradient.draw(in: rect, angle: 0)
        }
        NSColor.black.setStroke()
        NSBezierPath(rect: rect).stroke(1)
    }

    private static func dropper(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 4, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.midX + 1, y: box.midY + 1))
        path.line(to: NSPoint(x: box.midX - 2, y: box.midY + 4))
        path.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 3))
        path.line(to: NSPoint(x: box.maxX - 6, y: box.minY + 1))
        path.line(to: NSPoint(x: box.midX - 4, y: box.midY))
        path.close()
        path.stroke(1.2)
    }

    private static func measure(_ box: NSRect) {
        NSBezierPath(rect: NSRect(x: box.minX + 2, y: box.midY - 3, width: box.width - 4, height: 6)).stroke(1.3)
        line(box.minX + 4, box.midY - 3, box.minX + 4, box.midY + 3)
        line(box.maxX - 4, box.midY - 3, box.maxX - 4, box.midY + 3)
    }

    private static func zoom(_ box: NSRect) {
        let glass = NSRect(x: box.minX + 1, y: box.minY + 1, width: box.width * 0.62, height: box.height * 0.62)
        NSBezierPath(ovalIn: glass).stroke(1.35)
        line(glass.maxX - glass.width * 0.22, glass.maxY - glass.height * 0.22, box.maxX - 1, box.maxY - 1)
    }

    private static func hand(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: at(box, 0.28, 0.02))
        path.line(to: at(box, 0.28, 0.48))
        path.line(to: at(box, 0.14, 0.55))
        path.line(to: at(box, 0.14, 0.78))
        path.curve(to: at(box, 0.48, 0.96), controlPoint1: at(box, 0.14, 0.96), controlPoint2: at(box, 0.3, 0.96))
        path.line(to: at(box, 0.86, 0.72))
        path.line(to: at(box, 0.86, 0.42))
        path.line(to: at(box, 0.7, 0.38))
        path.line(to: at(box, 0.7, 0.08))
        path.close()
        path.fill()
    }

    /// Shaper is a ring plus a filled stroke, not a spiral.
    private static func shaper(_ box: NSRect) {
        let ring = NSBezierPath(ovalIn: NSRect(x: box.minX + 1, y: box.minY + box.height * 0.12, width: box.width * 0.58, height: box.height * 0.72))
        ring.lineWidth = max(2.4, box.width * 0.14)
        ring.stroke()
        let blob = NSBezierPath()
        blob.move(to: at(box, 0.52, 0.18))
        blob.curve(to: at(box, 0.98, 0.72), controlPoint1: at(box, 0.82, 0.02), controlPoint2: at(box, 1.02, 0.4))
        blob.curve(to: at(box, 0.58, 0.48), controlPoint1: at(box, 0.92, 0.98), controlPoint2: at(box, 0.68, 0.82))
        blob.curve(to: at(box, 0.52, 0.18), controlPoint1: at(box, 0.46, 0.28), controlPoint2: at(box, 0.42, 0.22))
        blob.fill()
    }

    private static func shapeBuilder(_ box: NSRect) {
        NSBezierPath(ovalIn: box.insetBy(dx: 1, dy: 1)).stroke(1.2)
        let mark = NSBezierPath()
        mark.move(to: at(box, 0.5, 0.28))
        mark.line(to: at(box, 0.5, 0.72))
        mark.move(to: at(box, 0.28, 0.5))
        mark.line(to: at(box, 0.72, 0.5))
        mark.stroke(1.2)
    }

    private static func blendMark(_ box: NSRect) {
        NSBezierPath(rect: NSRect(x: box.minX + 1, y: box.minY + box.height * 0.28, width: box.width * 0.34, height: box.height * 0.34)).stroke(1.15)
        NSBezierPath(rect: NSRect(x: box.midX, y: box.minY + box.height * 0.42, width: box.width * 0.42, height: box.height * 0.42)).stroke(1.15)
        line(box.minX + box.width * 0.36, box.midY, box.midX, box.midY + 2)
    }

    private static func rotateView(_ box: NSRect) {
        let path = NSBezierPath()
        path.appendArc(withCenter: NSPoint(x: box.midX - 1, y: box.midY + 1), radius: box.width * 0.34, startAngle: 200, endAngle: 40, clockwise: false)
        path.stroke(1.2)
        let head = NSBezierPath()
        head.move(to: at(box, 0.72, 0.1))
        head.line(to: at(box, 0.96, 0.28))
        head.line(to: at(box, 0.68, 0.34))
        head.stroke(1.15)
    }
}

private extension NSBezierPath {
    func stroke(_ width: CGFloat) {
        lineWidth = width
        lineCapStyle = .round
        lineJoinStyle = .round
        stroke()
    }
}
