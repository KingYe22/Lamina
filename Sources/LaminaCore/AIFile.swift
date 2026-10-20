import Foundation

public enum AIFileError: Error, Equatable {
    case notPDF
    case missingDocument
    case corruptJSON
}

public enum AIFile {
    public static let marker = "/Type /LaminaDocument"

    public static func data(from document: LaminaDocument) throws -> Data {
        let json = try JSONEncoder.lamina.encode(document)
        let pages = document.artboards.isEmpty
            ? [Artboard(name: "画板 1", rect: Rect2(x: 0, y: 0, width: 612, height: 792))]
            : document.artboards
        var objects: [Data] = [Data()] // index 0 unused
        func add(_ string: String) -> Int {
            objects.append(Data(string.utf8))
            return objects.count - 1
        }
        let fontID = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
        var pageIDs: [Int] = []
        var contentIDs: [Int] = []
        for (index, board) in pages.enumerated() {
            let content = contentStream(document: document, artboardIndex: index, height: board.rect.height)
            let contentID = add("<< /Length \(content.count) >>\nstream\n\(content)\nendstream")
            contentIDs.append(contentID)
            let page = "<< /Type /Page /Parent PAGES 0 R /MediaBox [0 0 \(format(board.rect.width)) \(format(board.rect.height))] /Contents \(contentID) 0 R /Resources << /Font << /F1 \(fontID) 0 R >> >> >>"
            pageIDs.append(add(page))
        }
        let kids = pageIDs.map { "\($0) 0 R" }.joined(separator: " ")
        let pagesID = add("<< /Type /Pages /Kids [\(kids)] /Count \(pageIDs.count) >>")
        // Fix parent references now that pagesID is known.
        for pid in pageIDs {
            var text = String(data: objects[pid], encoding: .utf8) ?? ""
            text = text.replacingOccurrences(of: "/Parent PAGES 0 R", with: "/Parent \(pagesID) 0 R")
            objects[pid] = Data(text.utf8)
        }
        let jsonID = add("<< /Type /LaminaDocument /Length \(json.count) >>\nstream\n")
        // The JSON object above is incomplete; rebuild it with raw bytes so length is exact.
        var jsonObject = Data()
        jsonObject.append(Data("<< /Type /LaminaDocument /Length \(json.count) >>\nstream\n".utf8))
        jsonObject.append(json)
        jsonObject.append(Data("\nendstream".utf8))
        objects[jsonID] = jsonObject
        let catalogID = add("<< /Type /Catalog /Pages \(pagesID) 0 R /LaminaDocument \(jsonID) 0 R >>")
        // Reorder is unnecessary; catalog just points at ids.

        var body = Data()
        body.append(Data("%PDF-1.6\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8))
        var offsets = Array(repeating: 0, count: objects.count)
        for i in 1..<objects.count {
            offsets[i] = body.count
            body.append(Data("\(i) 0 obj\n".utf8))
            body.append(objects[i])
            body.append(Data("\nendobj\n".utf8))
        }
        let xrefStart = body.count
        var xref = "xref\n0 \(objects.count)\n"
        xref += "0000000000 65535 f \n"
        for i in 1..<objects.count {
            xref += String(format: "%010d 00000 n \n", offsets[i])
        }
        xref += "trailer\n<< /Size \(objects.count) /Root \(catalogID) 0 R >>\nstartxref\n\(xrefStart)\n%%EOF\n"
        body.append(Data(xref.utf8))
        return body
    }

    public static func document(from data: Data) throws -> LaminaDocument {
        guard let header = String(data: data.prefix(8), encoding: .ascii), header.hasPrefix("%PDF") else {
            throw AIFileError.notPDF
        }
        guard let json = extractJSON(from: data) else { throw AIFileError.missingDocument }
        do {
            return try JSONDecoder.lamina.decode(LaminaDocument.self, from: json)
        } catch {
            throw AIFileError.corruptJSON
        }
    }

    public static func extractJSON(from data: Data) -> Data? {
        guard let text = String(data: data, encoding: .isoLatin1) else { return nil }
        guard let typeRange = text.range(of: marker) else { return nil }
        let after = text[typeRange.upperBound...]
        guard let lengthRange = after.range(of: "/Length ") else { return nil }
        let lengthTail = after[lengthRange.upperBound...]
        let digits = lengthTail.prefix { $0.isNumber }
        guard let length = Int(digits), length >= 0 else { return nil }
        guard let streamRange = after.range(of: "stream\n") else { return nil }
        let start = streamRange.upperBound
        let utf = Data(text.utf8)
        // isoLatin1 round-trip keeps byte offsets equal to UTF-8 for PDF bytes < 128,
        // but JSON is UTF-8. Locate the stream in the original data instead.
        if let raw = rangeOfStream(in: data, length: length) {
            return data.subdata(in: raw)
        }
        _ = start
        return nil
    }

    private static func rangeOfStream(in data: Data, length: Int) -> Range<Data.Index>? {
        let markerData = Data(marker.utf8)
        guard let markerRange = data.range(of: markerData) else { return nil }
        let streamToken = Data("stream\n".utf8)
        guard let stream = data.range(of: streamToken, in: markerRange.upperBound..<data.endIndex) else { return nil }
        let start = stream.upperBound
        let end = start + length
        guard end <= data.count else { return nil }
        return start..<end
    }

    private static func contentStream(document: LaminaDocument, artboardIndex: Int, height: Double) -> String {
        var ops: [String] = []
        ops.append("q")
        ops.append("1 0 0 -1 0 \(format(height)) cm")
        let board = document.artboards.indices.contains(artboardIndex) ? document.artboards[artboardIndex] : nil
        if let board {
            ops.append("0.95 0.95 0.95 rg")
            ops.append("0 0 \(format(board.rect.width)) \(format(board.rect.height)) re f")
        }
        for layer in document.layers where layer.visible {
            for item in layer.items where !item.hidden {
                if let board, !itemIntersects(item, board.rect) && document.artboards.count > 1 {
                    continue
                }
                draw(item, into: &ops, transform: .identity, cmyk: document.colorMode == .cmyk)
            }
        }
        ops.append("Q")
        return ops.joined(separator: "\n")
    }

    private static func itemIntersects(_ item: ArtItem, _ rect: Rect2) -> Bool {
        let b = ItemGeometry.bounds(item)
        if b.isEmpty { return true }
        return b.intersects(rect.expanded(2))
    }

    private static func draw(_ item: ArtItem, into ops: inout [String], transform: Affine, cmyk: Bool) {
        let world = transform.concatenated(item.transform)
        switch item {
        case .path(let o):
            strokeFill(path: o.path, appearance: o.appearance, transform: world, into: &ops, cmyk: cmyk)
        case .compound(let o):
            for path in o.paths {
                strokeFill(path: path, appearance: o.appearance, transform: world, into: &ops, fillRule: o.fillRule, cmyk: cmyk)
            }
        case .text(let o):
            let origin = world.apply(o.kind == .area ? Vec2(o.frame.x, o.frame.y + o.fontSize) : o.origin)
            let safe = o.string.filter { $0.isASCII && $0 != "(" && $0 != ")" && $0 != "\\" }
            let shown = safe.isEmpty ? "Text" : safe
            ops.append("q")
            ops.append("1 0 0 -1 \(format(origin.x)) \(format(origin.y)) cm")
            if case .solid(let c) = o.appearance.fill {
                ops.append(colorOp(c, fill: true, cmyk: cmyk))
            } else {
                ops.append(cmyk ? "0 0 0 1 k" : "0 0 0 rg")
            }
            ops.append("BT /F1 \(format(o.fontSize)) Tf 0 0 Td (\(shown)) Tj ET")
            ops.append("Q")
        case .group(let g):
            for child in g.children {
                draw(child, into: &ops, transform: world, cmyk: cmyk)
            }
        case .clip(let c):
            ops.append("q")
            if case .path(let p) = c.clipper {
                appendPath(p.path, transform: world, into: &ops)
                ops.append("W n")
            }
            for child in c.contents {
                draw(child, into: &ops, transform: world, cmyk: cmyk)
            }
            ops.append("Q")
        case .graph(let g):
            let frame = world.apply(g.frame)
            ops.append("0.1 0.45 0.9 rg")
            ops.append("\(format(frame.x)) \(format(frame.y)) \(format(frame.width)) \(format(frame.height)) re f")
        case .placed(let p):
            let frame = world.apply(p.frame)
            ops.append("0.8 0.8 0.8 rg")
            ops.append("\(format(frame.x)) \(format(frame.y)) \(format(frame.width)) \(format(frame.height)) re f")
        case .mesh(let m):
            let origin = world.apply(m.origin)
            ops.append("0.7 0.7 0.9 rg")
            ops.append("\(format(origin.x)) \(format(origin.y)) \(format(m.cell.x * Double(m.columns))) \(format(m.cell.y * Double(m.rows))) re f")
        }
    }

    private static func strokeFill(path: PathItem, appearance: Appearance, transform: Affine, into ops: inout [String], fillRule: FillRule = .nonzero, cmyk: Bool = false) {
        guard !path.nodes.isEmpty else { return }
        let fills = appearance.allFills
        let strokes = appearance.allStrokes
        if fills.isEmpty && strokes.isEmpty {
            appendPath(path, transform: transform, into: &ops)
            ops.append("n")
            return
        }
        for fill in fills {
            appendPath(path, transform: transform, into: &ops)
            if case .solid(let c) = fill { ops.append(colorOp(c, fill: true, cmyk: cmyk)) }
            else { ops.append(cmyk ? "0 0 0 1 k" : "0 0 0 rg") }
            ops.append(fillRule == .evenOdd ? "f*" : "f")
        }
        for stroke in strokes {
            appendPath(path, transform: transform, into: &ops)
            if case .solid(let c) = stroke.paint { ops.append(colorOp(c, fill: false, cmyk: cmyk)) }
            else { ops.append(cmyk ? "0 0 0 1 K" : "0 0 0 RG") }
            ops.append("\(format(stroke.width)) w")
            ops.append("S")
        }
    }

    private static func colorOp(_ c: RGBA, fill: Bool, cmyk: Bool) -> String {
        if cmyk || c.cmykSource != nil {
            let device = c.deviceCMYK
            return "\(format(device.c)) \(format(device.m)) \(format(device.y)) \(format(device.k)) \(fill ? "k" : "K")"
        }
        return "\(rgb(c)) \(fill ? "rg" : "RG")"
    }

    private static func appendPath(_ path: PathItem, transform: Affine, into ops: inout [String]) {
        guard let first = path.nodes.first else { return }
        let p0 = transform.apply(first.anchor)
        ops.append("\(format(p0.x)) \(format(p0.y)) m")
        let count = path.nodes.count
        let segments = path.closed ? count : max(0, count - 1)
        for i in 0..<segments {
            let a = path.nodes[i]
            let b = path.nodes[(i + 1) % count]
            let c1 = transform.apply(a.outHandle ?? a.anchor)
            let c2 = transform.apply(b.inHandle ?? b.anchor)
            let p = transform.apply(b.anchor)
            if a.outHandle == nil && b.inHandle == nil {
                ops.append("\(format(p.x)) \(format(p.y)) l")
            } else {
                ops.append("\(format(c1.x)) \(format(c1.y)) \(format(c2.x)) \(format(c2.y)) \(format(p.x)) \(format(p.y)) c")
            }
        }
        if path.closed { ops.append("h") }
    }

    private static func rgb(_ c: RGBA) -> String {
        "\(format(c.r)) \(format(c.g)) \(format(c.b))"
    }

    private static func format(_ n: Double) -> String {
        String(format: "%.3f", n)
    }
}

extension JSONEncoder {
    static var lamina: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var lamina: JSONDecoder { JSONDecoder() }
}

public enum ItemGeometry {
    public static func bounds(_ item: ArtItem) -> Rect2 {
        switch item {
        case .path(let o):
            return o.transform.apply(Bezier.bounds(o.path))
        case .text(let o):
            let rect: Rect2
            if o.kind == .area && !o.frame.isEmpty {
                rect = o.frame
            } else {
                let width = max(8, Double(o.string.count) * o.fontSize * 0.6 * o.horizontalScale)
                let height = max(o.fontSize, o.leading)
                rect = Rect2(x: o.origin.x, y: o.origin.y - o.fontSize, width: width, height: height)
            }
            return o.transform.apply(rect)
        case .group(let g):
            let child = g.children.map { bounds($0) }.reduce(Rect2.zero) { partial, next in
                partial.isEmpty ? next : partial.union(next)
            }
            return g.transform.apply(child)
        case .compound(let o):
            let box = o.paths.map { Bezier.bounds($0) }.reduce(Rect2.zero) { $0.isEmpty ? $1 : $0.union($1) }
            return o.transform.apply(box)
        case .clip(let o):
            let content = o.contents.map { bounds($0) }.reduce(Rect2.zero) { $0.isEmpty ? $1 : $0.union($1) }
            let clip = bounds(o.clipper)
            let box = content.isEmpty ? clip : (clip.isEmpty ? content : Rect2(
                x: max(content.x, clip.x),
                y: max(content.y, clip.y),
                width: min(content.maxX, clip.maxX) - max(content.x, clip.x),
                height: min(content.maxY, clip.maxY) - max(content.y, clip.y)
            ))
            return o.transform.apply(box)
        case .placed(let o):
            return o.transform.apply(o.frame)
        case .mesh(let o):
            return o.transform.apply(Rect2(x: o.origin.x, y: o.origin.y, width: o.cell.x * Double(max(o.columns, 1)), height: o.cell.y * Double(max(o.rows, 1))))
        case .graph(let o):
            return o.transform.apply(o.frame)
        }
    }

    public static func hit(_ item: ArtItem, point: Vec2, tolerance: Double) -> UUID? {
        if item.hidden || item.locked { return nil }
        guard let inverse = item.transform.inverted else { return nil }
        let local = inverse.apply(point)
        switch item {
        case .path(let o):
            let filled = o.appearance.fill != nil
            return Bezier.hit(o.path, point: local, tolerance: tolerance, filled: filled) ? o.id : nil
        case .text(let o):
            let rect = Rect2(x: o.kind == .area ? o.frame.x : o.origin.x, y: o.kind == .area ? o.frame.y : o.origin.y - o.fontSize, width: o.kind == .area ? o.frame.width : max(8, Double(o.string.count) * o.fontSize * 0.6), height: o.kind == .area ? o.frame.height : o.fontSize)
            return rect.contains(local, inset: tolerance) ? o.id : nil
        case .group(let g):
            for child in g.children.reversed() {
                if let id = hit(child, point: local, tolerance: tolerance) { return id }
            }
            return nil
        case .compound(let o):
            for path in o.paths where Bezier.hit(path, point: local, tolerance: tolerance, filled: o.appearance.fill != nil) {
                return o.id
            }
            return nil
        case .clip(let o):
            for child in o.contents.reversed() {
                if let id = hit(child, point: local, tolerance: tolerance) { return id }
            }
            return hit(o.clipper, point: local, tolerance: tolerance)
        case .placed(let o):
            return o.frame.contains(local, inset: tolerance) ? o.id : nil
        case .mesh(let o):
            let rect = Rect2(x: o.origin.x, y: o.origin.y, width: o.cell.x * Double(o.columns), height: o.cell.y * Double(o.rows))
            return rect.contains(local, inset: tolerance) ? o.id : nil
        case .graph(let o):
            return o.frame.contains(local, inset: tolerance) ? o.id : nil
        }
    }
}
