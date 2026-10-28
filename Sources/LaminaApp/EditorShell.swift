import AppKit
import LaminaCore

final class EditorShell: NSView {
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

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(frame: .zero)
        toolbar.workspace = workspace
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
        let top = bounds.height - titleBand
        tabs.frame = NSRect(x: toolWidth, y: top - tabHeight, width: max(0, bounds.width - toolWidth), height: tabHeight)
        status.frame = NSRect(x: toolWidth, y: 0, width: max(0, bounds.width - toolWidth - dockWidth), height: statusHeight)
        let bodyY = statusHeight
        let bodyH = max(0, top - tabHeight - statusHeight)
        // Top meets the title chrome. Left edge stays on the window.
        toolbar.frame = NSRect(x: 0, y: bodyY, width: toolWidth, height: max(0, top - statusHeight))
        let stripX = toolWidth
        let stripW = max(0, bounds.width - toolWidth)
        controlBar.frame = NSRect(x: stripX, y: bodyY + bodyH - WorkspaceMetrics.controlHeight, width: stripW, height: WorkspaceMetrics.controlHeight)
        let shadowH = WorkspaceMetrics.chromeInset - WorkspaceMetrics.controlHeight
        shadowBand.frame = NSRect(x: stripX, y: bodyY + bodyH - WorkspaceMetrics.chromeInset, width: stripW, height: shadowH)
        let columnH = max(0, bodyH - WorkspaceMetrics.chromeInset)
        let lift = WorkspaceMetrics.dockLift
        dock.frame = NSRect(x: bounds.width - dockWidth, y: bodyY, width: dockWidth, height: columnH + lift)
        canvas.frame = NSRect(x: toolWidth, y: bodyY, width: max(0, bounds.width - toolWidth - dockWidth), height: columnH)
        // Host reaches the window's right client edge. The properties dock stays underneath.
        // Shoulder is published before the frame change so a nested layout seats into this column.
        let floaterWidth = max(0, bounds.width - toolWidth)
        let shoulderWidth = min(dockWidth, floaterWidth)
        floaters.rightShoulder = DockFrame(
            x: Double(max(0, floaterWidth - shoulderWidth)),
            y: 0,
            width: Double(shoulderWidth),
            height: Double(columnH)
        )
        floaters.frame = NSRect(x: toolWidth, y: bodyY, width: floaterWidth, height: columnH)
        contextBar.frame = NSRect(x: canvas.frame.midX - 210, y: canvas.frame.maxY - 46, width: 420, height: 32)
        contextBar.isHidden = workspace.active.model.selection.isEmpty
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
