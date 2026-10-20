import Foundation

public struct DeviceCMYK: Codable, Equatable, Hashable, Sendable {
    public var c: Double
    public var m: Double
    public var y: Double
    public var k: Double

    public init(c: Double, m: Double, y: Double, k: Double) {
        self.c = c
        self.m = m
        self.y = y
        self.k = k
    }
}

public enum ColorPipeline {
    /// PDF DeviceCMYK to DeviceRGB (Adobe PDF Reference, additive complement of ink).
    public static func rgb(from cmyk: DeviceCMYK, alpha: Double = 1) -> RGBA {
        RGBA(
            r: 1 - min(1, cmyk.c + cmyk.k),
            g: 1 - min(1, cmyk.m + cmyk.k),
            b: 1 - min(1, cmyk.y + cmyk.k),
            a: alpha
        )
    }

    public static func cmyk(from color: RGBA) -> DeviceCMYK {
        let k = 1 - max(color.r, max(color.g, color.b))
        if k >= 0.999 { return DeviceCMYK(c: 0, m: 0, y: 0, k: 1) }
        let scale = 1 - k
        return DeviceCMYK(
            c: (1 - color.r - k) / scale,
            m: (1 - color.g - k) / scale,
            y: (1 - color.b - k) / scale,
            k: k
        )
    }

    /// Plate overprint: a zero ink channel leaves the destination plate.
    public static func overprint(top: DeviceCMYK, bottom: DeviceCMYK) -> DeviceCMYK {
        func plate(_ ink: Double, _ under: Double) -> Double {
            ink <= 0.0001 ? under : ink
        }
        return DeviceCMYK(
            c: plate(top.c, bottom.c),
            m: plate(top.m, bottom.m),
            y: plate(top.y, bottom.y),
            k: plate(top.k, bottom.k)
        )
    }
}

public struct RGBA: Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double
    /// Present when the color was authored as CMYK. RGB fields stay the device preview.
    public var cmykSource: DeviceCMYK?

    public init(r: Double, g: Double, b: Double, a: Double = 1, cmykSource: DeviceCMYK? = nil) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
        self.cmykSource = cmykSource
    }

    public init(cmyk: DeviceCMYK, a: Double = 1) {
        let preview = ColorPipeline.rgb(from: cmyk, alpha: a)
        self.r = preview.r
        self.g = preview.g
        self.b = preview.b
        self.a = a
        self.cmykSource = cmyk
    }

    public init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        if s.count >= 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        cmykSource = nil
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", channel(r), channel(g), channel(b))
    }

    public var svg: String {
        if a >= 0.999 { return hex }
        return String(format: "rgba(%.0f,%.0f,%.0f,%.3f)", r * 255, g * 255, b * 255, a)
    }

    private func channel(_ v: Double) -> Int {
        Int((min(1, max(0, v)) * 255).rounded())
    }

    public static let black = RGBA(r: 0, g: 0, b: 0)
    public static let white = RGBA(r: 1, g: 1, b: 1)
    public static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    public func inverted() -> RGBA { RGBA(r: 1 - r, g: 1 - g, b: 1 - b, a: a, cmykSource: nil) }

    public func grayscale() -> RGBA {
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return RGBA(r: y, g: y, b: y, a: a)
    }

    public func withSaturation(_ amount: Double) -> RGBA {
        let gray = grayscale()
        return RGBA(
            r: Math2.clamp(gray.r + (r - gray.r) * amount, 0, 1),
            g: Math2.clamp(gray.g + (g - gray.g) * amount, 0, 1),
            b: Math2.clamp(gray.b + (b - gray.b) * amount, 0, 1),
            a: a
        )
    }

    public var cmyk: (c: Double, m: Double, y: Double, k: Double) {
        if let source = cmykSource { return (source.c, source.m, source.y, source.k) }
        let device = ColorPipeline.cmyk(from: self)
        return (device.c, device.m, device.y, device.k)
    }

    public var deviceCMYK: DeviceCMYK {
        cmykSource ?? ColorPipeline.cmyk(from: self)
    }

    public func mixed(with other: RGBA, t: Double) -> RGBA {
        RGBA(
            r: Math2.lerp(r, other.r, t),
            g: Math2.lerp(g, other.g, t),
            b: Math2.lerp(b, other.b, t),
            a: Math2.lerp(a, other.a, t)
        )
    }
}

extension RGBA: Codable {
    enum CodingKeys: String, CodingKey { case r, g, b, a, cmykSource }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        r = try c.decode(Double.self, forKey: .r)
        g = try c.decode(Double.self, forKey: .g)
        b = try c.decode(Double.self, forKey: .b)
        a = try c.decodeIfPresent(Double.self, forKey: .a) ?? 1
        cmykSource = try c.decodeIfPresent(DeviceCMYK.self, forKey: .cmykSource)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(r, forKey: .r)
        try c.encode(g, forKey: .g)
        try c.encode(b, forKey: .b)
        try c.encode(a, forKey: .a)
        try c.encodeIfPresent(cmykSource, forKey: .cmykSource)
    }
}

public struct GradientStop: Codable, Equatable, Hashable, Sendable {
    public var color: RGBA
    public var location: Double
    public init(color: RGBA, location: Double) {
        self.color = color
        self.location = location
    }
}

public struct GradientPaint: Codable, Equatable, Hashable, Sendable {
    public var stops: [GradientStop]
    public var start: Vec2
    public var end: Vec2
    public init(stops: [GradientStop], start: Vec2, end: Vec2) {
        self.stops = stops
        self.start = start
        self.end = end
    }

    public static var blackWhite: GradientPaint {
        GradientPaint(
            stops: [
                GradientStop(color: .black, location: 0),
                GradientStop(color: .white, location: 1)
            ],
            start: Vec2(0, 0.5),
            end: Vec2(1, 0.5)
        )
    }
}

public enum Paint: Codable, Equatable, Hashable, Sendable {
    case solid(RGBA)
    case linear(GradientPaint)
    case radial(GradientPaint)

    public var solidColor: RGBA? {
        if case .solid(let c) = self { return c }
        return nil
    }

    public func mapColor(_ f: (RGBA) -> RGBA) -> Paint {
        switch self {
        case .solid(let c): return .solid(f(c))
        case .linear(var g):
            g.stops = g.stops.map { GradientStop(color: f($0.color), location: $0.location) }
            return .linear(g)
        case .radial(var g):
            g.stops = g.stops.map { GradientStop(color: f($0.color), location: $0.location) }
            return .radial(g)
        }
    }
}

public enum LineCap: String, Codable, Equatable, Hashable, Sendable { case butt, round, square }
public enum LineJoin: String, Codable, Equatable, Hashable, Sendable { case miter, round, bevel }
public enum BlendMode: String, Codable, Equatable, Hashable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, difference
}

public enum WidthProfile: String, Codable, Equatable, Hashable, Sendable {
    case uniform, linear, triangular, oval
}

public enum BrushVariationSource: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case fixed, random, pressure, stylusWheel, tilt, bearing, rotation
}

/// Illustrator variation row: the value at the low end of the controller and the value at the high end.
public struct BrushVariation: Codable, Equatable, Hashable, Sendable {
    public var source: BrushVariationSource
    public var minimum: Double
    public var maximum: Double

    public init(source: BrushVariationSource, minimum: Double, maximum: Double) {
        self.source = source
        self.minimum = minimum
        self.maximum = maximum
    }

    public static func fixed(_ value: Double) -> BrushVariation {
        BrushVariation(source: .fixed, minimum: value, maximum: value)
    }
}

public enum BrushColorization: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case none, tints, tintsAndShades, hueShift
}

public struct CalligraphicBrush: Codable, Equatable, Hashable, Sendable {
    public var angle: BrushVariation
    public var roundness: BrushVariation
    public var diameter: BrushVariation

    public init(angle: BrushVariation = .fixed(0), roundness: BrushVariation = .fixed(1), diameter: BrushVariation = .fixed(8)) {
        self.angle = angle
        self.roundness = roundness
        self.diameter = diameter
    }
}

public struct ScatterBrush: Codable, Equatable, Hashable, Sendable {
    public var size: BrushVariation
    public var spacing: BrushVariation
    public var scatter: BrushVariation
    public var rotation: BrushVariation
    public var rotationRelativeToPath: Bool
    public var colorization: BrushColorization
    public var artwork: PathItem

    public init(size: BrushVariation, spacing: BrushVariation, scatter: BrushVariation, rotation: BrushVariation, rotationRelativeToPath: Bool = true, colorization: BrushColorization = .tints, artwork: PathItem) {
        self.size = size
        self.spacing = spacing
        self.scatter = scatter
        self.rotation = rotation
        self.rotationRelativeToPath = rotationRelativeToPath
        self.colorization = colorization
        self.artwork = artwork
    }
}

public enum ArtBrushFit: String, Codable, Equatable, Hashable, Sendable {
    case stretchToFit, betweenGuides, proportional
}

public struct ArtBrush: Codable, Equatable, Hashable, Sendable {
    public var width: Double
    public var fit: ArtBrushFit
    public var startGuide: Double
    public var endGuide: Double
    public var flipAlong: Bool
    public var flipAcross: Bool
    public var adjustCorners: Bool
    public var colorization: BrushColorization
    public var artwork: PathItem

    public init(width: Double, fit: ArtBrushFit, startGuide: Double = 0.2, endGuide: Double = 0.8, flipAlong: Bool = false, flipAcross: Bool = false, adjustCorners: Bool = true, colorization: BrushColorization = .tints, artwork: PathItem) {
        self.width = width
        self.fit = fit
        self.startGuide = startGuide
        self.endGuide = endGuide
        self.flipAlong = flipAlong
        self.flipAcross = flipAcross
        self.adjustCorners = adjustCorners
        self.colorization = colorization
        self.artwork = artwork
    }
}

public enum PatternBrushFit: String, Codable, Equatable, Hashable, Sendable {
    case stretchToFit, addSpace, approximatePath
}

public struct PatternBrush: Codable, Equatable, Hashable, Sendable {
    public var side: PathItem
    public var outerCorner: PathItem?
    public var innerCorner: PathItem?
    public var start: PathItem?
    public var end: PathItem?
    public var fit: PatternBrushFit
    public var spacing: Double
    public var flipAlong: Bool
    public var flipAcross: Bool
    public var autoCorners: Bool
    public var colorization: BrushColorization

    public init(side: PathItem, outerCorner: PathItem? = nil, innerCorner: PathItem? = nil, start: PathItem? = nil, end: PathItem? = nil, fit: PatternBrushFit = .stretchToFit, spacing: Double = 0, flipAlong: Bool = false, flipAcross: Bool = false, autoCorners: Bool = true, colorization: BrushColorization = .tints) {
        self.side = side
        self.outerCorner = outerCorner
        self.innerCorner = innerCorner
        self.start = start
        self.end = end
        self.fit = fit
        self.spacing = spacing
        self.flipAlong = flipAlong
        self.flipAcross = flipAcross
        self.autoCorners = autoCorners
        self.colorization = colorization
    }
}

public enum BristleShape: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case roundPoint, roundBlunt, roundCurve, flatPoint, flatBlunt, flatCurve, fan
}

public struct BristleBrush: Codable, Equatable, Hashable, Sendable {
    public var shape: BristleShape
    public var size: Double
    public var density: Double
    public var thickness: Double
    public var paintOpacity: Double
    public var stiffness: Double

    public init(shape: BristleShape = .roundPoint, size: Double = 12, density: Double = 0.5, thickness: Double = 0.4, paintOpacity: Double = 0.8, stiffness: Double = 0.5) {
        self.shape = shape
        self.size = size
        self.density = density
        self.thickness = thickness
        self.paintOpacity = paintOpacity
        self.stiffness = stiffness
    }
}

public enum BrushDefinition: Equatable, Hashable, Sendable {
    case calligraphic(CalligraphicBrush)
    case scatter(ScatterBrush)
    case art(ArtBrush)
    case pattern(PatternBrush)
    case bristle(BristleBrush)

    public static func calligraphic(angle: Double, roundness: Double, diameter: Double = 8) -> BrushDefinition {
        .calligraphic(CalligraphicBrush(angle: .fixed(angle), roundness: .fixed(roundness), diameter: .fixed(diameter)))
    }

    public static func scatter(size: Double, spacing: Double, count: Int) -> BrushDefinition {
        .scatter(ScatterBrush(
            size: .fixed(size),
            spacing: .fixed(spacing),
            scatter: .fixed(Double(max(1, count)) * 2),
            rotation: .fixed(0),
            artwork: BrushArtwork.star(radius: max(1, size))
        ))
    }

    public static func art(width: Double) -> BrushDefinition {
        .art(ArtBrush(width: width, fit: .stretchToFit, artwork: BrushArtwork.taper))
    }

    public static func pattern(tile: Double) -> BrushDefinition {
        .pattern(PatternBrush(side: BrushArtwork.tile(tile), fit: .stretchToFit, autoCorners: true))
    }

    public static func bristle(count: Int, thickness: Double) -> BrushDefinition {
        .bristle(BristleBrush(density: min(1, Double(count) / 20), thickness: thickness, paintOpacity: 0.85, stiffness: 0.45))
    }
}

extension BrushDefinition: Codable {
    private enum Kind: String, Codable { case calligraphic, scatter, art, pattern, bristle }
    private enum Key: String, CodingKey { case kind, calligraphic, scatter, art, pattern, bristle, angle, roundness, size, spacing, count, width, tile, thickness }

    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: Key.self), keyed.contains(.kind) {
            switch try keyed.decode(Kind.self, forKey: .kind) {
            case .calligraphic: self = .calligraphic(try keyed.decode(CalligraphicBrush.self, forKey: .calligraphic))
            case .scatter: self = .scatter(try keyed.decode(ScatterBrush.self, forKey: .scatter))
            case .art: self = .art(try keyed.decode(ArtBrush.self, forKey: .art))
            case .pattern: self = .pattern(try keyed.decode(PatternBrush.self, forKey: .pattern))
            case .bristle: self = .bristle(try keyed.decode(BristleBrush.self, forKey: .bristle))
            }
            return
        }
        let keyed = try decoder.container(keyedBy: Key.self)
        if keyed.contains(.angle) || keyed.contains(.roundness) {
            let angle = try keyed.decodeIfPresent(Double.self, forKey: .angle) ?? 0
            let roundness = try keyed.decodeIfPresent(Double.self, forKey: .roundness) ?? 1
            self = .calligraphic(angle: angle, roundness: roundness)
            return
        }
        self = .calligraphic(angle: 0, roundness: 1)
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: Key.self)
        switch self {
        case .calligraphic(let brush):
            try keyed.encode(Kind.calligraphic, forKey: .kind)
            try keyed.encode(brush, forKey: .calligraphic)
        case .scatter(let brush):
            try keyed.encode(Kind.scatter, forKey: .kind)
            try keyed.encode(brush, forKey: .scatter)
        case .art(let brush):
            try keyed.encode(Kind.art, forKey: .kind)
            try keyed.encode(brush, forKey: .art)
        case .pattern(let brush):
            try keyed.encode(Kind.pattern, forKey: .kind)
            try keyed.encode(brush, forKey: .pattern)
        case .bristle(let brush):
            try keyed.encode(Kind.bristle, forKey: .kind)
            try keyed.encode(brush, forKey: .bristle)
        }
    }
}

public enum BrushArtwork {
    public static func star(radius: Double) -> PathItem {
        PathBuilder.star(center: .zero, radius: radius, points: 5, innerRatio: 0.45)
    }

    public static var taper: PathItem {
        PathItem(nodes: [
            .corner(Vec2(0, -0.15)), .corner(Vec2(0.75, -0.5)), .corner(Vec2(1, 0)),
            .corner(Vec2(0.75, 0.5)), .corner(Vec2(0, 0.15))
        ], closed: true, shape: .free)
    }

    public static func tile(_ side: Double) -> PathItem {
        PathBuilder.rectangle(Rect2(x: 0, y: -side / 2, width: max(2, side), height: max(2, side)))
    }
}

public struct StrokeSample: Codable, Equatable, Hashable, Sendable {
    public var point: Vec2
    public var pressure: Double
    public var tilt: Double
    public var bearing: Double
    public var rotation: Double
    public var wheel: Double

    public init(point: Vec2, pressure: Double = 1, tilt: Double = 0, bearing: Double = 0, rotation: Double = 0, wheel: Double = 0.5) {
        self.point = point
        self.pressure = pressure
        self.tilt = tilt
        self.bearing = bearing
        self.rotation = rotation
        self.wheel = wheel
    }
}

public struct StylusSample: Equatable, Sendable {
    public var pressure: Double
    public var tilt: Double
    public var bearing: Double
    public var rotation: Double
    public var wheel: Double

    public init(pressure: Double, tilt: Double, bearing: Double, rotation: Double, wheel: Double) {
        self.pressure = pressure
        self.tilt = tilt
        self.bearing = bearing
        self.rotation = rotation
        self.wheel = wheel
    }

    public static let mouse = StylusSample(pressure: 1, tilt: 0, bearing: 0, rotation: 0, wheel: 0.5)

    public var stroke: StrokeSample {
        StrokeSample(point: .zero, pressure: pressure, tilt: tilt, bearing: bearing, rotation: rotation, wheel: wheel)
    }
}

public struct StrokeStyle: Equatable, Hashable, Sendable {
    public var paint: Paint
    public var width: Double
    public var cap: LineCap
    public var join: LineJoin
    public var miterLimit: Double
    public var dash: [Double]
    public var brush: BrushDefinition?
    public var profile: WidthProfile
    /// Tablet samples recorded along a paintbrush stroke. Empty means a mouse stroke.
    public var samples: [StrokeSample]

    public init(paint: Paint = .solid(.black), width: Double = 1, cap: LineCap = .butt, join: LineJoin = .miter, miterLimit: Double = 4, dash: [Double] = [], brush: BrushDefinition? = nil, profile: WidthProfile = .uniform, samples: [StrokeSample] = []) {
        self.paint = paint
        self.width = width
        self.cap = cap
        self.join = join
        self.miterLimit = miterLimit
        self.dash = dash
        self.brush = brush
        self.profile = profile
        self.samples = samples
    }
}

extension StrokeStyle: Codable {
    enum CodingKeys: String, CodingKey { case paint, width, cap, join, miterLimit, dash, brush, profile, samples }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paint = try c.decodeIfPresent(Paint.self, forKey: .paint) ?? .solid(.black)
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 1
        cap = try c.decodeIfPresent(LineCap.self, forKey: .cap) ?? .butt
        join = try c.decodeIfPresent(LineJoin.self, forKey: .join) ?? .miter
        miterLimit = try c.decodeIfPresent(Double.self, forKey: .miterLimit) ?? 4
        dash = try c.decodeIfPresent([Double].self, forKey: .dash) ?? []
        brush = try c.decodeIfPresent(BrushDefinition.self, forKey: .brush)
        profile = try c.decodeIfPresent(WidthProfile.self, forKey: .profile) ?? .uniform
        samples = try c.decodeIfPresent([StrokeSample].self, forKey: .samples) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(paint, forKey: .paint)
        try c.encode(width, forKey: .width)
        try c.encode(cap, forKey: .cap)
        try c.encode(join, forKey: .join)
        try c.encode(miterLimit, forKey: .miterLimit)
        try c.encode(dash, forKey: .dash)
        try c.encodeIfPresent(brush, forKey: .brush)
        if profile != .uniform { try c.encode(profile, forKey: .profile) }
        if !samples.isEmpty { try c.encode(samples, forKey: .samples) }
    }
}

public enum LiveEffect: Codable, Equatable, Hashable, Sendable {
    case dropShadow(dx: Double, dy: Double, blur: Double, color: RGBA)
    case innerGlow(blur: Double, color: RGBA)
    case outerGlow(blur: Double, color: RGBA)
    case roundCorners(radius: Double)
    case feather(radius: Double)
    case scribble
    case warp(kind: String, bend: Double)
    case distort(kind: String, amount: Double)
    case offsetPath(distance: Double)
    case svgFilter(name: String)
    case extrude(depth: Double)
    case revolve(angle: Double)
    case inflate(amount: Double)
    case gaussianBlur(radius: Double)
    case rasterize(ppi: Double)
}

public struct Appearance: Equatable, Hashable, Sendable {
    public var fill: Paint?
    public var stroke: StrokeStyle?
    public var opacity: Double
    public var blend: BlendMode
    public var effects: [LiveEffect]
    public var additionalFills: [Paint]
    public var additionalStrokes: [StrokeStyle]
    public var overprintFill: Bool
    public var overprintStroke: Bool

    public init(fill: Paint? = .solid(.white), stroke: StrokeStyle? = StrokeStyle(), opacity: Double = 1, blend: BlendMode = .normal, effects: [LiveEffect] = [], additionalFills: [Paint] = [], additionalStrokes: [StrokeStyle] = [], overprintFill: Bool = false, overprintStroke: Bool = false) {
        self.fill = fill
        self.stroke = stroke
        self.opacity = opacity
        self.blend = blend
        self.effects = effects
        self.additionalFills = additionalFills
        self.additionalStrokes = additionalStrokes
        self.overprintFill = overprintFill
        self.overprintStroke = overprintStroke
    }

    public static var `default`: Appearance { Appearance() }
    public static var none: Appearance { Appearance(fill: nil, stroke: nil) }

    public var allFills: [Paint] {
        var list: [Paint] = []
        if let fill { list.append(fill) }
        list.append(contentsOf: additionalFills)
        return list
    }

    public var allStrokes: [StrokeStyle] {
        var list: [StrokeStyle] = []
        if let stroke { list.append(stroke) }
        list.append(contentsOf: additionalStrokes)
        return list
    }
}

extension Appearance: Codable {
    enum CodingKeys: String, CodingKey {
        case fill, stroke, opacity, blend, effects, additionalFills, additionalStrokes, overprintFill, overprintStroke
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill)
        stroke = try c.decodeIfPresent(StrokeStyle.self, forKey: .stroke)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        blend = try c.decodeIfPresent(BlendMode.self, forKey: .blend) ?? .normal
        effects = try c.decodeIfPresent([LiveEffect].self, forKey: .effects) ?? []
        additionalFills = try c.decodeIfPresent([Paint].self, forKey: .additionalFills) ?? []
        additionalStrokes = try c.decodeIfPresent([StrokeStyle].self, forKey: .additionalStrokes) ?? []
        overprintFill = try c.decodeIfPresent(Bool.self, forKey: .overprintFill) ?? false
        overprintStroke = try c.decodeIfPresent(Bool.self, forKey: .overprintStroke) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(fill, forKey: .fill)
        try c.encodeIfPresent(stroke, forKey: .stroke)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(blend, forKey: .blend)
        try c.encode(effects, forKey: .effects)
        if !additionalFills.isEmpty { try c.encode(additionalFills, forKey: .additionalFills) }
        if !additionalStrokes.isEmpty { try c.encode(additionalStrokes, forKey: .additionalStrokes) }
        if overprintFill { try c.encode(true, forKey: .overprintFill) }
        if overprintStroke { try c.encode(true, forKey: .overprintStroke) }
    }
}

public struct Swatch: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var paint: Paint
    public var global: Bool
    public var spot: Bool

    public init(id: UUID = UUID(), name: String, paint: Paint, global: Bool = false, spot: Bool = false) {
        self.id = id
        self.name = name
        self.paint = paint
        self.global = global
        self.spot = spot
    }
}
