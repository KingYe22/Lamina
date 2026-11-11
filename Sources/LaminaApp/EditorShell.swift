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
    private var outsidePanels: [ObjectIdentifier: NSPanel] = [:]
    private var extraColumns: [DockedColumn] = []
    private var columnFrames: [String: NSRect] = [:]
    private var columnBackgrounds: [NSRect] = []
    private var columnSerial = 0
    private var toolbarPath: PanelDragPath?
    private var indicator: DockIndicatorPanel?
    /// Ghost opacity while a docking indicator is showing. The capture did not measure it.
    private let dockGhostAlpha: CGFloat = 0.45

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
        // The context bar sits on the canvas, under every panel, so a panel tab stays clickable.
        // Floating panels still cover the dock when one snaps to the window's right edge.
        for view in [canvas, contextBar, shadowBand, dock, floaters, toolbar, status, controlBar, tabs] as [NSView] {
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
        if !edgeGuide.isHidden {
            let thickness = CGFloat(DockSnap.guideThickness)
            let guideX: CGFloat = edgeGuide.frame.midX < bounds.midX ? 0 : max(0, bounds.width - thickness)
            edgeGuide.frame = NSRect(x: guideX, y: 0, width: thickness, height: bounds.height)
        }
        applyDockedFrames(solved, dockX: dockX, toolWidth: toolWidth, bodyY: bodyY)
        if window?.inLiveResize == true { userResizedWindow = true }
        holdFloatingScreens()
        promoteOutsideFloaters()
        // Panels take their metric frames before the bar looks for open canvas.
        floaters.layoutSubtreeIfNeeded()
        // A launch-time slide is not a user resize. Panels the user has not
        // dragged stay on the metric grid while that grid still fits the window.
        // A shorter window leaves the held frame alone so a panel is not pushed
        // out over the home screen.
        if !userResizedWindow {
            floaters.restoreUntouchedFrames()
        }
        placeContextBar()
        dock.needsDisplay = true
    }

    func restingFrameReport() -> String {
        let host = floaters.frame
        let expected = [
            WorkspaceMetrics.appearance.rect(in: host.height),
            WorkspaceMetrics.align.rect(in: host.height),
            WorkspaceMetrics.stroke.rect(in: host.height)
        ]
        let lines = zip(floaters.dockPanels(), expected).map { panel, metric -> String in
            let home = panel.superview === floaters ? "host" : (panel.superview === self ? "shell" : "other")
            return "\(panel.tabs.map(\.rawValue).joined(separator: "+")) frame=(\(panel.frame.minX),\(panel.frame.minY)) metric=(\(metric.minX),\(metric.minY)) \(home)"
        }
        return "host=(\(host.minX),\(host.minY),\(host.width),\(host.height)) " + lines.joined(separator: " || ") + " hold=[\(holdTrace)] promote=[\(promoteTrace)]"
    }

    private var lastWindowFrame: NSRect?
    private var lastHostFrame: NSRect?
    /// False until the user drags a window edge. `setContentSize` and `center()`
    /// are not that, and must not slide the panels off the metric grid.
    private var userResizedWindow = false
    /// Last screen-hold pass that actually moved a panel, for the screenshot report.
    private var holdTrace = ""
    private var promoteTrace = ""

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        userResizedWindow = true
    }
    /// False until the window is on screen at a frame the display can hold.
    /// `center()` and the screen clamp run before that and must not walk panels.
    private var floatingHoldSettled = false

    /// A user resize keeps each floating panel on the same screen point.
    /// The host is bottom-left pinned, so a shorter window would otherwise lift a
    /// panel that sits on that edge by the whole height delta. Nudge only when
    /// the panel would miss the window entirely.
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
        var notes: [String] = []
        if decision.move, let oldWindow = lastWindowFrame, let oldHost = lastHostFrame,
           oldWindow.width > 1, oldWindow.height > 1, bounds.width > 1, bounds.height > 1 {
            let windowBox = DockBox(x: 0, y: 0, width: Double(bounds.width), height: Double(bounds.height))
            notes.append(String(format: "winΔ=(%.1f,%.1f) host %.1f→%.1f",
                                oldWindow.minX - newWindow.minX, oldWindow.minY - newWindow.minY,
                                oldHost.minX, newHost.minX))
            for panel in floaters.dockPanels()
            where panel.dockColumnID == nil && !panel.dragging && !panel.embeddedInDock
                && (panel.superview === floaters || panel.superview === self) {
                let inHost = panel.superview === floaters
                let oldInWindow = DockBox(
                    x: Double(inHost ? oldHost.minX + panel.frame.minX : panel.frame.minX),
                    y: Double(inHost ? oldHost.minY + panel.frame.minY : panel.frame.minY),
                    width: Double(panel.frame.width),
                    height: Double(panel.frame.height)
                )
                // A panel that remains inside the window keeps its screen point.
                // One that would leave becomes its own window. Nothing pulls it
                // back toward the metric origin.
                let raw = NSRect(
                    x: CGFloat(oldWindow.minX + oldInWindow.x - newWindow.minX),
                    y: CGFloat(oldWindow.minY + oldInWindow.y - newWindow.minY),
                    width: CGFloat(oldInWindow.width),
                    height: CGFloat(oldInWindow.height)
                )
                let name = panel.tabs.map(\.rawValue).joined(separator: "+")
                if bounds.insetBy(dx: -1, dy: -1).contains(raw) {
                    let placed = FloatingScreen.reposition(
                        panelInWindow: oldInWindow,
                        oldWindowOrigin: (Double(oldWindow.minX), Double(oldWindow.minY)),
                        newWindowOrigin: (Double(newWindow.minX), Double(newWindow.minY)),
                        windowBounds: windowBox
                    )
                    let originX = inHost ? placed.x - Double(newHost.minX) : placed.x
                    let originY = inHost ? placed.y - Double(newHost.minY) : placed.y
                    let before = panel.frame.minX
                    panel.frame = NSRect(
                        x: CGFloat(originX),
                        y: CGFloat(originY),
                        width: CGFloat(placed.width),
                        height: CGFloat(placed.height)
                    )
                    notes.append(String(format: "%@ %.1f→%.1f %@", name, before, panel.frame.minX, inHost ? "host" : "shell"))
                } else {
                    panel.departedShell = NSRect(
                        x: CGFloat(oldInWindow.x),
                        y: CGFloat(oldInWindow.y),
                        width: CGFloat(oldInWindow.width),
                        height: CGFloat(oldInWindow.height)
                    )
                    panel.departedWindowOrigin = oldWindow.origin
                    let screen = NSRect(
                        x: oldWindow.minX + CGFloat(oldInWindow.x),
                        y: oldWindow.minY + CGFloat(oldInWindow.y),
                        width: CGFloat(oldInWindow.width),
                        height: CGFloat(oldInWindow.height)
                    )
                    hostOutside(panel, screen: screen)
                    notes.append("\(name) outside")
                }
            }
        } else {
            notes.append("move=false")
        }
        if decision.move {
            holdTrace = notes.joined(separator: " | ")
        } else if holdTrace.isEmpty {
            holdTrace = "move=false"
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
        let frame: NSRect
        if let hostWindow = panel.window, hostWindow !== window, let shellWindow = window {
            let screen = hostWindow.convertToScreen(panel.convert(panel.bounds, to: nil))
            frame = convert(shellWindow.convertFromScreen(screen), from: nil)
            let key = ObjectIdentifier(panel)
            outsidePanels[key]?.orderOut(nil)
            outsidePanels.removeValue(forKey: key)
        } else {
            frame = panel.superview === self ? panel.frame : (panel.superview?.convert(panel.frame, to: self) ?? panel.frame)
        }
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
            originGroupID: panel.dragOriginGroupID ?? (panel.dockColumnID == nil ? nil : panel.dockGroupID)
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

    /// Top-left of the canvas, beside the toolbar. If a panel already occupies that
    /// corner, the bar steps down or right until it sits on open canvas.
    private func placeContextBar() {
        let selected = !workspace.active.model.selection.isEmpty
        let height: CGFloat = 28
        let canvasRect = canvas.frame
        guard canvasRect.width > 80, canvasRect.height > height + 16 else {
            contextBar.isHidden = true
            return
        }
        contextBar.isHidden = false
        let gap: CGFloat = 8
        var x = canvasRect.minX + gap
        var y = canvasRect.maxY - gap - height
        var width = min(contextBar.contentWidth(selected: selected), canvasRect.maxX - gap - x)
        var obstacles: [NSRect] = [dock.frame, toolbar.frame, tabs.frame, controlBar.frame, status.frame, shadowBand.frame]
        for panel in floaters.dockPanels() where !panel.isHidden {
            let frame = shellFrame(of: panel)
            if frame.width > 2, frame.height > 2 { obstacles.append(frame) }
        }
        if let local = floaters.generativeFrame() {
            obstacles.append(floaters.convert(local, to: self))
        }
        for _ in 0..<16 {
            let rect = NSRect(x: x, y: y, width: width, height: height)
            guard let hit = obstacles.first(where: { overlaps(rect, $0, gap: gap) }) else {
                contextBar.frame = rect
                return
            }
            var moved = false
            let below = hit.minY - gap - height
            if below <= y - 1, below >= canvasRect.minY + gap {
                y = below
                moved = true
            } else {
                let right = hit.maxX + gap
                if right >= x + 1, right + 80 <= canvasRect.maxX {
                    x = right
                    y = canvasRect.maxY - gap - height
                    width = min(contextBar.contentWidth(selected: selected), canvasRect.maxX - gap - x)
                    moved = true
                }
            }
            if !moved { break }
        }
        contextBar.frame = NSRect(x: canvasRect.minX + gap, y: canvasRect.minY + gap, width: width, height: height)
    }

    private func overlaps(_ rect: NSRect, _ obstacle: NSRect, gap: CGFloat) -> Bool {
        let hit = rect.intersection(obstacle.insetBy(dx: -gap, dy: -gap))
        return !hit.isNull && hit.width > 0.5 && hit.height > 0.5
    }

    private func hostOutside(_ panel: FloatPanel, screen: NSRect) {
        let key = ObjectIdentifier(panel)
        let host = outsidePanels[key] ?? NSPanel(
            contentRect: screen,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        host.isFloatingPanel = true
        host.level = .floating
        host.hasShadow = true
        host.backgroundColor = Theme.panel
        host.hidesOnDeactivate = false
        if panel.superview !== host.contentView {
            panel.removeFromSuperview()
            if host.contentView == nil { host.contentView = NSView() }
            host.contentView?.addSubview(panel)
        }
        host.setFrame(screen, display: true)
        panel.frame = NSRect(origin: .zero, size: screen.size)
        // The panel window's content view is not always at the window origin.
        // Put the panel's bounds on `screen`, or the trip back into the shell
        // shifts it by that inset.
        let got = host.convertToScreen(panel.convert(panel.bounds, to: nil))
        let dx = screen.origin.x - got.origin.x
        let dy = screen.origin.y - got.origin.y
        if abs(dx) > 0.5 || abs(dy) > 0.5 {
            panel.setFrameOrigin(NSPoint(x: dx, y: dy))
        }
        outsidePanels[key] = host
        if !host.isVisible { host.orderFront(nil) }
    }

    /// A floating panel that misses the window becomes its own window. A panel that
    /// only touches the edge stays in the shell: the snap test parks appearance
    /// flush with that edge, and pulling it out shifts it by the toolbar width.
    private func promoteOutsideFloaters() {
        guard let window else { return }
        var seen = Set<ObjectIdentifier>()
        var notes: [String] = []
        let candidates = subviews.compactMap { $0 as? FloatPanel } + floaters.dockPanels()
        for panel in candidates where panel.dockColumnID == nil && !panel.dragging && !panel.embeddedInDock && !panel.isHidden {
            let key = ObjectIdentifier(panel)
            if seen.contains(key) { continue }
            seen.insert(key)
            let panelFrame: NSRect
            if panel.window === window {
                panelFrame = shellFrame(of: panel)
            } else if let hostWindow = panel.window {
                let screen = hostWindow.convertToScreen(panel.convert(panel.bounds, to: nil))
                panelFrame = convert(window.convertFromScreen(screen), from: nil)
            } else {
                continue
            }
            // Flush with the edge is still inside. Only a panel that actually hangs
            // out by more than 2 pt leaves the shell.
            let hangsOut = panelFrame.minX < -2 || panelFrame.maxX > bounds.width + 2
                || panelFrame.minY < -2 || panelFrame.maxY > bounds.height + 2
            let name = panel.tabs.map(\.rawValue).joined(separator: "+")
            notes.append(String(format: "%@ shell=(%.1f,%.1f) %@", name, panelFrame.minX, panelFrame.maxY, hangsOut ? "out" : "in"))
            if !hangsOut {
                if panel.window !== window {
                    panel.removeFromSuperview()
                    let restored = returningFrame(panel, converted: panelFrame, window: window)
                    floaters.receiveFloating(panel, frameInShell: restored)
                    panel.departedShell = nil
                }
                if let host = outsidePanels.removeValue(forKey: key) { host.orderOut(nil) }
                continue
            }
            if panel.window === window {
                panel.departedShell = panelFrame
                panel.departedWindowOrigin = window.frame.origin
            }
            let screen = window.convertToScreen(convert(panelFrame, to: nil))
            hostOutside(panel, screen: screen)
        }
        for key in outsidePanels.keys where !seen.contains(key) {
            outsidePanels[key]?.orderOut(nil)
            outsidePanels.removeValue(forKey: key)
        }
        promoteTrace = notes.joined(separator: " | ")
    }

    /// A panel that has not been dragged comes back to the shell frame it left,
    /// shifted only by a real window-origin change. The screen conversion is kept
    /// for a panel the user has moved, because that frame is no longer the one
    /// it left with.
    private func returningFrame(_ panel: FloatPanel, converted: NSRect, window: NSWindow) -> NSRect {
        guard !panel.adjustedByUser, let saved = panel.departedShell else { return converted }
        let dx = window.frame.origin.x - panel.departedWindowOrigin.x
        let dy = window.frame.origin.y - panel.departedWindowOrigin.y
        return saved.offsetBy(dx: -dx, dy: -dy)
    }

    /// Docked panels sit under the floater host. A floating or dragged panel sits above the status bar.
    private func place(_ panel: FloatPanel, floating: Bool) {
        if panel.window !== window, panel.window != nil, panel.dockColumnID == nil, !panel.dragging {
            return
        }
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
        // Right column, toolbar-right, and window-edge bars are this one list.
        // A bar with no tint still starts with the covered primer so its solid
        // fill is the same later device-RGB fill as the right bar.
        for step in DockBarDrawing.steps(for: chrome) {
            pieces.append(.fill(shellRect(from: step.rect), CGFloat(step.alpha)))
        }
        if case .outline(let frame) = chrome {
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
