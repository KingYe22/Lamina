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
    private var extraColumns: [DockedColumn] = []
    private var columnFrames: [String: NSRect] = [:]
    private var columnBackgrounds: [NSRect] = []
    private var columnSerial = 0
    private var toolbarPath: PanelDragPath?
    private var indicator: DockIndicatorPanel?
    /// Ghost opacity while a docking indicator is showing. The capture did not measure it.
    private let dockGhostAlpha: CGFloat = 0.45
    /// Light-blue wash over the part of the right hot zone the solid bar does not cover.
    /// The capture did not measure the alpha.
    private let dockTintAlpha: CGFloat = 0.20

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

    private var layingOut = false

    override func layout() {
        super.layout()
        guard !layingOut else { return }
        layingOut = true
        defer { layingOut = false }
        let solved = DockLayout.solve(dockInput())
        let keptIDs = Set(solved.columns.map(\.id))
        extraColumns.removeAll { !keptIDs.contains($0.id) }

        let titleBand = WorkspaceMetrics.titleBand
        let tabHeight = WorkspaceMetrics.documentTabHeight
        let toolWidth = WorkspaceMetrics.toolWidth
        let dockWidth = WorkspaceMetrics.dockWidth
        let leading = CGFloat(solved.canvas.x)
        let trailingTool: CGFloat = 0
        let top = bounds.height - titleBand
        let span = CGFloat(max(0, solved.canvas.width))
        tabs.frame = NSRect(x: leading, y: top - tabHeight, width: max(0, bounds.width - leading - trailingTool), height: tabHeight)
        status.frame = NSRect(x: leading, y: CGFloat(solved.status.y), width: span, height: CGFloat(solved.status.height))
        let bodyY = CGFloat(solved.status.height)
        let bodyH = max(0, top - tabHeight - bodyY)
        let dockX = CGFloat(solved.properties.x)
        let windowEdge = extraColumns.reduce(CGFloat(0)) { $1.place == .windowEdge ? $0 + $1.width : $0 }
        if toolbarDock != .none {
            if toolbar.superview !== self {
                toolbar.removeFromSuperview()
                toolbar.autoresizingMask = []
                addSubview(toolbar, positioned: .below, relativeTo: status)
            }
            // Right redock parks the toolbar on the properties column's left edge,
            // where the right-column bar is drawn, and leaves the properties column put.
            let toolX: CGFloat = toolbarDock == .right ? dockX - toolWidth : windowEdge
            toolbar.frame = NSRect(x: toolX, y: bodyY, width: toolWidth, height: max(0, top - bodyY))
        }
        let stripX = leading
        let stripW = max(0, bounds.width - leading - trailingTool)
        controlBar.frame = NSRect(x: stripX, y: bodyY + bodyH - WorkspaceMetrics.controlHeight, width: stripW, height: WorkspaceMetrics.controlHeight)
        let shadowH = WorkspaceMetrics.chromeInset - WorkspaceMetrics.controlHeight
        shadowBand.frame = NSRect(x: stripX, y: bodyY + bodyH - WorkspaceMetrics.chromeInset, width: stripW, height: shadowH)
        let columnH = CGFloat(solved.columnBodyHeight)
        // The properties strip always occupies the right edge. 属性 fills it, or the
        // remainder under panels that are actually seated there — never the panel
        // currently following the pointer.
        dock.frame = nsRect(solved.propertiesContent)
        canvas.frame = NSRect(x: leading, y: bodyY, width: span, height: columnH)
        // Host reaches the window's right client edge. Shoulder is the properties
        // column in floater coordinates, published before the frame change.
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
        applyDockedFrames(solved, dockX: dockX, toolWidth: toolWidth, bodyY: bodyY)
        holdFloatingScreens()
        dock.needsDisplay = true
    }

    private var lastWindowFrame: NSRect?
    private var lastHostFrame: NSRect?
    /// False until the window is on screen at a frame the display can hold.
    /// `center()` and the screen clamp run before that and must not walk panels.
    private var floatingHoldSettled = false

    /// A user resize keeps each floating panel on the same screen point, then pulls
    /// it back inside the host so a shorter window cannot slide 外观 under the title bar.
    private func holdFloatingScreens() {
        guard let window else { return }
        let newWindow = window.frame
        let newHost = floaters.frame
        let changed = lastWindowFrame.map { windowFrameChanged($0, newWindow) } ?? false
        let decision = FloatingScreen.holdDecision(
            alreadySettled: floatingHoldSettled,
            windowVisible: window.isVisible,
            frameFitsScreen: windowFitsScreen(newWindow),
            windowFrameChanged: changed
        )
        floatingHoldSettled = decision.settled
        if decision.move, let oldWindow = lastWindowFrame, let oldHost = lastHostFrame,
           oldWindow.width > 1, oldWindow.height > 1 {
            for panel in floaters.dockPanels()
            where panel.dockColumnID == nil && !panel.dragging && !panel.embeddedInDock && panel.superview === floaters {
                let oldInWindow = DockBox(
                    x: Double(oldHost.minX + panel.frame.minX),
                    y: Double(oldHost.minY + panel.frame.minY),
                    width: Double(panel.frame.width),
                    height: Double(panel.frame.height)
                )
                let host = DockBox(
                    x: Double(newHost.minX),
                    y: Double(newHost.minY),
                    width: Double(newHost.width),
                    height: Double(newHost.height)
                )
                let placed = FloatingScreen.reposition(
                    panelInWindow: oldInWindow,
                    oldWindowOrigin: (Double(oldWindow.minX), Double(oldWindow.minY)),
                    newWindowOrigin: (Double(newWindow.minX), Double(newWindow.minY)),
                    hostInWindow: host
                )
                panel.frame = NSRect(
                    x: CGFloat(placed.x - host.x),
                    y: CGFloat(placed.y - host.y),
                    width: CGFloat(placed.width),
                    height: CGFloat(placed.height)
                )
            }
        }
        lastWindowFrame = newWindow
        lastHostFrame = newHost
    }

    /// Half a point ignores floating-point noise in `window.frame`. It is not a dock measurement.
    private func windowFrameChanged(_ old: NSRect, _ new: NSRect) -> Bool {
        abs(old.origin.x - new.origin.x) > 0.5
            || abs(old.origin.y - new.origin.y) > 0.5
            || abs(old.size.width - new.size.width) > 0.5
            || abs(old.size.height - new.size.height) > 0.5
    }

    /// True when the frame sits in the visible screen, including a window flush with the menu bar.
    private func windowFitsScreen(_ frame: NSRect) -> Bool {
        guard let screen = window?.screen ?? NSScreen.main else { return false }
        let visible = screen.visibleFrame.insetBy(dx: -1, dy: -1)
        return visible.contains(frame)
    }

    var toolbarIsDocked: Bool { toolbarDock == .left || toolbarDock == .right }

    func toolbarGripDown() {}

    func toolbarGripDragged(undocked: Bool, event: NSEvent, start: NSEvent) {
        if toolbarDock != .none {
            guard undocked else { return }
            beginFloating()
            // The column is already gone. Follow from this pointer so the
            // toolbar does not jump by the undock distance.
            toolbarPath = makeToolbarPath(windowPoint: event.locationInWindow)
        } else if toolbarPath == nil {
            toolbarPath = makeToolbarPath(windowPoint: start.locationInWindow)
        }
        guard var path = toolbarPath, toolbarDock == .none, let panel = toolbarPanel, let window else { return }
        let up = event.type == .leftMouseUp
        let placement = path.step(
            pointer: scenePoint(event.locationInWindow),
            scene: makeScene(drag: path),
            up: up
        )
        toolbarPath = path
        let shell = shellRect(from: placement.frame)
        panel.setFrame(window.convertToScreen(convert(shell, to: nil)), display: true)
        panel.alphaValue = placement.ghost ? dockGhostAlpha : 1
        if up {
            hideChrome()
            panel.alphaValue = 1
            toolbarPath = nil
            if case .redockToolbar(let side) = placement.target {
                dockToolbar(side)
            }
        } else {
            showChrome(placement.chrome)
        }
    }

    func focusCanvasFromToolbar() -> Bool {
        guard let window else { return false }
        window.makeFirstResponder(canvas.drawing)
        return true
    }

    private func beginFloating() {
        guard toolbarDock != .none, let window else { return }
        let screen = window.convertToScreen(convert(toolbar.frame, to: nil))
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
        if side == .left {
            // The toolbar lands on the window-edge bar. A panel column already
            // sitting on that edge moves to the toolbar's right.
            for index in extraColumns.indices where extraColumns[index].place == .windowEdge {
                extraColumns[index].place = .after
            }
        }
        toolbarDock = side
        toolbar.removeFromSuperview()
        toolbar.autoresizingMask = []
        addSubview(toolbar, positioned: .below, relativeTo: status)
        toolbarPanel?.orderOut(nil)
        toolbarPanel?.alphaValue = 1
        edgeGuide.isHidden = true
        hideChrome()
        needsLayout = true
        layoutSubtreeIfNeeded()
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
        Theme.panel.setFill()
        for rect in columnBackgrounds {
            rect.intersection(dirtyRect).fill()
        }
        let title = "Lamina" as NSString
        let font = Theme.ui(13, weight: .semibold)
        let size = title.size(withAttributes: [.font: font])
        title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 20), withAttributes: [
            .font: font, .foregroundColor: Theme.text
        ])
    }

    func releaseColumnIfEmpty() {
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func resizeColumn(_ id: String, to width: CGFloat) {
        let sharing = floaters.dockPanels().filter { $0.dockColumnID == id && !$0.isHidden }
        guard sharing.count <= 1, let index = extraColumns.firstIndex(where: { $0.id == id }) else { return }
        extraColumns[index].width = width
        needsLayout = true
    }

    func lift(_ panel: FloatPanel) {
        let frame = panel.superview === self ? panel.frame : (panel.superview?.convert(panel.frame, to: self) ?? panel.frame)
        if panel.superview !== self {
            panel.removeFromSuperview()
        }
        // The panel under the pointer paints above docked panels and above the floater host.
        place(panel, floating: DockLayer.layer(columnID: panel.dockColumnID, dragging: true) == .floating)
        panel.frame = frame
    }

    func makeDragPath(for panel: FloatPanel, windowPoint: NSPoint) -> PanelDragPath {
        panel.dragSlotHeight = panel.frame.height
        let size = panel.preferredSize.width > 1 ? panel.preferredSize : panel.frame.size
        return PanelDragPath(
            wasDocked: panel.dockColumnID != nil,
            origin: sceneFrame(of: panel.frame),
            startPointer: scenePoint(windowPoint),
            floatingWidth: Double(size.width),
            floatingHeight: Double(size.height),
            originGroupID: panel.dockColumnID == nil ? nil : panel.dockGroupID
        )
    }

    func dragStep(_ panel: FloatPanel, path: inout PanelDragPath, windowPoint: NSPoint, up: Bool) {
        let placement = path.step(pointer: scenePoint(windowPoint), scene: makeScene(drag: path), up: up)
        panel.frame = shellRect(from: placement.frame)
        if up {
            panel.alphaValue = 1
            hideChrome()
            commit(panel, placement)
        } else {
            panel.alphaValue = placement.ghost ? dockGhostAlpha : 1
            showChrome(placement.chrome)
            panel.needsDisplay = true
        }
    }

    private func commit(_ panel: FloatPanel, _ placement: DockPlacement) {
        panel.dragging = false
        var floated: NSRect?
        switch placement.target {
        case .stay, .restore:
            let height = DockLayout.heightOnRelease(
                target: placement.target,
                slotHeight: Double(panel.dragSlotHeight),
                carriedHeight: Double(panel.frame.height)
            )
            if height > 0 {
                panel.frame.size.height = CGFloat(height)
            }
        case .float:
            floated = panel.frame
            panel.preferredSize = panel.frame.size
            panel.expandedHeight = max(panel.expandedHeight, panel.frame.height)
            panel.dockColumnID = nil
        case .newColumn(_, let place, let width, let height):
            columnSerial += 1
            let id = "col-\(columnSerial)"
            extraColumns.append(DockedColumn(id: id, width: CGFloat(width), place: place))
            panel.dockColumnID = id
            panel.dockOrder = 0
            panel.preferredSize = NSSize(width: CGFloat(width), height: CGFloat(height))
            panel.expandedHeight = CGFloat(height)
        case .stack(let group, let above):
            let column = columnID(forGroup: group) ?? "properties"
            let peers = floaters.dockPanels().filter { $0 !== panel && $0.dockColumnID == column && !$0.isHidden }
            let edge = above ? (peers.map(\.dockOrder).min() ?? 0) - 1 : (peers.map(\.dockOrder).max() ?? 0) + 1
            panel.dockColumnID = column
            panel.dockOrder = edge
        case .join(let group):
            panel.dockColumnID = nil
            if group == "properties" {
                dock.adopt(panel)
            } else if let target = floaters.dockPanels().first(where: { $0.dockGroupID == group && $0 !== panel }) {
                floaters.merge(panel, into: target)
            } else {
                floated = panel.frame
                panel.preferredSize = panel.frame.size
            }
        case .redockToolbar:
            break
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let floated {
            floaters.receiveFloating(panel, frameInShell: floated)
        }
    }

    private func columnID(forGroup group: String) -> String? {
        if group == "properties" { return "properties" }
        return floaters.dockPanels().first { $0.dockGroupID == group }?.dockColumnID
    }

    private func makeToolbarPath(windowPoint: NSPoint) -> PanelDragPath {
        let frame = toolbarSceneFrame()
        return PanelDragPath(
            wasDocked: false,
            draggingToolbar: true,
            origin: frame,
            startPointer: scenePoint(windowPoint),
            floatingWidth: frame.width,
            floatingHeight: frame.height,
            toolbarWidth: Double(WorkspaceMetrics.toolWidth)
        )
    }

    private func toolbarSceneFrame() -> DockFrame {
        guard let panel = toolbarPanel, let window else {
            return DockFrame(x: 0, y: 0, width: Double(WorkspaceMetrics.toolWidth), height: 400)
        }
        let local = convert(window.convertFromScreen(panel.frame), from: nil)
        return sceneFrame(of: local)
    }

    private func dockInput() -> DockLayoutInput {
        let panels = floaters.dockPanels()
        let members = panels.map { panel in
            DockMember(
                id: panel.dockGroupID,
                columnID: panel.dockColumnID,
                order: panel.dockOrder,
                height: memberHeight(panel),
                dragging: panel.dragging,
                hidden: panel.isHidden,
                embedded: panel.embeddedInDock
            )
        }
        let columns = extraColumns.map {
            DockColumnSpec(id: $0.id, place: $0.place, width: Double($0.width))
        }
        return DockLayoutInput(
            windowWidth: Double(bounds.width),
            windowHeight: Double(bounds.height),
            titleBand: Double(WorkspaceMetrics.titleBand),
            documentTabHeight: Double(WorkspaceMetrics.documentTabHeight),
            statusHeight: 20,
            chromeInset: Double(WorkspaceMetrics.chromeInset),
            dockLift: Double(WorkspaceMetrics.dockLift),
            toolWidth: Double(WorkspaceMetrics.toolWidth),
            dockWidth: Double(WorkspaceMetrics.dockWidth),
            toolbarLeft: toolbarDock == .left,
            toolbarRight: toolbarDock == .right,
            columns: columns,
            members: members
        )
    }

    private func memberHeight(_ panel: FloatPanel) -> Double {
        let shell = shellFrame(of: panel)
        let height = shell.height > 0 ? shell.height : panel.frame.height
        if height > 0 { return Double(height) }
        return Double(panel.dragSlotHeight)
    }

    private func applyDockedFrames(_ solved: DockLayoutResult, dockX: CGFloat, toolWidth: CGFloat, bodyY: CGFloat) {
        var frames: [String: NSRect] = [:]
        var backgrounds: [NSRect] = []
        for column in solved.columns {
            guard let box = solved.columnFrames[column.id] else { continue }
            let rect = nsRect(box)
            frames[column.id] = rect
            backgrounds.append(rect)
        }
        frames["properties"] = nsRect(solved.properties)
        if toolbarDock == .right {
            let height = CGFloat(solved.properties.height)
            frames["toolbar"] = NSRect(x: dockX - toolWidth, y: bodyY, width: toolWidth, height: height)
        }
        let panels = Dictionary(uniqueKeysWithValues: floaters.dockPanels().map { ($0.dockGroupID, $0) })
        for panel in panels.values where panel.dragging && panel.superview === self {
            place(panel, floating: true)
        }
        for (id, box) in solved.memberFrames {
            guard let panel = panels[id], !panel.dragging else { continue }
            let floating = DockLayer.layer(columnID: panel.dockColumnID, dragging: panel.dragging) == .floating
            place(panel, floating: floating)
            panel.frame = nsRect(box)
        }
        columnFrames = frames
        if columnBackgrounds != backgrounds {
            columnBackgrounds = backgrounds
            needsDisplay = true
        }
    }

    /// Docked panels sit under the floater host. A floating or dragged panel sits above the status bar.
    private func place(_ panel: FloatPanel, floating: Bool) {
        if panel.superview !== self {
            panel.removeFromSuperview()
        }
        if floating {
            addSubview(panel, positioned: .above, relativeTo: status)
        } else {
            addSubview(panel, positioned: .below, relativeTo: floaters)
        }
    }

    private func nsRect(_ box: DockBox) -> NSRect {
        NSRect(x: CGFloat(box.x), y: CGFloat(box.y), width: CGFloat(box.width), height: CGFloat(box.height))
    }

    private func makeScene(drag: PanelDragPath) -> DockWorkspace {
        var columns: [DockColumnBox] = []
        var groups: [DockGroupBox] = []
        let propertiesRect = columnFrames["properties"] ?? dock.frame
        columns.append(DockColumnBox(id: "properties", frame: sceneFrame(of: propertiesRect), side: .right))
        for column in extraColumns {
            guard let rect = columnFrames[column.id] else { continue }
            let side: DockAnchor = column.place == .before ? .right : .left
            columns.append(DockColumnBox(id: column.id, frame: sceneFrame(of: rect), side: side))
        }
        if toolbarDock == .right, let rect = columnFrames["toolbar"] {
            columns.append(DockColumnBox(id: "toolbar", frame: sceneFrame(of: rect), side: .right))
        }
        // Docked and floating groups both accept a tab. The panel under the pointer is omitted.
        for panel in floaters.dockPanels() where !panel.isHidden && !panel.embeddedInDock {
            if panel.dragging, drag.originGroupID == panel.dockGroupID {
                groups.append(DockGroupBox(
                    id: panel.dockGroupID,
                    frame: drag.origin,
                    tabHeight: Double(panel.dockTabHeight),
                    columnID: panel.dockColumnID ?? "",
                    vacated: true
                ))
            } else if !panel.dragging {
                groups.append(DockGroupBox(
                    id: panel.dockGroupID,
                    frame: sceneFrame(of: shellFrame(of: panel)),
                    tabHeight: Double(panel.dockTabHeight),
                    columnID: panel.dockColumnID ?? ""
                ))
            }
        }
        groups.append(DockGroupBox(
            id: "properties",
            frame: sceneFrame(of: dock.frame),
            tabHeight: 37,
            columnID: "properties"
        ))
        let toolbarFrame: DockFrame? = toolbarDock == .left ? sceneFrame(of: toolbar.frame) : nil
        return DockWorkspace(
            host: DockFrame(x: 0, y: 0, width: Double(bounds.width), height: Double(bounds.height)),
            toolbar: toolbarFrame,
            columns: columns,
            groups: groups
        )
    }

    private func shellFrame(of panel: FloatPanel) -> NSRect {
        if panel.superview === self || panel.superview == nil { return panel.frame }
        return panel.superview?.convert(panel.frame, to: self) ?? panel.frame
    }

    private func sceneFrame(of rect: NSRect) -> DockFrame {
        DockFrame(
            x: Double(rect.minX),
            y: Double(bounds.height - rect.maxY),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    private func scenePoint(_ windowPoint: NSPoint) -> Vec2 {
        let point = convert(windowPoint, from: nil)
        return Vec2(Double(point.x), Double(bounds.height - point.y))
    }

    private func shellRect(from scene: DockFrame) -> NSRect {
        NSRect(
            x: CGFloat(scene.x),
            y: bounds.height - CGFloat(scene.y + scene.height),
            width: CGFloat(scene.width),
            height: CGFloat(scene.height)
        )
    }

    private func showChrome(_ chrome: DockChrome) {
        guard chrome != .none, let window else {
            hideChrome()
            return
        }
        var pieces: [DockIndicatorCanvas.Piece] = []
        switch chrome {
        case .none:
            break
        case .bar(let bar, let tint):
            if let tint {
                pieces.append(.fill(shellRect(from: tint), dockTintAlpha))
            }
            pieces.append(.fill(shellRect(from: bar), 1))
        case .line(let line):
            pieces.append(.fill(shellRect(from: line), 1))
        case .outline(let frame):
            pieces.append(.stroke(shellRect(from: frame)))
        }
        let panel = indicator ?? DockIndicatorPanel()
        indicator = panel
        panel.present(screen: window.convertToScreen(convert(bounds, to: nil)), pieces: pieces)
    }

    private func hideChrome() {
        indicator?.conceal()
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
