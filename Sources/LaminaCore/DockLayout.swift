import Foundation

/// One panel the dock layout may seat. A panel that is being dragged still
/// belongs to `columnID` until the gesture commits, so its column is not empty.
public struct DockMember: Equatable, Sendable {
    public var id: String
    public var columnID: String?
    public var order: Int
    public var height: Double
    public var dragging: Bool
    public var hidden: Bool
    public var embedded: Bool

    public init(
        id: String,
        columnID: String?,
        order: Int,
        height: Double,
        dragging: Bool = false,
        hidden: Bool = false,
        embedded: Bool = false
    ) {
        self.id = id
        self.columnID = columnID
        self.order = order
        self.height = height
        self.dragging = dragging
        self.hidden = hidden
        self.embedded = embedded
    }

    /// Still holding a column open. Hidden panels do not. A lifted panel does,
    /// until the gesture clears `columnID`.
    public var occupiesColumn: Bool { !hidden && columnID != nil }
}

public struct DockColumnSpec: Equatable, Sendable {
    public var id: String
    public var place: DockPlace
    public var width: Double

    public init(id: String, place: DockPlace, width: Double) {
        self.id = id
        self.place = place
        self.width = width
    }
}

/// Shell-space rectangle, origin at the bottom left, y growing up.
public struct DockBox: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    /// Shared interior, not a shared edge. Adjacent stacked panels do not overlap.
    public func overlaps(_ other: DockBox) -> Bool {
        let width = min(maxX, other.maxX) - max(x, other.x)
        let height = min(maxY, other.maxY) - max(y, other.y)
        return width > 1e-6 && height > 1e-6
    }
}

/// Where a panel is painted relative to the properties column.
public enum DockLayer: Int, Comparable, Sendable {
    case canvas = 0
    case properties = 1
    case docked = 2
    case floating = 3

    public static func < (lhs: DockLayer, rhs: DockLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// A panel with no column, and the panel under the pointer, paint above docked panels.
    public static func layer(columnID: String?, dragging: Bool) -> DockLayer {
        if dragging || columnID == nil { return .floating }
        return .docked
    }
}

public struct DockLayoutInput: Equatable, Sendable {
    public var windowWidth: Double
    public var windowHeight: Double
    public var titleBand: Double
    public var documentTabHeight: Double
    public var statusHeight: Double
    public var chromeInset: Double
    public var dockLift: Double
    public var toolWidth: Double
    public var dockWidth: Double
    public var toolbarLeft: Bool
    public var toolbarRight: Bool
    public var columns: [DockColumnSpec]
    public var members: [DockMember]

    public init(
        windowWidth: Double,
        windowHeight: Double,
        titleBand: Double,
        documentTabHeight: Double,
        statusHeight: Double,
        chromeInset: Double,
        dockLift: Double,
        toolWidth: Double,
        dockWidth: Double,
        toolbarLeft: Bool,
        toolbarRight: Bool,
        columns: [DockColumnSpec],
        members: [DockMember]
    ) {
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.titleBand = titleBand
        self.documentTabHeight = documentTabHeight
        self.statusHeight = statusHeight
        self.chromeInset = chromeInset
        self.dockLift = dockLift
        self.toolWidth = toolWidth
        self.dockWidth = dockWidth
        self.toolbarLeft = toolbarLeft
        self.toolbarRight = toolbarRight
        self.columns = columns
        self.members = members
    }
}

public struct DockLayoutResult: Equatable, Sendable {
    /// Extra columns that still have a member. The properties column is not in this list.
    public var columns: [DockColumnSpec]
    public var columnFrames: [String: DockBox]
    /// Full properties column. This frame is never dropped and never resized to a panel.
    public var properties: DockBox
    /// 属性 content under any panels seated in the properties column.
    public var propertiesContent: DockBox
    /// Docked panels only. The panel being dragged is absent so the pointer keeps its frame.
    public var memberFrames: [String: DockBox]
    public var canvas: DockBox
    public var status: DockBox
    public var columnBodyHeight: Double

    public init(
        columns: [DockColumnSpec],
        columnFrames: [String: DockBox],
        properties: DockBox,
        propertiesContent: DockBox,
        memberFrames: [String: DockBox],
        canvas: DockBox,
        status: DockBox,
        columnBodyHeight: Double
    ) {
        self.columns = columns
        self.columnFrames = columnFrames
        self.properties = properties
        self.propertiesContent = propertiesContent
        self.memberFrames = memberFrames
        self.canvas = canvas
        self.status = status
        self.columnBodyHeight = columnBodyHeight
    }
}

public enum DockLayout {
    /// Canvas and status width: the window, minus the docked toolbar, minus every
    /// extra column, minus the properties dock.
    public static func spanWidth(windowWidth: Double, toolbar: Double, columns: Double, dock: Double) -> Double {
        windowWidth - toolbar - columns - dock
    }

    /// Releasing into the same slot uses the height the column was holding.
    /// A float, a new column, or a stack keeps the height the pointer was carrying.
    public static func heightOnRelease(target: DockTarget, slotHeight: Double, carriedHeight: Double) -> Double {
        switch target {
        case .stay, .restore:
            return slotHeight > 0 ? slotHeight : carriedHeight
        default:
            return carriedHeight
        }
    }

    /// A column stays while any visible member still names it, including the panel
    /// under the pointer and a panel embedded in the properties view.
    public static func keptColumns(_ columns: [DockColumnSpec], members: [DockMember]) -> [DockColumnSpec] {
        let occupied = Set(members.compactMap { member -> String? in
            guard member.occupiesColumn, let id = member.columnID else { return nil }
            return id
        })
        return columns.filter { occupied.contains($0.id) }
    }

    public static func solve(_ input: DockLayoutInput) -> DockLayoutResult {
        let kept = keptColumns(input.columns, members: input.members)
        let top = input.windowHeight - input.titleBand
        let bodyHeight = top - input.documentTabHeight - input.statusHeight
        let columnBody = bodyHeight - input.chromeInset
        let columnHeight = columnBody + input.dockLift
        let toolbar = input.toolbarLeft || input.toolbarRight ? input.toolWidth : 0
        let columnSum = kept.reduce(0) { $0 + $1.width }
        let span = spanWidth(windowWidth: input.windowWidth, toolbar: toolbar, columns: columnSum, dock: input.dockWidth)

        let windowEdge = kept.filter { $0.place == .windowEdge }.reduce(0) { $0 + $1.width }
        let after = kept.filter { $0.place == .after }.reduce(0) { $0 + $1.width }
        let toolbarRight = input.toolbarRight ? input.toolWidth : 0
        let leading = windowEdge + (input.toolbarLeft ? input.toolWidth : 0) + after
        let dockX = input.windowWidth - input.dockWidth

        var columnFrames: [String: DockBox] = [:]
        var edgeX = 0.0
        for column in kept where column.place == .windowEdge {
            columnFrames[column.id] = DockBox(x: edgeX, y: input.statusHeight, width: column.width, height: columnHeight)
            edgeX += column.width
        }
        var afterX = windowEdge + (input.toolbarLeft ? input.toolWidth : 0)
        for column in kept where column.place == .after {
            columnFrames[column.id] = DockBox(x: afterX, y: input.statusHeight, width: column.width, height: columnHeight)
            afterX += column.width
        }
        var cursor = dockX - toolbarRight
        for column in kept where column.place == .before {
            cursor -= column.width
            columnFrames[column.id] = DockBox(x: cursor, y: input.statusHeight, width: column.width, height: columnHeight)
        }

        let properties = DockBox(x: dockX, y: input.statusHeight, width: input.dockWidth, height: columnHeight)
        var memberFrames: [String: DockBox] = [:]
        for column in kept {
            guard let rect = columnFrames[column.id] else { continue }
            seat(column.id, in: rect, members: input.members, into: &memberFrames)
        }
        let propertiesUsed = seat("properties", in: properties, members: input.members, into: &memberFrames)
        let propertiesContent: DockBox
        let remainder = properties.height - propertiesUsed
        // The dragging panel is not in `propertiesUsed`. A partial stack leaves 属性
        // in the space under it. An empty or over-full column keeps the full strip
        // so the properties column cannot collapse to a sliver.
        if propertiesUsed > 0 && remainder > 0 {
            propertiesContent = DockBox(
                x: properties.x,
                y: properties.y,
                width: properties.width,
                height: remainder
            )
        } else {
            propertiesContent = properties
        }

        let canvas = DockBox(x: leading, y: input.statusHeight, width: span, height: columnBody)
        let status = DockBox(x: leading, y: 0, width: span, height: input.statusHeight)
        return DockLayoutResult(
            columns: kept,
            columnFrames: columnFrames,
            properties: properties,
            propertiesContent: propertiesContent,
            memberFrames: memberFrames,
            canvas: canvas,
            status: status,
            columnBodyHeight: columnBody
        )
    }

    /// Pack visible, non-embedded, non-dragging members from the top of the column.
    /// Returns the height they occupy. The dragged panel is not given a frame.
    @discardableResult
    private static func seat(
        _ id: String,
        in rect: DockBox,
        members: [DockMember],
        into frames: inout [String: DockBox]
    ) -> Double {
        let seated = members
            .filter { $0.columnID == id && !$0.hidden && !$0.embedded && !$0.dragging }
            .sorted { lhs, rhs in
                lhs.order == rhs.order ? lhs.id < rhs.id : lhs.order < rhs.order
            }
        var top = rect.maxY
        for member in seated {
            let height = member.height
            top -= height
            frames[member.id] = DockBox(x: rect.x, y: top, width: rect.width, height: height)
        }
        return rect.maxY - top
    }
}
