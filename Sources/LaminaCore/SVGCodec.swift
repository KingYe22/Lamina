import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum SVGCodec {
    public static func write(_ document: LaminaDocument) -> String {
        let board = document.artboards.first?.rect ?? Rect2(x: 0, y: 0, width: 800, height: 600)
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:lamina=\"https://lamina.app/ns\" width=\"\(fmt(board.width))\" height=\"\(fmt(board.height))\" viewBox=\"\(fmt(board.x)) \(fmt(board.y)) \(fmt(board.width)) \(fmt(board.height))\">")
        lines.append("<metadata><lamina:doc version=\"\(document.version)\" title=\"\(esc(document.title))\" color-mode=\"\(document.colorMode.rawValue)\" units=\"\(document.units.rawValue)\" ppi=\"\(fmt(document.rasterPPI))\"/></metadata>")
        lines.append("<defs>")
        var gradIndex = 0
        func emitGrad(_ paint: Paint, id: String) -> String? {
            switch paint {
            case .linear(let g):
                lines.append("<linearGradient id=\"\(id)\" x1=\"\(fmt(g.start.x))\" y1=\"\(fmt(g.start.y))\" x2=\"\(fmt(g.end.x))\" y2=\"\(fmt(g.end.y))\" gradientUnits=\"objectBoundingBox\">")
                for stop in g.stops {
                    lines.append("<stop offset=\"\(fmt(stop.location * 100))%\" stop-color=\"\(stop.color.hex)\" stop-opacity=\"\(fmt(stop.color.a))\"/>")
                }
                lines.append("</linearGradient>")
                return "url(#\(id))"
            case .radial(let g):
                lines.append("<radialGradient id=\"\(id)\" cx=\"\(fmt(g.end.x))\" cy=\"\(fmt(g.end.y))\" r=\"\(fmt(max(0.01, g.start.distance(to: g.end))))\" gradientUnits=\"objectBoundingBox\">")
                for stop in g.stops {
                    lines.append("<stop offset=\"\(fmt(stop.location * 100))%\" stop-color=\"\(stop.color.hex)\" stop-opacity=\"\(fmt(stop.color.a))\"/>")
                }
                lines.append("</radialGradient>")
                return "url(#\(id))"
            case .solid:
                return nil
            }
        }
        for layer in document.layers {
            func walk(_ item: ArtItem) {
                switch item {
                case .path(let o):
                    collect(o.appearance)
                case .text(let o):
                    collect(o.appearance)
                case .compound(let o):
                    collect(o.appearance)
                case .group(let o):
                    o.children.forEach(walk)
                case .clip(let o):
                    walk(o.clipper)
                    o.contents.forEach(walk)
                default:
                    break
                }
            }
            func collect(_ appearance: Appearance) {
                if let fill = appearance.fill, case .solid = fill {} else if let fill = appearance.fill {
                    _ = emitGrad(fill, id: "g\(gradIndex)"); gradIndex += 1
                }
                if let stroke = appearance.stroke?.paint, case .solid = stroke {} else if let stroke = appearance.stroke?.paint {
                    _ = emitGrad(stroke, id: "g\(gradIndex)"); gradIndex += 1
                }
            }
            layer.items.forEach(walk)
        }
        // Gradients above were emitted while counting, but IDs must match writer below.
        // Rebuild defs deterministically instead.
        lines.removeAll { $0.hasPrefix("<linearGradient") || $0.hasPrefix("<radialGradient") || $0.hasPrefix("<stop") || $0 == "</linearGradient>" || $0 == "</radialGradient>" }
        gradIndex = 0
        var gradientIDs: [String: String] = [:]
        func paintRef(_ paint: Paint, key: String) -> String {
            switch paint {
            case .solid(let c):
                return c.hex
            case .linear, .radial:
                if let existing = gradientIDs[key] { return "url(#\(existing))" }
                let id = "g\(gradIndex)"
                gradIndex += 1
                gradientIDs[key] = id
                if case .linear(let g) = paint {
                    lines.append("<linearGradient id=\"\(id)\" x1=\"\(fmt(g.start.x))\" y1=\"\(fmt(g.start.y))\" x2=\"\(fmt(g.end.x))\" y2=\"\(fmt(g.end.y))\" gradientUnits=\"objectBoundingBox\">")
                    for stop in g.stops {
                        lines.append("<stop offset=\"\(fmt(stop.location * 100))%\" stop-color=\"\(stop.color.hex)\" stop-opacity=\"\(fmt(stop.color.a))\"/>")
                    }
                    lines.append("</linearGradient>")
                } else if case .radial(let g) = paint {
                    let r = max(0.05, g.start.distance(to: g.end))
                    lines.append("<radialGradient id=\"\(id)\" cx=\"\(fmt(g.start.x))\" cy=\"\(fmt(g.start.y))\" r=\"\(fmt(r))\" gradientUnits=\"objectBoundingBox\">")
                    for stop in g.stops {
                        lines.append("<stop offset=\"\(fmt(stop.location * 100))%\" stop-color=\"\(stop.color.hex)\" stop-opacity=\"\(fmt(stop.color.a))\"/>")
                    }
                    lines.append("</radialGradient>")
                }
                return "url(#\(id))"
            }
        }
        // The defs block is still open; paintRef appends into `lines` which currently ends at <defs>.
        // We'll call paintRef during element writing, so gradients must be known first.
        // Pre-walk to emit gradients now.
        var preKey = 0
        func pre(_ appearance: Appearance) {
            if let fill = appearance.fill {
                _ = paintRef(fill, key: "f\(preKey)")
            }
            if let stroke = appearance.stroke?.paint {
                _ = paintRef(stroke, key: "s\(preKey)")
            }
            preKey += 1
        }
        for layer in document.layers {
            func walk(_ item: ArtItem) {
                switch item {
                case .path(let o): pre(o.appearance)
                case .text(let o): pre(o.appearance)
                case .compound(let o): pre(o.appearance)
                case .group(let g): g.children.forEach(walk)
                case .clip(let c):
                    walk(c.clipper); c.contents.forEach(walk)
                default: break
                }
            }
            layer.items.forEach(walk)
        }
        lines.append("</defs>")
        lines.append("<g id=\"artboards\" data-role=\"artboards\">")
        for board in document.artboards {
            lines.append("<rect data-role=\"artboard\" id=\"\(board.id.uuidString)\" data-name=\"\(esc(board.name))\" x=\"\(fmt(board.rect.x))\" y=\"\(fmt(board.rect.y))\" width=\"\(fmt(board.rect.width))\" height=\"\(fmt(board.rect.height))\" fill=\"none\"/>")
        }
        lines.append("</g>")
        // Second pass uses the same preKey order. Reset and reuse gradientIDs.
        var useKey = 0
        func style(_ appearance: Appearance, keyBase: Int) -> String {
            var parts: [String] = []
            if let fill = appearance.fill {
                let ref = resolved(fill, key: "f\(keyBase)")
                parts.append("fill=\"\(ref)\"")
                if case .solid(let c) = fill, c.a < 0.999 { parts.append("fill-opacity=\"\(fmt(c.a))\"") }
            } else {
                parts.append("fill=\"none\"")
            }
            if let stroke = appearance.stroke {
                let ref = resolved(stroke.paint, key: "s\(keyBase)")
                parts.append("stroke=\"\(ref)\"")
                parts.append("stroke-width=\"\(fmt(stroke.width))\"")
                parts.append("stroke-linecap=\"\(stroke.cap.rawValue)\"")
                parts.append("stroke-linejoin=\"\(stroke.join.rawValue)\"")
                if !stroke.dash.isEmpty {
                    parts.append("stroke-dasharray=\"\(stroke.dash.map(fmt).joined(separator: " "))\"")
                }
            } else {
                parts.append("stroke=\"none\"")
            }
            if appearance.opacity < 0.999 { parts.append("opacity=\"\(fmt(appearance.opacity))\"") }
            return parts.joined(separator: " ")
        }
        func resolved(_ paint: Paint, key: String) -> String {
            switch paint {
            case .solid(let c): return c.hex
            default:
                if let id = gradientIDs[key] { return "url(#\(id))" }
                return "#000000"
            }
        }
        func transformAttr(_ t: Affine) -> String {
            if t == .identity { return "" }
            return " transform=\"\(t.svgMatrix)\""
        }
        func writeItem(_ item: ArtItem) {
            let hidden = item.hidden ? " display=\"none\"" : ""
            let locked = item.locked ? " data-locked=\"true\"" : ""
            switch item {
            case .path(let o):
                let key = useKey
                useKey += 1
                let shapeAttr = shapeAttribute(o.path.shape)
                lines.append("<path id=\"\(o.id.uuidString)\" data-name=\"\(esc(o.name))\" data-role=\"path\"\(shapeAttr) d=\"\(pathData(o.path))\" \(style(o.appearance, keyBase: key))\(transformAttr(o.transform))\(hidden)\(locked)/>")
            case .text(let o):
                let key = useKey
                useKey += 1
                if o.kind == .area {
                    lines.append("<text id=\"\(o.id.uuidString)\" data-name=\"\(esc(o.name))\" data-role=\"text\" data-kind=\"area\" data-frame=\"\(fmt(o.frame.x)),\(fmt(o.frame.y)),\(fmt(o.frame.width)),\(fmt(o.frame.height))\" x=\"\(fmt(o.frame.x))\" y=\"\(fmt(o.frame.y + o.fontSize))\" font-family=\"\(esc(o.fontName))\" font-size=\"\(fmt(o.fontSize))\" font-weight=\"\(o.bold ? "700" : "400")\" font-style=\"\(o.italic ? "italic" : "normal")\" text-decoration=\"\(o.underline ? "underline" : "none")\" text-anchor=\"\(anchor(o.alignment))\" letter-spacing=\"\(fmt(o.tracking))\" \(style(o.appearance, keyBase: key))\(transformAttr(o.transform))\(hidden)\(locked)>\(esc(o.string))</text>")
                } else {
                    lines.append("<text id=\"\(o.id.uuidString)\" data-name=\"\(esc(o.name))\" data-role=\"text\" data-kind=\"\(o.kind.rawValue)\" x=\"\(fmt(o.origin.x))\" y=\"\(fmt(o.origin.y))\" font-family=\"\(esc(o.fontName))\" font-size=\"\(fmt(o.fontSize))\" font-weight=\"\(o.bold ? "700" : "400")\" font-style=\"\(o.italic ? "italic" : "normal")\" text-decoration=\"\(o.underline ? "underline" : "none")\" text-anchor=\"\(anchor(o.alignment))\" letter-spacing=\"\(fmt(o.tracking))\" \(style(o.appearance, keyBase: key))\(transformAttr(o.transform))\(hidden)\(locked)>\(esc(o.string))</text>")
                }
            case .group(let g):
                lines.append("<g id=\"\(g.id.uuidString)\" data-name=\"\(esc(g.name))\" data-role=\"group\" data-symbol=\"\(g.isSymbol)\" data-live-paint=\"\(g.isLivePaint)\" opacity=\"\(fmt(g.opacity))\"\(transformAttr(g.transform))\(hidden)\(locked)>")
                g.children.forEach(writeItem)
                lines.append("</g>")
            case .compound(let o):
                let key = useKey
                useKey += 1
                let d = o.paths.map(pathData).joined()
                lines.append("<path id=\"\(o.id.uuidString)\" data-name=\"\(esc(o.name))\" data-role=\"compound\" fill-rule=\"\(o.fillRule == .evenOdd ? "evenodd" : "nonzero")\" d=\"\(d)\" \(style(o.appearance, keyBase: key))\(transformAttr(o.transform))\(hidden)\(locked)/>")
            case .clip(let o):
                let clipID = "clip-\(o.id.uuidString)"
                lines.append("<clipPath id=\"\(clipID)\">")
                if case .path(let p) = o.clipper {
                    lines.append("<path d=\"\(pathData(p.path))\"/>")
                }
                lines.append("</clipPath>")
                lines.append("<g id=\"\(o.id.uuidString)\" data-name=\"\(esc(o.name))\" data-role=\"clip\" clip-path=\"url(#\(clipID))\"\(transformAttr(o.transform))\(hidden)\(locked)>")
                writeItem(o.clipper)
                o.contents.forEach(writeItem)
                lines.append("</g>")
            case .placed(let o):
                lines.append("<rect id=\"\(o.id.uuidString)\" data-name=\"\(esc(o.name))\" data-role=\"placed\" data-kind=\"\(esc(o.kind))\" x=\"\(fmt(o.frame.x))\" y=\"\(fmt(o.frame.y))\" width=\"\(fmt(o.frame.width))\" height=\"\(fmt(o.frame.height))\" fill=\"#CCCCCC\"\(transformAttr(o.transform))\(hidden)\(locked)/>")
            case .mesh(let o):
                lines.append("<g id=\"\(o.id.uuidString)\" data-name=\"\(esc(o.name))\" data-role=\"mesh\"\(transformAttr(o.transform))\(hidden)\(locked)>")
                if o.columns > 0 && o.rows > 0 {
                    for r in 0..<o.rows {
                        for c in 0..<o.columns {
                            let idx = min(o.colors.count - 1, r * o.columns + c)
                            let color = o.colors.isEmpty ? RGBA.white : o.colors[max(0, idx)]
                            let x = o.origin.x + o.cell.x * Double(c)
                            let y = o.origin.y + o.cell.y * Double(r)
                            lines.append("<rect x=\"\(fmt(x))\" y=\"\(fmt(y))\" width=\"\(fmt(o.cell.x))\" height=\"\(fmt(o.cell.y))\" fill=\"\(color.hex)\"/>")
                        }
                    }
                }
                lines.append("</g>")
            case .graph(let o):
                lines.append("<g id=\"\(o.id.uuidString)\" data-name=\"\(esc(o.name))\" data-role=\"graph\" data-values=\"\(o.values.map(fmt).joined(separator: ","))\"\(transformAttr(o.transform))\(hidden)\(locked)>")
                let maxV = max(o.values.max() ?? 1, 0.001)
                let count = max(o.values.count, 1)
                let gap = o.frame.width / Double(count)
                for (i, value) in o.values.enumerated() {
                    let h = o.frame.height * (value / maxV)
                    let x = o.frame.x + gap * Double(i) + gap * 0.15
                    let y = o.frame.maxY - h
                    let w = gap * 0.7
                    lines.append("<rect x=\"\(fmt(x))\" y=\"\(fmt(y))\" width=\"\(fmt(w))\" height=\"\(fmt(h))\" fill=\"\(o.color.hex)\"/>")
                }
                lines.append("</g>")
            }
        }
        for (index, layer) in document.layers.enumerated() {
            let visible = layer.visible ? "true" : "false"
            let display = layer.visible ? "" : " display=\"none\""
            lines.append("<g id=\"\(layer.id.uuidString)\" data-role=\"layer\" data-name=\"\(esc(layer.name))\" data-visible=\"\(visible)\" data-locked=\"\(layer.locked)\" data-color=\"\(layer.colorHex)\" data-index=\"\(index)\"\(display)>")
            layer.items.forEach(writeItem)
            lines.append("</g>")
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    public static func read(_ svg: String) throws -> LaminaDocument {
        let parser = SVGParser()
        return try parser.parse(svg)
    }

    private static func fmt(_ n: Double) -> String {
        if n == n.rounded() && abs(n) < 1e9 { return String(Int(n.rounded())) }
        var s = String(format: "%.4f", n)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func anchor(_ align: TextAlign) -> String {
        switch align {
        case .left: return "start"
        case .center: return "middle"
        case .right, .justify: return "end"
        }
    }

    private static func shapeAttribute(_ shape: ShapeKind) -> String {
        switch shape {
        case .line: return " data-shape=\"line\""
        case .rectangle: return " data-shape=\"rectangle\""
        case .roundedRectangle(let r): return " data-shape=\"roundedRectangle\" data-radius=\"\(fmt(r))\""
        case .ellipse: return " data-shape=\"ellipse\""
        case .polygon(let n): return " data-shape=\"polygon\" data-sides=\"\(n)\""
        case .star(let n, let ratio): return " data-shape=\"star\" data-points=\"\(n)\" data-inner=\"\(fmt(ratio))\""
        case .free: return " data-shape=\"free\""
        }
    }

    static func pathData(_ path: PathItem) -> String {
        guard let first = path.nodes.first else { return "" }
        var d = "M \(fmt(first.anchor.x)) \(fmt(first.anchor.y))"
        let count = path.nodes.count
        let segments = path.closed ? count : max(0, count - 1)
        if count == 1 { return d }
        for i in 0..<segments {
            let a = path.nodes[i]
            let b = path.nodes[(i + 1) % count]
            let c1 = a.outHandle
            let c2 = b.inHandle
            if c1 == nil && c2 == nil {
                d += " L \(fmt(b.anchor.x)) \(fmt(b.anchor.y))"
            } else {
                let p1 = c1 ?? a.anchor
                let p2 = c2 ?? b.anchor
                d += " C \(fmt(p1.x)) \(fmt(p1.y)) \(fmt(p2.x)) \(fmt(p2.y)) \(fmt(b.anchor.x)) \(fmt(b.anchor.y))"
            }
        }
        if path.closed { d += " Z" }
        return d
    }
}

private final class SVGParser: NSObject, XMLParserDelegate {
    private struct Frame {
        var name: String
        var attrs: [String: String]
        var children: [ArtItem] = []
        var isLayer = false
        var isArtboardGroup = false
    }

    private var stack: [Frame] = []
    private var textBuffer = ""
    private var textAttrs: [String: String] = [:]
    private var capturingText = false
    private var document = LaminaDocument.blank()
    private var artboards: [Artboard] = []
    private var layers: [Layer] = []
    private var gradients: [String: Paint] = [:]
    private var currentGradientID: String?
    private var currentStops: [GradientStop] = []
    private var currentGradientKind: String?
    private var currentGradientAttrs: [String: String] = [:]
    private var title = "未标题-1"
    private var colorMode: ColorMode = .rgb
    private var units: UnitKind = .pt
    private var ppi: Double = 72
    private var error: Error?

    func parse(_ svg: String) throws -> LaminaDocument {
        guard let data = svg.data(using: .utf8) else { throw SVGError.badEncoding }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        if !parser.parse() {
            throw error ?? SVGError.invalid
        }
        if layers.isEmpty {
            var layer = Layer(name: "图层 1")
            layer.items = stack.first?.children ?? []
            layers = [layer]
        }
        if artboards.isEmpty {
            artboards = [Artboard(name: "画板 1", rect: Rect2(x: 0, y: 0, width: 800, height: 600))]
        }
        document = LaminaDocument(
            title: title,
            colorMode: colorMode,
            units: units,
            artboards: artboards,
            layers: layers,
            swatches: Swatch.defaults,
            rasterPPI: ppi
        )
        return document
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "svg":
            stack.append(Frame(name: "svg", attrs: attributes))
        case "doc":
            if let t = attributes["title"] { title = unescape(t) }
            if let m = attributes["color-mode"], let mode = ColorMode(rawValue: m) { colorMode = mode }
            if let u = attributes["units"], let unit = UnitKind(rawValue: u) { units = unit }
            if let p = attributes["ppi"], let v = Double(p) { ppi = v }
        case "linearGradient", "radialGradient":
            currentGradientID = attributes["id"]
            currentGradientKind = name
            currentGradientAttrs = attributes
            currentStops = []
        case "stop":
            let color = RGBA(hex: attributes["stop-color"] ?? "#000000")
            var offset = attributes["offset"] ?? "0"
            offset = offset.replacingOccurrences(of: "%", with: "")
            let loc = (Double(offset) ?? 0) / (offset == attributes["offset"] && !(attributes["offset"] ?? "").contains("%") && (Double(offset) ?? 0) > 1 ? 1 : ( (attributes["offset"] ?? "").contains("%") ? 100 : 1))
            let location: Double = {
                let raw = attributes["offset"] ?? "0"
                if raw.hasSuffix("%") { return (Double(raw.dropLast()) ?? 0) / 100 }
                return Double(raw) ?? 0
            }()
            _ = loc
            var c = color
            if let op = attributes["stop-opacity"], let a = Double(op) { c.a = a }
            currentStops.append(GradientStop(color: c, location: location))
        case "g":
            var frame = Frame(name: "g", attrs: attributes)
            if attributes["data-role"] == "layer" { frame.isLayer = true }
            if attributes["data-role"] == "artboards" { frame.isArtboardGroup = true }
            stack.append(frame)
        case "text":
            capturingText = true
            textBuffer = ""
            textAttrs = attributes
        case "path", "rect", "ellipse", "circle", "line", "polygon", "polyline":
            if attributes["data-role"] == "artboard" {
                let rect = Rect2(
                    x: num(attributes["x"]),
                    y: num(attributes["y"]),
                    width: num(attributes["width"]),
                    height: num(attributes["height"])
                )
                let id = uuid(attributes["id"])
                artboards.append(Artboard(id: id, name: unescape(attributes["data-name"] ?? "画板"), rect: rect))
            } else if let item = makeShape(name, attributes) {
                append(item)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingText { textBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "text":
            capturingText = false
            append(makeText())
        case "g":
            guard let frame = stack.popLast() else { return }
            if frame.isArtboardGroup { return }
            if frame.isLayer {
                let id = uuid(frame.attrs["id"])
                let layer = Layer(
                    id: id,
                    name: unescape(frame.attrs["data-name"] ?? "图层"),
                    visible: frame.attrs["data-visible"] != "false",
                    locked: frame.attrs["data-locked"] == "true",
                    items: frame.children,
                    colorHex: frame.attrs["data-color"] ?? "#1473E6"
                )
                layers.append(layer)
                return
            }
            if frame.attrs["data-role"] == "clip" {
                var contents = frame.children
                let clipper = contents.isEmpty
                    ? ArtItem.path(PathObject(path: PathItem(nodes: [], closed: true)))
                    : contents.removeFirst()
                let clip = ClipObject(
                    id: uuid(frame.attrs["id"]),
                    name: unescape(frame.attrs["data-name"] ?? "剪切组"),
                    clipper: clipper,
                    contents: contents,
                    transform: transform(frame.attrs["transform"]),
                    locked: frame.attrs["data-locked"] == "true",
                    hidden: frame.attrs["display"] == "none"
                )
                append(.clip(clip))
                return
            }
            let group = GroupObject(
                id: uuid(frame.attrs["id"]),
                name: unescape(frame.attrs["data-name"] ?? "组"),
                children: frame.children,
                transform: transform(frame.attrs["transform"]),
                locked: frame.attrs["data-locked"] == "true",
                hidden: frame.attrs["display"] == "none",
                opacity: num(frame.attrs["opacity"], 1),
                isSymbol: frame.attrs["data-symbol"] == "true",
                isLivePaint: frame.attrs["data-live-paint"] == "true"
            )
            if frame.attrs["data-role"] == "mesh" || frame.attrs["data-role"] == "graph" || frame.attrs["data-role"] == "group" || frame.attrs["data-role"] == nil {
                if frame.attrs["data-role"] == "graph" {
                    let values = (frame.attrs["data-values"] ?? "").split(separator: ",").compactMap { Double($0) }
                    let box = Rect2.enclosing(frame.children.flatMap { boundsPoints($0) })
                    let graph = GraphObject(id: uuid(frame.attrs["id"]), name: unescape(frame.attrs["data-name"] ?? "柱形图"), frame: box, values: values.isEmpty ? [1, 2, 3] : values)
                    append(.graph(graph))
                } else if frame.attrs["data-role"] == "mesh" {
                    append(.group(group))
                } else if !frame.children.isEmpty || frame.attrs["data-role"] == "group" {
                    append(.group(group))
                }
            }
        case "linearGradient", "radialGradient":
            if let id = currentGradientID {
                let start = Vec2(num(currentGradientAttrs["x1"], 0), num(currentGradientAttrs["y1"], 0))
                let end = Vec2(num(currentGradientAttrs["x2"], 1), num(currentGradientAttrs["y2"], 0))
                let stops = currentStops.isEmpty
                    ? [GradientStop(color: .black, location: 0), GradientStop(color: .white, location: 1)]
                    : currentStops
                let paint: Paint = name == "radialGradient"
                    ? .radial(GradientPaint(stops: stops, start: Vec2(num(currentGradientAttrs["cx"], 0.5), num(currentGradientAttrs["cy"], 0.5)), end: Vec2(num(currentGradientAttrs["cx"], 0.5) + num(currentGradientAttrs["r"], 0.5), num(currentGradientAttrs["cy"], 0.5))))
                    : .linear(GradientPaint(stops: stops, start: start, end: end))
                gradients[id] = paint
            }
            currentGradientID = nil
        default:
            break
        }
    }

    private func append(_ item: ArtItem) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].children.append(item)
    }

    private func makeText() -> ArtItem {
        let a = textAttrs
        let kind = TextKind(rawValue: a["data-kind"] ?? "point") ?? .point
        var origin = Vec2(num(a["x"]), num(a["y"]))
        var frame = Rect2.zero
        if let raw = a["data-frame"] {
            let p = raw.split(separator: ",").compactMap { Double($0) }
            if p.count == 4 { frame = Rect2(x: p[0], y: p[1], width: p[2], height: p[3]) }
        }
        let size = num(a["font-size"], 24)
        let align: TextAlign = {
            switch a["text-anchor"] {
            case "middle": return .center
            case "end": return .right
            default: return .left
            }
        }()
        let text = TextObject(
            id: uuid(a["id"]),
            name: unescape(a["data-name"] ?? "文字"),
            kind: kind,
            string: unescape(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)),
            origin: kind == .area ? Vec2(frame.x, frame.y) : origin,
            frame: frame,
            fontName: unescape(a["font-family"] ?? "PingFang SC"),
            fontSize: size,
            tracking: num(a["letter-spacing"]),
            alignment: align,
            bold: a["font-weight"] == "700" || a["font-weight"] == "bold",
            italic: a["font-style"] == "italic",
            underline: a["text-decoration"] == "underline",
            appearance: appearance(a),
            transform: transform(a["transform"]),
            locked: a["data-locked"] == "true",
            hidden: a["display"] == "none"
        )
        return .text(text)
    }

    private func makeShape(_ name: String, _ a: [String: String]) -> ArtItem? {
        if a["data-role"] == "placed" {
            let placed = PlacedObject(
                id: uuid(a["id"]),
                name: unescape(a["data-name"] ?? "置入"),
                kind: a["data-kind"] ?? "image",
                frame: Rect2(x: num(a["x"]), y: num(a["y"]), width: num(a["width"]), height: num(a["height"])),
                dataBase64: "",
                transform: transform(a["transform"]),
                locked: a["data-locked"] == "true",
                hidden: a["display"] == "none"
            )
            return .placed(placed)
        }
        let appearance = appearance(a)
        let xform = transform(a["transform"])
        let hidden = a["display"] == "none"
        let locked = a["data-locked"] == "true"
        let id = uuid(a["id"])
        let itemName = unescape(a["data-name"] ?? "路径")
        if a["data-role"] == "compound" || (a["d"]?.contains("Z") == true && (a["d"]?.components(separatedBy: "M").count ?? 0) > 2) && a["data-role"] == "compound" {
            let paths = splitSubpaths(a["d"] ?? "")
            let rule: FillRule = a["fill-rule"] == "evenodd" ? .evenOdd : .nonzero
            return .compound(CompoundObject(id: id, name: itemName, paths: paths, appearance: appearance, transform: xform, fillRule: rule, locked: locked, hidden: hidden))
        }
        let path: PathItem
        switch name {
        case "path":
            let sub = splitSubpaths(a["d"] ?? "")
            if a["data-role"] == "compound" || sub.count > 1 && a["fill-rule"] != nil {
                let rule: FillRule = a["fill-rule"] == "evenodd" ? .evenOdd : .nonzero
                return .compound(CompoundObject(id: id, name: itemName, paths: sub, appearance: appearance, transform: xform, fillRule: rule, locked: locked, hidden: hidden))
            }
            path = sub.first ?? PathItem(nodes: [], closed: false)
        case "rect":
            let rect = Rect2(x: num(a["x"]), y: num(a["y"]), width: num(a["width"]), height: num(a["height"]))
            let radius = num(a["rx"])
            path = radius > 0 ? PathBuilder.roundedRect(rect, radius: radius) : PathBuilder.rectangle(rect)
        case "ellipse", "circle":
            if name == "circle" {
                let cx = num(a["cx"]), cy = num(a["cy"]), r = num(a["r"])
                path = PathBuilder.ellipse(Rect2(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            } else {
                let cx = num(a["cx"]), cy = num(a["cy"]), rx = num(a["rx"]), ry = num(a["ry"])
                path = PathBuilder.ellipse(Rect2(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
            }
        case "line":
            path = PathBuilder.line(Vec2(num(a["x1"]), num(a["y1"])), Vec2(num(a["x2"]), num(a["y2"])))
        case "polygon", "polyline":
            let pts = points(a["points"] ?? "")
            path = PathItem(nodes: pts.map { .corner($0) }, closed: name == "polygon", shape: .free)
        default:
            return nil
        }
        var shaped = path
        if let shape = a["data-shape"] {
            switch shape {
            case "line": shaped.shape = .line
            case "rectangle": shaped.shape = .rectangle
            case "roundedRectangle": shaped.shape = .roundedRectangle(radius: num(a["data-radius"]))
            case "ellipse": shaped.shape = .ellipse
            case "polygon": shaped.shape = .polygon(sides: Int(num(a["data-sides"], 6)))
            case "star": shaped.shape = .star(points: Int(num(a["data-points"], 5)), innerRatio: num(a["data-inner"], 0.4))
            default: shaped.shape = .free
            }
        }
        return .path(PathObject(id: id, name: itemName, path: shaped, appearance: appearance, transform: xform, locked: locked, hidden: hidden))
    }

    private func appearance(_ a: [String: String]) -> Appearance {
        let fill = paint(a["fill"], opacity: a["fill-opacity"])
        var stroke: StrokeStyle?
        if let s = a["stroke"], s != "none" {
            var style = StrokeStyle(paint: paint(s, opacity: a["stroke-opacity"]) ?? .solid(.black), width: num(a["stroke-width"], 1))
            if let cap = a["stroke-linecap"], let v = LineCap(rawValue: cap) { style.cap = v }
            if let join = a["stroke-linejoin"], let v = LineJoin(rawValue: join) { style.join = v }
            if let dash = a["stroke-dasharray"], dash != "none" {
                style.dash = dash.split(separator: " ").compactMap { Double($0) }
            }
            stroke = style
        }
        let opacity = num(a["opacity"], 1)
        let fillPaint: Paint? = a["fill"] == "none" ? nil : fill
        return Appearance(fill: fillPaint, stroke: stroke, opacity: opacity)
    }

    private func paint(_ raw: String?, opacity: String?) -> Paint? {
        guard var raw else { return .solid(.black) }
        raw = raw.trimmingCharacters(in: .whitespaces)
        if raw == "none" { return nil }
        if raw.hasPrefix("url(#"), let id = raw.dropFirst(5).split(separator: ")").first {
            return gradients[String(id)] ?? .linear(.blackWhite)
        }
        var color = RGBA(hex: raw)
        if let opacity, let a = Double(opacity) { color.a = a }
        return .solid(color)
    }

    private func splitSubpaths(_ d: String) -> [PathItem] {
        let commands = SVGPath.parse(d)
        if commands.isEmpty { return [] }
        var current: [PathNode] = []
        var closed = false
        var paths: [PathItem] = []
        func flush() {
            if !current.isEmpty {
                paths.append(PathItem(nodes: current, closed: closed, shape: .free))
            }
            current = []
            closed = false
        }
        var cx = 0.0, cy = 0.0
        var sx = 0.0, sy = 0.0
        for cmd in commands {
            switch cmd {
            case .move(let x, let y, let relative):
                if !current.isEmpty { flush() }
                cx = relative ? cx + x : x
                cy = relative ? cy + y : y
                sx = cx; sy = cy
                current = [PathNode.corner(Vec2(cx, cy))]
            case .line(let x, let y, let relative):
                cx = relative ? cx + x : x
                cy = relative ? cy + y : y
                current.append(.corner(Vec2(cx, cy)))
            case .cubic(let x1, let y1, let x2, let y2, let x, let y, let relative):
                let a1x = relative ? cx + x1 : x1
                let a1y = relative ? cy + y1 : y1
                let a2x = relative ? cx + x2 : x2
                let a2y = relative ? cy + y2 : y2
                let nx = relative ? cx + x : x
                let ny = relative ? cy + y : y
                if !current.isEmpty {
                    let last = current.count - 1
                    current[last].outHandle = Vec2(a1x, a1y)
                }
                current.append(PathNode(anchor: Vec2(nx, ny), inHandle: Vec2(a2x, a2y), corner: .smooth))
                cx = nx; cy = ny
            case .close:
                closed = true
                if current.count >= 2,
                   let first = current.first?.anchor,
                   let last = current.last?.anchor,
                   first.almostEqual(last, eps: 0.05) {
                    let closing = current.removeLast()
                    if let incoming = closing.inHandle {
                        current[0].inHandle = incoming
                    }
                }
                cx = sx; cy = sy
                flush()
            }
        }
        flush()
        return paths
    }

    private func transform(_ raw: String?) -> Affine {
        guard let raw, raw.contains("matrix") else { return .identity }
        let nums = raw.replacingOccurrences(of: "matrix(", with: "").replacingOccurrences(of: ")", with: "")
            .split { ", ".contains($0) }.compactMap { Double($0) }
        guard nums.count == 6 else { return .identity }
        return Affine(a: nums[0], b: nums[1], c: nums[2], d: nums[3], tx: nums[4], ty: nums[5])
    }

    private func points(_ raw: String) -> [Vec2] {
        let nums = raw.split { ", ".contains($0) }.compactMap { Double($0) }
        var pts: [Vec2] = []
        var i = 0
        while i + 1 < nums.count {
            pts.append(Vec2(nums[i], nums[i + 1]))
            i += 2
        }
        return pts
    }

    private func boundsPoints(_ item: ArtItem) -> [Vec2] {
        switch item {
        case .path(let o): return o.path.nodes.map(\.anchor)
        default: return []
        }
    }

    private func num(_ raw: String?, _ fallback: Double = 0) -> Double {
        guard let raw else { return fallback }
        return Double(raw) ?? fallback
    }

    private func uuid(_ raw: String?) -> UUID {
        if let raw, let id = UUID(uuidString: raw) { return id }
        return UUID()
    }

    private func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

private enum SVGError: Error { case badEncoding, invalid }

private enum SVGCommand {
    case move(Double, Double, Bool)
    case line(Double, Double, Bool)
    case cubic(Double, Double, Double, Double, Double, Double, Bool)
    case close
}

private enum SVGPath {
    static func parse(_ d: String) -> [SVGCommand] {
        var commands: [SVGCommand] = []
        let scalars = Array(d)
        var i = 0
        func skip() {
            while i < scalars.count && " \n\t\r,".contains(scalars[i]) { i += 1 }
        }
        func readNumber() -> Double? {
            skip()
            guard i < scalars.count else { return nil }
            let start = i
            if scalars[i] == "+" || scalars[i] == "-" { i += 1 }
            var saw = false
            while i < scalars.count && (scalars[i].isNumber || scalars[i] == ".") {
                saw = true
                i += 1
            }
            if i < scalars.count && (scalars[i] == "e" || scalars[i] == "E") {
                i += 1
                if i < scalars.count && (scalars[i] == "+" || scalars[i] == "-") { i += 1 }
                while i < scalars.count && scalars[i].isNumber { i += 1 }
            }
            if !saw && start == i { return nil }
            // If we consumed only a sign, rewind.
            if i == start { return nil }
            return Double(String(scalars[start..<i]))
        }
        while i < scalars.count {
            skip()
            guard i < scalars.count else { break }
            let op = scalars[i]
            if !"MmLlHhVvCcSsQqTtZz".contains(op) {
                i += 1
                continue
            }
            i += 1
            let rel = op.isLowercase
            switch op.lowercased() {
            case "m":
                var first = true
                while let x = readNumber(), let y = readNumber() {
                    commands.append(first ? .move(x, y, rel) : .line(x, y, rel))
                    first = false
                }
            case "l":
                while let x = readNumber(), let y = readNumber() {
                    commands.append(.line(x, y, rel))
                }
            case "h":
                while let x = readNumber() {
                    commands.append(.line(x, 0, rel))
                }
            case "v":
                while let y = readNumber() {
                    commands.append(.line(0, y, rel))
                }
            case "c":
                while let x1 = readNumber(), let y1 = readNumber(), let x2 = readNumber(), let y2 = readNumber(), let x = readNumber(), let y = readNumber() {
                    commands.append(.cubic(x1, y1, x2, y2, x, y, rel))
                }
            case "z":
                commands.append(.close)
            default:
                // Skip unsupported command's numbers.
                while readNumber() != nil {}
            }
        }
        return commands
    }
}
