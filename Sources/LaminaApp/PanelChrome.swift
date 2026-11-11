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

/// One logical pixel on every outer edge and under the title bar.
enum PanelHairline {
    static func draw(in bounds: NSRect, titleHeight: CGFloat) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.shouldAntialias = false
        Theme.line.setFill()
        let width = bounds.width
        let height = bounds.height
        guard width >= 2, height >= 2 else {
            context.restoreGraphicsState()
            return
        }
        NSRect(x: 0, y: 0, width: width, height: 1).fill()
        NSRect(x: 0, y: height - 1, width: width, height: 1).fill()
        NSRect(x: 0, y: 0, width: 1, height: height).fill()
        NSRect(x: width - 1, y: 0, width: 1, height: height).fill()
        let dividerY = min(max(titleHeight - 1, 1), height - 2)
        NSRect(x: 1, y: dividerY, width: width - 2, height: 1).fill()
        context.restoreGraphicsState()
    }
}

/// Extra generative surface. It never replaces Appearance, Align, or Stroke.
final class GenerativePanel: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        Theme.color(0x424242).setFill()
        let titleH = WorkspaceMetrics.panelTitleHeight
        NSRect(x: 0, y: 0, width: bounds.width, height: titleH).fill()
        ("生成式" as NSString).draw(at: NSPoint(x: 10, y: 4), withAttributes: [
            .font: Theme.ui(13, weight: .semibold), .foregroundColor: Theme.color(0xF3F3F3)
        ])
        ("外观、对齐和描边保持不变。" as NSString).draw(at: NSPoint(x: 12, y: 36), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: Theme.color(0xD1D1D1)
        ])
        let button = NSRect(x: 12, y: 68, width: 88, height: 26)
        Theme.accent.setFill()
        NSBezierPath(roundedRect: button, xRadius: 2, yRadius: 2).fill()
        let label = "生成" as NSString
        let font = Theme.ui(13, weight: .medium)
        let size = label.size(withAttributes: [.font: font])
        label.draw(
            at: NSPoint(x: button.midX - size.width / 2, y: button.midY - size.height / 2),
            withAttributes: [.font: font, .foregroundColor: NSColor.white]
        )
        PanelHairline.draw(in: bounds, titleHeight: titleH)
    }
}

/// Bright blue snap guide. Drawn above the panels and ignored by hit testing.
final class DockGuideOverlay: NSView {
    var guides: [DockGuide] = []
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        Theme.color(DockSnap.guideHex).setFill()
        let thickness = CGFloat(DockSnap.guideThickness)
        for guide in guides {
            switch guide.axis {
            case .vertical(let x):
                let origin = min(max(x - thickness / 2, 0), max(0, bounds.width - thickness))
                NSRect(x: origin, y: 0, width: thickness, height: bounds.height).fill()
            case .horizontal(let y):
                let origin = min(max(y - thickness / 2, 0), max(0, bounds.height - thickness))
                NSRect(x: 0, y: origin, width: bounds.width, height: thickness).fill()
            }
        }
    }
}

/// Host for the floating panels. Empty space passes the click through to the canvas.
final class FloatingPanels: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    private let guideOverlay = DockGuideOverlay(frame: .zero)
    private let generative = GenerativePanel(frame: .zero)
    weak var workspace: Workspace? {
        didSet {
            for panel in panels { panel.workspace = workspace }
        }
    }
    private var panels: [FloatPanel] = []
    private var placed = false
    /// Properties column, in this view. The shell fills it in during layout.
    var rightShoulder: DockFrame?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // A flexible-height or bottom-pinned mask walks every floater up by the
        // window's height delta before the screen-position correction runs.
        autoresizingMask = []
        autoresizesSubviews = false
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.isOpaque = false
        layer?.backgroundColor = nil
        clipsToBounds = true
        let appearance = FloatPanel(tabs: [.appearance])
        let grouped = FloatPanel(tabs: [.transform, .align, .pathfinder])
        grouped.active = .align
        let stroke = FloatPanel(tabs: [.stroke, .opacity])
        panels = [appearance, grouped, stroke]
        for panel in panels {
            panel.host = self
            addSubview(panel)
        }
        generative.isHidden = true
        addSubview(generative)
        addSubview(guideOverlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync() {
        panels.forEach { $0.sync() }
        generative.isHidden = workspace?.active.model.generativeOpen != true
        generative.needsDisplay = true
    }

    override func layout() {
        super.layout()
        layer?.isOpaque = false
        layer?.backgroundColor = nil
        guideOverlay.frame = bounds
        placeGenerative()
        guard bounds.width > 400, bounds.height > 200 else { return }
        let size = bounds.size
        // A window resize must not put floating panels back on the metric grid.
        if FloatingPlacement.resetsFrames(alreadyPlaced: placed) {
            placed = true
            placedSize = size
            let metrics = [
                WorkspaceMetrics.appearance.rect(in: bounds.height),
                WorkspaceMetrics.align.rect(in: bounds.height),
                WorkspaceMetrics.stroke.rect(in: bounds.height)
            ]
            for (panel, rect) in zip(panels, metrics) where panel.dockColumnID == nil && panel.superview === self && !panel.dragging {
                panel.metricFrame = rect
                panel.frame = rect
                panel.preferredSize = rect.size
                panel.expandedHeight = rect.height
            }
        }
        seatAnchoredPanels()
        reapplyRestingFrames()
    }

    /// Puts a panel that has not been moved back on the metric origin.
    func reapplyRestingFrames() {
        for panel in panels where panel.keepsMetricOrigin && panel.superview === self && !panel.dragging {
            guard let metric = panel.metricFrame, panel.frame != metric else { continue }
            panel.frame = metric
        }
    }

    private var placedSize = NSSize.zero

    /// Sits to the right of Align and Stroke so it does not cover them.
    private func placeGenerative() {
        let width = min(280, max(0, bounds.width - 16))
        let height: CGFloat = 132
        let x = min(648, max(0, bounds.width - width - 8))
        let y = bounds.height - 20 - height
        generative.frame = NSRect(x: x, y: y, width: width, height: height)
    }

    /// Appearance panel parked `gap` points from the host's right edge.
    /// `applySnap` false leaves the guide up; true commits the zero-gap frame.
    func poseRightShoulder(applySnap: Bool) {
        layoutSubtreeIfNeeded()
        guard bounds.width > 400, let panel = panels.first(where: { $0.tabs == [.appearance] }) else { return }
        panel.keepsMetricOrigin = false
        let gap: CGFloat = 4
        panel.frame.origin.x = bounds.width - panel.frame.width - gap
        let magnet = DockSnap.magnet(
            frame: dockBox(panel.frame),
            others: dockTargets(excluding: panel),
            host: dockBox(bounds)
        )
        if applySnap {
            panel.frame.origin = NSPoint(x: CGFloat(magnet.frame.x), y: CGFloat(magnet.frame.y))
            showGuides([])
        } else {
            showGuides(magnet.guides)
        }
        panel.needsDisplay = true
    }

    func restoreMetricFrames() {
        placed = false
        placedSize = .zero
        for panel in panels {
            panel.keepsMetricOrigin = true
            panel.metricFrame = nil
        }
        showGuides([])
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func dockBox(_ rect: NSRect) -> DockFrame {
        DockFrame(
            x: Double(rect.origin.x), y: Double(rect.origin.y),
            width: Double(rect.size.width), height: Double(rect.size.height)
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for child in subviews.reversed() where !child.isHidden && child.frame.contains(local) {
            if child is DockGuideOverlay { continue }
            return child.hitTest(point) ?? child
        }
        return nil
    }

    func bringToFront(_ panel: FloatPanel) {
        addSubview(panel, positioned: .below, relativeTo: guideOverlay)
    }

    func showGuides(_ guides: [DockGuide]) {
        guideOverlay.guides = guides
        guideOverlay.frame = bounds
        addSubview(guideOverlay, positioned: .above, relativeTo: nil)
        guideOverlay.needsDisplay = true
    }

    func dockTargets(excluding panel: FloatPanel) -> [DockFrame] {
        subviews.compactMap { $0 as? FloatPanel }.filter { $0 !== panel && !$0.isHidden }.map {
            DockFrame(x: Double($0.frame.origin.x), y: Double($0.frame.origin.y), width: Double($0.frame.width), height: Double($0.frame.height))
        }
    }

    func anchoredFrames(excluding panel: FloatPanel) -> [DockFrame] {
        panels.filter { $0 !== panel && $0.columnSeat == .right && !$0.isHidden }.map { dockBox($0.frame) }
    }

    func leftFrames(excluding panel: FloatPanel) -> [DockFrame] {
        panels.filter { $0 !== panel && $0.columnSeat == .left && !$0.isHidden }.map { dockBox($0.frame) }
    }

    /// Union of panels already in the left column, used as that column's inner edge.
    func leftColumnFrame(excluding panel: FloatPanel? = nil) -> DockFrame? {
        let frames = panels.filter { $0 !== panel && $0.columnSeat == .left && !$0.isHidden }.map { dockBox($0.frame) }
        guard var union = frames.first else { return nil }
        for frame in frames.dropFirst() {
            let minX = min(union.minX, frame.minX)
            let minY = min(union.minY, frame.minY)
            let maxX = max(union.maxX, frame.maxX)
            let maxY = max(union.maxY, frame.maxY)
            union = DockFrame(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return union
    }

    /// Put every latched panel back in its column. Layout and the drag loop
    /// both call this, so a display pass cannot leave the raw drag frame behind.
    func seatAnchoredPanels() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let host = dockBox(bounds)
        if let shoulder = rightShoulder {
            for panel in panels where panel.columnSeat == .right {
                panel.keepsMetricOrigin = false
                let seated = DockSnap.commitShoulder(
                    proposed: dockBox(panel.frame),
                    shoulder: shoulder,
                    host: host,
                    occupied: anchoredFrames(excluding: panel)
                )
                let rect = NSRect(x: seated.x, y: seated.y, width: seated.width, height: seated.height)
                if panel.frame != rect { panel.frame = rect }
            }
        }
        for panel in panels where panel.columnSeat == .left {
            panel.keepsMetricOrigin = false
            let seated = DockSnap.commitLeft(
                proposed: dockBox(panel.frame),
                host: host,
                occupied: leftFrames(excluding: panel)
            )
            let rect = NSRect(x: seated.x, y: seated.y, width: seated.width, height: seated.height)
            if panel.frame != rect { panel.frame = rect }
        }
    }

    func dockPanels() -> [FloatPanel] { panels }

    /// Host-local frame of the generative card, when it is on screen.
    func generativeFrame() -> NSRect? {
        generative.isHidden ? nil : generative.frame
    }

    func addFloating(_ panel: FloatPanel) {
        panel.workspace = workspace
        panel.host = self
        if !panels.contains(where: { $0 === panel }) {
            panels.append(panel)
        }
        addSubview(panel, positioned: .below, relativeTo: guideOverlay)
    }

    /// `frameInShell` is in the editor shell's coordinates. Called after layout
    /// so a removed column has already moved this host.
    func receiveFloating(_ panel: FloatPanel, frameInShell: NSRect) {
        panel.workspace = workspace
        panel.host = self
        panel.embeddedInDock = false
        if !panels.contains(where: { $0 === panel }) {
            panels.append(panel)
        }
        if panel.superview !== self {
            panel.removeFromSuperview()
            addSubview(panel, positioned: .below, relativeTo: guideOverlay)
        }
        if let shell = superview {
            panel.keepsMetricOrigin = false
            panel.frame = convert(frameInShell, from: shell)
        }
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
        addSubview(born, positioned: .below, relativeTo: guideOverlay)
    }
}

final class FloatPanel: NSView {
    weak var workspace: Workspace?
    weak var host: FloatingPanels?
    var tabs: [PanelKind]
    var active: PanelKind
    var collapsed = false
    private let weightField = PanelField(text: "1")
    private let limitField = PanelField(text: "10")
    private let xField = PanelField(text: "0 mm")
    private let yField = PanelField(text: "0 mm")
    private let wField = PanelField(text: "0 mm")
    private let hField = PanelField(text: "0 mm")
    /// Set while a tab is pulled out of its group, so the old slot waits for 31 pt.
    var dragOriginGroupID: String?
    private var strokeOptionsHidden = false
    private var alignTarget = 0
    private let alignTargets = ["对齐所选对象", "对齐画板", "关键对象"]
    private var strokeAlign = 0
    private var arrowHead = 0
    private var scaleStrokes = false
    private var dashAlign = false
    var dragging = false
    /// Mouse-up landed while a dock guide was lit. Layout keeps seating it.
    var columnSeat: DockAnchor = .none
    /// False after a drag, resize, dock, or screen-position hold.
    var keepsMetricOrigin = true
    /// Host-local metric frame. Set once, when the panel is first placed.
    var metricFrame: NSRect?
    var preferredSize = NSSize.zero
    var expandedHeight: CGFloat = 0
    var dockColumnID: String?
    var dockOrder = 0
    var dragSlotHeight: CGFloat = 0
    var embeddedInDock = false
    var suppressContent = false
    var onDragEnd: (() -> Void)?
    var dockGroupID: String { "p\(ObjectIdentifier(self).hashValue)" }
    var dockTabHeight: CGFloat { titleHeight }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(tabs: [PanelKind]) {
        self.tabs = tabs
        self.active = tabs[0]
        super.init(frame: .zero)
        autoresizingMask = []
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 0
        // Only the panel that shows the field gets the control. A hidden
        // zero-frame text field on Appearance and Align was enough, with the
        // canvas bar under the floater host, to leave those layers 5 pt right.
        if tabs.contains(.stroke) {
            for field in [weightField, limitField] {
                field.alignment = .center
                field.font = Theme.ui(13)
                addSubview(field)
            }
        }
        for field in [xField, yField, wField, hField] {
            field.alignment = .center
            field.font = Theme.ui(13)
            field.isHidden = true
            field.autoresizingMask = []
        }
        weightField.onLeave = { [weak self] in self?.applyWeight() }
        limitField.onLeave = { [weak self] in self?.applyLimit() }
        xField.onLeave = { [weak self] in self?.applyGeometry(self?.xField, key: "x") }
        yField.onLeave = { [weak self] in self?.applyGeometry(self?.yField, key: "y") }
        wField.onLeave = { [weak self] in self?.applyGeometry(self?.wField, key: "w") }
        hField.onLeave = { [weak self] in self?.applyGeometry(self?.hField, key: "h") }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sync() {
        if let width = workspace?.active.model.currentStroke?.width {
            weightField.stringValue = width == width.rounded() ? "\(Int(width))" : String(format: "%.1f", width)
        }
        if let limit = workspace?.active.model.currentStroke?.miterLimit {
            limitField.stringValue = "\(Int(limit))"
        }
        if let readout = workspace?.active.model.selectionReadout() {
            if !xField.fieldIsEditing { xField.stringValue = readout.x + " mm" }
            if !yField.fieldIsEditing { yField.stringValue = readout.y + " mm" }
            if !wField.fieldIsEditing { wField.stringValue = readout.width + " mm" }
            if !hField.fieldIsEditing { hField.stringValue = readout.height + " mm" }
        }
        needsDisplay = true
        needsLayout = true
    }

    private var enabled: Bool { !(workspace?.active.model.selection.isEmpty ?? true) }
    /// Same 22 pt title bar on Appearance, Align, and Stroke. Tabs sit inside it.
    private var titleHeight: CGFloat { WorkspaceMetrics.panelTitleHeight }
    /// Content hits stay on the controls placed by the metric crop.
    private var interactionTop: CGFloat {
        if collapsed { return titleHeight }
        if tabs == [.appearance] { return 51 }
        if tabs.contains(.stroke) { return 37 }
        if tabs.contains(.align) { return 50 }
        return titleHeight
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        guard let metric = metricFrame else {
            super.setFrameOrigin(newOrigin)
            return
        }
        let kept = RestingFrame.origin(
            proposedX: Double(newOrigin.x), proposedY: Double(newOrigin.y),
            metricX: Double(metric.origin.x), metricY: Double(metric.origin.y),
            proposedWidth: Double(bounds.width), proposedHeight: Double(bounds.height),
            metricWidth: Double(metric.width), metricHeight: Double(metric.height),
            keepsMetric: keepsMetricOrigin
        )
        super.setFrameOrigin(NSPoint(x: kept.x, y: kept.y))
    }

    override func layout() {
        super.layout()
        let showStroke = !collapsed && !suppressContent && !embeddedInDock && active == .stroke && !strokeOptionsHidden
        weightField.isHidden = !showStroke
        limitField.isHidden = !showStroke
        let showTransform = !collapsed && !suppressContent && !embeddedInDock && active == .transform
        if showTransform { installTransformFields() }
        for field in [xField, yField, wField, hField] { field.isHidden = !showTransform }
        if showTransform {
            let fields = [xField, yField, wField, hField]
            for (index, field) in fields.enumerated() {
                field.frame = NSRect(x: 36, y: 28 + CGFloat(index) * 28, width: min(160, bounds.width - 48), height: 20)
            }
        }
        if showStroke {
            weightField.frame = NSRect(x: 78, y: 48, width: 64, height: 20)
            limitField.frame = NSRect(x: 248, y: 114, width: 40, height: 18)
            let ink = enabled ? Theme.text : Theme.color(0x878787)
            weightField.textColor = ink
            limitField.textColor = ink
        }
        restoreRestingOrigin()
    }

    private var transformFieldsInstalled = false

    private func installTransformFields() {
        guard !transformFieldsInstalled else { return }
        transformFieldsInstalled = true
        for field in [xField, yField, wField, hField] where field.superview !== self {
            addSubview(field)
        }
    }

    private func restoreRestingOrigin() {
        guard let metric = metricFrame else { return }
        let kept = RestingFrame.origin(
            proposedX: Double(frame.origin.x), proposedY: Double(frame.origin.y),
            metricX: Double(metric.origin.x), metricY: Double(metric.origin.y),
            proposedWidth: Double(bounds.width), proposedHeight: Double(bounds.height),
            metricWidth: Double(metric.width), metricHeight: Double(metric.height),
            keepsMetric: keepsMetricOrigin
        )
        let origin = NSPoint(x: kept.x, y: kept.y)
        if frame.origin != origin { super.setFrameOrigin(origin) }
    }

    private var syncingLayer = false

    /// The frame can already be the metric while the layer is still 5 pt to the
    /// right. Put the layer on the frame immediately before it is composited.
    override func viewWillDraw() {
        super.viewWillDraw()
        guard !syncingLayer else { return }
        syncingLayer = true
        restoreRestingOrigin()
        if keepsMetricOrigin, let layer {
            let anchor = layer.anchorPoint
            let size = layer.bounds.size
            let origin = CGPoint(
                x: layer.position.x - anchor.x * size.width,
                y: layer.position.y - anchor.y * size.height
            )
            let dx = frame.minX - origin.x
            let dy = frame.minY - origin.y
            if abs(dx) > 0.5 || abs(dy) > 0.5 {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.position = CGPoint(x: layer.position.x + dx, y: layer.position.y + dy)
                CATransaction.commit()
            }
        }
        syncingLayer = false
    }

    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(rect: bounds).addClip()
        if embeddedInDock {
            drawEmbeddedBody()
            return
        }
        Theme.panel.setFill()
        bounds.fill()
        Theme.color(0x424242).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: titleHeight).fill()
        if tabs.count < 2 || collapsed {
            let title = (collapsed ? tabs.map(\.rawValue).joined(separator: " / ") : active.rawValue) as NSString
            title.draw(at: NSPoint(x: 10, y: 4), withAttributes: [
                .font: Theme.ui(13, weight: .semibold), .foregroundColor: Theme.color(0xF3F3F3)
            ])
        }
        drawGlyph("«", NSRect(x: bounds.width - 46, y: 3, width: 16, height: 16))
        drawGlyph("×", NSRect(x: bounds.width - 24, y: 3, width: 16, height: 16))
        var activeTab: (CGFloat, CGFloat)?
        if !collapsed, tabs.count > 1 {
            let measured = tabs == [.transform, .align, .pathfinder]
            let spots: [CGFloat] = measured ? [12, 69.5, 118.5] : []
            var x: CGFloat = 8
            for (index, tab) in tabs.enumerated() {
                let on = tab == active
                let font = Theme.ui(13, weight: on ? .semibold : .regular)
                let color: NSColor = on ? Theme.color(0xF3F3F3) : Theme.color(0xB0B0B0)
                if measured, spots.indices.contains(index) { x = spots[index] }
                (tab.rawValue as NSString).draw(at: NSPoint(x: x, y: 4), withAttributes: [
                    .font: font, .foregroundColor: color
                ])
                let labelWidth = (tab.rawValue as NSString).size(withAttributes: [.font: font]).width
                if on { activeTab = (x, labelWidth) }
                if !measured { x += labelWidth + 12 }
            }
        }
        if !collapsed {
            PanelIcons.menu(in: NSRect(x: bounds.width - 68, y: 4, width: 14, height: 12))
            if !suppressContent {
                drawBody(NSRect(x: 8, y: titleHeight + 8, width: bounds.width - 16, height: max(0, bounds.height - titleHeight - 18)))
                Theme.dim.setFill()
                let grip = NSRect(x: bounds.midX - 16, y: bounds.height - 8, width: 32, height: 3)
                NSBezierPath(roundedRect: grip, xRadius: 1, yRadius: 1).fill()
            }
        }
        PanelHairline.draw(in: bounds, titleHeight: titleHeight)
        if let activeTab, let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            context.shouldAntialias = false
            Theme.text.setFill()
            NSRect(x: activeTab.0, y: titleHeight - 1, width: activeTab.1, height: 1).fill()
            context.restoreGraphicsState()
        }
    }

    private func drawGlyph(_ text: String, _ rect: NSRect) {
        let font = Theme.ui(13)
        let size = (text as NSString).size(withAttributes: [.font: font])
        (text as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: [
            .font: font, .foregroundColor: Theme.dim
        ])
    }

    private func drawAppearance(_ rect: NSRect) {
        _ = rect
        let ink = Theme.color(0xF3F3F3)
        let dim = Theme.color(0xD1D1D1)
        let shown = workspace?.active.model.appearanceAttributes
            ?? AppearanceAttributes(targetName: "未选择对象", fill: Appearance.documentDefault.fill, stroke: Appearance.documentDefault.stroke)
        (shown.targetName as NSString).draw(at: place(33.5, 150), withAttributes: [
            .font: Theme.ui(13, weight: .semibold), .foregroundColor: ink
        ])
        appearanceRow(top: 168.5, title: "描边:", paint: shown.stroke?.paint, detail: strokeDetail(shown.stroke), ink: ink, dim: dim, link: true)
        opacityLine(top: 198, indented: true, ink: dim)
        appearanceRow(top: 230, title: "填色:", paint: shown.fill, detail: "", ink: ink, dim: dim, link: false)
        opacityLine(top: 260.5, indented: true, ink: dim)
        opacityLine(top: 290, indented: false, ink: dim)
        let centers: [CGFloat] = [41.75, 74.25, 108.5, 212.75, 247, 278]
        for (index, center) in centers.enumerated() {
            let point = place(center, 318)
            appearanceIcon(index, in: NSRect(x: point.x - 9, y: point.y, width: 18, height: 16))
        }
    }

    private func strokeDetail(_ stroke: StrokeStyle?) -> String {
        guard let stroke else { return "" }
        if abs(stroke.width - stroke.width.rounded()) < 0.05 {
            return "\(Int(stroke.width.rounded())) pt"
        }
        return String(format: "%.1f pt", stroke.width)
    }

    private func appearanceRow(top: CGFloat, title: String, paint: Paint?, detail: String, ink: NSColor, dim: NSColor, link: Bool) {
        let eye = place(33.5, top)
        PanelIcons.eye(in: NSRect(x: eye.x, y: eye.y + 1, width: 16, height: 12), open: true)
        disclosure(at: place(67, top + 3), open: true, color: dim)
        (title as NSString).draw(at: place(90.5, top), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: ink
        ])
        let origin = place(145.5, top - 1.5)
        let chip = NSRect(x: origin.x, y: origin.y, width: 13, height: 12)
        paintChip(chip, paint: paint)
        if !detail.isEmpty {
            var attributes: [NSAttributedString.Key: Any] = [.font: Theme.ui(13), .foregroundColor: dim]
            if link { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            (detail as NSString).draw(at: place(164, top), withAttributes: attributes)
        }
    }

    /// Same paint the toolbar wells draw. Nil is the red none slash, not a stand-in black.
    private func paintChip(_ rect: NSRect, paint: Paint?) {
        guard let paint else {
            noneSwatch(rect)
            return
        }
        switch paint {
        case .solid(let color):
            PanelIcons.swatch(in: rect, color: color.nsColor)
        case .linear(let gradient), .radial(let gradient):
            let stops = gradient.stops.map(\.color.nsColor)
            let colors = stops.count >= 2 ? [stops[0], stops[stops.count - 1]] : [NSColor.white, NSColor.black]
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            NSGradient(colors: colors)?.draw(in: rect, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.65).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }

    private func opacityLine(top: CGFloat, indented: Bool, ink: NSColor) {
        let eye = place(33.5, top)
        PanelIcons.eye(in: NSRect(x: eye.x, y: eye.y + 1, width: 16, height: 12), open: true)
        let textX: CGFloat = indented ? 119 : 90.5
        ("不透明度：默认值" as NSString).draw(at: place(textX, top), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: ink
        ])
    }

    private func noneSwatch(_ rect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.black.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        NSColor(calibratedRed: 0.80, green: 0.00, blue: 0.13, alpha: 1).setStroke()
        let slash = NSBezierPath()
        slash.lineWidth = 2.2
        slash.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 1))
        slash.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
        slash.stroke()
    }

    private func disclosure(at origin: NSPoint, open: Bool, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if open {
            path.move(to: NSPoint(x: origin.x, y: origin.y))
            path.line(to: NSPoint(x: origin.x + 4, y: origin.y + 5))
            path.line(to: NSPoint(x: origin.x + 8, y: origin.y))
        } else {
            path.move(to: NSPoint(x: origin.x, y: origin.y + 6))
            path.line(to: NSPoint(x: origin.x + 5, y: origin.y + 3))
            path.line(to: NSPoint(x: origin.x, y: origin.y))
        }
        path.stroke()
    }

    /// Footer, left to right: new stroke, new fill, fx, clear, duplicate, delete.
    private func appearanceIcon(_ index: Int, in rect: NSRect) {
        let color: NSColor = (!enabled && index >= 3) ? Theme.color(0x6E6E6E) : Theme.color(0xE4E4E4)
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.lineWidth = 1.1
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch index {
        case 0:
            path.appendRect(rect.insetBy(dx: 3.5, dy: 2.5))
            path.stroke()
        case 1:
            path.appendRect(rect.insetBy(dx: 3.5, dy: 2.5))
            path.fill()
        case 2:
            ("fx" as NSString).draw(at: NSPoint(x: rect.minX + 1, y: rect.minY + 1), withAttributes: [
                .font: Theme.ui(12, weight: .medium), .foregroundColor: color
            ])
        case 3:
            path.appendOval(in: rect.insetBy(dx: 2.5, dy: 1.5))
            path.move(to: NSPoint(x: rect.minX + 5, y: rect.minY + 3))
            path.line(to: NSPoint(x: rect.maxX - 5, y: rect.maxY - 3))
            path.stroke()
        case 4:
            path.appendRect(NSRect(x: rect.minX + 2, y: rect.minY + 4, width: rect.width - 8, height: rect.height - 7))
            path.appendRect(NSRect(x: rect.minX + 6, y: rect.minY + 1, width: rect.width - 8, height: rect.height - 7))
            path.stroke()
        default:
            let body = NSRect(x: rect.minX + 4, y: rect.minY + 1, width: rect.width - 8, height: rect.height - 6)
            path.appendRect(body)
            path.move(to: NSPoint(x: rect.minX + 3, y: body.maxY))
            path.line(to: NSPoint(x: rect.maxX - 3, y: body.maxY))
            path.move(to: NSPoint(x: rect.midX - 2.5, y: body.maxY))
            path.line(to: NSPoint(x: rect.midX - 2.5, y: rect.maxY - 1))
            path.line(to: NSPoint(x: rect.midX + 2.5, y: rect.maxY - 1))
            path.line(to: NSPoint(x: rect.midX + 2.5, y: body.maxY))
            path.stroke()
        }
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
        _ = ink
        let labels = ["X", "Y", "W", "H"]
        let readout = workspace?.active.model.selectionReadout()
        let xText = (readout?.x ?? "0") + " mm"
        let yText = (readout?.y ?? "0") + " mm"
        let wText = (readout?.width ?? "0") + " mm"
        let hText = (readout?.height ?? "0") + " mm"
        let values = [xText, yText, wText, hText]
        let labelColor = Theme.color(0xC2C2C2)
        let labelFont = Theme.ui(13)
        for index in 0..<4 {
            let y = rect.minY + CGFloat(index) * 28
            let label = labels[index] as NSString
            label.draw(at: NSPoint(x: rect.minX, y: y + 2), withAttributes: [
                .font: labelFont, .foregroundColor: labelColor
            ])
            let field = NSRect(x: rect.minX + 22, y: y, width: min(140, rect.width - 22), height: 20)
            PanelIcons.stepper(field, title: values[index])
        }
        let extra = Theme.color(0xD1D1D1)
        let extraFont = Theme.ui(12)
        let angle = "∠ 0°" as NSString
        angle.draw(at: NSPoint(x: rect.minX, y: rect.minY + 120), withAttributes: [.font: extraFont, .foregroundColor: extra])
        let shear = "倾斜 0°" as NSString
        shear.draw(at: NSPoint(x: rect.minX + 70, y: rect.minY + 120), withAttributes: [.font: extraFont, .foregroundColor: extra])
        if let readout {
            let name = "\(readout.name)属性" as NSString
            name.draw(at: NSPoint(x: rect.minX, y: rect.minY + 146), withAttributes: [.font: extraFont, .foregroundColor: extra])
            let size = "W \(readout.width) mm   H \(readout.height) mm" as NSString
            size.draw(at: NSPoint(x: rect.minX, y: rect.minY + 166), withAttributes: [.font: extraFont, .foregroundColor: extra])
        }
        PanelIcons.checkbox(at: NSPoint(x: rect.minX, y: rect.minY + 190), on: false, title: "缩放圆角")
        PanelIcons.checkbox(at: NSPoint(x: rect.minX, y: rect.minY + 212), on: false, title: "缩放描边和效果")
    }

    private func drawAlign(_ rect: NSRect, ink: NSColor) {
        _ = rect
        let origin = cropOrigin
        let label = Theme.color(0xD1D1D1)
        cropText("对齐对象", x: 330, top: 172.5, size: 14, color: label)
        cropText("分布对象", x: 330, top: 250, size: 14, color: label)
        cropText("分布间距", x: 330, top: 327.5, size: 14, color: label)
        let icon = Theme.color(0xC2C2C2)
        for name in ["a0", "a1", "a2", "a3", "a4", "a5", "a6", "b0", "b1", "b2", "c0", "c1"] {
            TracedMarks.draw(name, origin: origin, color: icon)
        }
        let spacing = place(458, 352)
        let value = NSRect(x: spacing.x, y: spacing.y, width: 48, height: 18)
        Theme.color(0x454545).setFill()
        NSBezierPath(roundedRect: value, xRadius: 2, yRadius: 2).fill()
        let valueText = "0 mm" as NSString
        let valueFont = Theme.ui(11)
        let valueSize = valueText.size(withAttributes: [.font: valueFont])
        valueText.draw(
            at: NSPoint(x: value.midX - valueSize.width / 2, y: value.midY - valueSize.height / 2),
            withAttributes: [.font: valueFont, .foregroundColor: Theme.color(0x878787)]
        )
        cropText("对齐到", x: 516, top: 327, size: 13, color: label)
        for index in 0..<3 {
            let point = place(510.5 + CGFloat(index) * 40.5, 351)
            let slot = NSRect(x: point.x, y: point.y, width: 22, height: 18)
            if alignTarget != 0, index == alignTarget {
                Theme.focus.setStroke()
                let ring = NSBezierPath(roundedRect: slot.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
                ring.lineWidth = 1
                ring.stroke()
            }
            PanelIcons.align(index, in: slot)
        }
        _ = ink
    }

    /// Glyphs stay at the metric crop even if the host resizes or the panel moves.
    /// A live superview height was sliding the body out while the title stayed put.
    private var cropOrigin: NSPoint {
        let metric: WorkspaceMetrics.PanelFrame
        if tabs.contains(.stroke) {
            metric = WorkspaceMetrics.stroke
        } else if tabs.count == 1 && tabs.contains(.appearance) {
            metric = WorkspaceMetrics.appearance
        } else {
            metric = WorkspaceMetrics.align
        }
        return NSPoint(x: metric.x, y: WorkspaceMetrics.chromeInset + metric.top)
    }

    /// Crop point (y grows down from the body top) into this flipped panel.
    private func place(_ cropX: CGFloat, _ cropY: CGFloat) -> NSPoint {
        let origin = cropOrigin
        return NSPoint(x: cropX - origin.x, y: cropY - origin.y)
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
        _ = rect
        let stroke = workspace?.active.model.currentStroke
        let label = enabled ? Theme.color(0xD1D1D1) : Theme.color(0x878787)
        let bright = Theme.color(0xD1D1D1)
        caption("粗细", at: place(362.5, 442.5), ink: bright)
        let weightBox = NSRect(x: place(410, 437).x, y: place(410, 437).y, width: 18, height: 22)
        stepperArrows(weightBox)
        let weightLabel = workspace?.active.model.currentStroke.map { stroke -> String in
            stroke.width == stroke.width.rounded() ? "\(Int(stroke.width)) pt" : String(format: "%.2f pt", stroke.width)
        } ?? "1 pt"
        PanelIcons.popup(NSRect(x: place(490, 437).x, y: place(490, 437).y, width: 72, height: 22), title: weightLabel)

        caption("端点", at: place(362.5, 475.5), ink: label)
        iconRow(3, x: place(412, 472).x, y: place(412, 472).y, selected: enabled ? capIndex(stroke?.cap) : -1, muted: !enabled) { PanelIcons.cap($0, in: $1) }

        caption("边角", at: place(362.5, 508.5), ink: label)
        iconRow(3, x: place(412, 505).x, y: place(412, 505).y, selected: enabled ? joinIndex(stroke?.join) : -1, muted: !enabled) { PanelIcons.corner($0, in: $1) }
        caption("限制", at: place(520, 508.5), ink: label)
        ("×" as NSString).draw(at: NSPoint(x: limitField.frame.maxX + 4, y: limitField.frame.minY + 1), withAttributes: [
            .font: Theme.ui(12), .foregroundColor: label
        ])

        caption("对齐描边", at: place(330.5, 543), ink: label)
        iconRow(3, x: place(412, 540).x, y: place(412, 540).y, selected: enabled ? strokeAlign : -1, muted: !enabled) { PanelIcons.strokeAlign($0, in: $1) }

        let dash = place(330.5, 584)
        PanelIcons.checkbox(at: dash, on: enabled && !(stroke?.dash.isEmpty ?? true), title: "")
        ("虚线" as NSString).draw(at: NSPoint(x: dash.x + 18, y: dash.y), withAttributes: [
            .font: Theme.ui(13), .foregroundColor: label
        ])
        PanelIcons.cap(0, in: NSRect(x: place(535, 582).x, y: place(535, 582).y, width: 18, height: 16))
        PanelIcons.corner(0, in: NSRect(x: place(584, 582).x, y: place(584, 582).y, width: 18, height: 16))

        let names = ["虚线", "间隙", "虚线", "间隙", "虚线", "间隙"]
        let columns: [CGFloat] = [336, 387, 436, 487, 536, 587]
        for (index, name) in names.enumerated() {
            let origin = place(columns[index], 643.5)
            (name as NSString).draw(at: origin, withAttributes: [
                .font: Theme.ui(11), .foregroundColor: label
            ])
            PanelIcons.field(NSRect(x: origin.x, y: origin.y + 16, width: 44, height: 18), text: "", align: .center)
        }

        caption("箭头", at: place(330.5, 682), ink: label)
        let arrowY = place(372, 678).y
        let arrowX = place(372, 678).x
        let popupW: CGFloat = 108
        PanelIcons.popup(NSRect(x: arrowX, y: arrowY, width: popupW, height: 22), title: arrowTitle)
        swapArrows(NSRect(x: arrowX + popupW + 3, y: arrowY + 2, width: 14, height: 16))
        PanelIcons.popup(NSRect(x: arrowX + popupW + 20, y: arrowY, width: popupW, height: 22), title: "无")

        caption("缩放", at: place(362.5, 722.5), ink: label)
        let scaleY = place(403, 719).y
        PanelIcons.field(NSRect(x: place(403, 719).x, y: scaleY, width: 62, height: 20), text: "100%", align: .center)
        PanelIcons.field(NSRect(x: place(470, 719).x, y: scaleY, width: 62, height: 20), text: "100%", align: .center)
        chainLink(NSRect(x: place(538, 722).x, y: scaleY + 4, width: 16, height: 12), linked: true)

        caption("对齐", at: place(362.5, 759), ink: label)
        segmentPair(place(410, 756), selected: dashAlign ? 1 : 0)
        caption("配置文件", at: place(330.5, 802.5), ink: label)
        PanelIcons.popup(NSRect(x: place(400, 799).x, y: place(400, 799).y, width: 150, height: 22), title: profileTitle(stroke?.profile))
        flipMark(NSRect(x: place(558, 802).x, y: place(558, 802).y, width: 14, height: 16))
        _ = ink
    }

    private func swapArrows(_ rect: NSRect) {
        Theme.color(0xC2C2C2).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.1
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.minX, y: rect.midY - 3))
        path.line(to: NSPoint(x: rect.maxX - 3, y: rect.midY - 3))
        path.move(to: NSPoint(x: rect.maxX - 6, y: rect.midY - 6))
        path.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY - 3))
        path.line(to: NSPoint(x: rect.maxX - 6, y: rect.midY))
        path.move(to: NSPoint(x: rect.maxX, y: rect.midY + 4))
        path.line(to: NSPoint(x: rect.minX + 3, y: rect.midY + 4))
        path.move(to: NSPoint(x: rect.minX + 6, y: rect.midY + 1))
        path.line(to: NSPoint(x: rect.minX + 2, y: rect.midY + 4))
        path.line(to: NSPoint(x: rect.minX + 6, y: rect.midY + 7))
        path.stroke()
    }

    private func chainLink(_ rect: NSRect, linked: Bool) {
        let color = Theme.color(0xC2C2C2)
        _ = linked
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.appendOval(in: NSRect(x: rect.minX, y: rect.midY - 3, width: 7, height: 6))
        path.appendOval(in: NSRect(x: rect.maxX - 7, y: rect.midY - 3, width: 7, height: 6))
        path.stroke()
    }

    private func segmentPair(_ origin: NSPoint, selected: Int) {
        for index in 0..<2 {
            let rect = NSRect(x: origin.x + CGFloat(index) * 28, y: origin.y, width: 24, height: 18)
            if selected != 0, index == selected {
                Theme.focus.setStroke()
                let ring = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
                ring.lineWidth = 1
                ring.stroke()
            }
            Theme.color(0xC2C2C2).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.15
            let inset = rect.insetBy(dx: 4, dy: 4)
            path.move(to: NSPoint(x: inset.minX, y: inset.minY))
            path.line(to: NSPoint(x: inset.minX, y: inset.maxY))
            path.move(to: NSPoint(x: inset.maxX, y: inset.minY))
            path.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
            let markX = index == 0 ? inset.minX + 3 : inset.maxX - 3
            path.move(to: NSPoint(x: markX, y: inset.minY + 1))
            path.line(to: NSPoint(x: markX, y: inset.maxY - 1))
            path.stroke()
        }
    }

    private func flipMark(_ rect: NSRect) {
        Theme.color(0xC2C2C2).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.1
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.midX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX + 1, y: rect.midY))
        path.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY))
        path.close()
        path.move(to: NSPoint(x: rect.midX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + 1, y: rect.midY))
        path.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY))
        path.stroke()
    }

    private func stepperArrows(_ rect: NSRect) {
        Theme.dim.setStroke()
        let up = NSBezierPath()
        up.lineWidth = 1.1
        up.lineCapStyle = .round
        up.move(to: NSPoint(x: rect.minX + 3, y: rect.midY - 1))
        up.line(to: NSPoint(x: rect.midX, y: rect.minY + 3))
        up.line(to: NSPoint(x: rect.maxX - 3, y: rect.midY - 1))
        up.stroke()
        let down = NSBezierPath()
        down.lineWidth = 1.1
        down.lineCapStyle = .round
        down.move(to: NSPoint(x: rect.minX + 3, y: rect.midY + 2))
        down.line(to: NSPoint(x: rect.midX, y: rect.maxY - 2))
        down.line(to: NSPoint(x: rect.maxX - 3, y: rect.midY + 2))
        down.stroke()
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

    private func caption(_ text: String, at point: NSPoint, ink: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: Theme.ui(13), .foregroundColor: ink == Theme.text ? Theme.dim : ink
        ])
    }

    private func caption(_ text: String, y: CGFloat, ink: NSColor) {
        caption(text, at: NSPoint(x: 8, y: y), ink: ink)
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

    private func drawBody(_ content: NSRect) {
        let ink = Theme.color(0xD1D1D1)
        switch active {
        case .appearance: drawAppearance(content)
        case .transform: drawTransform(content, ink: ink)
        case .align: drawAlign(content, ink: ink)
        case .pathfinder: drawPathfinder(content, ink: enabled ? Theme.text : Theme.color(0x707070))
        case .stroke: drawStroke(content, ink: ink)
        case .opacity: drawOpacity(content, ink: ink)
        }
    }

    private func drawEmbeddedBody() {
        Theme.panel.setFill()
        bounds.fill()
        guard !suppressContent else { return }
        drawBody(NSRect(x: 8, y: 8, width: max(0, bounds.width - 16), height: max(0, bounds.height - 16)))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !embeddedInDock, NSRect(x: bounds.width - 24, y: 2, width: 20, height: 20).contains(point) {
            trackControl(event) { [weak self] in self?.closeFromChrome() }
            return
        }
        if !embeddedInDock, NSRect(x: bounds.width - 48, y: 2, width: 20, height: 20).contains(point) {
            trackControl(event) { [weak self] in self?.applyCollapse(!((self?.collapsed) ?? false)) }
            return
        }
        if !embeddedInDock, NSRect(x: bounds.width - 72, y: 2, width: 22, height: 18).contains(point) {
            trackControl(event) { [weak self] in self?.showMenu() }
            return
        }
        if !collapsed, tabs.count > 1, point.y < titleHeight, let tab = tab(at: point) {
            trackTab(tab, from: event)
            return
        }
        // Title bar and the bottom pill both move. A horizontal pill drag used to
        // hit the resize band and leave the panel pixel-identical.
        let region = PanelChromeHit.region(
            x: Double(point.x),
            y: Double(point.y),
            width: Double(bounds.width),
            height: Double(bounds.height),
            titleHeight: Double(titleHeight)
        )
        switch region {
        case .move:
            dragMove(event)
        case .resize:
            dragResize(event)
        case .content:
            handleContent(point)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        if active == .stroke {
            menu.addItem(withTitle: strokeOptionsHidden ? "显示选项" : "隐藏选项", action: #selector(menuStrokeOptions), keyEquivalent: "")
            for item in menu.items { item.target = self }
            NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: self)
            return
        }
        if active == .transform {
            for title in IllustratorParity.transformMenu {
                if title == "-" { menu.addItem(.separator()); continue }
                let item = NSMenuItem(title: title, action: #selector(menuTransform(_:)), keyEquivalent: "")
                item.target = self
                item.state = (title == "仅变换对象" || title == "使用符号的套版色点") ? .on : .off
                menu.addItem(item)
            }
            NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: self)
            return
        }
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

    @objc private func menuStrokeOptions() {
        strokeOptionsHidden.toggle()
        needsLayout = true
        needsDisplay = true
    }

    @objc private func menuTransform(_ sender: NSMenuItem) {
        guard let model = workspace?.active.model else { return }
        switch sender.title {
        case "水平翻转": model.perform("水平翻转")
        case "垂直翻转": model.perform("垂直翻转")
        case "隐藏选项": strokeOptionsHidden.toggle()
        default: model.status = sender.title
        }
        workspace?.touch()
        needsDisplay = true
    }

    @objc private func menuCollapse() { applyCollapse(true) }
    @objc private func menuClose() { closeFromChrome() }

    private func applyCollapse(_ collapse: Bool) {
        guard collapse != collapsed else { return }
        if collapse {
            expandedHeight = max(frame.size.height, titleHeight + 1)
            collapsed = true
            frame.size.height = CGFloat(PanelCollapse.height(collapsed: true, expanded: Double(expandedHeight), title: Double(titleHeight)))
        } else {
            collapsed = false
            let remembered = expandedHeight > titleHeight + 1 ? expandedHeight : preferredSize.height
            frame.size.height = CGFloat(PanelCollapse.height(
                collapsed: false,
                expanded: Double(max(remembered, titleHeight + 1)),
                title: Double(titleHeight)
            ))
        }
        needsLayout = true
        needsDisplay = true
    }

    private func closeFromChrome() {
        isHidden = true
        dockColumnID = nil
        embeddedInDock = false
        editorShell?.releaseColumnIfEmpty()
    }

    /// A click on the title buttons still runs the button. Moving past the
    /// column-undock stationary distance starts the same drag the title bar uses.
    private func trackControl(_ event: NSEvent, act: @escaping () -> Void) {
        let start = event.locationInWindow
        let source = window
        while true {
            guard let next = source?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { return }
            let dx = next.locationInWindow.x - start.x
            let dy = next.locationInWindow.y - start.y
            if hypot(dx, dy) > CGFloat(IllustratorDock.undockStationary) {
                trackDrag(from: event, first: next)
                return
            }
            if next.type == .leftMouseUp {
                act()
                return
            }
        }
    }
    @objc private func menuSplit() { host?.split(self); needsDisplay = true }
    @objc private func menuMerge() {
        guard let other = host?.subviews.compactMap({ $0 as? FloatPanel }).first(where: { $0 !== self && !$0.isHidden }) else { return }
        host?.merge(self, into: other)
    }

    /// A short click switches tabs. Moving the pointer starts a panel drag, so a
    /// grouped panel such as 路径查找器 can still be pulled into the shoulder.
    private func trackTab(_ tab: PanelKind, from event: NSEvent) {
        let start = event.locationInWindow
        while true {
            guard let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            let dx = next.locationInWindow.x - start.x
            let dy = next.locationInWindow.y - start.y
            if hypot(dx, dy) <= CGFloat(IllustratorDock.undockStationary) {
                if next.type == .leftMouseUp {
                    active = tab
                    needsLayout = true
                    needsDisplay = true
                    return
                }
                continue
            }
            guard let born = extract(tab) else { return }
            born.trackDrag(from: event, first: next)
            return
        }
    }

    /// Pull one tab out. The source keeps the other tabs and only shrinks.
    private func extract(_ tab: PanelKind) -> FloatPanel? {
        guard tabs.count > 1, let host else { return nil }
        tabs.removeAll { $0 == tab }
        if active == tab { active = tabs[0] }
        suppressContent = true
        needsDisplay = true
        shrinkToRemainingTabs()
        let born = FloatPanel(tabs: [tab])
        born.dragOriginGroupID = dockGroupID
        born.workspace = workspace
        let shellFrame = superview?.convert(frame, to: editorShell) ?? frame
        host.addFloating(born)
        if let shell = editorShell {
            born.frame = host.convert(shellFrame, from: shell)
        } else {
            born.frame = frame
        }
        if let fit = Self.fittedSize(tabs: [tab]) {
            born.preferredSize = NSSize(
                width: fit.width > 1 ? fit.width : frame.width,
                height: fit.height > 1 ? fit.height : frame.height
            )
            born.expandedHeight = born.preferredSize.height
            born.frame.size = born.preferredSize
        }
        born.onDragEnd = { [weak self] in
            self?.suppressContent = false
            self?.needsDisplay = true
        }
        return born
    }

    private func shrinkToRemainingTabs() {
        guard let fit = Self.fittedSize(tabs: tabs) else { return }
        var size = frame.size
        if fit.width > 1 { size.width = fit.width }
        if fit.height > 1 { size.height = fit.height }
        frame.size = size
        preferredSize = size
        expandedHeight = size.height
        if let id = dockColumnID {
            editorShell?.resizeColumn(id, to: size.width)
        }
    }

    static func fittedSize(tabs: [PanelKind]) -> NSSize? {
        let fit = PanelContentFit.size(tabs: tabs.map(\.rawValue))
        return NSSize(width: CGFloat(fit.width), height: CGFloat(fit.height))
    }

    private func tab(at point: NSPoint) -> PanelKind? {
        let measured = tabs == [.transform, .align, .pathfinder]
        let spots: [CGFloat] = measured ? [12, 69.5, 118.5, bounds.width] : []
        var x: CGFloat = 8
        for (index, tab) in tabs.enumerated() {
            let font = Theme.ui(13, weight: .semibold)
            let width = (tab.rawValue as NSString).size(withAttributes: [.font: font]).width + 12
            let start = measured && spots.indices.contains(index) ? spots[index] : x
            let end = measured && spots.indices.contains(index + 1) ? spots[index + 1] : start + width
            if point.x >= start && point.x < end { return tab }
            x = end
        }
        return nil
    }

    private func dragMove(_ event: NSEvent) {
        guard !dragging else { return }
        trackDrag(from: event, first: nil)
    }

    func beginMeasuredDrag(from event: NSEvent, first: NSEvent?) {
        trackDrag(from: event, first: first)
    }

    /// Title, tab, and button drags all come through here. The pointer is handed
    /// to `PanelDragPath`, which is the measured Illustrator zone test.
    private func trackDrag(from event: NSEvent, first: NSEvent?) {
        keepsMetricOrigin = false
        dragging = true
        let source = event.window ?? window
        guard let shell = editorShell else {
            dragging = false
            let ended = onDragEnd
            onDragEnd = nil
            ended?()
            return
        }
        shell.lift(self)
        var path = shell.makeDragPath(for: self, windowPoint: shellPoint(event))
        var pending = first
        while true {
            let sample: NSEvent?
            if let queued = pending {
                sample = queued
                pending = nil
            } else {
                sample = source?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])
            }
            guard let sample else { break }
            let up = sample.type == .leftMouseUp
            shell.dragStep(self, path: &path, windowPoint: shellPoint(sample), up: up)
            window?.displayIfNeeded()
            if up { break }
        }
        dragging = false
        dragOriginGroupID = nil
        alphaValue = 1
        let ended = onDragEnd
        onDragEnd = nil
        ended?()
    }

    private func shellPoint(_ event: NSEvent) -> NSPoint {
        guard let shell = editorShell, let shellWindow = shell.window else { return event.locationInWindow }
        if event.window === shellWindow || event.window == nil { return event.locationInWindow }
        let screen = event.window?.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)) ?? .zero
        return shellWindow.convertFromScreen(screen).origin
    }

    private func dragResize(_ event: NSEvent) {
        keepsMetricOrigin = false
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
        expandedHeight = frame.size.height
        preferredSize.height = frame.size.height
        if preferredSize.width < 1 { preferredSize.width = frame.size.width }
    }

    private func handleContent(_ point: NSPoint) {
        guard let workspace else { return }
        let model = workspace.active.model
        let top = interactionTop
        switch active {
        case .appearance:
            let localY = point.y - top
            if localY < 36 {
                cycleOpacity(model)
            } else if point.x < 120, localY > 100 {
                let index = Int((point.x - 8) / 28)
                if index == 0 { model.addStrokeLayer(); model.status = "添加描边" }
                else if index == 1 { model.addFillLayer() }
                else if index == 2 { _ = workspace.perform("效果 圆角") }
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
            let valueMenu = place(490, 437)
            if NSRect(x: valueMenu.x, y: valueMenu.y, width: 72, height: 22).contains(point) {
                showStrokeWeights()
                return
            }
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

    private func applyGeometry(_ field: PanelField?, key: String) {
        guard let field, let model = workspace?.active.model else { return }
        model.applyGeometryField(key, text: field.stringValue)
        workspace?.touch()
        sync()
    }

    private func showStrokeWeights() {
        let menu = NSMenu()
        let current = workspace?.active.model.currentStroke?.width
        for weight in IllustratorParity.strokeWeights {
            let title = weight == weight.rounded() ? "\(Int(weight)) pt" : String(format: "%.2f pt", weight)
            let item = NSMenuItem(title: title, action: #selector(pickStrokeWeight(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = weight
            if let current, abs(current - weight) < 0.001 { item.state = .on }
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: self)
    }

    @objc private func pickStrokeWeight(_ sender: NSMenuItem) {
        guard let weight = sender.representedObject as? Double, let model = workspace?.active.model else { return }
        mutateStroke(model) { $0.width = weight }
        model.status = "描边 \(sender.title)"
        workspace?.touch()
        sync()
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
