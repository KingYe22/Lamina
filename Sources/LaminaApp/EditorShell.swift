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
        // Canvas, then floating panels, then docked chrome. Artwork cannot paint over a bar.
        for view in [canvas, floaters, shadowBand, contextBar, dock, toolbar, status, controlBar, tabs] as [NSView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let titleBand: CGFloat = 28
        let tabHeight: CGFloat = 28
        let statusHeight: CGFloat = 20
        let toolWidth = WorkspaceMetrics.toolWidth
        let dockWidth = WorkspaceMetrics.dockWidth
        let top = bounds.height - titleBand
        tabs.frame = NSRect(x: 0, y: top - tabHeight, width: bounds.width, height: tabHeight)
        status.frame = NSRect(x: toolWidth, y: 0, width: max(0, bounds.width - toolWidth - dockWidth), height: statusHeight)
        let bodyY = statusHeight
        let bodyH = max(0, top - tabHeight - statusHeight)
        toolbar.frame = NSRect(x: 0, y: bodyY, width: toolWidth, height: bodyH)
        let stripX = toolWidth
        let stripW = max(0, bounds.width - toolWidth)
        controlBar.frame = NSRect(x: stripX, y: bodyY + bodyH - WorkspaceMetrics.controlHeight, width: stripW, height: WorkspaceMetrics.controlHeight)
        let shadowH = WorkspaceMetrics.chromeInset - WorkspaceMetrics.controlHeight
        shadowBand.frame = NSRect(x: stripX, y: bodyY + bodyH - WorkspaceMetrics.chromeInset, width: stripW, height: shadowH)
        let columnH = max(0, bodyH - WorkspaceMetrics.chromeInset)
        let lift = WorkspaceMetrics.dockLift
        dock.frame = NSRect(x: bounds.width - dockWidth, y: bodyY, width: dockWidth, height: columnH + lift)
        canvas.frame = NSRect(x: toolWidth, y: bodyY, width: max(0, bounds.width - toolWidth - dockWidth), height: columnH)
        floaters.frame = canvas.frame
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
