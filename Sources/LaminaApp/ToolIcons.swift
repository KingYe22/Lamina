import AppKit
import LaminaCore

/// Original vectors whose silhouettes follow the public Illustrator tool shapes.
enum ToolIcons {
    static func draw(_ tool: Tool, in rect: NSRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        let box = rect.insetBy(dx: 2, dy: 2)
        switch tool {
        case .selection: arrow(box, filled: true)
        case .directSelection: arrow(box, filled: false)
        case .groupSelection: arrow(box, filled: true); plus(NSRect(x: box.maxX - 7, y: box.maxY - 7, width: 6, height: 6), color: color)
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
        case .rectangle: NSBezierPath(rect: box.insetBy(dx: 1, dy: 3)).stroke(1.6)
        case .roundedRectangle: NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 3), xRadius: 4, yRadius: 4).stroke(1.6)
        case .ellipse: NSBezierPath(ovalIn: box.insetBy(dx: 1, dy: 2)).stroke(1.6)
        case .polygon: poly(box, sides: 6).stroke(1.6)
        case .star: star(box).stroke(1.5)
        case .flare: flare(box)
        case .brush: brush(box)
        case .blobBrush: brush(box); NSBezierPath(ovalIn: NSRect(x: box.maxX - 8, y: box.minY, width: 7, height: 7)).fill()
        case .pencil: pencil(box)
        case .smooth: wave(box)
        case .pathEraser: pencil(box); minus(NSRect(x: box.minX, y: box.maxY - 6, width: 7, height: 4))
        case .joinTool: join(box)
        case .shaper: wave(box); NSBezierPath(rect: box.insetBy(dx: 4, dy: 5)).stroke(1)
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
        default: arrow(box, filled: true)
        }
    }

    private enum NibMark { case plus, minus }

    private static func arrow(_ box: NSRect, filled: Bool) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 2, y: box.minY + 1))
        path.line(to: NSPoint(x: box.minX + 2, y: box.maxY - 1))
        path.line(to: NSPoint(x: box.midX + 1, y: box.midY))
        path.line(to: NSPoint(x: box.maxX - 1, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.midX, y: box.midY - 1))
        path.line(to: NSPoint(x: box.minX + 7, y: box.minY + 1))
        path.close()
        if filled { path.fill() } else { path.stroke(1.5) }
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
        path.move(to: NSPoint(x: box.minX + 4, y: box.minY + 3))
        path.curve(to: NSPoint(x: box.midX, y: box.maxY - 2), controlPoint1: NSPoint(x: box.minX, y: box.midY), controlPoint2: NSPoint(x: box.midX - 6, y: box.maxY))
        path.curve(to: NSPoint(x: box.maxX - 2, y: box.midY), controlPoint1: NSPoint(x: box.maxX, y: box.maxY), controlPoint2: NSPoint(x: box.maxX, y: box.midY + 4))
        path.curve(to: NSPoint(x: box.midX + 2, y: box.minY + 4), controlPoint1: NSPoint(x: box.maxX - 2, y: box.minY + 2), controlPoint2: NSPoint(x: box.midX + 8, y: box.minY + 2))
        path.stroke(1.4)
    }

    private static func nib(_ box: NSRect, mark: NibMark?, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 3, y: box.minY + 2))
        path.line(to: NSPoint(x: box.midX + 1, y: box.midY - 1))
        path.line(to: NSPoint(x: box.maxX - 2, y: box.maxY - 3))
        path.line(to: NSPoint(x: box.maxX - 5, y: box.maxY - 1))
        path.line(to: NSPoint(x: box.midX - 2, y: box.midY - 2))
        path.line(to: NSPoint(x: box.minX + 1, y: box.minY + 5))
        path.close()
        path.fill()
        if mark == .plus { plus(NSRect(x: box.minX, y: box.maxY - 8, width: 7, height: 7), color: color) }
        if mark == .minus { minus(NSRect(x: box.minX, y: box.maxY - 5, width: 7, height: 3)) }
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
        path.move(to: NSPoint(x: box.minX + 3, y: box.minY + 4))
        path.curve(to: NSPoint(x: box.maxX - 3, y: box.maxY - 4), controlPoint1: NSPoint(x: box.minX + 2, y: box.maxY - 2), controlPoint2: NSPoint(x: box.maxX - 2, y: box.minY + 2))
        path.stroke(1.6)
        NSBezierPath(ovalIn: NSRect(x: box.maxX - 6, y: box.maxY - 6, width: 4, height: 4)).fill()
    }

    private static func glyph(_ text: String, _ box: NSRect, color: NSColor, vertical: Bool = false) {
        let font = NSFont(name: "Times-Bold", size: box.height * 0.92) ?? NSFont.systemFont(ofSize: box.height * 0.9, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2 + 1), withAttributes: attrs)
        if vertical {
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: box.maxX - 2, y: box.minY + 2))
            bar.line(to: NSPoint(x: box.maxX - 2, y: box.maxY - 2))
            bar.stroke(1.2)
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
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 3, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.maxX - 5, y: box.minY + 7))
        path.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 3))
        path.line(to: NSPoint(x: box.maxX - 7, y: box.minY + 2))
        path.line(to: NSPoint(x: box.minX + 1, y: box.maxY - 6))
        path.close()
        path.fill()
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
        let body = NSBezierPath(roundedRect: NSRect(x: box.minX + 4, y: box.minY + 3, width: box.width - 8, height: box.height - 6), xRadius: 2, yRadius: 2)
        body.stroke(1.5)
        line(box.minX + 4, box.midY, box.maxX - 4, box.midY)
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
        path.fill()
    }

    private static func rotate(_ box: NSRect) {
        let path = NSBezierPath()
        path.appendArc(withCenter: NSPoint(x: box.midX, y: box.midY), radius: box.width * 0.34, startAngle: 40, endAngle: 320, clockwise: false)
        path.stroke(1.6)
        let head = NSBezierPath()
        head.move(to: NSPoint(x: box.midX + box.width * 0.1, y: box.minY + 3))
        head.line(to: NSPoint(x: box.midX + box.width * 0.34, y: box.minY + 1))
        head.line(to: NSPoint(x: box.midX + box.width * 0.22, y: box.minY + 8))
        head.close()
        head.fill()
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
        let rect = box.insetBy(dx: 2, dy: 3)
        NSBezierPath(rect: rect).stroke(1.2)
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * 0.45, height: rect.height)).fill()
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
        path.fill()
    }

    private static func measure(_ box: NSRect) {
        NSBezierPath(rect: NSRect(x: box.minX + 2, y: box.midY - 3, width: box.width - 4, height: 6)).stroke(1.3)
        line(box.minX + 4, box.midY - 3, box.minX + 4, box.midY + 3)
        line(box.maxX - 4, box.midY - 3, box.maxX - 4, box.midY + 3)
    }

    private static func zoom(_ box: NSRect) {
        let r = box.width * 0.28
        NSBezierPath(ovalIn: NSRect(x: box.minX + 1, y: box.minY + box.height * 0.28, width: r * 2, height: r * 2)).stroke(1.6)
        line(box.minX + 1 + r * 1.55, box.minY + box.height * 0.28 + r * 0.45, box.maxX - 1, box.minY + 2)
    }

    private static func hand(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 7, y: box.maxY - 1))
        path.line(to: NSPoint(x: box.minX + 7, y: box.midY + 1))
        path.line(to: NSPoint(x: box.minX + 4, y: box.midY - 2))
        path.line(to: NSPoint(x: box.minX + 4, y: box.minY + 5))
        path.curve(to: NSPoint(x: box.midX + 2, y: box.minY + 2), controlPoint1: NSPoint(x: box.minX + 4, y: box.minY + 1), controlPoint2: NSPoint(x: box.midX - 2, y: box.minY + 1))
        path.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 6))
        path.line(to: NSPoint(x: box.maxX - 3, y: box.midY + 2))
        path.line(to: NSPoint(x: box.maxX - 6, y: box.midY))
        path.line(to: NSPoint(x: box.maxX - 6, y: box.maxY - 5))
        path.close()
        path.stroke(1.3)
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
