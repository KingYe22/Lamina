import AppKit
import LaminaCore

final class IllustratorToolbar: NSView {
    weak var workspace: Workspace?
    private var buttons: [ToolIconButton] = []
    private let fillControl = FillStrokeWell()
    private let swatches = SwatchTrio()
    private let modes = ModeTrio()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        for (title, tools) in Self.groups {
            for tool in tools {
                let button = ToolIconButton(tool: tool, groupTitle: title)
                button.target = self
                button.action = #selector(pick(_:))
                addSubview(button)
                buttons.append(button)
            }
        }
        addSubview(fillControl)
        addSubview(swatches)
        addSubview(modes)
        fillControl.onFill = { [weak self] in self?.activateFill(true) }
        fillControl.onStroke = { [weak self] in self?.activateFill(false) }
        swatches.onColor = { [weak self] in self?.workspace?.perform("选择颜色填充模式") }
        swatches.onGradient = { [weak self] in self?.workspace?.perform("选择渐变填色模式") }
        swatches.onNone = { [weak self] in self?.workspace?.perform("选择无描边/填充模式") }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static let groups: [(String, [Tool])] = [
        ("选择", [.selection, .directSelection]),
        ("形状", [.rectangle, .ellipse, .polygon, .line]),
        ("绘制", [.brush, .pen, .pencil, .eraser]),
        ("修改", [.rotate, .scale]),
        ("文字", [.text]),
        ("导航", [.zoom, .hand]),
        ("颜色", [.gradient, .eyedropper])
    ]

    func sync() {
        let current = workspace?.active.model.tool
        for button in buttons {
            button.isCurrent = button.tool == current
            button.needsDisplay = true
        }
        if let model = workspace?.active.model {
            fillControl.fill = model.currentFill?.solidColor?.nsColor ?? .white
            fillControl.stroke = model.currentStroke?.paint.solidColor?.nsColor ?? .black
            fillControl.fillActive = model.activeAttrIsFill
            fillControl.needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 6
        var lastGroup = ""
        for button in buttons {
            if button.groupTitle != lastGroup {
                button.showsTitle = true
                y += 14
                lastGroup = button.groupTitle
            } else {
                button.showsTitle = false
            }
            button.frame = NSRect(x: 4, y: y, width: bounds.width - 8, height: 26)
            y += 26
        }
        let bottom = bounds.height
        modes.frame = NSRect(x: 4, y: bottom - 26, width: bounds.width - 8, height: 22)
        swatches.frame = NSRect(x: 6, y: bottom - 44, width: bounds.width - 12, height: 18)
        fillControl.frame = NSRect(x: 8, y: bottom - 92, width: bounds.width - 16, height: 44)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        var y: CGFloat = 6
        var last = ""
        for button in buttons {
            if button.groupTitle != last {
                y += 2
                let title = button.groupTitle as NSString
                title.draw(at: NSPoint(x: 6, y: y), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: Theme.dim
                ])
                y += 12
                last = button.groupTitle
            }
            y += 26
        }
    }

    @objc private func pick(_ sender: ToolIconButton) {
        guard let model = workspace?.active.model else { return }
        model.tool = sender.tool
        model.status = sender.tool.title
        workspace?.touch()
        window?.makeFirstResponder(window?.contentView.flatMap { findCanvas($0) })
    }

    private func activateFill(_ fill: Bool) {
        guard let model = workspace?.active.model else { return }
        model.activeAttrIsFill = fill
        model.status = fill ? "填色" : "描边"
        workspace?.touch()
    }

    private func findCanvas(_ view: NSView) -> NSView? {
        if view is VectorCanvas { return view }
        for child in view.subviews {
            if let found = findCanvas(child) { return found }
        }
        return nil
    }
}

final class ToolIconButton: NSControl {
    let tool: Tool
    let groupTitle: String
    var showsTitle = false
    var isCurrent = false

    init(tool: Tool, groupTitle: String) {
        self.tool = tool
        self.groupTitle = groupTitle
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if isCurrent {
            Theme.accent.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        let side: CGFloat = 22
        let icon = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        ToolIcons.draw(tool, in: icon, color: isCurrent ? .white : Theme.text)
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

final class FillStrokeWell: NSView {
    var fill: NSColor = .white
    var stroke: NSColor = .black
    var fillActive = true
    var onFill: (() -> Void)?
    var onStroke: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let back = NSRect(x: 10, y: 8, width: 22, height: 22)
        let front = NSRect(x: 2, y: 16, width: 22, height: 22)
        stroke.setFill()
        NSBezierPath(rect: back).fill()
        NSColor.black.setStroke()
        NSBezierPath(rect: back).stroke(1)
        fill.setFill()
        NSBezierPath(rect: front).fill()
        (fillActive ? Theme.accent : NSColor.black).setStroke()
        NSBezierPath(rect: front).lineWidth = fillActive ? 2 : 1
        NSBezierPath(rect: front).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.x > 16 && point.y < 24 { onStroke?() } else { onFill?() }
    }
}

final class SwatchTrio: NSView {
    var onColor: (() -> Void)?
    var onGradient: (() -> Void)?
    var onNone: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width / 3
        chip(NSRect(x: 0, y: 0, width: w - 2, height: bounds.height), kind: 0)
        chip(NSRect(x: w, y: 0, width: w - 2, height: bounds.height), kind: 1)
        chip(NSRect(x: w * 2, y: 0, width: w - 2, height: bounds.height), kind: 2)
    }

    private func chip(_ rect: NSRect, kind: Int) {
        Theme.raised.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        switch kind {
        case 0:
            NSColor.white.setFill()
            NSBezierPath(rect: rect.insetBy(dx: 4, dy: 4)).fill()
        case 1:
            NSColor.white.setFill()
            NSBezierPath(rect: rect.insetBy(dx: 4, dy: 4)).fill()
            Theme.accent.setFill()
            NSBezierPath(rect: NSRect(x: rect.minX + 4, y: rect.minY + 4, width: rect.width * 0.4, height: rect.height - 8)).fill()
        default:
            NSColor.white.setFill()
            NSBezierPath(rect: rect.insetBy(dx: 4, dy: 4)).fill()
            NSColor.systemRed.setStroke()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 4, y: rect.maxY - 4))
            slash.line(to: NSPoint(x: rect.maxX - 4, y: rect.minY + 4))
            slash.lineWidth = 1.4
            slash.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let third = bounds.width / 3
        if x < third { onColor?() }
        else if x < third * 2 { onGradient?() }
        else { onNone?() }
    }
}

final class ModeTrio: NSView {
    private var drawMode = 0
    private var screenMode = 0

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width / 3
        for index in 0..<3 {
            let rect = NSRect(x: CGFloat(index) * w, y: 1, width: w - 2, height: bounds.height - 2)
            PanelIcons.well(rect, selected: false)
            let icon = rect.insetBy(dx: 2, dy: 2)
            switch index {
            case 0: PanelIcons.drawMode(drawMode, in: icon)
            case 1: PanelIcons.screenMode(screenMode, in: icon)
            default: PanelIcons.ellipsis(in: NSRect(x: icon.midX - 7, y: icon.midY - 2, width: 14, height: 6))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let third = bounds.width / 3
        if x < third { drawMode = (drawMode + 1) % 3 }
        else if x < third * 2 { screenMode = (screenMode + 1) % 3 }
        needsDisplay = true
    }
}

private extension NSBezierPath {
    func stroke(_ width: CGFloat) {
        lineWidth = width
        stroke()
    }
}
