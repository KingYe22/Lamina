import AppKit
import LaminaCore

final class IllustratorToolbar: NSView {
    weak var workspace: Workspace?
    private var slots: [ToolSlotButton] = []
    private let fillControl = FillStrokeWell()
    private let swatches = SwatchTrio()
    private let modes = ModeTrio()
    private var shield: NSView?
    private var flyout: ToolFlyoutView?

    override var isFlipped: Bool { true }

    static let groups: [[Tool]] = [
        [.selection, .directSelection, .groupSelection, .magicWand, .lasso],
        [.pen, .addAnchor, .deleteAnchor, .convertAnchor, .curvature],
        [.text, .areaText, .pathText, .verticalText, .touchType],
        [.line, .arc, .spiral, .rectGrid, .polarGrid],
        [.rectangle, .roundedRectangle, .ellipse, .polygon, .star, .flare],
        [.brush, .blobBrush],
        [.pencil, .smooth, .pathEraser, .joinTool, .shaper],
        [.eraser, .scissors, .knife],
        [.rotate, .reflect],
        [.scale, .shear, .reshape],
        [.freeTransform],
        [.width],
        [.gradient, .mesh],
        [.eyedropper, .measure],
        [.hand],
        [.zoom]
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        for tools in Self.groups {
            let button = ToolSlotButton(tools: tools)
            button.onSelect = { [weak self] tool in self?.choose(tool) }
            button.onFlyout = { [weak self] button in self?.showFlyout(for: button) }
            addSubview(button)
            slots.append(button)
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

    func sync() {
        let current = workspace?.active.model.tool
        for slot in slots {
            if let current, slot.tools.contains(current) { slot.tool = current }
            slot.isCurrent = slot.tool == current
            slot.needsDisplay = true
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
        var y: CGFloat = 4
        let height: CGFloat = 26
        for slot in slots {
            slot.frame = NSRect(x: 2, y: y, width: bounds.width - 4, height: height)
            y += height
        }
        let bottom = bounds.height
        modes.frame = NSRect(x: 4, y: bottom - 26, width: bounds.width - 8, height: 22)
        swatches.frame = NSRect(x: 6, y: bottom - 46, width: bounds.width - 12, height: 16)
        fillControl.frame = NSRect(x: 8, y: bottom - 96, width: bounds.width - 16, height: 44)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        Hover.install(on: self)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let slot = slots.first(where: { $0.frame.contains(point) }) {
            RichTooltip.shared.show(from: self, localPoint: point, title: ToolTips.heading(slot.tool), body: ToolTips.body(slot.tool))
            return
        }
        if fillControl.frame.contains(point) {
            RichTooltip.shared.show(from: self, localPoint: point, title: "填色与描边", body: "单击前方色块编辑填色，单击后方色块编辑描边。")
            return
        }
        if swatches.frame.contains(point) {
            RichTooltip.shared.show(from: self, localPoint: point, title: "颜色", body: "颜色、渐变或无。")
            return
        }
        if modes.frame.contains(point) {
            RichTooltip.shared.show(from: self, localPoint: point, title: "绘图模式与屏幕模式", body: "切换正常绘图、背面绘图、内部绘图，以及屏幕模式。")
            return
        }
        RichTooltip.shared.hide()
    }

    override func mouseExited(with event: NSEvent) { RichTooltip.shared.hide() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
    }

    func revealTooltipForShot() {
        layoutSubtreeIfNeeded()
        guard let slot = slots.first(where: { $0.tools.contains(.rectangle) }) else { return }
        let point = NSPoint(x: slot.frame.midX, y: slot.frame.midY)
        RichTooltip.shared.show(from: self, localPoint: point, title: ToolTips.heading(.rectangle), body: ToolTips.body(.rectangle))
    }

    func revealFlyoutForShot() {
        layoutSubtreeIfNeeded()
        RichTooltip.shared.hide()
        guard let slot = slots.first(where: { $0.tools.contains(.rectangle) }) else { return }
        showFlyout(for: slot)
    }

    private func choose(_ tool: Tool) {
        guard let model = workspace?.active.model else { return }
        model.tool = tool
        model.status = tool.title
        dismissFlyout()
        workspace?.touch()
        window?.makeFirstResponder(findCanvas(window?.contentView))
    }

    private func showFlyout(for slot: ToolSlotButton) {
        guard slot.tools.count > 1, let content = window?.contentView else { return }
        dismissFlyout()
        let shield = FlyoutShield(frame: content.bounds)
        shield.onClose = { [weak self] in self?.dismissFlyout() }
        let row: CGFloat = 28
        let menu = ToolFlyoutView(frame: NSRect(x: 0, y: 0, width: 168, height: row * CGFloat(slot.tools.count) + 8))
        menu.tools = slot.tools
        menu.onPick = { [weak self] tool in self?.choose(tool) }
        let top = slot.convert(NSPoint(x: slot.bounds.maxX, y: 0), to: content)
        var origin = NSPoint(x: top.x + 4, y: top.y - menu.frame.height)
        if origin.y < 8 { origin.y = 8 }
        menu.frame.origin = origin
        content.addSubview(shield)
        content.addSubview(menu)
        self.shield = shield
        flyout = menu
    }

    private func dismissFlyout() {
        shield?.removeFromSuperview()
        flyout?.removeFromSuperview()
        shield = nil
        flyout = nil
    }

    private func activateFill(_ fill: Bool) {
        guard let model = workspace?.active.model else { return }
        model.activeAttrIsFill = fill
        model.status = fill ? "填色" : "描边"
        workspace?.touch()
    }

    private func findCanvas(_ view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is VectorCanvas { return view }
        for child in view.subviews {
            if let found = findCanvas(child) { return found }
        }
        return nil
    }
}

final class ToolSlotButton: NSView {
    let tools: [Tool]
    var tool: Tool
    var isCurrent = false
    var onSelect: ((Tool) -> Void)?
    var onFlyout: ((ToolSlotButton) -> Void)?

    init(tools: [Tool]) {
        self.tools = tools
        self.tool = tools[0]
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if isCurrent {
            Theme.accent.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        let side: CGFloat = 18
        let icon = NSRect(x: (bounds.width - side) / 2 - 1, y: (bounds.height - side) / 2, width: side, height: side)
        ToolIcons.draw(tool, in: icon, color: isCurrent ? .white : Theme.text)
        if tools.count > 1 {
            let tri = NSBezierPath()
            let x = bounds.maxX - 7
            let y = bounds.maxY - 6
            tri.move(to: NSPoint(x: x, y: y))
            tri.line(to: NSPoint(x: x + 5, y: y))
            tri.line(to: NSPoint(x: x + 2.5, y: y + 4))
            tri.close()
            (isCurrent ? NSColor.white : Theme.dim).setFill()
            tri.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), tools.count > 1 {
            let index = (tools.firstIndex(of: tool) ?? 0) + 1
            tool = tools[index % tools.count]
            onSelect?(tool)
            return
        }
        let until = Date().addingTimeInterval(0.38)
        var released = false
        while Date() < until {
            guard let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged, .rightMouseDown]) else { break }
            if next.type == .leftMouseUp { released = true; break }
            if next.type == .rightMouseDown {
                onFlyout?(self)
                return
            }
        }
        if !released, tools.count > 1 {
            onFlyout?(self)
        } else {
            onSelect?(tool)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard tools.count > 1 else { onSelect?(tool); return }
        onFlyout?(self)
    }
}

final class ToolFlyoutView: NSView {
    var tools: [Tool] = []
    var onPick: ((Tool) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.2, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        NSColor(calibratedWhite: 0.45, alpha: 1).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
        for (index, tool) in tools.enumerated() {
            let y = 4 + CGFloat(index) * 28
            let icon = NSRect(x: 8, y: y + 4, width: 18, height: 18)
            ToolIcons.draw(tool, in: icon, color: .white)
            let title = ToolTips.heading(tool) as NSString
            title.draw(at: NSPoint(x: 32, y: y + 6), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white
            ])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        let index = Int((y - 4) / 28)
        guard tools.indices.contains(index) else { return }
        onPick?(tools[index])
    }
}

final class FlyoutShield: NSView {
    var onClose: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClose?() }
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
        NSBezierPath(rect: back).stroke()
        fill.setFill()
        NSBezierPath(rect: front).fill()
        (fillActive ? Theme.accent : NSColor.black).setStroke()
        let outline = NSBezierPath(rect: front)
        outline.lineWidth = fillActive ? 2 : 1
        outline.stroke()
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
