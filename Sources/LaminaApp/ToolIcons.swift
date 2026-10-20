import AppKit

/// Original vector tool marks. The silhouettes follow the public Illustrator tool shapes.
enum ToolIcons {
    static func draw(_ tool: Tool, in rect: NSRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        let box = rect.insetBy(dx: 3, dy: 3)
        switch tool {
        case .selection: arrow(box, filled: true)
        case .directSelection: arrow(box, filled: false)
        case .rectangle: box.insetBy(dx: 1, dy: 3).nsPath.stroke(2)
        case .ellipse: NSBezierPath(ovalIn: box.insetBy(dx: 1, dy: 2)).stroke(2)
        case .polygon: polygon(box, sides: 6).stroke(2)
        case .line:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: box.minX + 1, y: box.maxY - 1))
            path.line(to: NSPoint(x: box.maxX - 1, y: box.minY + 1))
            path.stroke(2)
        case .brush: brush(box)
        case .pen: pen(box)
        case .pencil: pencil(box)
        case .eraser: eraser(box)
        case .rotate: rotate(box)
        case .scale: scale(box)
        case .text: textMark(box, color: color)
        case .zoom: zoom(box)
        case .hand: hand(box)
        case .gradient: gradient(box, color: color)
        case .eyedropper: dropper(box)
        default: arrow(box, filled: true)
        }
    }

    private static func arrow(_ box: NSRect, filled: Bool) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 1, y: box.minY + 1))
        path.line(to: NSPoint(x: box.minX + 1, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.midX + 1, y: box.midY + 1))
        path.line(to: NSPoint(x: box.maxX - 1, y: box.maxY - 1))
        path.line(to: NSPoint(x: box.midX - 1, y: box.midY + 3))
        path.line(to: NSPoint(x: box.minX + 5, y: box.minY + 1))
        path.close()
        if filled { path.fill() } else { path.stroke(1.6) }
    }

    private static func polygon(_ box: NSRect, sides: Int) -> NSBezierPath {
        let path = NSBezierPath()
        let c = NSPoint(x: box.midX, y: box.midY)
        let r = min(box.width, box.height) / 2
        for i in 0..<sides {
            let a = CGFloat(i) / CGFloat(sides) * .pi * 2 - .pi / 2
            let p = NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
    }

    private static func brush(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 3, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.maxX - 4, y: box.minY + 6))
        path.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 3))
        path.line(to: NSPoint(x: box.maxX - 6, y: box.minY + 2))
        path.line(to: NSPoint(x: box.minX + 1, y: box.maxY - 5))
        path.close()
        path.fill()
    }

    private static func pen(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.midX, y: box.maxY - 1))
        path.line(to: NSPoint(x: box.maxX - 3, y: box.midY))
        path.line(to: NSPoint(x: box.midX + 2, y: box.midY))
        path.line(to: NSPoint(x: box.midX + 2, y: box.minY + 2))
        path.line(to: NSPoint(x: box.midX - 2, y: box.minY + 2))
        path.line(to: NSPoint(x: box.midX - 2, y: box.midY))
        path.line(to: NSPoint(x: box.minX + 3, y: box.midY))
        path.close()
        path.fill()
    }

    private static func pencil(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 2, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.maxX - 5, y: box.minY + 5))
        path.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 2))
        path.line(to: NSPoint(x: box.maxX - 6, y: box.minY + 1))
        path.close()
        path.stroke(1.6)
    }

    private static func eraser(_ box: NSRect) {
        let body = NSRect(x: box.minX + 3, y: box.minY + 4, width: box.width - 6, height: box.height - 8)
        NSBezierPath(roundedRect: body, xRadius: 2, yRadius: 2).stroke(1.6)
        let band = NSBezierPath()
        band.move(to: NSPoint(x: body.minX, y: body.midY))
        band.line(to: NSPoint(x: body.maxX, y: body.midY))
        band.stroke(1.4)
    }

    private static func rotate(_ box: NSRect) {
        let path = NSBezierPath()
        path.appendArc(withCenter: NSPoint(x: box.midX, y: box.midY + 1), radius: box.width * 0.36, startAngle: 30, endAngle: 300, clockwise: false)
        path.stroke(1.7)
        let head = NSBezierPath()
        head.move(to: NSPoint(x: box.midX + box.width * 0.18, y: box.minY + 3))
        head.line(to: NSPoint(x: box.midX + box.width * 0.38, y: box.minY + 1))
        head.line(to: NSPoint(x: box.midX + box.width * 0.28, y: box.minY + 8))
        head.close()
        head.fill()
    }

    private static func scale(_ box: NSRect) {
        let a = NSBezierPath()
        a.move(to: NSPoint(x: box.minX + 2, y: box.maxY - 2))
        a.line(to: NSPoint(x: box.minX + 2, y: box.midY))
        a.move(to: NSPoint(x: box.minX + 2, y: box.maxY - 2))
        a.line(to: NSPoint(x: box.midX, y: box.maxY - 2))
        a.stroke(1.7)
        let b = NSBezierPath()
        b.move(to: NSPoint(x: box.maxX - 2, y: box.minY + 2))
        b.line(to: NSPoint(x: box.maxX - 2, y: box.midY))
        b.move(to: NSPoint(x: box.maxX - 2, y: box.minY + 2))
        b.line(to: NSPoint(x: box.midX, y: box.minY + 2))
        b.stroke(1.7)
    }

    private static func textMark(_ box: NSRect, color: NSColor) {
        let title = "T" as NSString
        let font = NSFont.systemFont(ofSize: box.height * 0.95, weight: .bold)
        let size = title.size(withAttributes: [.font: font])
        title.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: [
            .font: font, .foregroundColor: color
        ])
    }

    private static func zoom(_ box: NSRect) {
        let r = box.width * 0.32
        NSBezierPath(ovalIn: NSRect(x: box.minX + 1, y: box.minY + 1, width: r * 2, height: r * 2)).stroke(1.7)
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: box.minX + 1 + r * 1.7, y: box.minY + 1 + r * 1.7))
        handle.line(to: NSPoint(x: box.maxX - 1, y: box.maxY - 1))
        handle.stroke(2)
    }

    private static func hand(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 7, y: box.maxY - 2))
        path.line(to: NSPoint(x: box.minX + 7, y: box.midY))
        path.line(to: NSPoint(x: box.minX + 4, y: box.midY - 2))
        path.line(to: NSPoint(x: box.minX + 4, y: box.minY + 6))
        path.curve(to: NSPoint(x: box.midX, y: box.minY + 2), controlPoint1: NSPoint(x: box.minX + 4, y: box.minY + 2), controlPoint2: NSPoint(x: box.midX - 4, y: box.minY + 2))
        path.line(to: NSPoint(x: box.maxX - 4, y: box.minY + 6))
        path.line(to: NSPoint(x: box.maxX - 4, y: box.midY + 2))
        path.line(to: NSPoint(x: box.maxX - 7, y: box.midY - 2))
        path.line(to: NSPoint(x: box.maxX - 7, y: box.maxY - 6))
        path.close()
        path.stroke(1.4)
    }

    private static func gradient(_ box: NSRect, color: NSColor) {
        let rect = box.insetBy(dx: 1, dy: 3)
        NSBezierPath(rect: rect).stroke(1.4)
        color.withAlphaComponent(0.85).setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * 0.45, height: rect.height)).fill()
    }

    private static func dropper(_ box: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + 4, y: box.maxY - 3))
        path.line(to: NSPoint(x: box.midX + 2, y: box.midY))
        path.line(to: NSPoint(x: box.midX - 1, y: box.midY + 3))
        path.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 4))
        path.line(to: NSPoint(x: box.maxX - 6, y: box.minY + 2))
        path.line(to: NSPoint(x: box.midX - 4, y: box.midY))
        path.close()
        path.stroke(1.5)
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

private extension NSRect {
    var nsPath: NSBezierPath { NSBezierPath(rect: self) }
}
