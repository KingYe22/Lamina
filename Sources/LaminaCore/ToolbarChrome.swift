import Foundation

/// Which edge a panel or the toolbar joined. `.none` stays floating.
public enum DockAnchor: Equatable, Sendable {
    case none
    case left
    case right
}

/// Toolbar strip geometry from the 0.4.6 lock.
///
/// Traced glyph outer edges are 6.40 and 72.10 in the unscaled toolbar.
/// `placedX` maps that span so both chrome insets are exactly `contentInset`,
/// on a strip of any width.
public enum ToolbarChrome {
    public static let stripWidth: Double = 81
    public static let contentInset: Double = 8
    /// |left − right| must stay inside this.
    public static let insetTolerance: Double = 1
    public static let selectedWellWidth: Double = 22
    /// Dashed grip is about 11 pt tall. The hit row is the full strip and at least 22 pt.
    public static let gripVisualHeight: Double = 11
    public static let gripHitHeight: Double = 22
    /// Traced y of the `<<` collapse row. The row is this band, then the grip.
    public static let tracedCollapseTop: Double = 16
    public static let tracedCollapseBottom: Double = 32
    /// Traced center of the dashed grip, just under the collapse row.
    public static let tracedGripCenterY: Double = 39.5
    /// Traced top of the 「选择」 tool slots. Icons must sit below the grip hit.
    public static let tracedSelectionMinY: Double = 83.40
    /// Shifts traced toolbar y into the view. Negative, so the collapse row
    /// sits on the top edge. The old `+toolbarLift` pad left a dead band above `<<`.
    public static let contentOffsetY: Double = -tracedCollapseTop

    /// `viewY = tracedY + contentOffsetY`.
    public static func viewY(_ tracedY: Double) -> Double {
        tracedY + contentOffsetY
    }

    /// Collapse row in view points. Its top is the toolbar's top edge.
    public static var collapseRow: DockFrame {
        DockFrame(
            x: 0,
            y: viewY(tracedCollapseTop),
            width: stripWidth,
            height: tracedCollapseBottom - tracedCollapseTop
        )
    }

    public static var gripCenterY: Double { viewY(tracedGripCenterY) }

    /// Dashed grip marks, centered under the collapse row.
    public static var gripVisualFrame: DockFrame {
        DockFrame(
            x: 0,
            y: gripCenterY - gripVisualHeight / 2,
            width: stripWidth,
            height: gripVisualHeight
        )
    }
    /// Press-drag at least this far and the docked toolbar becomes a floating window.
    public static let undockTravel: Double = 12
    public static let tracedContentMinX: Double = 6.40
    public static let tracedContentMaxX: Double = 72.10

    public static func xScale(stripWidth: Double = ToolbarChrome.stripWidth) -> Double {
        let span = tracedContentMaxX - tracedContentMinX
        let room = stripWidth - 2 * contentInset
        guard span > 1, room > 1 else { return 1 }
        return room / span
    }

    /// Traced toolbar x → x on a strip whose outer glyph edges sit `contentInset` from both sides.
    public static func placedX(_ tracedX: Double, stripWidth: Double = ToolbarChrome.stripWidth) -> Double {
        contentInset + (tracedX - tracedContentMinX) * xScale(stripWidth: stripWidth)
    }

    public static func insets(stripWidth: Double = ToolbarChrome.stripWidth) -> (left: Double, right: Double) {
        let left = placedX(tracedContentMinX, stripWidth: stripWidth)
        let right = stripWidth - placedX(tracedContentMaxX, stripWidth: stripWidth)
        return (left, right)
    }

    /// Rounded selection well, `selectedWellWidth` wide, centered in the slot.
    public static func selectedWell(slot: DockFrame, wellWidth: Double = ToolbarChrome.selectedWellWidth) -> DockFrame {
        let width = min(wellWidth, slot.width)
        let x = slot.x + (slot.width - width) / 2
        return DockFrame(x: x, y: slot.y, width: width, height: slot.height)
    }

    /// Full-width hit row centered on the dashed grip. Height is `gripHitHeight` (≥ 22).
    public static func gripHitRect(stripWidth: Double, gripCenterY: Double) -> DockFrame {
        DockFrame(
            x: 0,
            y: gripCenterY - gripHitHeight / 2,
            width: stripWidth,
            height: gripHitHeight
        )
    }
}

/// Grip gesture. A docked toolbar undocks once the pointer travels `undockTravel`.
/// An already floating toolbar moves on the first event.
public struct ToolbarGripDrag: Equatable, Sendable {
    public var start: Vec2
    public var wasDocked: Bool
    public private(set) var floating: Bool

    public init(start: Vec2, docked: Bool) {
        self.start = start
        wasDocked = docked
        floating = !docked
    }

    public mutating func step(pointer: Vec2) -> Bool {
        if !wasDocked {
            floating = true
            return true
        }
        if pointer.distance(to: start) + 1e-9 >= ToolbarChrome.undockTravel {
            floating = true
        }
        return floating
    }
}

/// Magnetic redock of the floating toolbar against the host window's screen edges.
public enum ToolbarSnap {
    public static func edge(
        panelMinX: Double,
        panelMaxX: Double,
        hostMinX: Double,
        hostMaxX: Double,
        threshold: Double = DockSnap.threshold
    ) -> DockAnchor {
        let left = panelMinX - hostMinX
        if left >= -threshold - 1e-9, left <= threshold + 1e-9 { return .left }
        let right = hostMaxX - panelMaxX
        if right >= -threshold - 1e-9, right <= threshold + 1e-9 { return .right }
        return .none
    }
}

/// Title-bar double-click. Traffic lights and text fields are not title chrome.
public enum TitlebarZoom {
    public static func shouldZoom(clickCount: Int, inTitleChrome: Bool, onInteractiveControl: Bool) -> Bool {
        clickCount >= 2 && inTitleChrome && !onInteractiveControl
    }
}

/// Hit regions on a floating panel. y grows downward (flipped panel).
/// The view still handles the close / collapse / menu buttons before asking.
public enum PanelPointerRegion: Equatable, Sendable {
    /// Title bar or the bottom pill. Both move the panel and can dock.
    case move
    case resize
    case content
}

public enum PanelChromeHit {
    public static let bottomBand: Double = 16
    public static let gripWidth: Double = 44

    public static func region(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        titleHeight: Double
    ) -> PanelPointerRegion {
        if y >= 0, y < titleHeight { return .move }
        let gripMin = (width - gripWidth) / 2
        if y >= height - bottomBand, x >= gripMin, x < gripMin + gripWidth { return .move }
        if y > height - 12 { return .resize }
        return .content
    }
}
