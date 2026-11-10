import Foundation

/// Magnetic docking measured on Adobe Illustrator 2026 (30.5.1), 2026-11-09.
///
/// Coordinates are y-down, the same orientation as the capture (global CG).
/// The pointer decides the target. The dragged frame keeps following the pointer
/// until mouse-up; the blue chrome is only a preview.
///
/// Distances that the capture did not bracket are named below and are not filled
/// in with a guessed midpoint. See the notes on each constant.
public enum IllustratorDock {
    /// Solid indicator blue sampled from the held drag. Not the old #0072EF rail.
    public static let barHex = 0x2C62CB
    /// Bar thickness. The right-column bar measured −389.25…−383 (about 6.25 pt).
    public static let barThickness = 6.0
    /// Horizontal group line. The capture's lines were about 5.5 pt (105.5…111, 833.5…839).
    public static let lineThickness = 6.0

    /// Right-column hot zone, measured against column minX = −381.
    /// Tint starts at −412.5 (31.5 pt left). Pointer −413 is outside, −410 is inside.
    /// Pointer −384 is inside and −383 is outside, so the inner edge is 2 pt left of
    /// the column and is exclusive. The zone is entirely outside the column.
    public static let rightOuter = 31.5
    public static let rightInner = 2.0

    /// Left of a docked toolbar. Pointer +5 and +15 pt past the toolbar's right edge
    /// show the bar; +40 does not. The open interval (15, 40) was not sampled, so the
    /// zone stops at the last YES sample.
    public static let toolbarRightReach = 15.0

    /// Window-left strip while a toolbar column is present.
    /// +3 and +9 pt inside the window show the edge bar; +16 (over the toolbar body) does not.
    /// (9, 16) was not sampled.
    public static let windowEdgeWithToolbar = 9.0

    /// Window-left strip after the toolbar has been undocked.
    /// Pointers +2…+19 show the bar; +31 does not. (19, 31) was not sampled.
    public static let windowEdgeBare = 19.0

    /// Top insert zone. y = group top − 6 is the line; top − 9 is nothing.
    /// top − 7 and top − 8 were not sampled (the sweep stepped by 3 pt).
    public static let topOuter = 6.0
    /// How far the top line still wins when approaching from above (y = top + 6).
    public static let topInto = 6.0
    /// Hysteresis band relative to the group top. From above, y = top + 3 is the line.
    /// From below, the same y is the tab outline. top + 7 and top + 8 were not sampled.
    public static let hysteresisLow = 3.0
    public static let hysteresisHigh = 8.0
    /// Tab outline continues this far past the tab bar into the content.
    public static let tabInto = 2.0
    /// Bottom stack zone. y = bottom − 37 is nothing; y = bottom − 34 is the line.
    /// The 34 pt figure is the measured band, not the tab-bar height.
    public static let bottomBand = 34.0

    /// Undock. 7.3 pt does not move the group. 15.5 pt follows.
    /// The true threshold lies somewhere in (7.3, 15.5] and was not bracketed.
    /// Movement starts just after the last stationary sample so both samples hold.
    public static let undockStationary = 7.3
    /// Column undock stays opaque at the 15.5 pt follow sample and turns into a
    /// ghost at the 31 pt sample (outline over the vacated slot). The open
    /// interval (15.5, 31) was not sampled, so the ghost starts at 31.
    /// An already-floating drag is a different sample: it ghosts as soon as an
    /// indicator is showing.
    public static let undockGhost = 31.0

    public static func rightHot(edge: Double, pointerX: Double) -> Bool {
        pointerX >= edge - rightOuter - 1e-9 && pointerX < edge - rightInner - 1e-9
    }

    public static func rightChrome(column: DockFrame) -> (bar: DockFrame, tint: DockFrame) {
        // The bar sits flush on the column edge. The capture's pixel span ended
        // about 2 pt short of that edge; the retest measured the same gap. The
        // pointer zone is unchanged: −410 is inside, −383 is outside.
        let barX = column.minX - barThickness
        let bar = DockFrame(x: barX, y: column.minY, width: barThickness, height: column.height)
        let tint = DockFrame(
            x: column.minX - rightOuter,
            y: column.minY,
            width: rightOuter - rightInner - barThickness,
            height: column.height
        )
        return (bar, tint)
    }

    /// Device-RGB components of `barHex`, so a screen capture stores #2C62CB
    /// instead of the sRGB-tagged conversion of the same hex.
    public static func barDeviceComponents() -> (r: Double, g: Double, b: Double) {
        (
            Double((barHex >> 16) & 0xFF) / 255,
            Double((barHex >> 8) & 0xFF) / 255,
            Double(barHex & 0xFF) / 255
        )
    }

    public static func edgeBar(x: Double, span: DockFrame) -> DockFrame {
        DockFrame(x: x, y: span.minY, width: barThickness, height: span.height)
    }
}

/// Device-RGB fill shared by the right column bar, the bar just right of the
/// toolbar, and the window-edge bar. An sRGB colour of the same hex is stored
/// in a screenshot as #3D62C5; these components are stored as #2C62CB.
public struct DockBarPaint: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static func device(alpha: Double) -> DockBarPaint {
        let parts = IllustratorDock.barDeviceComponents()
        return DockBarPaint(red: parts.r, green: parts.g, blue: parts.b, alpha: alpha)
    }
}

public enum DockPlace: Equatable, Sendable {
    /// New column on the lower-x side of `beside`.
    case before
    /// New column on the higher-x side of `beside`.
    case after
    /// New column on the window's left edge.
    case windowEdge
}

public enum DockTarget: Equatable, Sendable {
    case stay
    case float
    case newColumn(beside: String, place: DockPlace, width: Double, height: Double)
    case stack(group: String, above: Bool)
    case join(group: String)
    case restore(group: String)
    case redockToolbar(DockAnchor)
}

public enum DockChrome: Equatable, Sendable {
    case none
    case bar(DockFrame, tint: DockFrame?)
    case line(DockFrame)
    case outline(DockFrame)
}

public struct DockColumnBox: Equatable, Sendable {
    public var id: String
    public var frame: DockFrame
    public var side: DockAnchor

    public init(id: String, frame: DockFrame, side: DockAnchor) {
        self.id = id
        self.frame = frame
        self.side = side
    }
}

public struct DockGroupBox: Equatable, Sendable {
    public var id: String
    public var frame: DockFrame
    public var tabHeight: Double
    public var columnID: String
    /// The group was picked up. The rectangle is the hole it left.
    public var vacated: Bool

    public init(id: String, frame: DockFrame, tabHeight: Double, columnID: String, vacated: Bool = false) {
        self.id = id
        self.frame = frame
        self.tabHeight = tabHeight
        self.columnID = columnID
        self.vacated = vacated
    }
}

/// Columns, groups, and the optional toolbar in one y-down space.
public struct DockWorkspace: Equatable, Sendable {
    public var host: DockFrame
    public var toolbar: DockFrame?
    public var columns: [DockColumnBox]
    public var groups: [DockGroupBox]

    public init(host: DockFrame, toolbar: DockFrame?, columns: [DockColumnBox], groups: [DockGroupBox]) {
        self.host = host
        self.toolbar = toolbar
        self.columns = columns
        self.groups = groups
    }
}

public struct DockPlacement: Equatable, Sendable {
    public var frame: DockFrame
    public var chrome: DockChrome
    public var ghost: Bool
    public var following: Bool
    public var target: DockTarget

    public init(frame: DockFrame, chrome: DockChrome, ghost: Bool, following: Bool, target: DockTarget) {
        self.frame = frame
        self.chrome = chrome
        self.ghost = ghost
        self.following = following
        self.target = target
    }
}

enum DockBand: Equatable {
    case none
    case top
    case tab
}

/// What `FloatPanel.trackDrag` / `IllustratorToolbar.trackGrip` decide.
/// The view converts pointer and frames into this y-down space and applies `target` on mouse-up.
public struct PanelDragPath: Equatable, Sendable {
    public let wasDocked: Bool
    public let draggingToolbar: Bool
    public let origin: DockFrame
    public let startPointer: Vec2
    public let floatingWidth: Double
    public let floatingHeight: Double
    public let originGroupID: String?
    /// Toolbar's docked width, used when the toolbar itself is the dragged item.
    public let toolbarWidth: Double
    private var band: DockBand = .none

    public init(
        wasDocked: Bool,
        draggingToolbar: Bool = false,
        origin: DockFrame,
        startPointer: Vec2,
        floatingWidth: Double,
        floatingHeight: Double,
        originGroupID: String? = nil,
        toolbarWidth: Double = 0
    ) {
        self.wasDocked = wasDocked
        self.draggingToolbar = draggingToolbar
        self.origin = origin
        self.startPointer = startPointer
        self.floatingWidth = floatingWidth
        self.floatingHeight = floatingHeight
        self.originGroupID = originGroupID
        self.toolbarWidth = toolbarWidth
    }

    public mutating func step(pointer: Vec2, scene: DockWorkspace, up: Bool) -> DockPlacement {
        let travel = pointer.distance(to: startPointer)
        // Tab and group drags use the same stationary sample as a column undock:
        // 7.3 pt does not move the panel, and 10.4 pt (the retest's follow sample,
        // already past 7.3) does. The toolbar keeps its own grip threshold.
        let following = draggingToolbar
            ? (!wasDocked || travel > IllustratorDock.undockStationary + 1e-9)
            : (travel > IllustratorDock.undockStationary + 1e-9)
        var frame = origin
        if following {
            frame.x = origin.x + (pointer.x - startPointer.x)
            frame.y = origin.y + (pointer.y - startPointer.y)
            frame.width = floatingWidth
            frame.height = floatingHeight
        }
        guard following else {
            band = .none
            return DockPlacement(frame: origin, chrome: .none, ghost: false, following: false, target: .stay)
        }
        let hit = resolve(pointer: pointer, scene: scene)
        let ghost = wasDocked && !draggingToolbar
            ? (hit.chrome != .none && travel + 1e-9 >= IllustratorDock.undockGhost)
            : (hit.chrome != .none)
        let target = up ? hit.target : .stay
        return DockPlacement(frame: frame, chrome: up ? .none : hit.chrome, ghost: up ? false : ghost, following: true, target: target)
    }

    private struct Hit {
        var chrome: DockChrome
        var target: DockTarget
    }

    private mutating func resolve(pointer: Vec2, scene: DockWorkspace) -> Hit {
        if let slot = scene.groups.first(where: { $0.vacated && $0.id == originGroupID && contains($0.frame, pointer) }) {
            band = .none
            return Hit(chrome: .outline(slot.frame), target: .restore(group: slot.id))
        }
        if let group = group(at: pointer, scene: scene), !group.vacated {
            if let zone = groupZone(pointer: pointer, group: group) {
                return zone
            }
        } else if !pointInAnyGroup(pointer, scene: scene) {
            band = .none
        }
        if let column = rightColumn(scene: scene),
           IllustratorDock.rightHot(edge: column.frame.minX, pointerX: pointer.x),
           pointer.y >= column.frame.minY - 1e-9, pointer.y <= column.frame.maxY + 1e-9 {
            let chrome = IllustratorDock.rightChrome(column: column.frame)
            let width = draggingToolbar ? toolbarWidth : floatingWidth
            let height = draggingToolbar ? column.frame.height : floatingHeight
            let target: DockTarget = draggingToolbar
                ? .redockToolbar(.right)
                : .newColumn(beside: column.id, place: .before, width: width, height: height)
            return Hit(chrome: .bar(chrome.bar, tint: chrome.tint), target: target)
        }
        if let left = leftHit(pointer: pointer, scene: scene) {
            return left
        }
        return Hit(chrome: .none, target: .float)
    }

    private func rightColumn(scene: DockWorkspace) -> DockColumnBox? {
        scene.columns.filter { $0.side == .right }.min { $0.frame.minX < $1.frame.minX }
    }

    private func leftHit(pointer: Vec2, scene: DockWorkspace) -> Hit? {
        guard pointer.y >= scene.host.minY - 1e-9, pointer.y <= scene.host.maxY + 1e-9 else { return nil }
        guard pointer.x >= scene.host.minX - 1e-9 else { return nil }
        // A column already occupies this x. The right-hand zone is the same idea:
        // inside the column the edge bar stays off. Stacking another column on
        // top of one was not measured.
        if scene.columns.contains(where: { contains($0.frame, pointer) }) { return nil }
        if let toolbar = scene.toolbar {
            let past = pointer.x - toolbar.maxX
            // The toolbar-right bar is a new column for a panel. While the toolbar
            // itself is the dragged item its column is already gone, so this zone
            // is not a second toolbar dock.
            if !draggingToolbar,
               past > 1e-9, past <= IllustratorDock.toolbarRightReach + 1e-9,
               pointer.y >= toolbar.minY - 1e-9, pointer.y <= toolbar.maxY + 1e-9 {
                let bar = IllustratorDock.edgeBar(x: toolbar.maxX, span: toolbar)
                let target = DockTarget.newColumn(beside: "toolbar", place: .after, width: floatingWidth, height: floatingHeight)
                return Hit(chrome: .bar(bar, tint: nil), target: target)
            }
            let inside = pointer.x - scene.host.minX
            if inside >= -1e-9, inside <= IllustratorDock.windowEdgeWithToolbar + 1e-9 {
                let bar = IllustratorDock.edgeBar(x: scene.host.minX, span: scene.host)
                let target: DockTarget = draggingToolbar
                    ? .redockToolbar(.left)
                    : .newColumn(beside: "window", place: .windowEdge, width: floatingWidth, height: floatingHeight)
                return Hit(chrome: .bar(bar, tint: nil), target: target)
            }
            return nil
        }
        let inside = pointer.x - scene.host.minX
        if inside >= -1e-9, inside <= IllustratorDock.windowEdgeBare + 1e-9 {
            let span = scene.columns.first?.frame ?? scene.host
            let bar = IllustratorDock.edgeBar(x: scene.host.minX, span: span)
            let target: DockTarget = draggingToolbar
                ? .redockToolbar(.left)
                : .newColumn(beside: "window", place: .windowEdge, width: floatingWidth, height: floatingHeight)
            return Hit(chrome: .bar(bar, tint: nil), target: target)
        }
        return nil
    }

    private mutating func groupZone(pointer: Vec2, group: DockGroupBox) -> Hit? {
        let top = group.frame.minY
        let bottom = group.frame.maxY
        let tabBottom = top + group.tabHeight
        if pointer.y >= bottom - IllustratorDock.bottomBand - 1e-9,
           pointer.y <= bottom + 1e-9,
           pointer.y > tabBottom + IllustratorDock.tabInto + 1e-9 {
            band = .none
            let line = DockFrame(x: group.frame.minX, y: bottom - IllustratorDock.lineThickness, width: group.frame.width, height: IllustratorDock.lineThickness)
            return Hit(chrome: .line(line), target: .stack(group: group.id, above: false))
        }
        let y = pointer.y
        let hysteresis = y >= top + IllustratorDock.hysteresisLow - 1e-9 && y <= top + IllustratorDock.hysteresisHigh + 1e-9
        if hysteresis {
            let keepTop = band == .top || (band != .tab && y <= top + IllustratorDock.topInto + 1e-9)
            if keepTop {
                band = .top
                return topLine(group)
            }
            band = .tab
            return Hit(chrome: .outline(group.frame), target: .join(group: group.id))
        }
        if y >= top - IllustratorDock.topOuter - 1e-9 && y < top + IllustratorDock.hysteresisLow {
            band = .top
            return topLine(group)
        }
        if y > top + IllustratorDock.hysteresisHigh && y <= tabBottom + IllustratorDock.tabInto + 1e-9 {
            band = .tab
            return Hit(chrome: .outline(group.frame), target: .join(group: group.id))
        }
        band = .none
        return nil
    }

    private func topLine(_ group: DockGroupBox) -> Hit {
        let line = DockFrame(
            x: group.frame.minX,
            y: group.frame.minY,
            width: group.frame.width,
            height: IllustratorDock.lineThickness
        )
        return Hit(chrome: .line(line), target: .stack(group: group.id, above: true))
    }

    private func group(at pointer: Vec2, scene: DockWorkspace) -> DockGroupBox? {
        let occupied = scene.groups.filter { !$0.vacated && near($0, pointer) }
        if let inside = occupied.first(where: { contains($0.frame, pointer) }) { return inside }
        return occupied.first
    }

    private func pointInAnyGroup(_ pointer: Vec2, scene: DockWorkspace) -> Bool {
        scene.groups.contains { !$0.vacated && near($0, pointer) }
    }

    private func near(_ group: DockGroupBox, _ pointer: Vec2) -> Bool {
        guard pointer.x >= group.frame.minX - 1e-9, pointer.x < group.frame.maxX - 1e-9 else { return false }
        return pointer.y >= group.frame.minY - IllustratorDock.topOuter - 1e-9
            && pointer.y <= group.frame.maxY + 1e-9
    }

    private func contains(_ frame: DockFrame, _ pointer: Vec2) -> Bool {
        pointer.x >= frame.minX - 1e-9 && pointer.x < frame.maxX - 1e-9
            && pointer.y >= frame.minY - 1e-9 && pointer.y <= frame.maxY + 1e-9
    }
}

extension IllustratorDock {
    /// Toolbar column for a redock. Left is the window edge. Right is immediately
    /// left of the right dock, where the right-column bar is drawn. The existing
    /// column frame is not modified.
    public static func toolbarColumn(scene: DockWorkspace, side: DockAnchor, width: Double) -> DockFrame? {
        switch side {
        case .left:
            let y = scene.toolbar?.minY ?? scene.columns.map(\.frame.minY).min() ?? scene.host.minY
            let height = scene.toolbar?.height ?? scene.columns.map(\.frame.height).max() ?? scene.host.height
            return DockFrame(x: scene.host.minX, y: y, width: width, height: height)
        case .right:
            guard let column = scene.columns.filter({ $0.side == .right }).min(by: { $0.frame.minX < $1.frame.minX }) else { return nil }
            return DockFrame(x: column.frame.minX - width, y: column.frame.minY, width: width, height: column.frame.height)
        case .none:
            return nil
        }
    }

    /// Where a new column's group lands. The existing column frame is not modified.
    /// The group sits on the column's top edge and keeps `height` (the floating height).
    public static func insertedFrame(scene: DockWorkspace, target: DockTarget) -> DockFrame? {
        guard case .newColumn(let beside, let place, let width, let height) = target else { return nil }
        switch place {
        case .before:
            guard let column = scene.columns.first(where: { $0.id == beside }) else { return nil }
            return DockFrame(x: column.frame.minX - width, y: column.frame.minY, width: width, height: height)
        case .after:
            guard beside == "toolbar", let toolbar = scene.toolbar else { return nil }
            return DockFrame(x: toolbar.maxX, y: toolbar.minY, width: width, height: height)
        case .windowEdge:
            let y = scene.toolbar?.minY ?? scene.columns.map(\.frame.minY).min() ?? scene.host.minY
            return DockFrame(x: scene.host.minX, y: y, width: width, height: height)
        }
    }
}

/// Collapse restores the height the panel had, not a fixed 312 pt.
public enum PanelCollapse {
    public static func height(collapsed: Bool, expanded: Double, title: Double) -> Double {
        collapsed ? title : max(expanded, title)
    }
}

/// Window resize must not put floating panels back on the metric grid.
public enum FloatingPlacement {
    public static func resetsFrames(alreadyPlaced: Bool) -> Bool {
        !alreadyPlaced
    }
}

/// Properties-panel crop, locked to the design window.
///
/// Subtracting the live dock origin slides the 属性 UI out of the column as soon
/// as the window is not 1033 pt wide. The strip is the same gray as the canvas,
/// so the column looks gone. Width and height changing together is when that
/// was reported; the origin must not depend on the live frame either way.
public enum PropertiesChrome {
    public static let designWindowWidth = 1033.0
    public static let designDockWidth = 312.0
    public static let designToolWidth = 81.0
    public static let designChromeInset = 89.0
    public static let designDockLift = 36.0

    public static var originX: Double { designWindowWidth - designDockWidth - designToolWidth }
    public static var originY: Double { designChromeInset - designDockLift }

    public static func localX(cropX: Double) -> Double { cropX - originX }
    public static func localY(cropY: Double) -> Double { cropY - originY }
}

/// A group's frame after one tab leaves. The body is the measured panel, not the
/// width of the remaining tab labels. Drawing is clipped to that frame.
public enum PanelContentFit {
    public static let alignWidth = 313.0
    public static let alignHeight = 283.0
    public static let appearanceWidth = 302.0
    public static let appearanceHeight = 243.0
    public static let strokeWidth = 313.0
    public static let strokeHeight = 442.0

    public static func size(tabs: [String]) -> (width: Double, height: Double) {
        let names = Set(tabs)
        if names.contains("描边") || names.contains("透明度") {
            return (strokeWidth, strokeHeight)
        }
        if names == ["外观"] {
            return (appearanceWidth, appearanceHeight)
        }
        if names.contains("变换") || names.contains("对齐") || names.contains("路径查找器") {
            return (alignWidth, alignHeight)
        }
        return (alignWidth, alignHeight)
    }

    /// A glyph past the frame paints on the canvas unless the panel clips.
    public static func staysInside(contentMaxX: Double, frameWidth: Double, clipsToBounds: Bool) -> Bool {
        if clipsToBounds { return true }
        return contentMaxX <= frameWidth + 1e-6
    }
}

/// Status-bar strings. The hint yields to the trailing cluster so the two never overlap.
public struct StatusBarItems: Equatable, Sendable {
    public var hintX: Double
    public var hintWidth: Double
    public var trailingX: Double
    public var trailingWidth: Double

    public init(hintX: Double, hintWidth: Double, trailingX: Double, trailingWidth: Double) {
        self.hintX = hintX
        self.hintWidth = hintWidth
        self.trailingX = trailingX
        self.trailingWidth = trailingWidth
    }

    public var overlaps: Bool {
        guard hintWidth > 0.5, trailingWidth > 0.5 else { return false }
        return hintX + hintWidth > trailingX + 1e-6
    }
}

public enum StatusBarLayout {
    public static func place(
        barWidth: Double,
        hintWidth: Double,
        trailingWidth: Double,
        leftInset: Double = 10,
        rightInset: Double = 12,
        gap: Double = 8
    ) -> StatusBarItems {
        let room = max(0, barWidth - leftInset - rightInset)
        let trail = min(max(0, trailingWidth), room)
        let trailingX = barWidth - rightInset - trail
        let hintRoom = max(0, trailingX - gap - leftInset)
        let hint = min(max(0, hintWidth), hintRoom)
        return StatusBarItems(hintX: leftInset, hintWidth: hint, trailingX: trailingX, trailingWidth: trail)
    }
}

/// Floating panels keep their screen position when the window resizes.
/// Coordinates are y-up, in the window. A height change that keeps the window's
/// top fixed raises the origin by the same amount; subtracting that delta
/// cancels a bottom-left pin. A panel that still overlaps the window is not
/// moved, even if it hangs past an edge. One that would miss the window
/// entirely is nudged back in.
public enum FloatingScreen {
    public static func reposition(
        panelInWindow: DockBox,
        oldWindowOrigin: (x: Double, y: Double),
        newWindowOrigin: (x: Double, y: Double),
        windowBounds: DockBox
    ) -> DockBox {
        let x = panelInWindow.x + oldWindowOrigin.x - newWindowOrigin.x
        let y = panelInWindow.y + oldWindowOrigin.y - newWindowOrigin.y
        return DockBox(
            x: nudgeInto(origin: x, length: panelInWindow.width, low: windowBounds.x, high: windowBounds.maxX),
            y: nudgeInto(origin: y, length: panelInWindow.height, low: windowBounds.y, high: windowBounds.maxY),
            width: panelInWindow.width,
            height: panelInWindow.height
        )
    }

    /// Smallest shift that puts the panel back inside [low, high]. An overlap,
    /// including a panel that only partly hangs out, is left where it is.
    private static func nudgeInto(origin: Double, length: Double, low: Double, high: Double) -> Double {
        if length <= 1e-9 { return origin }
        if origin < high - 1e-9 && origin + length > low + 1e-9 { return origin }
        if origin + length <= low + 1e-9 { return low }
        let room = high - low
        if length >= room - 1e-9 { return low }
        return high - length
    }

    /// Launch centering and the screen clamp are not a user resize. Holding
    /// starts on the first on-screen frame that fits, and that frame is recorded
    /// without moving panels. A later window-frame change keeps screen position.
    public static func holdDecision(
        alreadySettled: Bool,
        windowVisible: Bool,
        frameFitsScreen: Bool,
        windowFrameChanged: Bool
    ) -> (settled: Bool, move: Bool) {
        if !alreadySettled {
            return (windowVisible && frameFitsScreen, false)
        }
        return (true, windowFrameChanged)
    }
}

/// Screen-space pen close. Both points are in the same space (view points).
public enum PenCloseHit {
    public static func screen(pointer: Vec2, anchor: Vec2, limit: Double = ToolBehaviors.penCloseSlop) -> Bool {
        pointer.distance(to: anchor) <= limit + 1e-9
    }

    /// View point (y up) ↔ document point. Matches `VectorCanvas` / `CanvasDrawing`.
    public static func documentPoint(viewX: Double, viewY: Double, viewHeight: Double, pan: Vec2, zoom: Double) -> Vec2 {
        let zoom = max(zoom, 0.0001)
        return Vec2(viewX / zoom + pan.x, (viewHeight - viewY) / zoom + pan.y)
    }

    public static func viewPoint(document: Vec2, viewHeight: Double, pan: Vec2, zoom: Double) -> Vec2 {
        Vec2((document.x - pan.x) * zoom, viewHeight - (document.y - pan.y) * zoom)
    }
}
