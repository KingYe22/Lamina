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
        for view in [tabs, toolbar, canvas, status, dock, floaters, contextBar] as [NSView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let titleBand: CGFloat = 28
        let tabHeight: CGFloat = 28
        let statusHeight: CGFloat = 26
        let toolWidth: CGFloat = 52
        let dockWidth: CGFloat = 280
        let top = bounds.height - titleBand
        tabs.frame = NSRect(x: 0, y: top - tabHeight, width: bounds.width, height: tabHeight)
        status.frame = NSRect(x: 0, y: 0, width: bounds.width, height: statusHeight)
        let bodyY = statusHeight
        let bodyH = max(0, top - tabHeight - statusHeight)
        toolbar.frame = NSRect(x: 0, y: bodyY, width: toolWidth, height: bodyH)
        dock.frame = NSRect(x: bounds.width - dockWidth, y: bodyY, width: dockWidth, height: bodyH)
        canvas.frame = NSRect(x: toolWidth, y: bodyY, width: max(0, bounds.width - toolWidth - dockWidth), height: bodyH)
        let floaterWidth: CGFloat = 220
        floaters.frame = NSRect(
            x: canvas.frame.maxX - floaterWidth - 8,
            y: canvas.frame.minY + 8,
            width: floaterWidth,
            height: max(0, canvas.frame.height - 16)
        )
        contextBar.frame = NSRect(x: canvas.frame.midX - 150, y: canvas.frame.maxY - 42, width: 300, height: 30)
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
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let size = title.size(withAttributes: [.font: font])
        title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 20), withAttributes: [
            .font: font, .foregroundColor: Theme.text
        ])
    }
}
