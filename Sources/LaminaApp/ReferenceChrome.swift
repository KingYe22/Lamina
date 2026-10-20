import AppKit

/// Point geometry shared by the workspace. Nothing here loads a screenshot.
enum WorkspaceMetrics {
    static let windowWidth: CGFloat = 1033
    static let windowHeight: CGFloat = 970
    static let toolWidth: CGFloat = 81
    static let dockWidth: CGFloat = 312
    static let controlHeight: CGFloat = 37.5
    /// Control bar plus the flat shadow drawn under it. Canvas and the dock start here.
    static let chromeInset: CGFloat = 89
    static let appearance = PanelFrame(x: 20, top: 37, width: 298, height: 212)
    static let align = PanelFrame(x: 323, top: 37, width: 308, height: 266)
    static let stroke = PanelFrame(x: 323, top: 340, width: 308, height: 403)

    struct PanelFrame {
        var x: CGFloat
        var top: CGFloat
        var width: CGFloat
        var height: CGFloat

        func rect(in host: CGFloat) -> NSRect {
            NSRect(x: x, y: host - top - height, width: width, height: height)
        }
    }
}

/// Flat shadow under the control bar. A filled rectangle, not a screenshot.
final class ShadowBand: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        Theme.color(0x424242).setFill()
        bounds.fill()
        Theme.color(0x383838).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

/// The strip above the canvas: bell, search, workspace, and panels. Drawn with paths.
final class ControlBar: NSView {
    weak var workspace: Workspace?
    private let buttons: [ChromeIconButton]

    override init(frame frameRect: NSRect) {
        let kinds: [ChromeIcon] = [.bell, .search, .workspace, .panels]
        buttons = kinds.map { ChromeIconButton(kind: $0) }
        super.init(frame: frameRect)
        for button in buttons {
            button.target = self
            button.action = #selector(press(_:))
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let side: CGFloat = 28
        let gap: CGFloat = 8
        var x = bounds.width - 12 - side
        for button in buttons.reversed() {
            button.frame = NSRect(x: x, y: (bounds.height - side) / 2, width: side, height: side)
            x -= side + gap
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        Theme.color(0x404040).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    @objc private func press(_ sender: ChromeIconButton) {
        let name: String
        switch sender.kind {
        case .bell: name = "通知"
        case .search: name = "搜索"
        case .workspace: name = "工作区"
        case .panels: name = "面板"
        }
        workspace?.active.model.status = name
        workspace?.touch()
    }
}

enum ChromeIcon { case bell, search, workspace, panels }

final class ChromeIconButton: NSButton {
    let kind: ChromeIcon
    private var hovered = false

    init(kind: ChromeIcon) {
        self.kind = kind
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = false
        focusRingType = .none
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered || isHighlighted {
            Theme.color(0x464646).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        Theme.icon.setStroke()
        Theme.icon.setFill()
        let box = bounds.insetBy(dx: 6, dy: 6)
        switch kind {
        case .bell: bell(box)
        case .search: search(box)
        case .workspace: workspaceMark(box)
        case .panels: panels(box)
        }
    }

    private func bell(_ box: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.3
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: box.midX, y: box.minY + 1))
        path.line(to: NSPoint(x: box.minX + 2, y: box.minY + 1))
        path.line(to: NSPoint(x: box.minX + 2, y: box.midY))
        path.curve(
            to: NSPoint(x: box.midX, y: box.maxY - 1),
            controlPoint1: NSPoint(x: box.minX + 2, y: box.maxY - 4),
            controlPoint2: NSPoint(x: box.midX - 4, y: box.maxY - 1)
        )
        path.curve(
            to: NSPoint(x: box.maxX - 2, y: box.midY),
            controlPoint1: NSPoint(x: box.midX + 4, y: box.maxY - 1),
            controlPoint2: NSPoint(x: box.maxX - 2, y: box.maxY - 4)
        )
        path.line(to: NSPoint(x: box.maxX - 2, y: box.minY + 1))
        path.close()
        path.stroke()
        NSBezierPath(ovalIn: NSRect(x: box.midX - 1.5, y: box.minY - 1, width: 3, height: 3)).fill()
    }

    private func search(_ box: NSRect) {
        let glass = NSRect(x: box.minX, y: box.minY + 3, width: box.width - 5, height: box.height - 5)
        let path = NSBezierPath(ovalIn: glass)
        path.lineWidth = 1.4
        path.stroke()
        let handle = NSBezierPath()
        handle.lineWidth = 1.4
        handle.lineCapStyle = .round
        handle.move(to: NSPoint(x: glass.maxX - 2, y: glass.minY + 2))
        handle.line(to: NSPoint(x: box.maxX, y: box.minY))
        handle.stroke()
    }

    private func workspaceMark(_ box: NSRect) {
        let frame = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5)
        frame.lineWidth = 1.3
        frame.stroke()
        let split = NSBezierPath()
        split.lineWidth = 1.2
        split.move(to: NSPoint(x: box.minX + box.width * 0.38, y: box.minY + 1))
        split.line(to: NSPoint(x: box.minX + box.width * 0.38, y: box.maxY - 1))
        split.stroke()
    }

    private func panels(_ box: NSRect) {
        let gap: CGFloat = 2
        let w = (box.width - gap) / 2
        let h = (box.height - gap) / 2
        for row in 0..<2 {
            for column in 0..<2 {
                let rect = NSRect(
                    x: box.minX + CGFloat(column) * (w + gap),
                    y: box.minY + CGFloat(row) * (h + gap),
                    width: w,
                    height: h
                )
                let path = NSBezierPath(rect: rect.insetBy(dx: 0.4, dy: 0.4))
                path.lineWidth = 1.1
                path.stroke()
            }
        }
    }
}
