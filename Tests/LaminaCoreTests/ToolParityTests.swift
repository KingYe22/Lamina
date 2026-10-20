import XCTest
@testable import LaminaCore

final class ToolParityTests: XCTestCase {
    private func drag(_ model: EditorModel, _ tool: Tool, from a: Vec2, to b: Vec2, shift: Bool = false, option: Bool = false, command: Bool = false) {
        model.tool = tool
        model.pointerDown(at: a, shift: shift, option: option, command: command)
        model.pointerDrag(to: b, shift: shift, option: option, command: command)
        model.pointerUp(at: b, shift: shift, option: option, command: command)
    }

    private func box(_ model: EditorModel) -> Rect2 {
        ItemGeometry.bounds(model.document.flatItems()[0])
    }

    func testCalligraphicPressureChangesRibbon() {
        let path = PathBuilder.line(Vec2(0, 0), Vec2(100, 0))
        var stroke = StrokeStyle(brush: .calligraphic(CalligraphicBrush(
            angle: .fixed(0),
            roundness: .fixed(1),
            diameter: BrushVariation(source: .pressure, minimum: 2, maximum: 20)
        )))
        stroke.samples = [
            StrokeSample(point: .zero, pressure: 0),
            StrokeSample(point: Vec2(100, 0), pressure: 1)
        ]
        let items = BrushEngine.expand(path: path, stroke: stroke)
        guard case .path(let object) = items.first else { return XCTFail("书法没有展开") }
        let start = object.path.nodes.map(\.anchor).filter { $0.x < 8 }
        let end = object.path.nodes.map(\.anchor).filter { $0.x > 92 }
        let startH = (start.map(\.y).max() ?? 0) - (start.map(\.y).min() ?? 0)
        let endH = (end.map(\.y).max() ?? 0) - (end.map(\.y).min() ?? 0)
        XCTAssertLessThan(startH, 6)
        XCTAssertGreaterThan(endH, 14)
    }

    func testScatterTintAndCount() {
        let path = PathBuilder.line(Vec2(0, 0), Vec2(80, 0))
        let stroke = StrokeStyle(paint: .solid(RGBA(hex: "#3366CC")), brush: .scatter(ScatterBrush(
            size: .fixed(8),
            spacing: .fixed(20),
            scatter: .fixed(0),
            rotation: .fixed(0),
            colorization: .tints,
            artwork: BrushArtwork.star(radius: 4)
        )))
        let items = BrushEngine.expand(path: path, stroke: stroke)
        XCTAssertGreaterThanOrEqual(items.count, 3)
        if case .path(let object) = items.first {
            let hex = object.appearance.fill?.solidColor?.hex ?? ""
            XCTAssertNotEqual(hex, RGBA.black.hex)
        } else {
            XCTFail("散点")
        }
    }

    func testArtBetweenGuidesDiffersFromStretch() {
        let path = PathBuilder.line(Vec2(0, 0), Vec2(100, 0))
        let art = ArtBrush(width: 10, fit: .betweenGuides, startGuide: 0.2, endGuide: 0.8, adjustCorners: false, artwork: BrushArtwork.taper)
        let stretch = ArtBrush(width: 10, fit: .stretchToFit, adjustCorners: false, artwork: BrushArtwork.taper)
        let a = BrushEngine.expand(path: path, stroke: StrokeStyle(brush: .art(art)))
        let b = BrushEngine.expand(path: path, stroke: StrokeStyle(brush: .art(stretch)))
        guard case .path(let left) = a.first, case .path(let right) = b.first else { return XCTFail("艺术画笔") }
        let ax = left.path.nodes.map(\.anchor.x).sorted()
        let bx = right.path.nodes.map(\.anchor.x).sorted()
        XCTAssertGreaterThan(abs((ax[ax.count / 2]) - (bx[bx.count / 2])), 4)
    }

    func testPatternFitChangesTileCount() {
        let path = PathBuilder.line(Vec2(0, 0), Vec2(100, 0))
        let stretch = BrushEngine.expand(path: path, stroke: StrokeStyle(brush: .pattern(PatternBrush(side: BrushArtwork.tile(25), fit: .stretchToFit, autoCorners: false))))
        let spaced = BrushEngine.expand(path: path, stroke: StrokeStyle(brush: .pattern(PatternBrush(side: BrushArtwork.tile(30), fit: .addSpace, spacing: 4, autoCorners: false))))
        XCTAssertGreaterThanOrEqual(stretch.count, 3)
        XCTAssertGreaterThan(stretch.count, spaced.count)
    }

    func testBristleDensityAndAccumulation() {
        let path = PathBuilder.line(Vec2(0, 0), Vec2(40, 0))
        let light = BristleBrush(shape: .roundPoint, size: 8, density: 0.1, thickness: 0.4, paintOpacity: 0.8, stiffness: 0.2)
        let heavy = BristleBrush(shape: .fan, size: 8, density: 1, thickness: 0.8, paintOpacity: 0.9, stiffness: 0.2)
        let a = BrushEngine.expand(path: path, stroke: StrokeStyle(brush: .bristle(light)))
        let b = BrushEngine.expand(path: path, stroke: StrokeStyle(brush: .bristle(heavy)))
        XCTAssertGreaterThan(b.count, a.count)
        let preview = BrushEngine.bristlePreview(path: path, stroke: StrokeStyle(brush: .bristle(heavy)), brush: heavy)
        XCTAssertNotNil(preview)
        XCTAssertGreaterThan(preview?.rgba.max() ?? 0, 0)
    }

    func testBrushLibraryAndExpandAppearance() {
        let model = EditorModel()
        XCTAssertGreaterThanOrEqual(model.brushLibrary.count, 5)
        model.tool = .brush
        model.brush = model.brushLibrary[0].brush
        model.pointerDown(at: Vec2(10, 10), shift: false, option: false, command: false, stylus: StylusSample(pressure: 0.2, tilt: 0.4, bearing: 0.5, rotation: 0.2, wheel: 0.3))
        model.pointerDrag(to: Vec2(80, 30), shift: false, option: false, command: false, stylus: StylusSample(pressure: 0.9, tilt: 0.5, bearing: 1, rotation: 0.4, wheel: 0.8))
        model.pointerUp(at: Vec2(80, 40), shift: false, option: false, command: false)
        guard case .path(let painted) = model.document.item(id: model.selection[0]) else { return XCTFail("画笔") }
        XCTAssertFalse(painted.appearance.stroke?.samples.isEmpty ?? true)
        model.perform("扩展外观")
        guard case .group(let group) = model.document.item(id: model.selection[0]) else { return XCTFail("扩展外观") }
        XCTAssertFalse(group.children.isEmpty)
    }

    func testPenModifiersContinueAndClose() {
        let model = EditorModel()
        model.tool = .pen
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(0, -30), shift: false, option: true, command: false)
        model.pointerUp(at: Vec2(0, -30), shift: false, option: true, command: false)
        XCTAssertNil(model.penNodes[0].inHandle)
        XCTAssertNotNil(model.penNodes[0].outHandle)
        model.pointerDown(at: Vec2(30, 2), shift: true, option: false, command: false)
        XCTAssertEqual(model.penNodes[1].anchor.y, 0, accuracy: 0.01)
        model.pointerDrag(to: Vec2(40, 10), shift: false, option: false, command: false, space: true)
        XCTAssertGreaterThan(abs(model.penNodes[1].anchor.x - 30), 1)
        model.finishPen()
        XCTAssertEqual(model.document.objectCount, 1)

        model.tool = .pen
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        XCTAssertEqual(model.penCursor, .continuePath)
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(10, 40), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        XCTAssertEqual(model.penNodes.count, 0)
        guard case .path(let closed) = model.document.flatItems().last else { return XCTFail("闭合") }
        XCTAssertTrue(closed.path.closed)
    }

    func testPenAutoAddAndRubberCursor() {
        let model = EditorModel()
        drag(model, .rectangle, from: Vec2(0, 0), to: Vec2(40, 20))
        model.tool = .pen
        model.autoAddDelete = true
        model.pointerDown(at: Vec2(20, 0), shift: false, option: false, command: false)
        guard case .path(let object) = model.document.flatItems()[0] else { return XCTFail() }
        XCTAssertGreaterThan(object.path.nodes.count, 4)
        XCTAssertEqual(model.penCursor, .add)
        let cursor = ToolBehaviors.penCursor(nodes: [.corner(.zero), .corner(Vec2(10, 0)), .corner(Vec2(10, 10))], hover: Vec2(1, 1), zoom: 1, nearAnchor: false, nearSegment: false, nearForeignEnd: false)
        XCTAssertEqual(cursor, .close)
        XCTAssertFalse(ToolBehaviors.rubber(from: .corner(.zero), to: Vec2(8, 3)).isEmpty)
    }

    func testCurvatureAndAnchorPoint() {
        let model = EditorModel()
        model.tool = .curvature
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(30, 10), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(60, 0), shift: false, option: false, command: false, clickCount: 1)
        XCTAssertEqual(model.penNodes[1].corner, .smooth)
        model.pointerDown(at: Vec2(30, 10), shift: false, option: false, command: false, clickCount: 2)
        XCTAssertEqual(model.penNodes[1].corner, .corner)
        model.finishPen()
        model.tool = .convertAnchor
        model.pointerDown(at: model.document.flatItems()[0].letPath.nodes[0].anchor, shift: false, option: false, command: false)
        model.pointerUp(at: model.document.flatItems()[0].letPath.nodes[0].anchor, shift: false, option: false, command: false)
        model.tool = .convertAnchor
        let anchor = model.document.flatItems()[0].letPath.nodes[1].anchor
        model.pointerDown(at: anchor, shift: false, option: false, command: false)
        model.pointerDrag(to: anchor + Vec2(15, -10), shift: false, option: false, command: false)
        model.pointerUp(at: anchor + Vec2(15, -10), shift: false, option: false, command: false)
        XCTAssertNotNil(model.document.flatItems()[0].letPath.nodes[1].outHandle)
    }

    func testSelectionDirectGroupZoomHand() {
        let model = EditorModel()
        drag(model, .rectangle, from: Vec2(10, 10), to: Vec2(80, 60))
        drag(model, .ellipse, from: Vec2(100, 10), to: Vec2(150, 50))
        model.tool = .selection
        model.pointerDown(at: Vec2(20, 20), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(30, 25), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(30, 25), shift: false, option: false, command: false)
        XCTAssertGreaterThan(model.document.flatItems()[0].transform.tx, 5)
        model.tool = .directSelection
        let node = model.document.flatItems()[0].letPath.nodes[0]
        model.pointerDown(at: node.anchor + Vec2(model.document.flatItems()[0].transform.tx, 0), shift: false, option: false, command: false)
        XCTAssertTrue(model.selectedAnchors.contains(node.id))
        model.selection = model.document.flatItems().map(\.id)
        model.perform("编组选定图稿")
        model.tool = .groupSelection
        model.pointerDown(at: Vec2(40, 30), shift: false, option: false, command: false)
        XCTAssertFalse(model.selection.isEmpty)
        let zoom = model.zoom
        drag(model, .zoom, from: Vec2(0, 0), to: Vec2(2, 2))
        XCTAssertNotEqual(model.zoom, zoom)
        let pan = model.pan
        drag(model, .hand, from: Vec2(0, 0), to: Vec2(40, 10))
        XCTAssertNotEqual(model.pan.x, pan.x)
        model.tool = .rotateView
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(0, 240), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(0, 240), shift: false, option: false, command: false)
        XCTAssertGreaterThan(abs(model.viewRotation), 0.05)
    }

    func testMagicWandAndLasso() {
        let model = EditorModel()
        model.currentFill = .solid(RGBA(hex: "#224488"))
        drag(model, .rectangle, from: Vec2(0, 0), to: Vec2(20, 20))
        model.currentFill = .solid(RGBA(hex: "#224499"))
        drag(model, .rectangle, from: Vec2(40, 0), to: Vec2(60, 20))
        model.currentFill = .solid(RGBA(hex: "#CC2200"))
        drag(model, .rectangle, from: Vec2(80, 0), to: Vec2(100, 20))
        model.wandTolerance = 0.08
        model.tool = .magicWand
        model.pointerDown(at: Vec2(10, 10), shift: false, option: false, command: false)
        XCTAssertEqual(model.selection.count, 2)
        model.tool = .lasso
        model.pointerDown(at: Vec2(-5, 25), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(15, 25), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(15, -5), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(-5, -5), shift: false, option: false, command: false)
        XCTAssertEqual(model.selection.count, 1)
    }

    func testShapeToolsAndLineConstraint() {
        let model = EditorModel()
        drag(model, .line, from: Vec2(0, 0), to: Vec2(10, 1), shift: true)
        XCTAssertEqual(box(model).height, 0, accuracy: 0.2)
        drag(model, .rectangle, from: Vec2(0, 0), to: Vec2(30, 10), shift: true)
        let rect = model.document.flatItems().last!
        let bounds = ItemGeometry.bounds(rect)
        XCTAssertEqual(bounds.width, bounds.height, accuracy: 0.2)
        drag(model, .roundedRectangle, from: Vec2(0, 40), to: Vec2(30, 70))
        drag(model, .ellipse, from: Vec2(40, 40), to: Vec2(80, 70))
        drag(model, .polygon, from: Vec2(0, 80), to: Vec2(40, 120))
        drag(model, .star, from: Vec2(50, 80), to: Vec2(90, 120))
        drag(model, .arc, from: Vec2(0, 140), to: Vec2(40, 180), shift: true)
        drag(model, .spiral, from: Vec2(50, 140), to: Vec2(100, 190))
        drag(model, .rectGrid, from: Vec2(0, 200), to: Vec2(40, 240))
        drag(model, .polarGrid, from: Vec2(50, 200), to: Vec2(100, 250))
        drag(model, .flare, from: Vec2(110, 200), to: Vec2(160, 250))
        let names = model.document.flatItems().map(\.name)
        XCTAssertTrue(names.contains("极坐标网格"))
        XCTAssertTrue(names.contains("光晕"))
        XCTAssertTrue(names.contains("弧形"))
        XCTAssertGreaterThan(model.document.objectCount, 8)
    }

    func testPencilSmoothPathEraserJoinShaper() {
        let model = EditorModel()
        model.fidelity = 3
        model.smoothness = 0.8
        model.tool = .pencil
        var x = 0.0
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        while x < 80 {
            x += 3
            model.pointerDrag(to: Vec2(x, sin(x / 6) * 8), shift: false, option: false, command: false)
        }
        model.pointerUp(at: Vec2(80, 0), shift: false, option: false, command: false)
        let pencil = model.document.flatItems()[0].letPath
        XCTAssertLessThan(pencil.nodes.count, 20)
        XCTAssertEqual(pencil.nodes[1].corner, .smooth)
        model.tool = .smooth
        model.pointerDown(at: pencil.nodes[0].anchor, shift: false, option: false, command: false)
        model.pointerDrag(to: pencil.nodes[min(2, pencil.nodes.count - 1)].anchor, shift: false, option: false, command: false)
        model.pointerUp(at: pencil.nodes[min(2, pencil.nodes.count - 1)].anchor, shift: false, option: false, command: false)
        model.tool = .line
        drag(model, .line, from: Vec2(0, 40), to: Vec2(30, 40))
        drag(model, .line, from: Vec2(34, 40), to: Vec2(70, 40))
        model.selection = model.document.flatItems().suffix(2).map(\.id)
        model.tool = .joinTool
        model.pointerDown(at: Vec2(30, 40), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(36, 40), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(36, 40), shift: false, option: false, command: false)
        XCTAssertTrue(model.document.flatItems().contains { $0.name == "路径" && $0.letPath.nodes.count >= 3 })
        let before = model.document.objectCount
        model.selection = [model.document.flatItems()[0].id]
        model.tool = .pathEraser
        let nodes = model.document.flatItems()[0].letPath.nodes
        model.pointerDown(at: nodes[nodes.count / 2].anchor, shift: false, option: false, command: false)
        model.pointerDrag(to: nodes[nodes.count / 2].anchor + Vec2(4, 0), shift: false, option: false, command: false)
        model.pointerUp(at: nodes[nodes.count / 2].anchor + Vec2(6, 0), shift: false, option: false, command: false)
        XCTAssertNotEqual(model.document.objectCount, before)
        model.tool = .shaper
        let circle = (0..<24).map { i -> Vec2 in
            let a = Double(i) / 24 * Double.pi * 2
            return Vec2(200 + cos(a) * 20, 40 + sin(a) * 16)
        }
        model.pointerDown(at: circle[0], shift: false, option: false, command: false)
        for point in circle.dropFirst() { model.pointerDrag(to: point, shift: false, option: false, command: false) }
        model.pointerUp(at: circle[0], shift: false, option: false, command: false)
        XCTAssertTrue(model.document.flatItems().contains { $0.name == "椭圆" || $0.name == "形状工具" || $0.letPath.closed })
    }

    func testEraserScissorsKnifeShapeBuilder() {
        let model = EditorModel()
        drag(model, .rectangle, from: Vec2(0, 0), to: Vec2(100, 80))
        model.tool = .eraser
        model.eraserDiameter = 12
        model.pointerDown(at: Vec2(-5, 40), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(50, 40), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(110, 40), shift: false, option: false, command: false)
        XCTAssertGreaterThan(model.document.objectCount, 1)
        drag(model, .rectangle, from: Vec2(0, 100), to: Vec2(80, 160))
        model.tool = .scissors
        model.pointerDown(at: Vec2(40, 100), shift: false, option: false, command: false)
        XCTAssertTrue(model.status.contains("剪刀"))
        drag(model, .rectangle, from: Vec2(0, 200), to: Vec2(80, 260))
        model.tool = .knife
        model.pointerDown(at: Vec2(0, 230), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(80, 230), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(90, 230), shift: false, option: false, command: false)
        XCTAssertGreaterThanOrEqual(model.document.flatItems().filter { $0.name == "矩形" || $0.name == "路径" }.count, 1)
        drag(model, .rectangle, from: Vec2(200, 0), to: Vec2(300, 100))
        drag(model, .rectangle, from: Vec2(250, 50), to: Vec2(350, 150))
        model.selection = Array(model.document.flatItems().suffix(2).map(\.id))
        model.tool = .shapeBuilder
        model.pointerDown(at: Vec2(220, 20), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(220, 80), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(220, 90), shift: false, option: true, command: false)
        XCTAssertTrue(model.status.contains("形状生成器"))
    }

    func testTransformsWarpPuppetWidth() {
        let model = EditorModel()
        drag(model, .rectangle, from: Vec2(0, 0), to: Vec2(80, 60))
        model.tool = .rotate
        model.pointerDown(at: Vec2(80, 0), shift: true, option: false, command: false)
        model.pointerDrag(to: Vec2(80, 40), shift: true, option: false, command: false)
        model.pointerUp(at: Vec2(80, 40), shift: true, option: false, command: false)
        XCTAssertNotEqual(model.document.flatItems()[0].transform, .identity)
        drag(model, .rectangle, from: Vec2(100, 0), to: Vec2(160, 40))
        model.selection = [model.document.flatItems().last!.id]
        model.tool = .reflect
        model.pointerDown(at: Vec2(130, -10), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(180, 20), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(180, 20), shift: false, option: false, command: false)
        XCTAssertGreaterThan(abs(model.document.flatItems().last!.transform.d - 1), 0.05)
        model.selection = [model.document.flatItems()[0].id]
        model.tool = .scale
        model.pointerDown(at: Vec2(90, 10), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(120, 30), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(120, 30), shift: false, option: false, command: false)
        model.tool = .shear
        model.pointerDown(at: Vec2(70, 10), shift: true, option: false, command: false)
        model.pointerDrag(to: Vec2(100, 10), shift: true, option: false, command: false)
        model.pointerUp(at: Vec2(100, 10), shift: true, option: false, command: false)
        model.tool = .reshape
        let before = model.document.flatItems()[0].letPath.nodes.map(\.anchor)
        model.pointerDown(at: before[0], shift: false, option: false, command: false)
        model.pointerDrag(to: before[0] + Vec2(0, 25), shift: false, option: false, command: false)
        model.pointerUp(at: before[0] + Vec2(0, 25), shift: false, option: false, command: false)
        XCTAssertNotEqual(model.document.flatItems()[0].letPath.nodes[0].anchor.y, before[0].y)
        model.warpKind = .twirl
        model.tool = .warp
        model.pointerDown(at: Vec2(40, 30), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(55, 30), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(55, 30), shift: false, option: false, command: false)
        XCTAssertEqual(model.document.flatItems()[0].letPath.shape, .free)
        model.tool = .freeTransform
        let corner = ItemGeometry.bounds(model.document.flatItems()[0])
        model.pointerDown(at: Vec2(corner.maxX, corner.maxY), shift: false, option: false, command: true)
        model.pointerDrag(to: Vec2(corner.maxX + 20, corner.maxY + 10), shift: false, option: false, command: true)
        model.pointerUp(at: Vec2(corner.maxX + 20, corner.maxY + 10), shift: false, option: false, command: true)
        model.tool = .width
        model.pointerDown(at: Vec2(corner.midX, corner.minY), shift: false, option: true, command: false)
        model.pointerDrag(to: Vec2(corner.midX, corner.minY - 18), shift: false, option: true, command: false)
        model.pointerUp(at: Vec2(corner.midX, corner.minY - 18), shift: false, option: true, command: false)
        XCTAssertFalse(model.document.flatItems()[0].letPathWidths.isEmpty)
        model.tool = .puppet
        model.puppetPins = []
        model.pointerDown(at: Vec2(10, 10), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(10, 10), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(70, 50), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(90, 70), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(90, 70), shift: false, option: false, command: false)
        XCTAssertGreaterThanOrEqual(model.puppetPins.count, 2)
    }

    func testSymbolsMeshGradientEyedropperMeasureBlend() {
        let model = EditorModel()
        drag(model, .star, from: Vec2(0, 0), to: Vec2(20, 20))
        model.symbolKind = .sprayer
        model.tool = .symbolSprayer
        model.pointerDown(at: Vec2(40, 40), shift: false, option: false, command: false)
        XCTAssertGreaterThan(model.document.objectCount, 2)
        model.symbolKind = .sizer
        model.tool = .symbolSprayer
        model.pointerDown(at: Vec2(40, 40), shift: false, option: false, command: false)
        model.tool = .mesh
        model.pointerDown(at: Vec2(10, 80), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(12, 82), shift: false, option: false, command: false)
        let mesh = model.document.flatItems().compactMap { if case .mesh(let m) = $0 { return m } else { return nil } }.first
        XCTAssertEqual(mesh?.columns, 5)
        drag(model, .rectangle, from: Vec2(0, 140), to: Vec2(80, 180))
        model.selection = [model.document.flatItems().last!.id]
        model.document.updateItem(model.selection[0]) { item in
            if case .path(var o) = item {
                o.appearance.fill = .linear(GradientPaint(stops: [GradientStop(color: RGBA(hex: "#AA0000"), location: 0), GradientStop(color: RGBA(hex: "#0000AA"), location: 1)], start: Vec2(0, 0.5), end: Vec2(1, 0.5)))
                item = .path(o)
            }
        }
        model.tool = .gradient
        model.pointerDown(at: Vec2(0, 160), shift: true, option: false, command: false)
        model.pointerDrag(to: Vec2(80, 150), shift: true, option: false, command: false)
        model.pointerUp(at: Vec2(80, 150), shift: true, option: false, command: false)
        if case .linear(let g) = model.currentFill {
            XCTAssertEqual(g.stops[0].color.hex, RGBA(hex: "#AA0000").hex)
            XCTAssertEqual(g.start.y, g.end.y, accuracy: 0.02)
        } else { XCTFail("渐变") }
        model.tool = .eyedropper
        model.pointerDown(at: Vec2(10, 10), shift: false, option: false, command: false)
        XCTAssertNotNil(model.currentFill)
        model.currentFill = .solid(RGBA(hex: "#00AA44"))
        model.tool = .eyedropper
        model.pointerDown(at: Vec2(20, 150), shift: false, option: true, command: false)
        model.tool = .measure
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(30, 40), shift: false, option: false, command: false)
        XCTAssertEqual(model.measure.dx, 30, accuracy: 0.1)
        XCTAssertEqual(model.measure.dy, 40, accuracy: 0.1)
        drag(model, .rectangle, from: Vec2(200, 0), to: Vec2(230, 20))
        drag(model, .rectangle, from: Vec2(260, 40), to: Vec2(300, 70))
        model.selection = []
        model.tool = .blend
        model.pointerDown(at: Vec2(210, 10), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(270, 50), shift: false, option: false, command: false)
        XCTAssertTrue(model.document.flatItems().contains { $0.name == "混合" })
    }

    func testLivePaintPerspectiveArtboardSliceGraphType() {
        let model = EditorModel()
        drag(model, .rectangle, from: Vec2(0, 0), to: Vec2(80, 80))
        drag(model, .rectangle, from: Vec2(40, 40), to: Vec2(120, 120))
        model.selection = Array(model.document.flatItems().suffix(2).map(\.id))
        model.perform("进行实时上色（使用油漆桶工具时）")
        model.tool = .livePaintBucket
        model.currentFill = .solid(RGBA(hex: "#1144AA"))
        model.pointerDown(at: Vec2(20, 20), shift: false, option: false, command: false)
        XCTAssertTrue(model.status.contains("实时上色"))
        model.tool = .livePaintSelection
        model.pointerDown(at: Vec2(20, 20), shift: false, option: false, command: false)
        XCTAssertEqual(model.selection.count, 1)
        let before = model.perspectiveGrid.leftVanishing
        model.tool = .perspectiveGrid
        model.pointerDown(at: before, shift: false, option: false, command: false)
        model.pointerDrag(to: before + Vec2(-30, 10), shift: false, option: false, command: false)
        model.pointerUp(at: before + Vec2(-30, 10), shift: false, option: false, command: false)
        XCTAssertNotEqual(model.perspectiveGrid.leftVanishing.x, before.x)
        model.showPerspective = true
        drag(model, .rectangle, from: Vec2(100, 200), to: Vec2(180, 260))
        model.tool = .perspectiveSelection
        model.pointerDown(at: Vec2(120, 220), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(140, 230), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(140, 230), shift: false, option: false, command: false)
        XCTAssertFalse(model.selection.isEmpty)
        model.tool = .artboard
        model.pointerDown(at: Vec2(900, 20), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(1100, 200), shift: false, option: false, command: false)
        XCTAssertEqual(model.document.artboards.count, 2)
        model.tool = .slice
        model.pointerDown(at: Vec2(10, 300), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(80, 360), shift: false, option: false, command: false)
        XCTAssertEqual(model.document.slices.count, 1)
        model.showPerspective = false
        model.chartKind = .pie
        drag(model, .columnGraph, from: Vec2(200, 200), to: Vec2(320, 320))
        XCTAssertTrue(model.document.flatItems().contains { if case .graph(let g) = $0 { return g.kind == .pie } else { return false } })
    }

    func testTypeToolsAndBlob() {
        let model = EditorModel()
        model.tool = .text
        model.pointerDown(at: Vec2(10, 10), shift: false, option: false, command: false)
        XCTAssertEqual(model.document.flatItems()[0].name, "文字")
        model.tool = .areaText
        model.pointerDown(at: Vec2(0, 40), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(120, 100), shift: false, option: false, command: false)
        guard case .text(let area) = model.document.flatItems().last else { return XCTFail() }
        XCTAssertEqual(area.kind, .area)
        XCTAssertGreaterThan(area.frame.width, 50)
        model.tool = .verticalText
        model.pointerDown(at: Vec2(140, 40), shift: false, option: false, command: false)
        guard case .text(let vertical) = model.document.flatItems().last else { return XCTFail() }
        XCTAssertLessThan(vertical.leading, 0)
        drag(model, .rectangle, from: Vec2(0, 120), to: Vec2(80, 160))
        model.tool = .pathText
        model.pointerDown(at: Vec2(10, 130), shift: false, option: false, command: false)
        guard case .text(let onPath) = model.document.flatItems().last else { return XCTFail() }
        XCTAssertNotNil(onPath.onPath)
        model.tool = .touchType
        model.pointerDown(at: Vec2(12, 12), shift: false, option: false, command: false)
        XCTAssertFalse(model.glyphNudge.isEmpty)
        model.tool = .blobBrush
        model.blobDiameter = 10
        model.pointerDown(at: Vec2(0, 200), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(40, 210), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(70, 200), shift: false, option: false, command: false)
        XCTAssertTrue(model.document.flatItems().contains { $0.name == "斑点" })
        model.requestToolOptions()
        XCTAssertEqual(model.pendingDialog?.action, "工具选项")
        model.dialogValues = ["fidelity": "6", "smoothness": "0.4", "diameter": "22", "tolerance": "0.15"]
        model.perform("工具选项")
        XCTAssertEqual(model.fidelity, 6, accuracy: 0.01)
        XCTAssertEqual(model.wandTolerance, 0.15, accuracy: 0.001)
    }
}

private extension ArtItem {
    var letPath: PathItem {
        if case .path(let o) = self { return o.path }
        return PathItem(nodes: [], closed: false)
    }
    var letPathWidths: [WidthPoint] {
        if case .path(let o) = self { return o.widths }
        return []
    }
}
