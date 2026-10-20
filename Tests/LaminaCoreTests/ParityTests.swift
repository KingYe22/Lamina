import XCTest
@testable import LaminaCore

final class ParityTests: XCTestCase {
    func testInflateHelloAndPNGRoundTrip() {
        let hello = Data([120, 156, 203, 72, 205, 201, 201, 7, 0, 6, 44, 2, 21])
        XCTAssertEqual(Inflate.zlib(hello), Data("hello".utf8))
        var rgba = [UInt8](repeating: 255, count: 4 * 4 * 4)
        rgba[0] = 10
        rgba[1] = 20
        rgba[2] = 30
        let image = PNGImage(width: 4, height: 4, rgba: rgba)
        let back = PNGCodec.decode(PNGCodec.encode(image))
        XCTAssertEqual(back?.width, 4)
        XCTAssertEqual(back?.height, 4)
        XCTAssertEqual(back?.rgba[0], 10)
        XCTAssertEqual(back?.rgba[1], 20)
        XCTAssertEqual(back?.rgba[2], 30)
    }

    func testForeignPDFBecomesEditableVectors() throws {
        let content = """
        0 0 1 rg
        10 10 50 40 re
        f
        BT
        /F1 12 Tf
        1 0 0 1 20 70 Tm
        (Hi) Tj
        ET
        1 0 0 0 k
        80 20 30 20 re
        f
        """
        let data = pdfDocument(objects: [
            Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
            Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>".utf8),
            streamObject(Data(content.utf8), flate: false)
        ])
        let doc = try EditableFile.open(data: data, title: "外来")
        let paths = doc.layers.flatMap(\.items).compactMap { item -> PathObject? in
            if case .path(let object) = item { return object }
            return nil
        }
        XCTAssertGreaterThanOrEqual(paths.count, 2)
        let blue = paths[0]
        let box = Bezier.bounds(blue.path)
        XCTAssertEqual(box.x, 10, accuracy: 0.2)
        XCTAssertEqual(box.y, 50, accuracy: 0.2)
        XCTAssertEqual(box.width, 50, accuracy: 0.2)
        XCTAssertEqual(box.height, 40, accuracy: 0.2)
        let texts = doc.layers.flatMap(\.items).compactMap { item -> TextObject? in
            if case .text(let object) = item { return object }
            return nil
        }
        XCTAssertEqual(texts.first?.string, "Hi")
        XCTAssertEqual(texts.first?.origin.x ?? -1, 20, accuracy: 0.2)
        XCTAssertEqual(texts.first?.origin.y ?? -1, 30, accuracy: 0.2)
        let cmyk = paths.last?.appearance.fill?.solidColor?.cmykSource
        XCTAssertEqual(cmyk?.c ?? -1, 1, accuracy: 0.01)
        XCTAssertEqual(cmyk?.m ?? -1, 0, accuracy: 0.01)
    }

    func testFlateDecodeContentStream() throws {
        let content = Data("0 0 0 1 k\n0 0 20 10 re\nf\n".utf8)
        let data = pdfDocument(objects: [
            Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
            Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 40 20] /Contents 4 0 R >>".utf8),
            streamObject(content, flate: true)
        ])
        let doc = try EditableFile.open(data: data, title: "压缩")
        let paths = doc.layers.flatMap(\.items).compactMap { item -> PathObject? in
            if case .path(let object) = item { return object }
            return nil
        }
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].appearance.fill?.solidColor?.cmykSource?.k ?? -1, 1, accuracy: 0.01)
        let box = Bezier.bounds(paths[0].path)
        XCTAssertEqual(box.width, 20, accuracy: 0.2)
        XCTAssertEqual(box.height, 10, accuracy: 0.2)
    }

    func testLegacyAIPath() throws {
        let source = """
        %!PS-Adobe-3.0
        %%BoundingBox: 0 0 200 100
        %AI5_BeginLayer
        0 0 1 0 k
        10 20 m
        60 20 l
        60 70 l
        10 70 l
        h
        f
        """
        let doc = try EditableFile.open(data: Data(source.utf8), title: "旧式")
        guard case .path(let object) = doc.layers[0].items.first else { return XCTFail("path") }
        let box = Bezier.bounds(object.path)
        XCTAssertEqual(box.x, 10, accuracy: 0.2)
        XCTAssertEqual(box.y, 30, accuracy: 0.2)
        XCTAssertEqual(box.width, 50, accuracy: 0.2)
        XCTAssertEqual(box.height, 50, accuracy: 0.2)
        XCTAssertEqual(object.appearance.fill?.solidColor?.cmykSource?.y ?? -1, 1, accuracy: 0.01)
        XCTAssertEqual(doc.colorMode, .cmyk)
    }

    func testTraceBlackSquareAndThreeColors() {
        let width = 10
        let height = 10
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 3..<7 {
            for x in 2..<6 {
                let o = (y * width + x) * 4
                rgba[o] = 0
                rgba[o + 1] = 0
                rgba[o + 2] = 0
                rgba[o + 3] = 255
            }
        }
        let traced = ImageTrace.trace(rgba: rgba, width: width, height: height, preset: .blackAndWhiteLogo)
        XCTAssertEqual(traced.count, 1)
        XCTAssertTrue(traced[0].path.closed)
        let box = Bezier.bounds(traced[0].path)
        XCTAssertEqual(box.x, 2, accuracy: 1.5)
        XCTAssertEqual(box.y, 3, accuracy: 1.5)
        XCTAssertEqual(box.width, 4, accuracy: 1.5)
        XCTAssertEqual(box.height, 4, accuracy: 1.5)

        let bandW = 12
        let bandH = 8
        var bands = [UInt8](repeating: 0, count: bandW * bandH * 4)
        for y in 0..<bandH {
            for x in 0..<bandW {
                let o = (y * bandW + x) * 4
                if x < 4 { bands[o] = 255 }
                else if x < 8 { bands[o + 1] = 255 }
                else { bands[o + 2] = 255 }
                bands[o + 3] = 255
            }
        }
        let poster = ImageTrace.trace(rgba: bands, width: bandW, height: bandH, preset: .threeColors)
        XCTAssertEqual(poster.count, 3)
    }

    func testLivePaintFaces() {
        let a = PathBuilder.rectangle(Rect2(x: 0, y: 0, width: 100, height: 100))
        let b = PathBuilder.rectangle(Rect2(x: 50, y: 50, width: 100, height: 100))
        let faces = LivePaint.faces(paths: [a, b], gap: 0)
        XCTAssertEqual(faces.count, 3)
        guard faces.count == 3 else { return }
        let areas = faces.map { abs(Math2.signedArea($0.nodes.map(\.anchor))) }.sorted()
        XCTAssertEqual(areas[0], 2500, accuracy: 50)
        XCTAssertEqual(areas[1], 7500, accuracy: 80)
        XCTAssertEqual(areas[2], 7500, accuracy: 80)
    }

    func testWidthOutlineAndCMYK() throws {
        let line = PathItem(nodes: [.corner(Vec2(0, 0)), .corner(Vec2(100, 0))], closed: false, shape: .free)
        let widths = [WidthPoint(t: 0, left: 10, right: 10), WidthPoint(t: 1, left: 2, right: 2)]
        let outline = WidthStroke.outline(path: line, widths: widths, profile: .uniform, base: 1)
        let box = Bezier.bounds(outline)
        XCTAssertEqual(box.height, 20, accuracy: 1.5)
        XCTAssertGreaterThan(box.width, 90)

        let cyan = RGBA(cmyk: DeviceCMYK(c: 1, m: 0, y: 0, k: 0))
        let data = try JSONEncoder().encode(cyan)
        let back = try JSONDecoder().decode(RGBA.self, from: data)
        XCTAssertEqual(back.cmykSource?.c ?? -1, 1, accuracy: 0.001)
        let mixed = ColorPipeline.overprint(
            top: DeviceCMYK(c: 1, m: 0, y: 0, k: 0),
            bottom: DeviceCMYK(c: 0, m: 1, y: 0, k: 0)
        )
        XCTAssertEqual(mixed.c, 1, accuracy: 0.001)
        XCTAssertEqual(mixed.m, 1, accuracy: 0.001)
        XCTAssertEqual(mixed.y, 0, accuracy: 0.001)

        var doc = LaminaDocument.blank(title: "色", size: Vec2(100, 100))
        doc.colorMode = .cmyk
        doc.layers[0].items = [.path(PathObject(path: PathBuilder.rectangle(Rect2(x: 0, y: 0, width: 10, height: 10)), appearance: Appearance(fill: .solid(cyan), stroke: nil)))]
        let pdf = try AIFile.data(from: doc)
        let text = String(data: pdf, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(text.contains(" k"))
    }

    func testChartsExtrudeAndGlyph() {
        let pie = ChartBuilder.items(kind: .pie, frame: Rect2(x: 0, y: 0, width: 120, height: 120), series: [[4, 7, 3]], color: RGBA(hex: "#1473E6"))
        XCTAssertEqual(pie.count, 3)
        if case .path(let slice) = pie[0] {
            XCTAssertTrue(slice.path.closed)
            XCTAssertGreaterThanOrEqual(slice.path.nodes.count, 3)
        } else {
            XCTFail("pie")
        }
        for kind in ChartKind.allCases {
            let items = ChartBuilder.items(kind: kind, frame: Rect2(x: 0, y: 0, width: 200, height: 120), series: ChartBuilder.sampleSeries, color: .black)
            XCTAssertFalse(items.isEmpty, kind.rawValue)
        }
        let square = PathBuilder.rectangle(Rect2(x: 0, y: 0, width: 40, height: 40))
        let faces = Solid3D.extrude(square, color: RGBA(hex: "#1473E6"), depth: 16)
        XCTAssertGreaterThan(faces.count, 1)
        let glyph = GlyphOutline.outlines(for: TextObject(string: "H", origin: .zero, fontSize: 100))
        XCTAssertFalse(glyph.isEmpty)
        XCTAssertGreaterThanOrEqual(glyph[0].nodes.count, 8)
        XCTAssertEqual(Bezier.bounds(glyph[0]).width, 100, accuracy: 1)
    }

    func testDialogDefersUntilCommit() {
        let model = EditorModel()
        model.tool = .rectangle
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(40, 30), shift: false, option: false, command: false)
        guard let id = model.selection.first, case .path(let before) = model.document.item(id: id) else {
            return XCTFail("rect")
        }
        let original = Bezier.bounds(before.path)
        model.dialogsEnabled = true
        model.perform("偏移路径")
        XCTAssertEqual(model.pendingDialog?.title, "偏移路径")
        guard case .path(let held) = model.document.item(id: id) else { return XCTFail("held") }
        XCTAssertEqual(Bezier.bounds(held.path).width, original.width, accuracy: 0.01)
        model.commitDialog(["distance": "5"])
        guard case .path(let after) = model.document.item(id: id) else { return XCTFail("after") }
        XCTAssertGreaterThan(abs(Bezier.bounds(after.path).width - original.width), 2)
        XCTAssertNil(model.pendingDialog)
    }

    private func streamObject(_ data: Data, flate: Bool) -> Data {
        let payload = flate ? Inflate.store(data) : data
        let filter = flate ? " /Filter /FlateDecode" : ""
        var object = Data("<< /Length \(payload.count)\(filter) >>\nstream\n".utf8)
        object.append(payload)
        object.append(Data("\nendstream".utf8))
        return object
    }

    private func pdfDocument(objects: [Data]) -> Data {
        var body = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(body.count)
            body.append(Data("\(index + 1) 0 obj\n".utf8))
            body.append(object)
            body.append(Data("\nendobj\n".utf8))
        }
        let xref = body.count
        var table = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            table += String(format: "%010d 00000 n \n", offset)
        }
        table += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        body.append(Data(table.utf8))
        return body
    }
}
