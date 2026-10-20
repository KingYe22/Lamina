import AppKit
import LaminaCore

final class IllustratorToolbar: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    weak var workspace: Workspace?
    private var slots: [ToolSlotButton] = []
    private var sectionTitles: [(String, CGFloat)] = []
    private let footer = ToolbarFooter()
    private var shield: NSView?
    private var flyout: ToolFlyoutView?

    override var isFlipped: Bool { true }

    struct ToolSlotSpec {
        var tools: [Tool]
    }

    struct ToolSection {
        var title: String
        var rows: [[ToolSlotSpec]]
    }

    static let sections: [ToolSection] = [
        ToolSection(title: "选择", rows: [
            [ToolSlotSpec(tools: [.selection, .groupSelection, .magicWand]), ToolSlotSpec(tools: [.directSelection])],
            [ToolSlotSpec(tools: [.lasso])]
        ]),
        ToolSection(title: "形状", rows: [
            [ToolSlotSpec(tools: [.rectangle, .roundedRectangle, .star]), ToolSlotSpec(tools: [.ellipse, .line, .arc])],
            [ToolSlotSpec(tools: [.polygon]), ToolSlotSpec(tools: [.shaper])]
        ]),
        ToolSection(title: "绘图", rows: [
            [ToolSlotSpec(tools: [.brush]), ToolSlotSpec(tools: [.eraser])],
            [ToolSlotSpec(tools: [.blobBrush, .pencil]), ToolSlotSpec(tools: [.pen, .addAnchor, .deleteAnchor, .convertAnchor])],
            [ToolSlotSpec(tools: [.curvature])]
        ]),
        ToolSection(title: "修改", rows: [
            [ToolSlotSpec(tools: [.shapeBuilder]), ToolSlotSpec(tools: [.rotate, .reflect, .scale, .shear])],
            [ToolSlotSpec(tools: [.blend])]
        ]),
        ToolSection(title: "文字", rows: [
            [ToolSlotSpec(tools: [.text, .areaText, .pathText]), ToolSlotSpec(tools: [.verticalText])]
        ]),
        ToolSection(title: "导航", rows: [
            [ToolSlotSpec(tools: [.zoom]), ToolSlotSpec(tools: [.hand])],
            [ToolSlotSpec(tools: [.rotateView])]
        ]),
        ToolSection(title: "颜色", rows: [
            [ToolSlotSpec(tools: [.gradient, .mesh]), ToolSlotSpec(tools: [.eyedropper, .measure])]
        ])
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.panel.cgColor
        for section in Self.sections {
            for row in section.rows {
                for spec in row {
                    let button = ToolSlotButton(tools: spec.tools)
                    button.onSelect = { [weak self] tool in self?.choose(tool) }
                    button.onFlyout = { [weak self] button in self?.showFlyout(for: button) }
                    addSubview(button)
                    slots.append(button)
                }
            }
        }
        footer.onAction = { [weak self] name in self?.footerAction(name) }
        addSubview(footer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync() {
        let current = workspace?.active.model.tool
        for slot in slots {
            if let current, slot.tools.contains(current) { slot.tool = current }
            slot.isCurrent = slot.tool == current
            slot.needsDisplay = true
        }
        footer.sync(workspace?.active.model)
    }

    override func layout() {
        super.layout()
        // Positions are the reference toolbar.png bands divided by 2, in this flipped view.
        let footerTop: CGFloat = 627
        footer.frame = NSRect(x: 0, y: min(footerTop, bounds.height), width: bounds.width, height: max(0, bounds.height - footerTop))
        let frames: [(CGFloat, CGFloat)] = [
            (4, 80), (42, 80),
            (4, 114),
            (4, 170), (42, 170),
            (4, 200), (42, 200),
            (4, 252), (42, 252),
            (4, 284), (42, 284),
            (4, 315),
            (4, 368), (42, 368),
            (4, 400),
            (4, 453), (42, 453),
            (4, 508), (42, 508),
            (4, 539),
            (4, 593), (42, 593)
        ]
        for (index, slot) in slots.enumerated() {
            let origin = index < frames.count ? frames[index] : (CGFloat(4), CGFloat(80))
            slot.isHidden = origin.1 + 28 > footer.frame.minY
            slot.frame = NSRect(x: origin.0, y: origin.1, width: 36, height: 28)
        }
        sectionTitles = [
            ("选择", 65), ("形状", 149), ("绘图", 234), ("修改", 349),
            ("文字", 434), ("导航", 489), ("颜色", 574)
        ]
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
        if footer.frame.contains(point) {
            RichTooltip.shared.show(from: self, localPoint: point, title: "填色与描边", body: "互换填色和描边，或切回默认的白色填色与黑色描边。下方是颜色、渐变、无、绘图模式、屏幕模式和生成式 AI。")
            return
        }
        RichTooltip.shared.hide()
    }

    override func mouseExited(with event: NSEvent) { RichTooltip.shared.hide() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        drawHeader()
        for (title, y) in sectionTitles {
            (title as NSString).draw(at: NSPoint(x: 8, y: y), withAttributes: [
                .font: Theme.ui(11), .foregroundColor: Theme.dim
            ])
        }
    }

    private func drawHeader() {
        Theme.color(0x383838).setFill()
        NSRect(x: 0, y: 17, width: bounds.width, height: 1).fill()
        Theme.icon.setStroke()
        let chevron = NSBezierPath()
        chevron.lineWidth = 1.35
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.move(to: NSPoint(x: 12, y: 22))
        chevron.line(to: NSPoint(x: 7, y: 26))
        chevron.line(to: NSPoint(x: 12, y: 30))
        chevron.move(to: NSPoint(x: 18, y: 22))
        chevron.line(to: NSPoint(x: 13, y: 26))
        chevron.line(to: NSPoint(x: 18, y: 30))
        chevron.stroke()
        Theme.color(0x383838).setFill()
        NSRect(x: 0, y: 32, width: bounds.width, height: 1).fill()
        Theme.icon.setFill()
        let count = 6
        let span = CGFloat(count - 1) * 5
        let start = (bounds.width - span) / 2
        for index in 0..<count {
            NSBezierPath(ovalIn: NSRect(x: start + CGFloat(index) * 5, y: 38, width: 2.4, height: 2.4)).fill()
        }
    }

    private func footerAction(_ name: String) {
        guard let workspace else { return }
        let model = workspace.active.model
        switch name {
        case "填色": activateFill(true)
        case "描边": activateFill(false)
        case "绘图模式":
            model.drawMode = (model.drawMode + 1) % 3
            model.status = ["正常绘图", "背面绘图", "内部绘图"][model.drawMode]
            workspace.touch()
        case "屏幕模式":
            model.screenMode = (model.screenMode + 1) % 3
            switch model.screenMode {
            case 1:
                model.outline = true
                model.pixelPreview = false
                model.status = "轮廓"
            case 2:
                model.outline = false
                model.pixelPreview = true
                model.status = "像素预览"
            default:
                model.outline = false
                model.pixelPreview = false
                model.status = "预览"
            }
            workspace.touch()
        case "编辑工具栏":
            model.toolbarAdvanced.toggle()
            model.status = model.toolbarAdvanced ? "高级工具栏" : "基本工具栏"
            workspace.touch()
        case "生成式 AI":
            _ = workspace.perform("显示/隐藏 AI")
        default:
            _ = workspace.perform(name)
        }
        footer.sync(model)
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
    private var hovered = false

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
        if isCurrent {
            Theme.color(0x303030).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        } else if hovered {
            Theme.line.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        let side: CGFloat = 18
        let icon = NSRect(x: (bounds.width - side) / 2 - 1, y: (bounds.height - side) / 2, width: side, height: side)
        ToolIcons.draw(tool, in: icon, color: isCurrent ? NSColor(white: 0.93, alpha: 1) : Theme.icon)
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
        Theme.panel.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        Theme.field.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 1
        border.stroke()
        for (index, tool) in tools.enumerated() {
            let y = 4 + CGFloat(index) * 28
            let icon = NSRect(x: 8, y: y + 4, width: 18, height: 18)
            ToolIcons.draw(tool, in: icon, color: Theme.icon)
            let title = ToolTips.heading(tool) as NSString
            title.draw(at: NSPoint(x: 32, y: y + 6), withAttributes: [
                .font: Theme.ui(12),
                .foregroundColor: Theme.text
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

final class ToolbarFooter: NSView {
    var onAction: ((String) -> Void)?
    var fill: NSColor = .white
    var strokeColor: NSColor = .black
    var fillActive = true
    var drawMode = 0
    var screenMode = 0

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func sync(_ model: EditorModel?) {
        guard let model else { return }
        fill = model.currentFill?.solidColor?.nsColor ?? .white
        strokeColor = model.currentStroke?.paint.solidColor?.nsColor ?? .black
        fillActive = model.activeAttrIsFill
        drawMode = model.drawMode
        screenMode = model.screenMode
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let square: CGFloat = 41
        let behind = NSRect(x: 22, y: 22, width: square, height: square)
        let front = NSRect(x: 2, y: 2, width: square, height: square)
        fill.setFill()
        NSBezierPath(rect: behind).fill()
        NSColor.black.setStroke()
        NSBezierPath(rect: behind).stroke()
        strokeColor.setFill()
        NSBezierPath(rect: front).fill()
        NSColor.white.setStroke()
        let frontEdge = NSBezierPath(rect: front)
        frontEdge.lineWidth = 1
        frontEdge.stroke()
        (fillActive ? Theme.accent : NSColor.white).setStroke()
        let active = NSBezierPath(rect: fillActive ? behind.insetBy(dx: 1, dy: 1) : front.insetBy(dx: 1, dy: 1))
        active.lineWidth = 1.4
        active.stroke()
        swapArrows(NSRect(x: 48, y: 8, width: 18, height: 16))
        defaultMark(NSRect(x: 2, y: 52, width: 16, height: 16))

        let chipW: CGFloat = 22
        chip(NSRect(x: 1, y: 76, width: chipW, height: 23), kind: 0)
        chip(NSRect(x: 28, y: 76, width: chipW, height: 23), kind: 1)
        chip(NSRect(x: 54, y: 76, width: chipW, height: 23), kind: 2)
        iconWell(NSRect(x: 1, y: 108, width: chipW, height: 22)) { PanelIcons.drawMode(self.drawMode, in: $0.insetBy(dx: 3, dy: 3)) }
        iconWell(NSRect(x: 28, y: 108, width: chipW, height: 22)) { PanelIcons.screenMode(self.screenMode, in: $0.insetBy(dx: 3, dy: 3)) }
        iconWell(NSRect(x: 54, y: 108, width: chipW, height: 22)) {
            PanelIcons.ellipsis(in: NSRect(x: $0.midX - 7, y: $0.midY - 2, width: 14, height: 4))
        }
        columnMark(NSRect(x: bounds.midX - 16, y: 140, width: 32, height: 20))
        gripDots(y: 188)
        let ai = NSRect(x: 1, y: 207, width: max(20, bounds.width - 2), height: 35)
        Theme.accent.setFill()
        NSBezierPath(roundedRect: ai, xRadius: 5, yRadius: 5).fill()
        let title = "生成式 AI" as NSString
        let font = Theme.ui(11, weight: .semibold)
        let size = title.size(withAttributes: [.font: font])
        title.draw(at: NSPoint(x: ai.midX - size.width / 2 + 6, y: ai.midY - size.height / 2), withAttributes: [
            .font: font, .foregroundColor: NSColor.white
        ])
        NSColor.white.setFill()
        let spark = NSRect(x: ai.midX - size.width / 2 - 8, y: ai.midY - 4, width: 8, height: 8)
        let star = NSBezierPath()
        star.move(to: NSPoint(x: spark.midX, y: spark.maxY))
        star.line(to: NSPoint(x: spark.midX + 1.2, y: spark.midY + 1.2))
        star.line(to: NSPoint(x: spark.maxX, y: spark.midY))
        star.line(to: NSPoint(x: spark.midX + 1.2, y: spark.midY - 1.2))
        star.line(to: NSPoint(x: spark.midX, y: spark.minY))
        star.line(to: NSPoint(x: spark.midX - 1.2, y: spark.midY - 1.2))
        star.line(to: NSPoint(x: spark.minX, y: spark.midY))
        star.line(to: NSPoint(x: spark.midX - 1.2, y: spark.midY + 1.2))
        star.close()
        star.fill()
    }

    private func columnMark(_ rect: NSRect) {
        Theme.icon.setStroke()
        let left = NSRect(x: rect.minX, y: rect.minY + 2, width: 18, height: 16)
        let right = NSRect(x: rect.minX + 10, y: rect.minY, width: 18, height: 16)
        let rightPath = NSBezierPath(rect: right)
        rightPath.lineWidth = 1.1
        rightPath.stroke()
        Theme.panel.setFill()
        NSBezierPath(rect: left).fill()
        Theme.icon.setStroke()
        let leftPath = NSBezierPath(rect: left)
        leftPath.lineWidth = 1.1
        leftPath.stroke()
    }

    private func gripDots(y: CGFloat) {
        Theme.icon.setFill()
        let clusters = 3
        let cluster: CGFloat = 8
        let gap: CGFloat = 6
        let total = CGFloat(clusters) * cluster + CGFloat(clusters - 1) * gap
        var x = (bounds.width - total) / 2
        for _ in 0..<clusters {
            for col in 0..<2 {
                for row in 0..<2 {
                    NSBezierPath(ovalIn: NSRect(x: x + CGFloat(col) * 4, y: y + CGFloat(row) * 4, width: 2.4, height: 2.4)).fill()
                }
            }
            x += cluster + gap
        }
    }

    private func swapArrows(_ rect: NSRect) {
        Theme.icon.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: rect.minX, y: rect.midY + 3))
        path.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY + 3))
        path.move(to: NSPoint(x: rect.maxX - 5, y: rect.midY + 6))
        path.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY + 3))
        path.line(to: NSPoint(x: rect.maxX - 5, y: rect.midY))
        path.move(to: NSPoint(x: rect.maxX, y: rect.midY - 3))
        path.line(to: NSPoint(x: rect.minX + 2, y: rect.midY - 3))
        path.move(to: NSPoint(x: rect.minX + 5, y: rect.midY - 6))
        path.line(to: NSPoint(x: rect.minX + 2, y: rect.midY - 3))
        path.line(to: NSPoint(x: rect.minX + 5, y: rect.midY))
        path.stroke()
    }

    private func defaultMark(_ rect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: rect.minX + 3, y: rect.minY, width: 10, height: 10)).fill()
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY + 4, width: 10, height: 10)).fill()
        NSColor.black.setStroke()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY + 4, width: 10, height: 10)).stroke()
    }

    private func chip(_ rect: NSRect, kind: Int) {
        Theme.field.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        Theme.fieldBorder.setStroke()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).stroke()
        let inner = rect.insetBy(dx: 4, dy: 4)
        switch kind {
        case 0:
            NSColor.black.setFill()
            NSBezierPath(rect: inner).fill()
            NSColor.white.setStroke()
            NSBezierPath(rect: inner).stroke()
        case 1:
            if let gradient = NSGradient(colors: [NSColor.white, NSColor.black]) {
                gradient.draw(in: inner, angle: 0)
            }
            NSColor.black.setStroke()
            NSBezierPath(rect: inner).stroke()
        default:
            NSColor.white.setFill()
            NSBezierPath(rect: inner).fill()
            NSColor.systemRed.setStroke()
            let slash = NSBezierPath()
            slash.lineWidth = 1.3
            slash.move(to: NSPoint(x: inner.minX, y: inner.maxY))
            slash.line(to: NSPoint(x: inner.maxX, y: inner.minY))
            slash.stroke()
        }
    }

    private func iconWell(_ rect: NSRect, draw: (NSRect) -> Void) {
        Theme.field.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        draw(rect.insetBy(dx: 1, dy: 1))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if NSRect(x: 46, y: 6, width: 22, height: 20).contains(point) {
            onAction?("互换填色和描边")
        } else if NSRect(x: 2, y: 50, width: 18, height: 18).contains(point) {
            onAction?("把填色和描边设置为默认")
        } else if NSRect(x: 2, y: 2, width: 62, height: 62).contains(point) {
            let onFront = NSRect(x: 2, y: 2, width: 41, height: 41).contains(point)
            onAction?(onFront ? "描边" : "填色")
        } else if NSRect(x: 1, y: 76, width: 22, height: 23).contains(point) {
            onAction?("选择颜色填充模式")
        } else if NSRect(x: 28, y: 76, width: 22, height: 23).contains(point) {
            onAction?("选择渐变填色模式")
        } else if NSRect(x: 54, y: 76, width: 22, height: 23).contains(point) {
            onAction?("选择无描边/填充模式")
        } else if NSRect(x: 1, y: 108, width: 22, height: 22).contains(point) {
            onAction?("绘图模式")
        } else if NSRect(x: 28, y: 108, width: 22, height: 22).contains(point) {
            onAction?("屏幕模式")
        } else if NSRect(x: 54, y: 108, width: 22, height: 22).contains(point) || NSRect(x: bounds.midX - 18, y: 138, width: 36, height: 24).contains(point) {
            onAction?("编辑工具栏")
        } else if NSRect(x: 1, y: 207, width: max(20, bounds.width - 2), height: 35).contains(point) {
            onAction?("生成式 AI")
        }
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
