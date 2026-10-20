import AppKit
import LaminaCore
import SwiftUI

final class DocumentTabBar: NSView {
    weak var workspace: Workspace?
    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        guard let workspace else { return }
        var x: CGFloat = 8
        for (index, session) in workspace.sessions.enumerated() {
            let title = session.title as NSString
            let width = min(180, title.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width + 28)
            let rect = NSRect(x: x, y: 4, width: width, height: bounds.height - 8)
            let active = index == workspace.activeIndex
            (active ? Theme.raised : Theme.panel).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            title.draw(at: NSPoint(x: rect.minX + 10, y: rect.midY - 7), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: active ? .semibold : .regular),
                .foregroundColor: Theme.text
            ])
            x += width + 6
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let workspace else { return }
        let point = convert(event.locationInWindow, from: nil)
        var x: CGFloat = 8
        for (index, session) in workspace.sessions.enumerated() {
            let title = session.title as NSString
            let width = min(180, title.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width + 28)
            let rect = NSRect(x: x, y: 4, width: width, height: bounds.height - 8)
            if rect.contains(point) {
                workspace.select(index: index)
                return
            }
            x += width + 6
        }
    }
}

final class StatusBar: NSView {
    weak var workspace: Workspace?
    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        Theme.line.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)).fill()
        guard let model = workspace?.active.model else { return }
        let board = model.document.artboards.indices.contains(model.document.activeArtboard)
            ? model.document.artboards[model.document.activeArtboard].name
            : "画板"
        let zoom = "\(Int((model.zoom * 100).rounded()))%"
        let left = "\(model.tool.title)    \(model.status)" as NSString
        let right = "‹    \(board)    ›      −    \(zoom)    +" as NSString
        left.draw(at: NSPoint(x: 10, y: 6), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.dim])
        let size = right.size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)])
        right.draw(at: NSPoint(x: bounds.width - size.width - 12, y: 6), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.text])
    }

    override func mouseDown(with event: NSEvent) {
        guard let workspace else { return }
        let point = convert(event.locationInWindow, from: nil)
        let width = bounds.width
        if point.x > width - 36 {
            workspace.perform("放大")
        } else if point.x > width - 92 {
            workspace.perform("画板适合窗口大小")
        } else if point.x > width - 128 {
            workspace.perform("缩小")
        } else if point.x > width - 220 {
            workspace.stepArtboard(1)
        } else if point.x > width - 280 {
            workspace.stepArtboard(-1)
        }
    }
}

final class EditorShell: NSView {
    let workspace: Workspace
    let tabs = DocumentTabBar()
    let palette = ToolPalette()
    let canvas = CanvasHost()
    let status = StatusBar()
    let dock: NSHostingView<DockRoot>

    init(workspace: Workspace) {
        self.workspace = workspace
        dock = NSHostingView(rootView: DockRoot(workspace: workspace))
        super.init(frame: .zero)
        palette.workspace = workspace
        canvas.workspace = workspace
        tabs.workspace = workspace
        status.workspace = workspace
        for view in [tabs, palette, canvas, status, dock] as [NSView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let tabHeight: CGFloat = 32
        let statusHeight: CGFloat = 26
        let paletteWidth: CGFloat = 52
        let dockWidth: CGFloat = workspace.active.model.openPanels.isEmpty ? 0 : 300
        tabs.frame = NSRect(x: 0, y: bounds.height - tabHeight, width: bounds.width, height: tabHeight)
        status.frame = NSRect(x: 0, y: 0, width: bounds.width, height: statusHeight)
        palette.frame = NSRect(x: 0, y: statusHeight, width: paletteWidth, height: bounds.height - tabHeight - statusHeight)
        dock.frame = NSRect(x: bounds.width - dockWidth, y: statusHeight, width: dockWidth, height: bounds.height - tabHeight - statusHeight)
        canvas.frame = NSRect(
            x: paletteWidth,
            y: statusHeight,
            width: max(0, bounds.width - paletteWidth - dockWidth),
            height: bounds.height - tabHeight - statusHeight
        )
    }

    func sync() {
        palette.sync()
        canvas.sync()
        tabs.needsDisplay = true
        status.needsDisplay = true
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}
