import AppKit
import LaminaCore

final class EditorShell: NSView, ToolbarGripHost {
    let workspace: Workspace
    let tabs = DocumentTabBar()
    let toolbar = IllustratorToolbar()
    let canvas = CanvasHost()
    let status = IllustratorStatusBar()
    let dock = PropertiesDock()
    let floaters = FloatingPanels()
    let contextBar = ContextBar()
    private let controlBar = ControlBar()
    private let shadowBand = ShadowBand()
    private let edgeGuide = DockEdgeGuide()
    private var toolbarDock: DockAnchor = .left
    private var toolbarPanel: NSPanel?
    private var toolbarFloatOrigin = NSPoint.zero

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(frame: .zero)
        toolbar.workspace = workspace
        toolbar.host = self
        canvas.workspace = workspace
        tabs.workspace = workspace
        status.workspace = workspace
        dock.workspace = workspace
        floaters.workspace = workspace
        contextBar.workspace = workspace
        controlBar.workspace = workspace
        // Canvas, then the properties dock, then floating panels so a panel can cover the
        // dock when it snaps to the window's right edge. Docked chrome stays above the canvas.
        for view in [canvas, shadowBand, dock, floaters, contextBar, toolbar, status, controlBar, tabs] as [NSView] {
            addSubview(view)
        }
        edgeGuide.isHidden = true
        addSubview(edgeGuide)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let titleBand = WorkspaceMetrics.titleBand
        let tabHeight = WorkspaceMetrics.documentTabHeight
        let statusHeight: CGFloat = 20
        let toolWidth = WorkspaceMetrics.toolWidth
        let dockWidth = WorkspaceMetrics.dockWidth
        let leading: CGFloat = toolbarDock == .left ? toolWidth : 0
        let trailingTool: CGFloat = toolbarDock == .right ? toolWidth : 0
        let top = bounds.height - titleBand
        tabs.frame = NSRect(x: leading, y: top - tabHeight, width: max(0, bounds.width - leading - trailingTool), height: tabHeight)
        status.frame = NSRect(x: leading, y: 0, width: max(0, bounds.width - leading - trailingTool - dockWidth), height: statusHeight)
        let bodyY = statusHeight
        let bodyH = max(0, top - tabHeight - statusHeight)
        if toolbarDock != .none {
            if toolbar.superview !== self {
                toolbar.removeFromSuperview()
                toolbar.autoresizingMask = []
                addSubview(toolbar, positioned: .below, relativeTo: status)
            }
            let toolX: CGFloat = toolbarDock == .right ? bounds.width - toolWidth : 0
            toolbar.frame = NSRect(x: toolX, y: bodyY, width: toolWidth, height: max(0, top - statusHeight))
        }
        let stripX = leading
        let stripW = max(0, bounds.width - leading - trailingTool)
        controlBar.frame = NSRect(x: stripX, y: bodyY + bodyH - WorkspaceMetrics.controlHeight, width: stripW, height: WorkspaceMetrics.controlHeight)
        let shadowH = WorkspaceMetrics.chromeInset - WorkspaceMetrics.controlHeight
        shadowBand.frame = NSRect(x: stripX, y: bodyY + bodyH - WorkspaceMetrics.chromeInset, width: stripW, height: shadowH)
        let columnH = max(0, bodyH - WorkspaceMetrics.chromeInset)
        let lift = WorkspaceMetrics.dockLift
        dock.frame = NSRect(x: bounds.width - trailingTool - dockWidth, y: bodyY, width: dockWidth, height: columnH + lift)
        canvas.frame = NSRect(x: leading, y: bodyY, width: max(0, bounds.width - leading - trailingTool - dockWidth), height: columnH)
        // Host reaches the window's right client edge, or the floating/right toolbar.
        // Shoulder is published before the frame change so a nested layout seats into this column.
        let floaterWidth = max(0, bounds.width - leading - trailingTool)
        let shoulderWidth = min(dockWidth, floaterWidth)
        floaters.rightShoulder = DockFrame(
            x: Double(max(0, floaterWidth - shoulderWidth)),
            y: 0,
            width: Double(shoulderWidth),
            height: Double(columnH)
        )
        floaters.frame = NSRect(x: leading, y: bodyY, width: floaterWidth, height: columnH)
        contextBar.frame = NSRect(x: canvas.frame.midX - 210, y: canvas.frame.maxY - 46, width: 420, height: 32)
        contextBar.isHidden = workspace.active.model.selection.isEmpty
        if !edgeGuide.isHidden {
            let thickness = CGFloat(DockSnap.guideThickness)
            let guideX: CGFloat = edgeGuide.frame.midX < bounds.midX ? 0 : max(0, bounds.width - thickness)
            edgeGuide.frame = NSRect(x: guideX, y: 0, width: thickness, height: bounds.height)
        }
    }

    var toolbarIsDocked: Bool { toolbarDock == .left || toolbarDock == .right }

    func toolbarGripDown() {
        if toolbarDock == .none, let panel = toolbarPanel {
            toolbarFloatOrigin = panel.frame.origin
        }
    }

    func toolbarGripDragged(undocked: Bool, event: NSEvent, start: NSEvent) {
        if toolbarDock != .none {
            guard undocked else { return }
            beginFloating(start: start, event: event)
        }
        guard toolbarDock == .none, let panel = toolbarPanel, let window else { return }
        let delta = NSPoint(
            x: event.locationInWindow.x - start.locationInWindow.x,
            y: event.locationInWindow.y - start.locationInWindow.y
        )
        var origin = NSPoint(x: toolbarFloatOrigin.x + delta.x, y: toolbarFloatOrigin.y + delta.y)
        let host = window.frame
        let anchor = ToolbarSnap.edge(
            panelMinX: Double(origin.x),
            panelMaxX: Double(origin.x + panel.frame.width),
            hostMinX: Double(host.minX),
            hostMaxX: Double(host.maxX)
        )
        switch anchor {
        case .left: origin.x = host.minX
        case .right: origin.x = host.maxX - panel.frame.width
        case .none: break
        }
        panel.setFrameOrigin(origin)
        showEdgeGuide(anchor)
        if event.type == .leftMouseUp {
            edgeGuide.isHidden = true
            switch anchor {
            case .left: dockToolbar(.left)
            case .right: dockToolbar(.right)
            case .none: break
            }
        }
    }

    func focusCanvasFromToolbar() -> Bool {
        guard let window else { return false }
        window.makeFirstResponder(canvas.drawing)
        return true
    }

    private func beginFloating(start: NSEvent, event: NSEvent) {
        guard toolbarDock != .none, let window else { return }
        let screen = window.convertToScreen(convert(toolbar.frame, to: nil))
        let delta = NSPoint(
            x: event.locationInWindow.x - start.locationInWindow.x,
            y: event.locationInWindow.y - start.locationInWindow.y
        )
        toolbarFloatOrigin = NSPoint(x: screen.origin.x - delta.x, y: screen.origin.y - delta.y)
        let panel = toolbarPanel ?? makeToolbarPanel()
        toolbarPanel = panel
        toolbarDock = .none
        toolbar.removeFromSuperview()
        if panel.contentView == nil { panel.contentView = NSView() }
        panel.contentView?.addSubview(toolbar)
        panel.setFrame(screen, display: true)
        toolbar.autoresizingMask = [.width, .height]
        toolbar.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: screen.size)
        panel.orderFront(nil)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func dockToolbar(_ side: DockAnchor) {
        guard side == .left || side == .right else { return }
        toolbarDock = side
        toolbar.removeFromSuperview()
        toolbar.autoresizingMask = []
        addSubview(toolbar, positioned: .below, relativeTo: status)
        toolbarPanel?.orderOut(nil)
        edgeGuide.isHidden = true
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func showEdgeGuide(_ anchor: DockAnchor) {
        let thickness = CGFloat(DockSnap.guideThickness)
        switch anchor {
        case .left:
            edgeGuide.frame = NSRect(x: 0, y: 0, width: thickness, height: bounds.height)
            edgeGuide.isHidden = false
        case .right:
            edgeGuide.frame = NSRect(x: max(0, bounds.width - thickness), y: 0, width: thickness, height: bounds.height)
            edgeGuide.isHidden = false
        case .none:
            edgeGuide.isHidden = true
        }
        edgeGuide.needsDisplay = true
    }

    private func makeToolbarPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = Theme.panel
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }

    func sync() {
        toolbar.sync()
        canvas.sync()
        tabs.needsDisplay = true
        status.needsDisplay = true
        dock.sync()
        floaters.sync()
        contextBar.needsDisplay = true
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.window.setFill()
        dirtyRect.intersection(bounds).fill()
        let title = "Lamina" as NSString
        let font = Theme.ui(13, weight: .semibold)
        let size = title.size(withAttributes: [.font: font])
        title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 20), withAttributes: [
            .font: font, .foregroundColor: Theme.text
        ])
    }
}

/// 2 pt dock rail. It never takes the click.
final class DockEdgeGuide: NSView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        Theme.color(DockSnap.guideHex).setFill()
        bounds.fill()
    }
}
