import XCTest
@testable import LaminaCore

final class IllustratorParityTests: XCTestCase {
    func testZoomUsesTheMeasuredSteps() {
        XCTAssertEqual(IllustratorZoom.next(0.8779, out: false), 1, accuracy: 0.0001)
        XCTAssertEqual(IllustratorZoom.next(1, out: false), 1.5, accuracy: 0.0001)
        XCTAssertEqual(IllustratorZoom.next(1, out: true), 0.6667, accuracy: 0.0001)
        XCTAssertEqual(IllustratorZoom.next(0.6667, out: true), 0.5, accuracy: 0.0001)
        XCTAssertEqual(IllustratorZoom.next(0.5, out: true), 0.3333, accuracy: 0.0001)
        let model = EditorModel()
        model.zoom = 0.8779
        _ = model.perform("放大")
        XCTAssertEqual(model.zoom, 1, accuracy: 0.0001)
        _ = model.perform("放大")
        XCTAssertEqual(model.zoom, 1.5, accuracy: 0.0001)
        model.zoom = 1
        _ = model.perform("缩小")
        XCTAssertEqual(model.zoom, 0.6667, accuracy: 0.0001)
        XCTAssertTrue(model.keyDown(chord: KeyChord(modifiers: .command, key: .character("1"))))
        XCTAssertEqual(model.zoom, 1, accuracy: 0.0001)
    }

    func testDeleteRemovesTheSelectionAndUndoRestoresIt() {
        let model = EditorModel()
        model.tool = .rectangle
        model.pointerDown(at: Vec2(20, 20), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(80, 70), shift: false, option: false, command: false)
        XCTAssertEqual(model.document.flatItems().count, 1)
        XCTAssertTrue(model.keyDown(chord: KeyChord(key: .delete)))
        XCTAssertTrue(model.document.flatItems().isEmpty)
        model.undo()
        XCTAssertEqual(model.document.flatItems().count, 1)
    }

    func testPenClosesAtEightAndAddsAnAnchorAtTen() {
        let model = EditorModel()
        model.smartGuides = false
        model.tool = .pen
        for point in [Vec2.zero, Vec2(80, 0), Vec2(40, 40)] {
            model.pointerDown(at: point, shift: false, option: false, command: false)
            model.pointerUp(at: point, shift: false, option: false, command: false)
        }
        model.pointerMove(to: Vec2(8, 0))
        XCTAssertEqual(model.penHoverCursor, .close)
        model.pointerDown(at: Vec2(8, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(8, 0), shift: false, option: false, command: false)
        XCTAssertTrue(model.penNodes.isEmpty)
        guard case .path(let closed) = model.document.flatItems().last else { return XCTFail("closed") }
        XCTAssertTrue(closed.path.closed)

        let open = EditorModel()
        open.smartGuides = false
        open.tool = .pen
        for point in [Vec2.zero, Vec2(80, 0), Vec2(40, 40)] {
            open.pointerDown(at: point, shift: false, option: false, command: false)
            open.pointerUp(at: point, shift: false, option: false, command: false)
        }
        open.pointerMove(to: Vec2(10, 0))
        XCTAssertNotEqual(open.penHoverCursor, .close)
        open.pointerDown(at: Vec2(10, 0), shift: false, option: false, command: false)
        open.pointerUp(at: Vec2(10, 0), shift: false, option: false, command: false)
        XCTAssertEqual(open.penNodes.count, 4)
    }

    func testEyedropperPaintsTheSelection() {
        let model = EditorModel()
        model.tool = .rectangle
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(40, 40), shift: false, option: false, command: false)
        model.currentFill = .solid(.black)
        model.currentStroke = StrokeStyle(paint: .solid(.white), width: 2)
        model.tool = .ellipse
        model.pointerDown(at: Vec2(80, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(120, 40), shift: false, option: false, command: false)
        model.tool = .selection
        model.pointerDown(at: Vec2(10, 10), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(10, 10), shift: false, option: false, command: false)
        model.tool = .eyedropper
        model.pointerDown(at: Vec2(100, 20), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(100, 20), shift: false, option: false, command: false)
        guard case .path(let rect) = model.document.flatItems().first else { return XCTFail("rect") }
        XCTAssertEqual(rect.appearance.fill, .solid(.black))
        XCTAssertEqual(rect.appearance.stroke?.paint, .solid(.white))
    }

    func testShapeClickOpensTheMeasuredDialogAndCentersTheShape() {
        let model = EditorModel()
        model.tool = .rectangle
        model.pointerDown(at: Vec2(100, 80), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(100, 80), shift: false, option: false, command: false)
        XCTAssertEqual(model.pendingDialog?.title, "矩形")
        XCTAssertEqual(model.pendingDialog?.fields.first?.value, "53.451")
        model.commitDialog(["width": "10", "height": "10", "link": "1"])
        guard case .path(let rect) = model.document.flatItems().last else { return XCTFail("rect") }
        let box = ItemGeometry.bounds(.path(rect))
        XCTAssertEqual(box.center.x, 100, accuracy: 0.5)
        XCTAssertEqual(box.center.y, 80, accuracy: 0.5)
    }

    func testRotateReturnOpensTheRotateDialog() {
        let model = EditorModel()
        model.tool = .rotate
        XCTAssertTrue(model.keyDown(chord: KeyChord(key: .return)))
        XCTAssertEqual(model.pendingDialog?.title, "旋转")
        XCTAssertTrue(model.pendingDialog?.fields.contains { $0.label == "角度" } == true)
        XCTAssertFalse(model.pendingDialog?.fields.contains { $0.key == "fidelity" } == true)
        model.tool = .scale
        model.requestToolOptions()
        XCTAssertEqual(model.pendingDialog?.title, "比例缩放")
        model.tool = .reflect
        model.requestToolOptions()
        XCTAssertEqual(model.pendingDialog?.title, "镜像")
    }

    func testTypingReplacesThePlaceholder() {
        let model = EditorModel()
        model.tool = .text
        model.pointerDown(at: Vec2(10, 10), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(10, 10), shift: false, option: false, command: false)
        model.typeText("Ab")
        guard case .text(let text) = model.document.flatItems().last else { return XCTFail("text") }
        XCTAssertEqual(text.string, "Ab")
    }

    func testUnshiftedEqualSelectsAddAnchorAndOffAnchorWarns() {
        let model = EditorModel()
        XCTAssertTrue(model.keyDown(chord: KeyChord(key: .equal)))
        XCTAssertEqual(model.tool, .addAnchor)
        model.tool = .deleteAnchor
        model.pointerDown(at: Vec2(4, 4), shift: false, option: false, command: false)
        XCTAssertEqual(model.pendingDialog?.title, "请针对路径的锚点使用删除锚点工具。")
    }

    func testUnlockSelectsTheObjects() {
        let model = EditorModel()
        model.tool = .rectangle
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(20, 20), shift: false, option: false, command: false)
        _ = model.perform("锁定所选对象")
        XCTAssertTrue(model.selection.isEmpty)
        _ = model.perform("解锁所选对象")
        XCTAssertEqual(model.selection.count, 1)
    }

    func testDocumentSetupAndAverageShortcut() {
        let model = EditorModel()
        XCTAssertTrue(model.keyDown(chord: KeyChord(modifiers: [.option, .command], key: .character("p"))))
        XCTAssertEqual(model.pendingDialog?.title, "文档设置")
        XCTAssertEqual(model.pendingDialog?.fields.first { $0.key == "gridSize" }?.value, "中")
        let average = MenuCatalog.flattened().first { $0.title == "平均" }
        XCTAssertEqual(MenuCatalog.menuChord(for: average!), KeyChord(modifiers: [.option, .command], key: .character("j")))
        let actual = MenuCatalog.flattened().first { $0.title == "实际大小" }
        XCTAssertEqual(MenuCatalog.menuChord(for: actual!), KeyChord(modifiers: .command, key: .character("1")))
        let fitAll = MenuCatalog.flattened().first { $0.title == "全部适合窗口大小" }
        XCTAssertNil(MenuCatalog.menuChord(for: fitAll!))
        XCTAssertFalse(model.keyDown(chord: KeyChord(modifiers: [.option, .command], key: .character("0"))))
    }

    func testSelectionReadoutIsMillimetres() {
        let model = EditorModel()
        model.document.units = .mm
        model.tool = .rectangle
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(72, 72), shift: false, option: false, command: false)
        let readout = model.selectionReadout()
        XCTAssertEqual(readout?.name, "矩形")
        XCTAssertEqual(readout?.width, "25.4")
        model.applyGeometryField("x", text: "50")
        let moved = model.selectionReadout()
        XCTAssertEqual(moved?.x, "50")
    }

    func testEraserPiecesSelectIndependently() {
        let model = EditorModel()
        model.tool = .rectangle
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(100, 40), shift: false, option: false, command: false)
        model.tool = .eraser
        model.pointerDown(at: Vec2(50, -10), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(50, 50), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(50, 50), shift: false, option: false, command: false)
        XCTAssertGreaterThanOrEqual(model.document.flatItems().count, 2)
        model.tool = .selection
        model.pointerDown(at: Vec2(10, 20), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(10, 20), shift: false, option: false, command: false)
        XCTAssertEqual(model.selection.count, 1)
    }

    func testMiterLimitDefaultsToTen() {
        XCTAssertEqual(StrokeStyle().miterLimit, 10, accuracy: 0.001)
        XCTAssertEqual(IllustratorParity.strokeWeights.first, 0.25)
        XCTAssertEqual(IllustratorParity.strokeWeights.last, 60)
    }

    func testContextBarNamesTheIllustratorActions() {
        XCTAssertEqual(
            IllustratorParity.contextSelected,
            ["生成矢量", "编辑路径", "填色", "描边", "边角", "•••"]
        )
        XCTAssertEqual(IllustratorParity.contextEmpty, ["生成矢量", "绘制（铅笔）"])
    }
}
