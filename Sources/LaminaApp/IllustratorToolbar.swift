import AppKit
import LaminaCore

final class IllustratorToolbar: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { true }
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
        layer?.masksToBounds = true
        clipsToBounds = true
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

    /// Empty space in the band above the canvas drags the window. Tool buttons keep the click.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y < WorkspaceMetrics.chromeInset + WorkspaceMetrics.toolbarLift {
            window?.performDrag(with: event)
        }
    }

    func sync() {
        let current = workspace?.active.model.tool
        for slot in slots {
            if let current, slot.tools.contains(current) { slot.tool = current }
            slot.isCurrent = slot.tool == current
            if let rect = slotFrame(for: slot.tool) {
                slot.frame = rect
            }
            slot.needsDisplay = true
        }
        footer.sync(workspace?.active.model)
    }

    override func layout() {
        super.layout()
        let footerTop: CGFloat = 627 + WorkspaceMetrics.toolbarLift
        footer.frame = NSRect(x: 0, y: min(footerTop, bounds.height), width: bounds.width, height: max(0, bounds.height - footerTop))
        placeSlots()
        // Titles are drawn inside the lift transform, so these stay at the traced y.
        sectionTitles = [
            ("选择", 65), ("形状", 149.5), ("绘图", 234), ("修改", 349),
            ("文字", 434), ("导航", 489), ("颜色", 574)
        ]
    }

    private func placeSlots() {
        for slot in slots {
            if let rect = slotFrame(for: slot.tool) {
                slot.frame = rect
            }
            slot.isHidden = slot.frame.maxY > footer.frame.minY + 4
        }
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

    private func slotFrame(for tool: Tool) -> NSRect? {
        guard var rect = TracedIcons.bounds(for: tool) else { return nil }
        rect = rect.insetBy(dx: -0.5, dy: -0.5)
        rect.origin.y += WorkspaceMetrics.toolbarLift
        return rect
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        NSGraphicsContext.saveGraphicsState()
        AffineTransform(translationByX: 0, byY: WorkspaceMetrics.toolbarLift).concat()
        drawHeader()
        let current = workspace?.active.model.tool ?? .selection
        if current == .selection {
            Theme.color(0x303030).setFill()
            NSBezierPath(roundedRect: NSRect(x: 0.5, y: 80, width: 35, height: 27), xRadius: 2, yRadius: 2).fill()
        }
        Theme.color(0x2D8CEB).setFill()
        NSBezierPath(ovalIn: NSRect(x: 4.5, y: 252.5, width: 9, height: 9)).fill()
        Theme.color(0x4B4B4B).setFill()
        for y in [141, 226, 341, 426, 481, 566, 621] as [CGFloat] {
            NSRect(x: 0, y: y, width: bounds.width, height: 0.5).fill()
        }
        let font = Theme.ui(10)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: Theme.color(0xD1D1D1)
        ]
        for (title, y) in sectionTitles {
            let text = title as NSString
            let width = text.size(withAttributes: attrs).width
            text.draw(at: NSPoint(x: 36.5 - width / 2, y: y), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHeader() {
        Theme.color(0x5E5E5E).setFill()
        NSRect(x: 0, y: 16, width: bounds.width, height: 1).fill()
        Theme.color(0x383838).setFill()
        NSRect(x: 0, y: 17, width: bounds.width, height: 1).fill()
        Theme.color(0x424242).setFill()
        NSRect(x: 0, y: 18, width: bounds.width, height: 14).fill()
        Theme.color(0x383838).setFill()
        NSRect(x: 0, y: 32, width: bounds.width, height: 1).fill()
        Theme.color(0xC8C8C8).setFill()
        TracedChrome.chevron().fill()
        Theme.color(0x383838).setFill()
        for index in 0..<10 {
            let x = 24.25 + CGFloat(index) * 2.5
            NSBezierPath(roundedRect: NSRect(x: x, y: 37, width: 1.5, height: 5), xRadius: 0.75, yRadius: 0.75).fill()
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
            workspace.presentGenerative()
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
        if TracedIcons.contains(tool) {
            if isCurrent, tool != .selection {
                Theme.color(0x303030).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: -1, dy: -1), xRadius: 3, yRadius: 3).fill()
            }
            TracedIcons.draw(tool, toolbarOrigin: frame.origin)
            return
        }
        if isCurrent {
            Theme.color(0x303030).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        } else if hovered {
            Theme.line.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        let side: CGFloat = 22
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

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func sync(_ model: EditorModel?) {
        guard let model else { return }
        fill = model.currentFill?.solidColor?.nsColor ?? .white
        strokeColor = model.currentStroke?.paint.solidColor?.nsColor ?? .black
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let fillOuter = NSRect(x: 22, y: 23, width: 44.5, height: 44.5)
        Theme.color(0x2E2E2E).setFill()
        NSBezierPath(rect: fillOuter).fill()
        fill.setFill()
        NSBezierPath(rect: fillOuter.insetBy(dx: 1, dy: 1)).fill()
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        TracedChrome.fillSlash().fill()

        Theme.color(0x2E2E2E).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 1, width: 44, height: 44)).fill()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0.5, y: 1.5, width: 43, height: 43)).fill()
        strokeColor.setFill()
        NSBezierPath(rect: NSRect(x: 1.5, y: 2.5, width: 41, height: 41)).fill()

        Theme.color(0xC2C2C2).setFill()
        TracedChrome.swapArrows().fill()
        TracedChrome.defaultMark().fill()

        Theme.color(0x303030).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0.5, y: 77, width: 21.5, height: 22.5), xRadius: 1.5, yRadius: 1.5).fill()
        let colorChip = NSRect(x: 3, y: 81, width: 16, height: 15.5)
        NSColor.black.setFill()
        NSBezierPath(rect: colorChip).fill()
        NSColor.white.setStroke()
        let colorEdge = NSBezierPath(rect: colorChip)
        colorEdge.lineWidth = 0.6
        colorEdge.stroke()

        let grad = NSRect(x: 28, y: 81, width: 16, height: 15.5)
        NSColor.black.setFill()
        NSBezierPath(rect: grad).fill()
        let gradInner = grad.insetBy(dx: 1, dy: 1)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: gradInner).addClip()
        NSGradient(colors: [NSColor.white, Theme.color(0x2D2D2D)])?.draw(in: gradInner, angle: 0)
        NSGraphicsContext.restoreGraphicsState()

        let none = NSRect(x: 53, y: 81, width: 16, height: 15.5)
        NSColor.black.setFill()
        NSBezierPath(rect: none).fill()
        NSColor.white.setFill()
        NSBezierPath(rect: none.insetBy(dx: 1, dy: 1)).fill()
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        TracedChrome.noneSlash().fill()

        Theme.color(0x303030).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0.5, y: 107, width: 21.5, height: 22.5), xRadius: 1.5, yRadius: 1.5).fill()
        Theme.color(0xC2C2C2).setFill()
        TracedChrome.drawMode().fill()
        TracedChrome.screenMode().fill()
        Theme.color(0x6D6D6D).setFill()
        TracedChrome.thirdMode().fill()
        Theme.color(0xC2C2C2).setFill()
        TracedChrome.columnMark().fill()
        TracedChrome.editMark().fill()

        let ai = NSRect(x: 0.5, y: 208, width: 72.5, height: 34.5)
        Theme.color(0x1573E6).setFill()
        NSBezierPath(roundedRect: ai, xRadius: 1.5, yRadius: 1.5).fill()
        NSColor.white.setFill()
        TracedChrome.aiStars().fill()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if NSRect(x: 50, y: 1, width: 24, height: 18).contains(point) {
            onAction?("互换填色和描边")
        } else if NSRect(x: 0, y: 50, width: 18, height: 18).contains(point) {
            onAction?("把填色和描边设置为默认")
        } else if NSRect(x: 0, y: 1, width: 67, height: 67).contains(point) {
            let onFront = NSRect(x: 0, y: 1, width: 44, height: 44).contains(point)
            onAction?(onFront ? "描边" : "填色")
        } else if NSRect(x: 0.5, y: 77, width: 22, height: 23).contains(point) {
            onAction?("选择颜色填充模式")
        } else if NSRect(x: 28, y: 77, width: 18, height: 22).contains(point) {
            onAction?("选择渐变填色模式")
        } else if NSRect(x: 53, y: 77, width: 18, height: 22).contains(point) {
            onAction?("选择无描边/填充模式")
        } else if NSRect(x: 0.5, y: 107, width: 22, height: 23).contains(point) {
            onAction?("绘图模式")
        } else if NSRect(x: 28, y: 107, width: 22, height: 23).contains(point) {
            onAction?("屏幕模式")
        } else if NSRect(x: 52, y: 107, width: 22, height: 23).contains(point) || NSRect(x: 20, y: 138, width: 40, height: 52).contains(point) {
            onAction?("编辑工具栏")
        } else if NSRect(x: 0.5, y: 208, width: 72.5, height: 34.5).contains(point) {
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
