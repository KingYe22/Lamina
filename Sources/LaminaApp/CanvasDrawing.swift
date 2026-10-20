import AppKit
import LaminaCore
import PDFKit

struct DrawOptions {
    var outline = false
    var showArtboards = true
    var showEdges = true
    var showBoundingBox = true
    var showGuides = true
    var showGrid = false
    var transparencyGrid = false
    var showPerspective = false
    var perspectivePlane = 1
    var overprintPreview = false
    var zoom: Double = 1
    var pan = Vec2.zero
    var viewport = Vec2(1200, 800)
    var selection: [UUID] = []
    var selectedAnchors: Set<UUID> = []
    var tool: Tool = .selection
    var penNodes: [PathNode] = []
    var hover = Vec2.zero
    var hint: EditorModel.InteractionHint = .none
    var showAnchors = true
    var showHandles = true
    var rubberBand = true
    var livePaths: [PathItem] = []
    var liveOutline = false
    var perspective: PerspectiveGrid?
    var glyphNudge: [UUID: Vec2] = [:]
}

enum CanvasDrawing {
    private static let imageCache = NSCache<NSString, CGImage>()

    static func renderPNG(_ document: LaminaDocument, scale: CGFloat) -> Data? {
        let board = document.currentArtboard.rect
        let width = max(1, Int((board.width * Double(scale)).rounded()))
        let height = max(1, Int((board.height * Double(scale)).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: CGFloat(-board.x), y: CGFloat(-board.y))
        var options = DrawOptions()
        options.showArtboards = false
        options.outline = false
        drawArtwork(document, options: options, in: context)
        guard let image = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    static func draw(_ document: LaminaDocument, options: DrawOptions, in context: CGContext, size: CGSize) {
        applyTransform(context, size: size, zoom: options.zoom, pan: options.pan)
        if options.showGrid {
            drawGrid(options, in: context)
        }
        if options.showArtboards {
            for (index, board) in document.artboards.enumerated() {
                let rect = cgRect(board.rect)
                if options.transparencyGrid {
                    drawChecker(rect, in: context)
                } else if !options.outline {
                    context.setFillColor(CGColor(gray: 1, alpha: 1))
                    context.fill(rect)
                }
                context.setStrokeColor(index == document.activeArtboard ? Theme.accent.cgColor : CGColor(gray: 0.55, alpha: 1))
                context.setLineWidth(1 / options.zoom)
                context.stroke(rect)
            }
        }
        if options.showGuides {
            context.setStrokeColor(Theme.guide.cgColor)
            context.setLineWidth(0.75 / options.zoom)
            for guide in document.guides {
                context.beginPath()
                if guide.axis == .horizontal {
                    context.move(to: CGPoint(x: -100000, y: guide.position))
                    context.addLine(to: CGPoint(x: 100000, y: guide.position))
                } else {
                    context.move(to: CGPoint(x: guide.position, y: -100000))
                    context.addLine(to: CGPoint(x: guide.position, y: 100000))
                }
                context.strokePath()
            }
        }
        if options.showPerspective {
            drawPerspective(document, plane: options.perspectivePlane, grid: options.perspective, zoom: options.zoom, in: context)
        }
        drawArtwork(document, options: options, in: context)
        drawSelection(document, options: options, in: context)
        drawPen(options, in: context)
        drawHint(options, in: context)
        drawLive(document, options, in: context)
    }

    static func applyTransform(_ context: CGContext, size: CGSize, zoom: Double, pan: Vec2) {
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: CGFloat(zoom), y: CGFloat(-zoom))
        context.translateBy(x: CGFloat(-pan.x), y: CGFloat(-pan.y))
    }

    private static func drawArtwork(_ document: LaminaDocument, options: DrawOptions, in context: CGContext) {
        for layer in document.layers where layer.visible {
            let outline = options.outline || layer.outline
            for item in layer.items {
                drawItem(item, outline: outline, zoom: options.zoom, showEdges: options.showEdges, overprint: options.overprintPreview, nudge: options.glyphNudge[item.id] ?? .zero, in: context)
            }
        }
    }

    private static func drawItem(_ item: ArtItem, outline: Bool, zoom: Double, showEdges: Bool, overprint: Bool, nudge: Vec2 = .zero, in context: CGContext) {
        if item.hidden { return }
        context.saveGState()
        context.concatenate(cgAffine(item.transform))
        switch item {
        case .path(let object):
            strokeAndFill(path: object.path, widths: object.widths, appearance: object.appearance, outline: outline, zoom: zoom, overprint: overprint, in: context)
        case .compound(let object):
            let combined = CGMutablePath()
            for path in object.paths { combined.addPath(cgPath(path)) }
            paint(source: nil, path: combined, widths: [], bounds: box(of: combined), appearance: object.appearance, evenOdd: object.fillRule == .evenOdd, outline: outline, zoom: zoom, overprint: overprint, in: context)
        case .text(let object):
            drawText(object, outline: outline, nudge: nudge, in: context)
        case .group(let object):
            context.setAlpha(CGFloat(object.opacity))
            for child in object.children {
                drawItem(child, outline: outline, zoom: zoom, showEdges: showEdges, overprint: overprint, in: context)
            }
        case .clip(let object):
            if let clip = clipPath(object.clipper) {
                context.addPath(clip)
                context.clip()
            }
            for child in object.contents {
                drawItem(child, outline: outline, zoom: zoom, showEdges: showEdges, overprint: overprint, in: context)
            }
        case .placed(let object):
            drawPlaced(object, in: context)
        case .mesh(let object):
            drawMesh(object, in: context)
        case .graph(let object):
            drawGraph(object, outline: outline, zoom: zoom, overprint: overprint, in: context)
        }
        context.restoreGState()
    }

    private static func strokeAndFill(path: PathItem, widths: [WidthPoint], appearance: Appearance, outline: Bool, zoom: Double, overprint: Bool, in context: CGContext) {
        let cg = cgPath(path)
        paint(source: path, path: cg, widths: widths, bounds: box(of: cg), appearance: appearance, evenOdd: false, outline: outline, zoom: zoom, overprint: overprint, in: context)
    }

    private static func paint(source: PathItem?, path: CGPath, widths: [WidthPoint], bounds: CGRect, appearance: Appearance, evenOdd: Bool, outline: Bool, zoom: Double, overprint: Bool, in context: CGContext) {
        context.saveGState()
        context.setAlpha(CGFloat(appearance.opacity))
        context.setBlendMode(cgBlend(appearance.blend))
        if outline {
            context.addPath(path)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(CGFloat(1 / max(zoom, 0.01)))
            context.strokePath()
            context.restoreGState()
            return
        }
        if let shadow = appearance.effects.compactMap({ shadowOffset($0) }).first {
            context.setShadow(offset: CGSize(width: shadow.dx, height: shadow.dy), blur: CGFloat(shadow.blur), color: shadow.color.cgColor)
        }
        for fill in appearance.allFills {
            if overprint && appearance.overprintFill { context.setBlendMode(.multiply) }
            fillPath(path, bounds: bounds, paint: fill, evenOdd: evenOdd, in: context)
            context.setBlendMode(cgBlend(appearance.blend))
        }
        context.setShadow(offset: .zero, blur: 0)
        for effect in appearance.effects {
            if case .innerGlow(let blur, let color) = effect {
                context.saveGState()
                context.addPath(path)
                context.clip()
                context.addPath(path)
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(CGFloat(max(1, blur * 2)))
                context.strokePath()
                context.restoreGState()
            }
        }
        for stroke in appearance.allStrokes {
            if overprint && appearance.overprintStroke { context.setBlendMode(.multiply) }
            drawStroke(stroke, source: source, path: path, widths: widths, bounds: bounds, overprint: overprint, in: context)
            context.setBlendMode(cgBlend(appearance.blend))
        }
        context.restoreGState()
    }

    private static func shadowOffset(_ effect: LiveEffect) -> (dx: Double, dy: Double, blur: Double, color: RGBA)? {
        switch effect {
        case .dropShadow(let dx, let dy, let blur, let color):
            return (dx, dy, blur, color)
        case .outerGlow(let blur, let color):
            return (0, 0, blur, color)
        case .gaussianBlur(let radius), .feather(let radius):
            return (0, 0, radius, RGBA(r: 0, g: 0, b: 0, a: 0.35))
        default:
            return nil
        }
    }

    private static func drawStroke(_ stroke: StrokeStyle, source: PathItem?, path: CGPath, widths: [WidthPoint], bounds: CGRect, overprint: Bool, in context: CGContext) {
        let variable = stroke.brush != nil || stroke.profile != .uniform || !widths.isEmpty
        guard variable, let source else {
            strokePath(path, bounds: bounds, stroke: stroke, in: context)
            return
        }
        if stroke.brush != nil {
            for item in BrushEngine.expand(path: source, stroke: stroke) {
                drawItem(item, outline: false, zoom: 1, showEdges: false, overprint: overprint, in: context)
            }
            return
        }
        let outline = WidthStroke.outline(path: source, widths: widths, profile: stroke.profile, base: stroke.width)
        let cg = cgPath(outline)
        fillPath(cg, bounds: box(of: cg), paint: stroke.paint, evenOdd: false, in: context)
    }

    private static func fillPath(_ path: CGPath, bounds: CGRect, paint: Paint, evenOdd: Bool, in context: CGContext) {
        switch paint {
        case .solid(let color):
            context.addPath(path)
            context.setFillColor(color.cgColor)
            context.fillPath(using: evenOdd ? .evenOdd : .winding)
        case .linear(let gradient):
            context.saveGState()
            context.addPath(path)
            context.clip(using: evenOdd ? .evenOdd : .winding)
            if let shading = cgGradient(gradient) {
                let start = unitPoint(gradient.start, in: bounds)
                let end = unitPoint(gradient.end, in: bounds)
                context.drawLinearGradient(shading, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            context.restoreGState()
        case .radial(let gradient):
            context.saveGState()
            context.addPath(path)
            context.clip(using: evenOdd ? .evenOdd : .winding)
            if let shading = cgGradient(gradient) {
                let center = unitPoint(gradient.start, in: bounds)
                let edge = unitPoint(gradient.end, in: bounds)
                let radius = hypot(edge.x - center.x, edge.y - center.y)
                context.drawRadialGradient(shading, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(radius, 1), options: [.drawsAfterEndLocation])
            }
            context.restoreGState()
        }
    }

    private static func strokePath(_ path: CGPath, bounds: CGRect, stroke: StrokeStyle, in context: CGContext) {
        context.saveGState()
        context.addPath(path)
        context.setLineWidth(CGFloat(stroke.width))
        context.setLineCap(stroke.cap == .round ? .round : stroke.cap == .square ? .square : .butt)
        context.setLineJoin(stroke.join == .round ? .round : stroke.join == .bevel ? .bevel : .miter)
        context.setMiterLimit(CGFloat(stroke.miterLimit))
        if !stroke.dash.isEmpty {
            context.setLineDash(phase: 0, lengths: stroke.dash.map { CGFloat($0) })
        }
        switch stroke.paint {
        case .solid(let color):
            context.setStrokeColor(color.cgColor)
            context.strokePath()
        default:
            context.replacePathWithStrokedPath()
            let stroked = context.path ?? path
            fillPath(stroked, bounds: bounds, paint: stroke.paint, evenOdd: false, in: context)
        }
        context.restoreGState()
    }

    private static func drawText(_ object: TextObject, outline: Bool, nudge: Vec2 = .zero, in context: CGContext) {
        let color = outline ? RGBA.black : (object.appearance.fill?.solidColor ?? .black)
        let font = ctFont(name: object.fontName, size: object.fontSize, bold: object.bold, italic: object.italic)
        let paragraph = NSMutableParagraphStyle()
        switch object.alignment {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        case .justify: paragraph.alignment = .justified
        }
        let attributed = NSAttributedString(string: object.string.isEmpty ? " " : object.string, attributes: [
            .font: font,
            .foregroundColor: color.nsColor,
            .paragraphStyle: paragraph,
            .kern: NSNumber(value: object.tracking),
            .underlineStyle: object.underline ? NSUnderlineStyle.single.rawValue : 0
        ])
        context.saveGState()
        context.setAlpha(CGFloat(object.appearance.opacity))
        if object.kind == .area && !object.frame.isEmpty {
            context.translateBy(x: CGFloat(object.frame.x), y: CGFloat(object.frame.y + object.frame.height))
            context.scaleBy(x: 1, y: -1)
            let rect = CGRect(x: 0, y: 0, width: object.frame.width, height: object.frame.height)
            attributed.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
        } else if object.leading < 0 {
            context.translateBy(x: CGFloat(object.origin.x + nudge.x), y: CGFloat(object.origin.y + nudge.y))
            var y = 0.0
            for character in object.string {
                let piece = NSAttributedString(string: String(character), attributes: [
                    .font: font, .foregroundColor: color.nsColor
                ])
                context.saveGState()
                context.translateBy(x: 0, y: CGFloat(y + object.fontSize))
                context.scaleBy(x: 1, y: -1)
                piece.draw(at: .zero)
                context.restoreGState()
                y += object.fontSize * 1.15
            }
        } else {
            context.translateBy(x: CGFloat(object.origin.x + nudge.x), y: CGFloat(object.origin.y + nudge.y))
            context.scaleBy(x: CGFloat(object.horizontalScale), y: -1)
            attributed.draw(at: .zero)
        }
        context.restoreGState()
    }

    private static func ctFont(name: String, size: Double, bold: Bool, italic: Bool) -> NSFont {
        let base = NSFont(name: name, size: CGFloat(size)) ?? NSFont.systemFont(ofSize: CGFloat(size))
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if traits.isEmpty { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: traits)
    }

    private static func drawPlaced(_ object: PlacedObject, in context: CGContext) {
        let rect = cgRect(object.frame)
        let key = "\(object.id.uuidString)|\(object.kind)|\(object.dataBase64.count)" as NSString
        if let cached = imageCache.object(forKey: key) {
            context.draw(cached, in: rect)
            return
        }
        guard let data = Data(base64Encoded: object.dataBase64) else {
            context.setFillColor(CGColor(gray: 0.85, alpha: 1))
            context.fill(rect)
            return
        }
        let image: CGImage?
        if object.kind.hasPrefix("pdf:") {
            let index = Int(object.kind.dropFirst(4)) ?? 0
            image = pdfImage(data: data, page: index, pointSize: object.frame.size)
        } else {
            image = NSImage(data: data).flatMap { cgImage(from: $0) }
        }
        if let image {
            imageCache.setObject(image, forKey: key)
            context.draw(image, in: rect)
        } else {
            context.setStrokeColor(CGColor(gray: 0.4, alpha: 1))
            context.stroke(rect)
        }
    }

    private static func pdfImage(data: Data, page index: Int, pointSize: Vec2) -> CGImage? {
        guard let document = PDFDocument(data: data), let page = document.page(at: index) else { return nil }
        let size = NSSize(width: CGFloat(max(pointSize.x * 2, 2)), height: CGFloat(max(pointSize.y * 2, 2)))
        let thumb = page.thumbnail(of: size, for: .mediaBox)
        return cgImage(from: thumb)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposed = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    private static func drawMesh(_ object: MeshObject, in context: CGContext) {
        let cols = max(object.columns, 1)
        let rows = max(object.rows, 1)
        for row in 0..<rows {
            for col in 0..<cols {
                let index = min(object.colors.count - 1, row * cols + col)
                let color = object.colors.indices.contains(index) ? object.colors[index] : .white
                let rect = CGRect(
                    x: object.origin.x + object.cell.x * Double(col),
                    y: object.origin.y + object.cell.y * Double(row),
                    width: object.cell.x,
                    height: object.cell.y
                )
                context.setFillColor(color.cgColor)
                context.fill(rect)
            }
        }
    }

    private static func drawGraph(_ object: GraphObject, outline: Bool, zoom: Double, overprint: Bool, in context: CGContext) {
        let items = ChartBuilder.items(kind: object.kind, frame: object.frame, series: object.plotSeries, color: object.color)
        for item in items {
            drawItem(item, outline: outline, zoom: zoom, showEdges: false, overprint: overprint, in: context)
        }
    }

    private static func drawSelection(_ document: LaminaDocument, options: DrawOptions, in context: CGContext) {
        guard options.showEdges else { return }
        let boxes = options.selection.compactMap { document.item(id: $0) }.map { ItemGeometry.bounds($0) }.filter { !$0.isEmpty }
        guard let first = boxes.first else { return }
        let union = boxes.dropFirst().reduce(first) { $0.union($1) }
        context.saveGState()
        context.setStrokeColor(Theme.accent.cgColor)
        context.setLineWidth(1 / options.zoom)
        context.stroke(cgRect(union))
        if options.showBoundingBox, options.tool == .selection || options.tool == .freeTransform {
            let handles = [
                Vec2(union.minX, union.minY), Vec2(union.midX, union.minY), Vec2(union.maxX, union.minY),
                Vec2(union.maxX, union.midY), Vec2(union.maxX, union.maxY), Vec2(union.midX, union.maxY),
                Vec2(union.minX, union.maxY), Vec2(union.minX, union.midY)
            ]
            let side = 6 / options.zoom
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            for handle in handles {
                context.fill(CGRect(x: handle.x - side / 2, y: handle.y - side / 2, width: side, height: side))
                context.stroke(CGRect(x: handle.x - side / 2, y: handle.y - side / 2, width: side, height: side))
            }
        }
        if options.tool == .directSelection || options.tool == .pen || options.tool == .convertAnchor || options.tool == .addAnchor || options.tool == .deleteAnchor || options.tool == .curvature {
            for id in options.selection {
                guard let item = document.item(id: id), case .path(let object) = item else { continue }
                context.saveGState()
                context.concatenate(cgAffine(object.transform))
                let side = 5 / options.zoom
                for node in object.path.nodes where options.showAnchors {
                    let selected = options.selectedAnchors.contains(node.id)
                    context.setFillColor(selected ? Theme.accent.cgColor : CGColor(gray: 1, alpha: 1))
                    context.fill(CGRect(x: node.anchor.x - side / 2, y: node.anchor.y - side / 2, width: side, height: side))
                    context.stroke(CGRect(x: node.anchor.x - side / 2, y: node.anchor.y - side / 2, width: side, height: side))
                    if options.showHandles, let handle = node.inHandle {
                        strokeHandle(from: node.anchor, to: handle, zoom: options.zoom, in: context)
                    }
                    if options.showHandles, let handle = node.outHandle {
                        strokeHandle(from: node.anchor, to: handle, zoom: options.zoom, in: context)
                    }
                }
                context.restoreGState()
            }
        }
        context.restoreGState()
    }

    private static func strokeHandle(from anchor: Vec2, to handle: Vec2, zoom: Double, in context: CGContext) {
        context.beginPath()
        context.move(to: CGPoint(x: anchor.x, y: anchor.y))
        context.addLine(to: CGPoint(x: handle.x, y: handle.y))
        context.setStrokeColor(Theme.accent.cgColor)
        context.setLineWidth(0.75 / zoom)
        context.strokePath()
        let side = 4 / zoom
        context.setFillColor(Theme.accent.cgColor)
        context.fillEllipse(in: CGRect(x: handle.x - side / 2, y: handle.y - side / 2, width: side, height: side))
    }

    private static func drawPen(_ options: DrawOptions, in context: CGContext) {
        let penLike: Set<Tool> = [.pen, .curvature, .addAnchor, .deleteAnchor, .convertAnchor]
        guard penLike.contains(options.tool), options.penNodes.count > 0 else { return }
        context.beginPath()
        if let first = options.penNodes.first {
            context.move(to: CGPoint(x: first.anchor.x, y: first.anchor.y))
        }
        for (index, node) in options.penNodes.enumerated().dropFirst() {
            let prev = options.penNodes[index - 1]
            let c1 = prev.outHandle ?? prev.anchor
            let c2 = node.inHandle ?? node.anchor
            if prev.outHandle != nil || node.inHandle != nil {
                context.addCurve(to: CGPoint(x: node.anchor.x, y: node.anchor.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
            } else {
                context.addLine(to: CGPoint(x: node.anchor.x, y: node.anchor.y))
            }
        }
        if options.rubberBand, let last = options.penNodes.last {
            if let out = last.outHandle {
                context.addCurve(
                    to: CGPoint(x: options.hover.x, y: options.hover.y),
                    control1: CGPoint(x: out.x, y: out.y),
                    control2: CGPoint(x: options.hover.x, y: options.hover.y)
                )
            } else {
                context.addLine(to: CGPoint(x: options.hover.x, y: options.hover.y))
            }
        }
        context.setStrokeColor(Theme.accent.cgColor)
        context.setLineWidth(1 / options.zoom)
        context.strokePath()
        if options.showHandles {
            for node in options.penNodes {
                if let handle = node.inHandle { strokeHandle(from: node.anchor, to: handle, zoom: options.zoom, in: context) }
                if let handle = node.outHandle { strokeHandle(from: node.anchor, to: handle, zoom: options.zoom, in: context) }
            }
        }
    }

    private static func drawLive(_ document: LaminaDocument, _ options: DrawOptions, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.16, green: 0.48, blue: 0.95, alpha: 1))
        context.setFillColor(CGColor(red: 0.16, green: 0.48, blue: 0.95, alpha: 0.08))
        context.setLineWidth(1.1 / max(options.zoom, 0.01))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        if options.liveOutline {
            func walk(_ item: ArtItem) {
                let chosen = options.selection.contains(item.id)
                if chosen {
                    context.saveGState()
                    context.concatenate(cgAffine(item.transform))
                    switch item {
                    case .path(let object):
                        context.addPath(cgPath(object.path))
                    case .compound(let object):
                        for path in object.paths { context.addPath(cgPath(path)) }
                    default:
                        break
                    }
                    context.strokePath()
                    context.restoreGState()
                }
                for child in item.children { walk(child) }
            }
            for item in document.layers.flatMap(\.items) { walk(item) }
        }
        if !options.livePaths.isEmpty {
            for path in options.livePaths {
                let cg = cgPath(path)
                context.addPath(cg)
                if path.closed { context.fillPath() }
                context.addPath(cg)
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawHint(_ options: DrawOptions, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(Theme.accent.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1 / options.zoom)
        switch options.hint {
        case .none:
            break
        case .marquee(let rect):
            context.stroke(cgRect(rect))
        case .lasso(let points):
            guard let first = points.first else { break }
            context.beginPath()
            context.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() {
                context.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawGrid(_ options: DrawOptions, in context: CGContext) {
        let step = 32.0
        let x0 = options.pan.x - 64
        let y0 = options.pan.y - 64
        let x1 = options.pan.x + options.viewport.x / options.zoom + 64
        let y1 = options.pan.y + options.viewport.y / options.zoom + 64
        context.beginPath()
        context.setStrokeColor(CGColor(gray: 0.75, alpha: 0.35))
        context.setLineWidth(0.5 / options.zoom)
        var x = (x0 / step).rounded(.down) * step
        while x < x1 {
            context.move(to: CGPoint(x: x, y: y0))
            context.addLine(to: CGPoint(x: x, y: y1))
            x += step
        }
        var y = (y0 / step).rounded(.down) * step
        while y < y1 {
            context.move(to: CGPoint(x: x0, y: y))
            context.addLine(to: CGPoint(x: x1, y: y))
            y += step
        }
        context.strokePath()
    }

    private static func drawChecker(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        let size: CGFloat = 8
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var col = 0
            var x = rect.minX
            while x < rect.maxX {
                let gray: CGFloat = (row + col).isMultiple(of: 2) ? 0.92 : 0.78
                context.setFillColor(CGColor(gray: gray, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: size, height: size))
                x += size
                col += 1
            }
            y += size
            row += 1
        }
        context.restoreGState()
    }

    private static func drawPerspective(_ document: LaminaDocument, plane index: Int, grid supplied: PerspectiveGrid?, zoom: Double, in context: CGContext) {
        let plane: PerspectivePlane = index == 0 ? .left : index == 2 ? .right : .floor
        var grid = supplied ?? PerspectiveGrid(board: document.currentArtboard.rect, plane: plane)
        grid.plane = plane
        context.setStrokeColor(Theme.guide.withAlphaComponent(0.75).cgColor)
        context.setLineWidth(0.6 / zoom)
        for line in grid.lines() {
            context.addPath(cgPath(line))
        }
        context.strokePath()
    }

    private static func clipPath(_ item: ArtItem) -> CGPath? {
        switch item {
        case .path(let object):
            var path = cgPath(object.path)
            var transform = cgAffine(object.transform)
            path = path.copy(using: &transform) ?? path
            return path
        case .compound(let object):
            let path = CGMutablePath()
            for sub in object.paths { path.addPath(cgPath(sub), transform: cgAffine(object.transform)) }
            return path
        default:
            let bounds = ItemGeometry.bounds(item)
            return CGPath(rect: cgRect(bounds), transform: nil)
        }
    }

    static func cgPath(_ path: PathItem) -> CGPath {
        let result = CGMutablePath()
        guard let first = path.nodes.first else { return result }
        result.move(to: CGPoint(x: first.anchor.x, y: first.anchor.y))
        let count = path.nodes.count
        guard count > 1 else { return result }
        let segments = path.closed ? count : count - 1
        for index in 0..<segments {
            let a = path.nodes[index]
            let b = path.nodes[(index + 1) % count]
            let c1 = a.outHandle ?? a.anchor
            let c2 = b.inHandle ?? b.anchor
            if a.outHandle == nil && b.inHandle == nil {
                result.addLine(to: CGPoint(x: b.anchor.x, y: b.anchor.y))
            } else {
                result.addCurve(
                    to: CGPoint(x: b.anchor.x, y: b.anchor.y),
                    control1: CGPoint(x: c1.x, y: c1.y),
                    control2: CGPoint(x: c2.x, y: c2.y)
                )
            }
        }
        if path.closed { result.closeSubpath() }
        return result
    }

    private static func cgAffine(_ affine: Affine) -> CGAffineTransform {
        CGAffineTransform(a: CGFloat(affine.a), b: CGFloat(affine.b), c: CGFloat(affine.c), d: CGFloat(affine.d), tx: CGFloat(affine.tx), ty: CGFloat(affine.ty))
    }

    private static func cgRect(_ rect: Rect2) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private static func box(of path: CGPath) -> CGRect {
        path.boundingBoxOfPath
    }

    private static func unitPoint(_ unit: Vec2, in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.minX + CGFloat(unit.x) * bounds.width, y: bounds.minY + CGFloat(unit.y) * bounds.height)
    }

    private static func cgGradient(_ gradient: GradientPaint) -> CGGradient? {
        let stops = gradient.stops.sorted { $0.location < $1.location }
        let colors = stops.map { $0.color.cgColor } as CFArray
        let locations = stops.map { CGFloat($0.location) }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations)
    }

    private static func cgBlend(_ mode: BlendMode) -> CGBlendMode {
        switch mode {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .difference: return .difference
        }
    }
}
