import AppKit

/// Original vector controls. Shapes follow the public Illustrator panel layout, not Adobe artwork.
enum PanelIcons {
    static func menu(in rect: NSRect) {
        Theme.dim.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.1
        path.lineCapStyle = .round
        for step in 0..<3 {
            let y = rect.midY + CGFloat(step - 1) * 3.2
            path.move(to: NSPoint(x: rect.minX + 1, y: y))
            path.line(to: NSPoint(x: rect.maxX - 1, y: y))
        }
        path.stroke()
    }

    static func chevronDown(in rect: NSRect, color: NSColor = Theme.dim) {
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.minX, y: rect.midY - 2))
        path.line(to: NSPoint(x: rect.midX, y: rect.midY + 2))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY - 2))
        path.stroke()
    }

    static func field(_ rect: NSRect, text: String, align: NSTextAlignment = .left) {
        Theme.raised.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        Theme.line.setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        border.lineWidth = 1
        border.stroke()
        let font = NSFont.systemFont(ofSize: 11)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let x = align == .center ? rect.midX - size.width / 2 : rect.minX + 6
        (text as NSString).draw(at: NSPoint(x: x, y: rect.midY - size.height / 2), withAttributes: [
            .font: font, .foregroundColor: Theme.text
        ])
    }

    static func popup(_ rect: NSRect, title: String) {
        field(rect, text: title)
        chevronDown(in: NSRect(x: rect.maxX - 14, y: rect.midY - 3, width: 8, height: 6))
    }

    static func stepper(_ rect: NSRect, title: String) {
        field(NSRect(x: rect.minX, y: rect.minY, width: rect.width - 16, height: rect.height), text: title)
        let stack = NSRect(x: rect.maxX - 15, y: rect.minY, width: 14, height: rect.height)
        Theme.raised.setFill()
        NSBezierPath(roundedRect: stack, xRadius: 2, yRadius: 2).fill()
        chevronDown(in: NSRect(x: stack.minX + 3, y: stack.midY + 1, width: 8, height: 5))
        let up = NSBezierPath()
        Theme.dim.setStroke()
        up.lineWidth = 1.2
        up.lineCapStyle = .round
        up.move(to: NSPoint(x: stack.minX + 3, y: stack.midY - 2))
        up.line(to: NSPoint(x: stack.midX, y: stack.midY - 5))
        up.line(to: NSPoint(x: stack.maxX - 3, y: stack.midY - 2))
        up.stroke()
    }

    static func checkbox(at origin: NSPoint, on: Bool, title: String) {
        let box = NSRect(x: origin.x, y: origin.y, width: 13, height: 13)
        Theme.raised.setFill()
        NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
        (on ? Theme.accent : Theme.line).setStroke()
        let border = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
        border.lineWidth = 1
        border.stroke()
        if on {
            Theme.accent.setStroke()
            let mark = NSBezierPath()
            mark.lineWidth = 1.6
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            mark.move(to: NSPoint(x: box.minX + 3, y: box.midY))
            mark.line(to: NSPoint(x: box.minX + 5.5, y: box.minY + 3))
            mark.line(to: NSPoint(x: box.maxX - 2.5, y: box.maxY - 3))
            mark.stroke()
        }
        (title as NSString).draw(at: NSPoint(x: box.maxX + 6, y: origin.y - 1), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.text
        ])
    }

    static func well(_ rect: NSRect, selected: Bool) {
        (selected ? Theme.accent.withAlphaComponent(0.9) : Theme.raised).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
    }

    static func eye(in rect: NSRect, open: Bool) {
        let color = open ? Theme.text : Theme.dim
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.move(to: NSPoint(x: rect.minX, y: rect.midY))
        path.curve(to: NSPoint(x: rect.maxX, y: rect.midY),
                   controlPoint1: NSPoint(x: rect.minX + rect.width * 0.25, y: rect.minY),
                   controlPoint2: NSPoint(x: rect.maxX - rect.width * 0.25, y: rect.minY))
        path.move(to: NSPoint(x: rect.minX, y: rect.midY))
        path.curve(to: NSPoint(x: rect.maxX, y: rect.midY),
                   controlPoint1: NSPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY),
                   controlPoint2: NSPoint(x: rect.maxX - rect.width * 0.25, y: rect.maxY))
        path.stroke()
        if open {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 2.2, y: rect.midY - 2.2, width: 4.4, height: 4.4)).fill()
        } else {
            let slash = NSBezierPath()
            slash.lineWidth = 1.2
            slash.move(to: NSPoint(x: rect.minX, y: rect.minY))
            slash.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            slash.stroke()
        }
    }

    static func swatch(in rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1)).fill()
        NSColor.black.withAlphaComponent(0.65).setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    static func align(_ kind: Int, in rect: NSRect) {
        let ink = Theme.text
        ink.setStroke()
        let box = rect.insetBy(dx: 3, dy: 3)
        switch kind {
        case 0: edge(box, axis: .minX); object(NSRect(x: box.minX + 3, y: box.minY + 2, width: box.width - 5, height: box.height - 4))
        case 1:
            object(box.insetBy(dx: 2, dy: 2))
            guide(from: NSPoint(x: box.midX, y: box.minY), to: NSPoint(x: box.midX, y: box.maxY))
        case 2: edge(box, axis: .maxX); object(NSRect(x: box.minX + 1, y: box.minY + 2, width: box.width - 5, height: box.height - 4))
        case 3: edge(box, axis: .minY); object(NSRect(x: box.minX + 2, y: box.minY + 3, width: box.width - 4, height: box.height - 5))
        case 4:
            object(box.insetBy(dx: 2, dy: 2))
            guide(from: NSPoint(x: box.minX, y: box.midY), to: NSPoint(x: box.maxX, y: box.midY))
        default: edge(box, axis: .maxY); object(NSRect(x: box.minX + 2, y: box.minY + 1, width: box.width - 4, height: box.height - 5))
        }
    }

    static func distribute(_ kind: Int, in rect: NSRect) {
        let box = rect.insetBy(dx: 2, dy: 3)
        let horizontal = kind >= 3
        for index in 0..<3 {
            let t = CGFloat(index) / 2
            if horizontal {
                let x = box.minX + t * (box.width - 4)
                let height: CGFloat = index == 1 ? box.height - 2 : box.height * 0.62
                let y = box.midY - height / 2
                object(NSRect(x: x, y: y, width: 3.5, height: height))
            } else {
                let y = box.minY + t * (box.height - 3)
                let width: CGFloat = index == 1 ? box.width - 2 : box.width * 0.62
                let x = box.midX - width / 2
                object(NSRect(x: x, y: y, width: width, height: 3.2))
            }
        }
    }

    static func spacing(horizontal: Bool, in rect: NSRect) {
        let box = rect.insetBy(dx: 2, dy: 4)
        Theme.text.setStroke()
        if horizontal {
            object(NSRect(x: box.minX, y: box.minY + 1, width: 4, height: box.height - 2))
            object(NSRect(x: box.maxX - 4, y: box.minY + 1, width: 4, height: box.height - 2))
            arrow(from: NSPoint(x: box.minX + 6, y: box.midY), to: NSPoint(x: box.maxX - 6, y: box.midY))
        } else {
            object(NSRect(x: box.minX + 1, y: box.minY, width: box.width - 2, height: 4))
            object(NSRect(x: box.minX + 1, y: box.maxY - 4, width: box.width - 2, height: 4))
            arrow(from: NSPoint(x: box.midX, y: box.minY + 6), to: NSPoint(x: box.midX, y: box.maxY - 6))
        }
    }

    static func cap(_ kind: Int, in rect: NSRect) {
        let box = rect.insetBy(dx: 3, dy: 5)
        Theme.text.setStroke()
        Theme.text.setFill()
        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineCapStyle = kind == 1 ? .round : .square
        let endX = kind == 2 ? box.maxX : box.maxX - 2
        path.move(to: NSPoint(x: box.minX, y: box.midY))
        path.line(to: NSPoint(x: endX, y: box.midY))
        path.stroke()
        if kind == 0 {
            let stop = NSBezierPath()
            stop.move(to: NSPoint(x: endX, y: box.minY))
            stop.line(to: NSPoint(x: endX, y: box.maxY))
            stop.lineWidth = 1
            stop.stroke()
        }
    }

    static func corner(_ kind: Int, in rect: NSRect) {
        let box = rect.insetBy(dx: 4, dy: 4)
        Theme.text.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineJoinStyle = kind == 0 ? .miter : (kind == 1 ? .round : .bevel)
        path.lineCapStyle = .square
        path.move(to: NSPoint(x: box.minX, y: box.maxY))
        path.line(to: NSPoint(x: box.minX, y: box.minY))
        path.line(to: NSPoint(x: box.maxX, y: box.minY))
        path.stroke()
    }

    static func strokeAlign(_ kind: Int, in rect: NSRect) {
        let box = rect.insetBy(dx: 3, dy: 4)
        let outline = NSBezierPath(rect: box)
        Theme.dim.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        Theme.text.setStroke()
        let mark: NSBezierPath
        switch kind {
        case 1: mark = NSBezierPath(rect: box.insetBy(dx: 1.4, dy: 1.4))
        case 2: mark = NSBezierPath(rect: box.insetBy(dx: -0.4, dy: -0.4))
        default: mark = NSBezierPath(rect: box)
        }
        mark.lineWidth = 2.2
        mark.stroke()
    }

    static func artboard(in rect: NSRect) {
        let box = rect.insetBy(dx: 1, dy: 1)
        Theme.text.setStroke()
        let border = NSBezierPath(rect: box)
        border.lineWidth = 1.2
        border.stroke()
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: box.minX + 2, y: box.maxY - 2))
        mark.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 2))
        mark.lineWidth = 1
        mark.stroke()
    }

    static func gear(in rect: NSRect) {
        Theme.text.setStroke()
        let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
        circle.lineWidth = 1.3
        circle.stroke()
        let hub = NSBezierPath(ovalIn: rect.insetBy(dx: 6, dy: 6))
        hub.lineWidth = 1.2
        hub.stroke()
    }

    static func sliders(in rect: NSRect) {
        Theme.text.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        for index in 0..<3 {
            let y = rect.minY + 3 + CGFloat(index) * (rect.height - 6) / 2
            path.move(to: NSPoint(x: rect.minX + 1, y: y))
            path.line(to: NSPoint(x: rect.maxX - 1, y: y))
        }
        path.stroke()
        Theme.text.setFill()
        let knobs: [CGFloat] = [0.3, 0.65, 0.42]
        for (index, t) in knobs.enumerated() {
            let y = rect.minY + 3 + CGFloat(index) * (rect.height - 6) / 2
            let x = rect.minX + t * rect.width
            NSBezierPath(ovalIn: NSRect(x: x - 2, y: y - 2, width: 4, height: 4)).fill()
        }
    }

    static func drawMode(_ kind: Int, in rect: NSRect) {
        let box = rect.insetBy(dx: 2, dy: 2)
        Theme.text.setStroke()
        let back = NSRect(x: box.minX, y: box.minY + 3, width: box.width - 4, height: box.height - 4)
        let front = NSRect(x: box.minX + 4, y: box.minY, width: box.width - 4, height: box.height - 4)
        switch kind {
        case 1:
            NSBezierPath(rect: front).stroke(1.2)
            Theme.panel.setFill()
            NSBezierPath(rect: back).fill()
            NSBezierPath(rect: back).stroke(1.2)
        case 2:
            NSBezierPath(rect: box).stroke(1.2)
            NSBezierPath(rect: box.insetBy(dx: 3, dy: 3)).stroke(1.2)
        default:
            NSBezierPath(rect: back).stroke(1.2)
            Theme.panel.setFill()
            NSBezierPath(rect: front).fill()
            NSBezierPath(rect: front).stroke(1.2)
        }
    }

    static func screenMode(_ kind: Int, in rect: NSRect) {
        let box = rect.insetBy(dx: 2, dy: 3)
        Theme.text.setStroke()
        switch kind {
        case 1:
            NSBezierPath(rect: box).stroke(1.2)
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: box.minX, y: box.maxY - 3))
            bar.line(to: NSPoint(x: box.maxX, y: box.maxY - 3))
            bar.lineWidth = 1.2
            bar.stroke()
        case 2:
            cornerBrackets(box)
        default:
            NSBezierPath(roundedRect: box, xRadius: 1.5, yRadius: 1.5).lineWidth = 1.2
            NSBezierPath(roundedRect: box, xRadius: 1.5, yRadius: 1.5).stroke()
        }
    }

    static func ellipsis(in rect: NSRect) {
        Theme.text.setFill()
        for index in 0..<3 {
            let x = rect.minX + CGFloat(index) * 5
            NSBezierPath(ovalIn: NSRect(x: x, y: rect.midY - 1.4, width: 2.8, height: 2.8)).fill()
        }
    }

    static func pathfinder(_ kind: Int, in rect: NSRect) {
        let box = rect.insetBy(dx: 2, dy: 3)
        let left = NSBezierPath(ovalIn: NSRect(x: box.minX, y: box.minY + 1, width: box.width * 0.62, height: box.height - 2))
        let right = NSBezierPath(ovalIn: NSRect(x: box.maxX - box.width * 0.62, y: box.minY + 1, width: box.width * 0.62, height: box.height - 2))
        Theme.text.setStroke()
        left.lineWidth = 1.1
        right.lineWidth = 1.1
        left.stroke()
        right.stroke()
        if kind == 2 {
            Theme.text.setFill()
            // Lens: a short vertical mark in the overlap.
            NSBezierPath(rect: NSRect(x: box.midX - 1.2, y: box.midY - 3, width: 2.4, height: 6)).fill()
        }
    }

    private enum Axis { case minX, maxX, minY, maxY }

    private static func edge(_ box: NSRect, axis: Axis) {
        let path = NSBezierPath()
        path.lineWidth = 1.4
        switch axis {
        case .minX:
            path.move(to: NSPoint(x: box.minX, y: box.minY)); path.line(to: NSPoint(x: box.minX, y: box.maxY))
        case .maxX:
            path.move(to: NSPoint(x: box.maxX, y: box.minY)); path.line(to: NSPoint(x: box.maxX, y: box.maxY))
        case .minY:
            path.move(to: NSPoint(x: box.minX, y: box.minY)); path.line(to: NSPoint(x: box.maxX, y: box.minY))
        case .maxY:
            path.move(to: NSPoint(x: box.minX, y: box.maxY)); path.line(to: NSPoint(x: box.maxX, y: box.maxY))
        }
        path.stroke()
    }

    private static func object(_ rect: NSRect) {
        Theme.text.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.1
        path.stroke()
    }

    private static func guide(from start: NSPoint, to end: NSPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 1
        let pattern: [CGFloat] = [1.5, 1.5]
        pattern.withUnsafeBufferPointer { buffer in
            path.setLineDash(buffer.baseAddress, count: 2, phase: 0)
        }
        path.stroke()
    }

    private static func arrow(from start: NSPoint, to end: NSPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 1
        path.stroke()
        let angle = atan2(end.y - start.y, end.x - start.x)
        for turn in [-0.7, 0.7] as [CGFloat] {
            let head = NSBezierPath()
            head.move(to: end)
            head.line(to: NSPoint(x: end.x - 4 * cos(angle + turn), y: end.y - 4 * sin(angle + turn)))
            head.lineWidth = 1
            head.stroke()
        }
    }

    private static func cornerBrackets(_ box: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.3
        let m: CGFloat = 4
        path.move(to: NSPoint(x: box.minX, y: box.minY + m)); path.line(to: NSPoint(x: box.minX, y: box.minY)); path.line(to: NSPoint(x: box.minX + m, y: box.minY))
        path.move(to: NSPoint(x: box.maxX - m, y: box.minY)); path.line(to: NSPoint(x: box.maxX, y: box.minY)); path.line(to: NSPoint(x: box.maxX, y: box.minY + m))
        path.move(to: NSPoint(x: box.minX, y: box.maxY - m)); path.line(to: NSPoint(x: box.minX, y: box.maxY)); path.line(to: NSPoint(x: box.minX + m, y: box.maxY))
        path.move(to: NSPoint(x: box.maxX - m, y: box.maxY)); path.line(to: NSPoint(x: box.maxX, y: box.maxY)); path.line(to: NSPoint(x: box.maxX, y: box.maxY - m))
        path.stroke()
    }
}
