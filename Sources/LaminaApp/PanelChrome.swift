import AppKit
import LaminaCore

enum PanelKind: String {
    case appearance = "外观"
    case transform = "变换"
    case align = "对齐"
    case pathfinder = "路径查找器"
    case stroke = "描边"
    case opacity = "透明度"
}

/// Host for the floating panels. Empty space passes the click through to the canvas.
final class FloatingPanels: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    weak var workspace: Workspace? {
        didSet {
            for panel in panels { panel.workspace = workspace }
        }
    }
    private var panels: [FloatPanel] = []
    private var placed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let appearance = FloatPanel(tabs: [.appearance])
        let grouped = FloatPanel(tabs: [.transform, .align, .pathfinder])
        grouped.active = .align
        let stroke = FloatPanel(tabs: [.stroke, .opacity])
        panels = [appearance, grouped, stroke]
        for panel in panels {
            panel.host = self
            addSubview(panel)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync() {
        panels.forEach { $0.sync() }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 400, bounds.height > 200 else { return }
        let size = bounds.size
        if placed, size == placedSize { return }
        placed = true
        placedSize = size
        panels[0].frame = WorkspaceMetrics.appearance.rect(in: bounds.height)
        panels[1].frame = WorkspaceMetrics.align.rect(in: bounds.height)
        panels[2].frame = WorkspaceMetrics.stroke.rect(in: bounds.height)
    }

    private var placedSize = NSSize.zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for child in subviews.reversed() where !child.isHidden && child.frame.contains(local) {
            return child.hitTest(point) ?? child
        }
        return nil
    }

    func merge(_ panel: FloatPanel, into target: FloatPanel) {
        guard panel !== target else { return }
        for tab in panel.tabs where !target.tabs.contains(tab) {
            target.tabs.append(tab)
        }
        target.active = panel.active
        panel.isHidden = true
        target.needsLayout = true
        target.needsDisplay = true
    }

    func split(_ panel: FloatPanel) {
        guard panel.tabs.count > 1, let kind = panel.tabs.firstIndex(of: panel.active) else { return }
        let removed = panel.tabs.remove(at: kind)
        panel.active = panel.tabs[0]
        let born = FloatPanel(tabs: [removed])
        born.workspace = workspace
        born.host = self
        born.frame = panel.frame.offsetBy(dx: 24, dy: 24)
        panels.append(born)
        addSubview(born)
    }
}

final class FloatPanel: NSView {
    weak var workspace: Workspace?
    weak var host: FloatingPanels?
    var tabs: [PanelKind]
    var active: PanelKind
    var collapsed = false
    private let weightField = PanelField(text: "1 pt")
    private let limitField = PanelField(text: "4")
    private var alignTarget = 0
    private let alignTargets = ["对齐所选对象", "对齐画板", "关键对象"]
    private var strokeAlign = 0
    private var arrowHead = 0
    private var scaleStrokes = false
    private var dashAlign = false
    private var dragging = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(tabs: [PanelKind]) {
        self.tabs = tabs
        self.active = tabs[0]
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 0
        for field in [weightField, limitField] {
            field.alignment = .center
            field.font = Theme.ui(13)
            addSubview(field)
        }
        weightField.onLeave = { [weak self] in self?.applyWeight() }
        limitField.onLeave = { [weak self] in self?.applyLimit() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync() {
        if let width = workspace?.active.model.currentStroke?.width {
            weightField.stringValue = width == width.rounded() ? "\(Int(width)) pt" : String(format: "%.1f pt", width)
        }
        if let limit = workspace?.active.model.currentStroke?.miterLimit {
            limitField.stringValue = "\(Int(limit))"
        }
        needsDisplay = true
        needsLayout = true
    }

    private var enabled: Bool { !(workspace?.active.model.selection.isEmpty ?? true) }
    private var titleHeight: CGFloat { 26 }
    private var tabHeight: CGFloat { tabs.count > 1 && !collapsed ? 24 : 0 }

    override func layout() {
        super.layout()
        let showStroke = !collapsed && active == .stroke
        weightField.isHidden = !showStroke
        limitField.isHidden = !showStroke
        if showStroke {
            let top = titleHeight + tabHeight + 8
            weightField.frame = NSRect(x: 44, y: top - 1, width: bounds.width - 104, height: 20)
            limitField.frame = NSRect(x: 44, y: top + 74, width: 48, height: 20)
            weightField.textColor = enabled ? Theme.text : Theme.color(0x707070)
            limitField.textColor = weightField.textColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        Theme.panel.setFill()
        shape.fill()
        let headerH = titleHeight + tabHeight
        Theme.color(0x424242).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: headerH).fill()
        Theme.line.setFill()
        NSRect(x: 0, y: headerH - 1, width: bounds.width, height: 1).fill()
        if tabs.count < 2 || collapsed {
            let title = (collapsed ? tabs.map(\.rawValue).joined(separator: " / ") : active.rawValue) as NSString
            title.draw(at: NSPoint(x: 10, y: 8), withAttributes: [
                .font: Theme.ui(13, weight: .semibold), .foregroundColor: Theme.color(0xF3F3F3)
            ])
        }
        drawGlyph("«", NSRect(x: bounds.width - 46, y: 4, width: 16, height: 16))
        drawGlyph("×", NSRect(x: bounds.width - 24, y: 3, width: 16, height: 16))
        guard !collapsed else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        if tabs.count > 1 {
            let measured = tabs == [.transform, .align, .pathfinder]
            let spots: [CGFloat] = measured ? [12, 69.5, 118.5] : []
            var x: CGFloat = 8
            for (index, tab) in tabs.enumerated() {
                let on = tab == active
                let font = Theme.ui(13, weight: on ? .semibold : .regular)
                let color: NSColor = on ? Theme.color(0xF3F3F3) : Theme.color(0xB0B0B0)
                if measured, spots.indices.contains(index) { x = spots[index] }
                (tab.rawValue as NSString).draw(at: NSPoint(x: x, y: 6), withAttributes: [
                    .font: font, .foregroundColor: color
                ])
                if on {
                    Theme.text.setFill()
                    let w = (tab.rawValue as NSString).size(withAttributes: [.font: font]).width
                    NSRect(x: x, y: 24, width: w, height: 2).fill()
                }
                if !measured {
                    x += (tab.rawValue as NSString).size(withAttributes: [.font: font]).width + 12
                }
            }
            PanelIcons.menu(in: NSRect(x: bounds.width - 22, y: titleHeight + 6, width: 14, height: 12))
        } else {
            PanelIcons.menu(in: NSRect(x: bounds.width - 22, y: titleHeight + 8, width: 14, height: 12))
        }
        let content = NSRect(x: 8, y: titleHeight + tabHeight + 8, width: bounds.width - 16, height: bounds.height - titleHeight - tabHeight - 18)
        let ink = Theme.color(0xD1D1D1)
        switch active {
        case .appearance: drawAppearance(content)
        case .transform: drawTransform(content, ink: ink)
        case .align: drawAlign(content, ink: ink)
        case .pathfinder: drawPathfinder(content, ink: enabled ? Theme.text : Theme.color(0x707070))
        case .stroke: drawStroke(content, ink: ink)
        case .opacity: drawOpacity(content, ink: ink)
        }
        Theme.dim.setFill()
        let grip = NSRect(x: bounds.midX - 16, y: bounds.height - 8, width: 32, height: 3)
        NSBezierPath(roundedRect: grip, xRadius: 1, yRadius: 1).fill()
        Theme.line.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGlyph(_ text: String, _ rect: NSRect) {
        let font = Theme.ui(13)
        let size = (text as NSString).size(withAttributes: [.font: font])
        (text as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: [
            .font: font, .foregroundColor: Theme.dim
        ])
    }

    private func drawAppearance(_ rect: NSRect) {
        let heading = (workspace?.active.model.selection.isEmpty == false) ? "外观" : "未选择对象"
        (heading as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY), withAttributes: [
            .font: Theme.ui(13, weight: .semibold), .foregroundColor: Theme.color(0xD1D1D1)
        ])
        PanelIcons.eye(in: NSRect(x: rect.minX, y: rect.minY + 24, width: 16, height: 12), open: true)
        let twist = NSBezierPath()
        Theme.icon.setStroke()
        twist.lineWidth = 1.2
        twist.move(to: NSPoint(x: rect.minX + 22, y: rect.minY + 26))
        twist.line(to: NSPoint(x: rect.minX + 26, y: rect.minY + 30))
        twist.line(to: NSPoint(x: rect.minX + 30, y: rect.minY + 26))
        twist.stroke()
        PanelIcons.swatch(in: NSRect(x: rect.minX + 8, y: rect.minY + 32, width: 18, height: 18), color: .black)
        ("描边：" as NSString).draw(at: NSPoint(x: rect.minX + 32, y: rect.minY + 32), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: Theme.color(0xDDDDDD)
        ])
        (strokeDetail() as NSString).draw(at: NSPoint(x: rect.minX + 78, y: rect.minY + 33), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: Theme.color(0xC2C2C2)
        ])
        ("不透明度：默认值" as NSString).draw(at: NSPoint(x: rect.minX + 32, y: rect.minY + 62), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: Theme.color(0xC2C2C2)
        ])
        let y = rect.maxY - 28
        for index in 0..<4 {
            let box = NSRect(x: rect.minX + CGFloat(index) * 28, y: y, width: 24, height: 22)
            Theme.field.setFill()
            NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
            appearanceIcon(index, in: box.insetBy(dx: 4, dy: 4))
        }
    }

    private func strokeDetail() -> String {
        guard let width = workspace?.active.model.currentStroke?.width else { return "1 pt" }
        return width == width.rounded() ? "\(Int(width)) pt" : String(format: "%.1f pt", width)
    }

    private func appearanceIcon(_ index: Int, in rect: NSRect) {
        Theme.text.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        switch index {
        case 0:
            ( "fx" as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY), withAttributes: [
                .font: Theme.ui(11, weight: .semibold), .foregroundColor: Theme.text
            ])
            return
        case 1:
            path.appendOval(in: rect.insetBy(dx: 1, dy: 1))
            path.move(to: NSPoint(x: rect.midX, y: rect.minY))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY))
            path.move(to: NSPoint(x: rect.minX, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        case 2:
            path.move(to: NSPoint(x: rect.midX, y: rect.minY))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY))
            path.move(to: NSPoint(x: rect.minX, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        default:
            path.move(to: NSPoint(x: rect.minX, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        }
        path.stroke()
    }

    private func row(_ x: CGFloat, _ y: CGFloat, title: String, detail: String, color: NSColor) {
        PanelIcons.eye(in: NSRect(x: x, y: y, width: 16, height: 12), open: true)
        PanelIcons.swatch(in: NSRect(x: x + 22, y: y - 1, width: 14, height: 14), color: color)
        (title as NSString).draw(at: NSPoint(x: x + 42, y: y), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: Theme.text
        ])
        if !detail.isEmpty {
            (detail as NSString).draw(at: NSPoint(x: x + 78, y: y), withAttributes: [
                .font: Theme.ui(13), .foregroundColor: Theme.color(0xC2C2C2)
            ])
        }
    }

    private func drawTransform(_ rect: NSRect, ink: NSColor) {
        let labels = ["X", "Y", "W", "H"]
        let values = ["0", "0", "210", "297"]
        for index in 0..<4 {
            let y = rect.minY + CGFloat(index) * 28
            (labels[index] as NSString).draw(at: NSPoint(x: rect.minX, y: y + 2), withAttributes: [
                .font: Theme.ui(13), .foregroundColor: Theme.color(0xC2C2C2)
            ])
            PanelIcons.stepper(NSRect(x: rect.minX + 22, y: y, width: min(140, rect.width - 22), height: 20), title: values[index])
            _ = ink
        }
    }

    private func drawAlign(_ rect: NSRect, ink: NSColor) {
        let origin = cropOrigin
        let label = Theme.color(0xD1D1D1)
        cropText("对齐对象", x: 330, top: 172.5, size: 14, color: label)
        cropText("分布对象", x: 330, top: 250, size: 14, color: label)
        cropText("分布间距", x: 330, top: 327.5, size: 14, color: label)
        let icon = Theme.color(0xC2C2C2)
        for name in ["a0", "a1", "a2", "a3", "a4", "a5", "a6", "b0", "b1", "b2", "c0", "c1"] {
            TracedMarks.draw(name, origin: origin, color: icon)
        }
        cropText(alignTargets[alignTarget], x: 330, top: 372, size: 13, color: Theme.color(0xB0B0B0))
        _ = rect
        _ = ink
    }

    /// Top-left of this panel in comparison-crop points (y grows downward from the body).
    private var cropOrigin: NSPoint {
        let topInset = (superview?.bounds.height ?? 0) - frame.maxY
        return NSPoint(x: frame.minX, y: WorkspaceMetrics.chromeInset + topInset)
    }

    private func cropText(_ text: String, x: CGFloat, top: CGFloat, size: CGFloat, color: NSColor) {
        let origin = cropOrigin
        (text as NSString).draw(at: NSPoint(x: x - origin.x, y: top - origin.y - 2), withAttributes: [
            .font: Theme.ui(size), .foregroundColor: color
        ])
    }

    private func drawPathfinder(_ rect: NSRect, ink: NSColor) {
        caption("形状模式", y: rect.minY, ink: ink)
        iconRow(4, x: rect.minX, y: rect.minY + 16, muted: !enabled) { PanelIcons.pathfinder($0, in: $1) }
        caption("路径查找器", y: rect.minY + 48, ink: ink)
        iconRow(4, x: rect.minX, y: rect.minY + 64, muted: !enabled) { PanelIcons.pathfinder(($0 + 1) % 4, in: $1) }
    }

    private func drawStroke(_ rect: NSRect, ink: NSColor) {
        let stroke = workspace?.active.model.currentStroke
        let muted = Theme.color(0xD1D1D1)
        caption("粗细", y: rect.minY, ink: muted)
        PanelIcons.popup(NSRect(x: rect.maxX - 48, y: rect.minY - 2, width: 48, height: 20), title: "pt")
        caption("端点", y: rect.minY + 26, ink: muted)
        iconRow(3, x: rect.minX + 36, y: rect.minY + 24, selected: capIndex(stroke?.cap), muted: !enabled) { PanelIcons.cap($0, in: $1) }
        caption("边角", y: rect.minY + 52, ink: muted)
        iconRow(3, x: rect.minX + 36, y: rect.minY + 50, selected: joinIndex(stroke?.join), muted: !enabled) { PanelIcons.corner($0, in: $1) }
        caption("限制", y: rect.minY + 76, ink: muted)
        caption("对齐描边", y: rect.minY + 100, ink: muted)
        iconRow(3, x: rect.minX + 64, y: rect.minY + 98, selected: strokeAlign, muted: !enabled) { PanelIcons.strokeAlign($0, in: $1) }
        let dashY = rect.minY + 126
        PanelIcons.checkbox(at: NSPoint(x: rect.minX, y: dashY + 2), on: !(stroke?.dash.isEmpty ?? true), title: "")
        ("虚线" as NSString).draw(at: NSPoint(x: rect.minX + 18, y: dashY + 2), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: muted
        ])
        var dashX = rect.minX + 52
        let pattern = stroke?.dash ?? []
        for index in 0..<4 {
            let text = pattern.indices.contains(index) ? String(format: "%g", pattern[index]) : ""
            PanelIcons.field(NSRect(x: dashX, y: dashY, width: 28, height: 18), text: text, align: .center)
            dashX += 30
        }
        let arrowY = rect.minY + 150
        PanelIcons.popup(NSRect(x: rect.minX, y: arrowY, width: (rect.width - 8) / 2, height: 20), title: arrowTitle)
        PanelIcons.popup(NSRect(x: rect.midX + 4, y: arrowY, width: (rect.width - 8) / 2, height: 20), title: "箭头")
        caption("缩放", y: rect.minY + 176, ink: muted)
        PanelIcons.checkbox(at: NSPoint(x: rect.minX + 32, y: rect.minY + 176), on: scaleStrokes, title: "")
        ("对齐" as NSString).draw(at: NSPoint(x: rect.minX + 54, y: rect.minY + 176), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: muted
        ])
        PanelIcons.popup(NSRect(x: rect.minX + 88, y: rect.minY + 174, width: rect.width - 88, height: 20), title: dashAlign ? "边角" : "无")
        caption("配置文件", y: rect.minY + 202, ink: muted)
        PanelIcons.popup(NSRect(x: rect.minX + 64, y: rect.minY + 200, width: rect.width - 64, height: 20), title: profileTitle(stroke?.profile))
        _ = ink
    }

    private func capIndex(_ cap: LineCap?) -> Int {
        switch cap {
        case .round: return 1
        case .square: return 2
        default: return 0
        }
    }

    private func joinIndex(_ join: LineJoin?) -> Int {
        switch join {
        case .round: return 1
        case .bevel: return 2
        default: return 0
        }
    }

    private var arrowTitle: String {
        ["无", "末端", "起点", "两端"][arrowHead % 4]
    }

    private func profileTitle(_ profile: WidthProfile?) -> String {
        switch profile {
        case .linear: return "线性"
        case .triangular: return "三角"
        case .oval: return "椭圆"
        default: return "均匀"
        }
    }

    private func drawOpacity(_ rect: NSRect, ink: NSColor) {
        ("不透明度" as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: ink
        ])
        PanelIcons.popup(NSRect(x: rect.minX, y: rect.minY + 18, width: rect.width, height: 22), title: "100%")
        ("混合模式" as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY + 50), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: ink
        ])
        PanelIcons.popup(NSRect(x: rect.minX, y: rect.minY + 68, width: rect.width, height: 22), title: "正常")
    }

    private func caption(_ text: String, y: CGFloat, ink: NSColor) {
        (text as NSString).draw(at: NSPoint(x: 8, y: y), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: ink == Theme.text ? Theme.dim : ink
        ])
    }

    private func iconRow(_ count: Int, x: CGFloat, y: CGFloat, selected: Int = -1, muted: Bool = false, ink: NSColor = Theme.text, draw: (Int, NSRect) -> Void) {
        let width: CGFloat = count >= 6 ? 24 : 26
        for index in 0..<count {
            let rect = NSRect(x: x + CGFloat(index) * (width + 3), y: y, width: width, height: 20)
            if index == selected {
                Theme.color(0x303030).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            }
            draw(index, rect.insetBy(dx: 2, dy: 2))
            _ = muted
        }
        _ = ink
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if NSRect(x: bounds.width - 24, y: 2, width: 20, height: 20).contains(point) {
            isHidden = true
            return
        }
        if NSRect(x: bounds.width - 48, y: 2, width: 20, height: 20).contains(point) {
            collapsed.toggle()
            let height: CGFloat = collapsed ? 28 : 312
            frame.size.height = height
            needsDisplay = true
            return
        }
        if NSRect(x: bounds.width - 28, y: titleHeight + 2, width: 24, height: 20).contains(point) {
            showMenu()
            return
        }
        if !collapsed, tabs.count > 1, point.y < 28 {
            let measured = tabs == [.transform, .align, .pathfinder]
            let spots: [CGFloat] = measured ? [12, 69.5, 118.5, bounds.width] : []
            var x: CGFloat = 8
            for (index, tab) in tabs.enumerated() {
                let font = Theme.ui(13, weight: .semibold)
                let width = (tab.rawValue as NSString).size(withAttributes: [.font: font]).width + 12
                let start = measured && spots.indices.contains(index) ? spots[index] : x
                let end = measured && spots.indices.contains(index + 1) ? spots[index + 1] : start + width
                if point.x >= start && point.x < end {
                    active = tab
                    needsLayout = true
                    needsDisplay = true
                    return
                }
                x = end
            }
        }
        if point.y < titleHeight {
            dragMove(event)
            return
        }
        if point.y > bounds.height - 12 {
            dragResize(event)
            return
        }
        handleContent(point)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "折叠", action: #selector(menuCollapse), keyEquivalent: "")
        menu.addItem(withTitle: "关闭", action: #selector(menuClose), keyEquivalent: "")
        if tabs.count > 1 {
            menu.addItem(withTitle: "拆出当前选项卡", action: #selector(menuSplit), keyEquivalent: "")
        }
        if let others = host?.subviews.compactMap({ $0 as? FloatPanel }).filter({ $0 !== self && !$0.isHidden }), let other = others.first {
            let item = NSMenuItem(title: "合并到「\(other.active.rawValue)」", action: #selector(menuMerge), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: self)
    }

    @objc private func menuCollapse() {
        collapsed = true
        frame.size.height = 28
        needsLayout = true
        needsDisplay = true
    }
    @objc private func menuClose() { isHidden = true }
    @objc private func menuSplit() { host?.split(self); needsDisplay = true }
    @objc private func menuMerge() {
        guard let other = host?.subviews.compactMap({ $0 as? FloatPanel }).first(where: { $0 !== self && !$0.isHidden }) else { return }
        host?.merge(self, into: other)
    }

    private func dragMove(_ event: NSEvent) {
        guard !dragging else { return }
        dragging = true
        let start = event.locationInWindow
        let origin = frame.origin
        while true {
            guard let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            frame.origin = NSPoint(x: origin.x + next.locationInWindow.x - start.x, y: origin.y + next.locationInWindow.y - start.y)
            if next.type == .leftMouseUp { break }
        }
        dragging = false
    }

    private func dragResize(_ event: NSEvent) {
        let start = event.locationInWindow
        let height = frame.size.height
        let origin = frame.origin
        while true {
            guard let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            let delta = start.y - next.locationInWindow.y
            let nextHeight = max(120, height + delta)
            frame.origin.y = origin.y - (nextHeight - height)
            frame.size.height = nextHeight
            if next.type == .leftMouseUp { break }
        }
    }

    private func handleContent(_ point: NSPoint) {
        guard let workspace else { return }
        let model = workspace.active.model
        let top = titleHeight + tabHeight
        switch active {
        case .appearance:
            let localY = point.y - top
            if localY < 36 {
                cycleOpacity(model)
            } else if point.x < 120, localY > 100 {
                let index = Int((point.x - 8) / 28)
                if index == 0 { _ = workspace.perform("效果 圆角") }
                else if index == 2 { model.addFillLayer() }
                else if index == 3 { model.addStrokeLayer(); model.status = "添加描边" }
                else { model.status = "外观目标" }
            }
        case .align:
            let names = ["水平左对齐", "水平居中对齐", "水平右对齐", "垂直顶对齐", "垂直居中对齐", "垂直底对齐"]
            let row = point.y - top - 24
            if row < 30 {
                let index = Int((point.x - 8) / 29)
                if names.indices.contains(index) { _ = workspace.perform(names[index]) }
            } else if row > 100 {
                alignTarget = (alignTarget + 1) % alignTargets.count
                model.status = alignTargets[alignTarget]
            }
        case .pathfinder:
            guard model.selection.count >= 2 else { model.status = "路径查找器需要至少两个对象"; workspace.touch(); return }
            let names = ["路径查找器 联集", "路径查找器 相减", "路径查找器 交集", "路径查找器 差集"]
            let index = Int((point.x - 8) / 31)
            if names.indices.contains(index) { _ = workspace.perform(names[index]) }
        case .stroke:
            let row = point.y - top
            if row > 22 && row < 46, point.x > 40 {
                setCap(Int((point.x - 44) / 29), model: model)
            } else if row > 48 && row < 72, point.x > 40, point.x < bounds.width - 52 {
                setJoin(Int((point.x - 44) / 29), model: model)
            } else if row > 96 && row < 122 {
                guard enabled else { model.status = "对齐描边需要选中对象"; break }
                let index = Int((point.x - 72) / 29)
                strokeAlign = min(2, max(0, index))
                setAlign(strokeAlign, model: model)
            } else if row > 122 && row < 148 {
                toggleDash(model)
            } else if row > 148 && row < 174 {
                guard enabled else { model.status = "箭头需要选中对象"; break }
                arrowHead = (arrowHead + 1) % 4
                model.status = "箭头 \(arrowTitle)"
            } else if row > 174 && row < 198 {
                if point.x < 90 {
                    scaleStrokes.toggle()
                    model.status = scaleStrokes ? "缩放描边和效果" : "不缩放描边和效果"
                } else {
                    dashAlign.toggle()
                    model.status = dashAlign ? "虚线对齐边角" : "虚线不对齐"
                }
            } else if row > 198 && row < 224 {
                cycleProfile(model)
            }
        case .opacity:
            cycleOpacity(model)
        default:
            break
        }
        workspace.touch()
        needsDisplay = true
    }

    private func cycleOpacity(_ model: EditorModel) {
        model.beginChange()
        let steps = [1.0, 0.75, 0.5, 0.25]
        for id in model.selection {
            _ = model.document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                let current = steps.firstIndex(where: { abs($0 - object.appearance.opacity) < 0.01 }) ?? 0
                object.appearance.opacity = steps[(current + 1) % steps.count]
                item = .path(object)
            }
        }
        model.status = model.selection.isEmpty ? "未选择对象" : "不透明度"
    }

    private func mutateStroke(_ model: EditorModel, _ body: (inout StrokeStyle) -> Void) {
        var stroke = model.currentStroke ?? StrokeStyle()
        body(&stroke)
        model.applyStroke(stroke)
    }

    private func applyWeight() {
        guard let model = workspace?.active.model else { return }
        let cleaned = weightField.stringValue.replacingOccurrences(of: "pt", with: "").trimmingCharacters(in: .whitespaces)
        if let number = Double(cleaned) {
            mutateStroke(model) { $0.width = min(100, max(0, number)) }
            model.status = "描边 \(weightField.stringValue)"
        }
        workspace?.touch()
    }

    private func applyLimit() {
        guard let model = workspace?.active.model else { return }
        if let number = Double(limitField.stringValue) {
            mutateStroke(model) { $0.miterLimit = min(50, max(1, number)) }
            model.status = "斜接限制 \(Int(number))"
        }
        workspace?.touch()
    }

    private func toggleDash(_ model: EditorModel) {
        mutateStroke(model) { stroke in
            stroke.dash = stroke.dash.isEmpty ? [4, 3, 1, 3] : []
        }
        let on = !(model.currentStroke?.dash.isEmpty ?? true)
        model.status = on ? "虚线" : "实线"
    }

    private func cycleProfile(_ model: EditorModel) {
        let order: [WidthProfile] = [.uniform, .linear, .triangular, .oval]
        let current = model.currentStroke?.profile ?? .uniform
        let index = order.firstIndex(of: current) ?? 0
        let next = order[(index + 1) % order.count]
        mutateStroke(model) { $0.profile = next }
        model.status = "配置文件 \(profileTitle(next))"
    }

    private func setCap(_ index: Int, model: EditorModel) {
        let caps: [LineCap] = [.butt, .round, .square]
        guard caps.indices.contains(index) else { return }
        mutateStroke(model) { $0.cap = caps[index] }
        model.status = ["平头端点", "圆头端点", "方头端点"][index]
    }

    private func setJoin(_ index: Int, model: EditorModel) {
        let joins: [LineJoin] = [.miter, .round, .bevel]
        guard joins.indices.contains(index) else { return }
        mutateStroke(model) { $0.join = joins[index] }
        model.status = ["尖角", "圆角", "斜角"][index]
    }

    private func setAlign(_ index: Int, model: EditorModel) {
        guard (0..<3).contains(index) else { return }
        model.status = ["描边居中", "描边内侧", "描边外侧"][index]
    }
}
