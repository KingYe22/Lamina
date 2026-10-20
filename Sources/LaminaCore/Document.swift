import Foundation

public enum ColorMode: String, Codable, Equatable, Sendable { case rgb, cmyk }
public enum UnitKind: String, Codable, Equatable, Sendable { case pt, mm, px, inch }
public enum FillRule: String, Codable, Equatable, Sendable { case nonzero, evenOdd }
public enum TextKind: String, Codable, Equatable, Sendable { case point, area, path }
public enum TextAlign: String, Codable, Equatable, Sendable { case left, center, right, justify }
public enum CornerKind: String, Codable, Equatable, Sendable { case corner, smooth }
public enum GuideAxis: String, Codable, Equatable, Sendable { case horizontal, vertical }

public enum ShapeKind: Codable, Equatable, Hashable, Sendable {
    case line
    case rectangle
    case roundedRectangle(radius: Double)
    case ellipse
    case polygon(sides: Int)
    case star(points: Int, innerRatio: Double)
    case free

    public var label: String {
        switch self {
        case .line: return "直线"
        case .rectangle: return "矩形"
        case .roundedRectangle: return "圆角矩形"
        case .ellipse: return "椭圆"
        case .polygon: return "多边形"
        case .star: return "星形"
        case .free: return "路径"
        }
    }
}

public struct PathNode: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var anchor: Vec2
    public var inHandle: Vec2?
    public var outHandle: Vec2?
    public var corner: CornerKind

    public init(id: UUID = UUID(), anchor: Vec2, inHandle: Vec2? = nil, outHandle: Vec2? = nil, corner: CornerKind = .corner) {
        self.id = id
        self.anchor = anchor
        self.inHandle = inHandle
        self.outHandle = outHandle
        self.corner = corner
    }

    public static func corner(_ p: Vec2) -> PathNode { PathNode(anchor: p, corner: .corner) }
}

public struct PathItem: Codable, Equatable, Hashable, Sendable {
    public var nodes: [PathNode]
    public var closed: Bool
    public var shape: ShapeKind

    public init(nodes: [PathNode], closed: Bool, shape: ShapeKind = .free) {
        self.nodes = nodes
        self.closed = closed
        self.shape = shape
    }
}

public struct WidthPoint: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var t: Double
    public var left: Double
    public var right: Double
    public init(id: UUID = UUID(), t: Double, left: Double, right: Double) {
        self.id = id; self.t = t; self.left = left; self.right = right
    }
}

public struct PathObject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var path: PathItem
    public var appearance: Appearance
    public var transform: Affine
    public var locked: Bool
    public var hidden: Bool
    public var widths: [WidthPoint]

    public init(id: UUID = UUID(), name: String = "路径", path: PathItem, appearance: Appearance = .default, transform: Affine = .identity, locked: Bool = false, hidden: Bool = false, widths: [WidthPoint] = []) {
        self.id = id
        self.name = name
        self.path = path
        self.appearance = appearance
        self.transform = transform
        self.locked = locked
        self.hidden = hidden
        self.widths = widths
    }
}

public struct TextObject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: TextKind
    public var string: String
    public var origin: Vec2
    public var frame: Rect2
    public var fontName: String
    public var fontSize: Double
    public var tracking: Double
    public var leading: Double
    public var alignment: TextAlign
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var baselineShift: Double
    public var horizontalScale: Double
    public var appearance: Appearance
    public var transform: Affine
    public var locked: Bool
    public var hidden: Bool
    public var onPath: PathItem?

    public init(id: UUID = UUID(), name: String = "文字", kind: TextKind = .point, string: String = "文字", origin: Vec2 = .zero, frame: Rect2 = .zero, fontName: String = "PingFang SC", fontSize: Double = 24, tracking: Double = 0, leading: Double = 0, alignment: TextAlign = .left, bold: Bool = false, italic: Bool = false, underline: Bool = false, baselineShift: Double = 0, horizontalScale: Double = 1, appearance: Appearance = Appearance(fill: .solid(.black), stroke: nil), transform: Affine = .identity, locked: Bool = false, hidden: Bool = false, onPath: PathItem? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.string = string
        self.origin = origin
        self.frame = frame
        self.fontName = fontName
        self.fontSize = fontSize
        self.tracking = tracking
        self.leading = leading
        self.alignment = alignment
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.baselineShift = baselineShift
        self.horizontalScale = horizontalScale
        self.appearance = appearance
        self.transform = transform
        self.locked = locked
        self.hidden = hidden
        self.onPath = onPath
    }
}

public struct GroupObject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var children: [ArtItem]
    public var transform: Affine
    public var locked: Bool
    public var hidden: Bool
    public var opacity: Double
    public var isSymbol: Bool
    public var isLivePaint: Bool

    public init(id: UUID = UUID(), name: String = "组", children: [ArtItem], transform: Affine = .identity, locked: Bool = false, hidden: Bool = false, opacity: Double = 1, isSymbol: Bool = false, isLivePaint: Bool = false) {
        self.id = id
        self.name = name
        self.children = children
        self.transform = transform
        self.locked = locked
        self.hidden = hidden
        self.opacity = opacity
        self.isSymbol = isSymbol
        self.isLivePaint = isLivePaint
    }
}

public struct CompoundObject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var paths: [PathItem]
    public var appearance: Appearance
    public var transform: Affine
    public var fillRule: FillRule
    public var locked: Bool
    public var hidden: Bool

    public init(id: UUID = UUID(), name: String = "复合路径", paths: [PathItem], appearance: Appearance = .default, transform: Affine = .identity, fillRule: FillRule = .evenOdd, locked: Bool = false, hidden: Bool = false) {
        self.id = id
        self.name = name
        self.paths = paths
        self.appearance = appearance
        self.transform = transform
        self.fillRule = fillRule
        self.locked = locked
        self.hidden = hidden
    }
}

public struct ClipObject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var clipper: ArtItem
    public var contents: [ArtItem]
    public var transform: Affine
    public var locked: Bool
    public var hidden: Bool

    public init(id: UUID = UUID(), name: String = "剪切组", clipper: ArtItem, contents: [ArtItem], transform: Affine = .identity, locked: Bool = false, hidden: Bool = false) {
        self.id = id
        self.name = name
        self.clipper = clipper
        self.contents = contents
        self.transform = transform
        self.locked = locked
        self.hidden = hidden
    }
}

public struct PlacedObject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: String
    public var frame: Rect2
    public var dataBase64: String
    public var transform: Affine
    public var locked: Bool
    public var hidden: Bool

    public init(id: UUID = UUID(), name: String = "置入", kind: String, frame: Rect2, dataBase64: String, transform: Affine = .identity, locked: Bool = false, hidden: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frame = frame
        self.dataBase64 = dataBase64
        self.transform = transform
        self.locked = locked
        self.hidden = hidden
    }
}

public struct MeshObject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var columns: Int
    public var rows: Int
    public var origin: Vec2
    public var cell: Vec2
    public var colors: [RGBA]
    public var transform: Affine
    public var locked: Bool
    public var hidden: Bool

    public init(id: UUID = UUID(), name: String = "网格", columns: Int, rows: Int, origin: Vec2, cell: Vec2, colors: [RGBA], transform: Affine = .identity, locked: Bool = false, hidden: Bool = false) {
        self.id = id
        self.name = name
        self.columns = columns
        self.rows = rows
        self.origin = origin
        self.cell = cell
        self.colors = colors
        self.transform = transform
        self.locked = locked
        self.hidden = hidden
    }
}

public enum ChartKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case column, stackedColumn, bar, stackedBar, line, area, scatter, pie, radar

    public var title: String {
        switch self {
        case .column: return "柱形图"
        case .stackedColumn: return "堆积柱形图"
        case .bar: return "条形图"
        case .stackedBar: return "堆积条形图"
        case .line: return "折线图"
        case .area: return "面积图"
        case .scatter: return "散点图"
        case .pie: return "饼图"
        case .radar: return "雷达图"
        }
    }
}

public struct GraphObject: Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var frame: Rect2
    public var values: [Double]
    public var color: RGBA
    public var transform: Affine
    public var locked: Bool
    public var hidden: Bool
    public var kind: ChartKind
    public var series: [[Double]]

    public init(id: UUID = UUID(), name: String = "柱形图", frame: Rect2, values: [Double], color: RGBA = RGBA(hex: "#1473E6"), transform: Affine = .identity, locked: Bool = false, hidden: Bool = false, kind: ChartKind = .column, series: [[Double]] = []) {
        self.id = id
        self.name = name
        self.frame = frame
        self.values = values
        self.color = color
        self.transform = transform
        self.locked = locked
        self.hidden = hidden
        self.kind = kind
        self.series = series
    }

    public var plotSeries: [[Double]] {
        if series.isEmpty { return values.isEmpty ? [[1]] : [values] }
        return series
    }
}

extension GraphObject: Codable {
    enum CodingKeys: String, CodingKey { case id, name, frame, values, color, transform, locked, hidden, kind, series }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "柱形图"
        frame = try c.decode(Rect2.self, forKey: .frame)
        values = try c.decodeIfPresent([Double].self, forKey: .values) ?? []
        color = try c.decodeIfPresent(RGBA.self, forKey: .color) ?? RGBA(hex: "#1473E6")
        transform = try c.decodeIfPresent(Affine.self, forKey: .transform) ?? .identity
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        kind = try c.decodeIfPresent(ChartKind.self, forKey: .kind) ?? .column
        series = try c.decodeIfPresent([[Double]].self, forKey: .series) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(frame, forKey: .frame)
        try c.encode(values, forKey: .values)
        try c.encode(color, forKey: .color)
        try c.encode(transform, forKey: .transform)
        try c.encode(locked, forKey: .locked)
        try c.encode(hidden, forKey: .hidden)
        if kind != .column { try c.encode(kind, forKey: .kind) }
        if !series.isEmpty { try c.encode(series, forKey: .series) }
    }
}

public indirect enum ArtItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    case path(PathObject)
    case text(TextObject)
    case group(GroupObject)
    case compound(CompoundObject)
    case clip(ClipObject)
    case placed(PlacedObject)
    case mesh(MeshObject)
    case graph(GraphObject)

    public var id: UUID {
        switch self {
        case .path(let o): return o.id
        case .text(let o): return o.id
        case .group(let o): return o.id
        case .compound(let o): return o.id
        case .clip(let o): return o.id
        case .placed(let o): return o.id
        case .mesh(let o): return o.id
        case .graph(let o): return o.id
        }
    }

    public var name: String {
        get {
            switch self {
            case .path(let o): return o.name
            case .text(let o): return o.name
            case .group(let o): return o.name
            case .compound(let o): return o.name
            case .clip(let o): return o.name
            case .placed(let o): return o.name
            case .mesh(let o): return o.name
            case .graph(let o): return o.name
            }
        }
        set {
            switch self {
            case .path(var o): o.name = newValue; self = .path(o)
            case .text(var o): o.name = newValue; self = .text(o)
            case .group(var o): o.name = newValue; self = .group(o)
            case .compound(var o): o.name = newValue; self = .compound(o)
            case .clip(var o): o.name = newValue; self = .clip(o)
            case .placed(var o): o.name = newValue; self = .placed(o)
            case .mesh(var o): o.name = newValue; self = .mesh(o)
            case .graph(var o): o.name = newValue; self = .graph(o)
            }
        }
    }

    public var locked: Bool {
        get {
            switch self {
            case .path(let o): return o.locked
            case .text(let o): return o.locked
            case .group(let o): return o.locked
            case .compound(let o): return o.locked
            case .clip(let o): return o.locked
            case .placed(let o): return o.locked
            case .mesh(let o): return o.locked
            case .graph(let o): return o.locked
            }
        }
        set { setLocked(newValue) }
    }

    public var hidden: Bool {
        get {
            switch self {
            case .path(let o): return o.hidden
            case .text(let o): return o.hidden
            case .group(let o): return o.hidden
            case .compound(let o): return o.hidden
            case .clip(let o): return o.hidden
            case .placed(let o): return o.hidden
            case .mesh(let o): return o.hidden
            case .graph(let o): return o.hidden
            }
        }
        set { setHidden(newValue) }
    }

    public var transform: Affine {
        get {
            switch self {
            case .path(let o): return o.transform
            case .text(let o): return o.transform
            case .group(let o): return o.transform
            case .compound(let o): return o.transform
            case .clip(let o): return o.transform
            case .placed(let o): return o.transform
            case .mesh(let o): return o.transform
            case .graph(let o): return o.transform
            }
        }
        set { setTransform(newValue) }
    }

    public mutating func setLocked(_ value: Bool) {
        switch self {
        case .path(var o): o.locked = value; self = .path(o)
        case .text(var o): o.locked = value; self = .text(o)
        case .group(var o): o.locked = value; self = .group(o)
        case .compound(var o): o.locked = value; self = .compound(o)
        case .clip(var o): o.locked = value; self = .clip(o)
        case .placed(var o): o.locked = value; self = .placed(o)
        case .mesh(var o): o.locked = value; self = .mesh(o)
        case .graph(var o): o.locked = value; self = .graph(o)
        }
    }

    public mutating func setHidden(_ value: Bool) {
        switch self {
        case .path(var o): o.hidden = value; self = .path(o)
        case .text(var o): o.hidden = value; self = .text(o)
        case .group(var o): o.hidden = value; self = .group(o)
        case .compound(var o): o.hidden = value; self = .compound(o)
        case .clip(var o): o.hidden = value; self = .clip(o)
        case .placed(var o): o.hidden = value; self = .placed(o)
        case .mesh(var o): o.hidden = value; self = .mesh(o)
        case .graph(var o): o.hidden = value; self = .graph(o)
        }
    }

    public mutating func setTransform(_ value: Affine) {
        switch self {
        case .path(var o): o.transform = value; self = .path(o)
        case .text(var o): o.transform = value; self = .text(o)
        case .group(var o): o.transform = value; self = .group(o)
        case .compound(var o): o.transform = value; self = .compound(o)
        case .clip(var o): o.transform = value; self = .clip(o)
        case .placed(var o): o.transform = value; self = .placed(o)
        case .mesh(var o): o.transform = value; self = .mesh(o)
        case .graph(var o): o.transform = value; self = .graph(o)
        }
    }

    public var children: [ArtItem] {
        switch self {
        case .group(let o): return o.children
        case .clip(let o): return [o.clipper] + o.contents
        default: return []
        }
    }
}

public struct Layer: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var visible: Bool
    public var locked: Bool
    public var outline: Bool
    public var items: [ArtItem]
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, visible: Bool = true, locked: Bool = false, outline: Bool = false, items: [ArtItem] = [], colorHex: String = "#1473E6") {
        self.id = id
        self.name = name
        self.visible = visible
        self.locked = locked
        self.outline = outline
        self.items = items
        self.colorHex = colorHex
    }
}

public struct Artboard: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var rect: Rect2

    public init(id: UUID = UUID(), name: String, rect: Rect2) {
        self.id = id
        self.name = name
        self.rect = rect
    }
}

public struct Guide: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var axis: GuideAxis
    public var position: Double

    public init(id: UUID = UUID(), axis: GuideAxis, position: Double) {
        self.id = id
        self.axis = axis
        self.position = position
    }
}

public struct SliceRect: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var rect: Rect2
    public init(id: UUID = UUID(), rect: Rect2) {
        self.id = id
        self.rect = rect
    }
}

public struct LaminaDocument: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public var version: Int
    public var title: String
    public var colorMode: ColorMode
    public var units: UnitKind
    public var artboards: [Artboard]
    public var activeArtboard: Int
    public var layers: [Layer]
    public var activeLayer: Int
    public var swatches: [Swatch]
    public var guides: [Guide]
    public var slices: [SliceRect]
    public var rasterPPI: Double
    public var rulerOrigin: Vec2

    public init(version: Int = LaminaDocument.formatVersion, title: String, colorMode: ColorMode = .rgb, units: UnitKind = .pt, artboards: [Artboard], activeArtboard: Int = 0, layers: [Layer], activeLayer: Int = 0, swatches: [Swatch] = Swatch.defaults, guides: [Guide] = [], slices: [SliceRect] = [], rasterPPI: Double = 72, rulerOrigin: Vec2 = .zero) {
        self.version = version
        self.title = title
        self.colorMode = colorMode
        self.units = units
        self.artboards = artboards
        self.activeArtboard = activeArtboard
        self.layers = layers
        self.activeLayer = activeLayer
        self.swatches = swatches
        self.guides = guides
        self.slices = slices
        self.rasterPPI = rasterPPI
        self.rulerOrigin = rulerOrigin
    }

    public static func blank(title: String = "未标题-1", size: Vec2 = Vec2(800, 600)) -> LaminaDocument {
        let board = Artboard(name: "画板 1", rect: Rect2(x: 0, y: 0, width: size.x, height: size.y))
        let layer = Layer(name: "图层 1")
        return LaminaDocument(title: title, artboards: [board], layers: [layer])
    }

    public var currentArtboard: Artboard {
        let idx = min(max(0, activeArtboard), max(0, artboards.count - 1))
        return artboards[idx]
    }

    public var objectCount: Int {
        layers.reduce(0) { $0 + $1.items.reduce(0) { $0 + countItems($1) } }
    }

    private func countItems(_ item: ArtItem) -> Int {
        1 + item.children.reduce(0) { $0 + countItems($1) }
    }
}

extension Swatch {
    public static var defaults: [Swatch] {
        let solids: [(String, String)] = [
            ("白色", "#FFFFFF"), ("黑色", "#000000"), ("红色", "#FF2A2A"),
            ("绿色", "#22A06B"), ("蓝色", "#1473E6"), ("黄色", "#FFCD29"),
            ("青色", "#14C8C8"), ("品红", "#E114C8"), ("橙色", "#E86C14")
        ]
        var list = solids.map { Swatch(name: $0.0, paint: .solid(RGBA(hex: $0.1))) }
        let process: [(String, DeviceCMYK)] = [
            ("青", DeviceCMYK(c: 1, m: 0, y: 0, k: 0)),
            ("品红", DeviceCMYK(c: 0, m: 1, y: 0, k: 0)),
            ("黄", DeviceCMYK(c: 0, m: 0, y: 1, k: 0)),
            ("黑版", DeviceCMYK(c: 0, m: 0, y: 0, k: 1))
        ]
        list.append(contentsOf: process.map { Swatch(name: "CMYK \($0.0)", paint: .solid(RGBA(cmyk: $0.1)), global: true) })
        list.append(Swatch(name: "黑白渐变", paint: .linear(.blackWhite)))
        return list
    }
}
